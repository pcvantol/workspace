"""Original Genesis transport intents in the existing private concept database.

A shared operation witness detects initialized-store loss. Admission is durable
BEFORE the first POST; uncertain dispatch is recovered by original GET only.
"""
import json
import os
from .concept_baseline_mapping import canonical,digest
from .concept_baseline_intents import COLUMNS
from .project_concepts import ID,ConceptStorageUnavailable
from .project_concept_library import lifecycle_for
from .conversations import ConversationConflict
from .service import _private_json
from . import genesis_wire as wire

TABLE='genesis_intents_v1'
MARKER='genesis-intents-schema-v1.json'
WITNESS='genesis_intent_version'
COMMON={'operation_id','source_operation_id','expected_concept_revision','selection_digest'}
PLAN_COMMAND=COMMON|{'target_id'}
DECISION_COMMAND=COMMON|{'plan_operation_id','decision','reason'}
BINDING={'id','actor_id','context_id','concept_id','instance_id','principal_id','audience','dossier_id','producer_source','source_binding_id','source_principal_id','grant_id','human_binding'}

class GenesisIntents:
    def __init__(self,concepts):self.concepts=concepts;self.base=concepts.base

    def _schema(self,db,write=False):
        try:marker=_private_json(MARKER,dir_fd=self.base.root_fd)
        except FileNotFoundError:marker=None
        except (ValueError,OSError,UnicodeError) as error:raise ConceptStorageUnavailable('Genesis allocation unavailable') from error
        exists=db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(TABLE,)).fetchone() is not None
        witness=db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE json_extract(response,'$.genesis_intent_version')=1 LIMIT 1").fetchone() is not None
        if marker is not None and (marker!={'schema_version':1} or type(marker.get('schema_version')) is not int):raise ConceptStorageUnavailable('Genesis schema incompatible')
        if exists:
            if marker is None or {r[1] for r in db.execute('PRAGMA table_info('+TABLE+')')}!=COLUMNS:raise ConceptStorageUnavailable('Genesis allocation incomplete')
        elif marker is not None or witness:raise ConceptStorageUnavailable('initialized Genesis intents lost')
        elif write:
            db.execute('CREATE TABLE '+TABLE+' (actor_id TEXT NOT NULL,context_id TEXT NOT NULL,concept_id TEXT NOT NULL,operation_id TEXT NOT NULL,command_digest TEXT NOT NULL,record TEXT NOT NULL,record_digest TEXT NOT NULL,PRIMARY KEY(actor_id,context_id,operation_id))')
            fd=os.open(MARKER,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.base.root_fd)
            with os.fdopen(fd,'w') as stream:
                json.dump({'schema_version':1},stream);stream.flush();os.fsync(stream.fileno())
            os.fsync(self.base.root_fd);exists=True
        return exists

    def check(self,scope,identity,kind,command,binding,request):
        if kind not in ('PLAN','DECISION') or type(command) is not dict or set(command)!=(PLAN_COMMAND if kind=='PLAN' else DECISION_COMMAND):raise ValueError('closed Genesis command required')
        if any(not isinstance(command[k],str) or ID.fullmatch(command[k]) is None for k in ('operation_id','source_operation_id')):raise ValueError('original operation required')
        if type(command['expected_concept_revision']) is not int or not 1<=command['expected_concept_revision']<=1000001 or not isinstance(command['selection_digest'],str) or len(command['selection_digest'])!=64:raise ValueError('original selection required')
        if set(binding)!=BINDING or tuple(binding[k] for k in ('actor_id','context_id','concept_id'))!=(*scope,identity):raise PermissionError('Genesis actor/context denied')
        wire.request(request,kind)
        if any(request[k]!=binding[k] for k in ('instance_id','dossier_id')) or request['operation_id']!=command['operation_id']:raise ValueError('original request binding changed')
        if kind=='PLAN':
            if request['source_subject']['proposal_principal_id']!=binding['source_principal_id']:raise ValueError('source principal changed')
        elif any(request[k]!=command[k] for k in ('decision','reason')):raise ValueError('effect decision changed')

    def _original(self,db,row,scope,identity):
        try:
            v=json.loads(row['record']);op=v['command']['operation_id'];key=digest({'concept_id':identity,'command':v['command'],'binding':v['binding'],'kind':v['kind']})
            if set(v)!={'kind','command','binding','request','request_digest','metadata'} or len(row['record'].encode())>192000 or row['concept_id']!=identity or digest(v)!=row['record_digest'] or row['command_digest']!=key or row['operation_id']!=op or v['request_digest']!=wire.peer_digest(v['request']):raise ValueError('integrity')
            self.check(scope,identity,v['kind'],v['command'],v['binding'],v['request'])
            self.check_metadata(v['kind'],v['command'],v['request'],v['metadata'])
            roww=db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,op)).fetchone()
            expected={WITNESS:1,'concept_id':identity,'operation_id':op,'record_digest':row['record_digest']}
            if roww is None or roww['request_digest']!=key:raise ValueError('original allocation witness missing')
            witness=json.loads(roww['response'])
            if set(witness)-set(expected)-{'transport_admitted'} or any(witness.get(k)!=value for k,value in expected.items()) or ('transport_admitted' in witness and witness['transport_admitted'] is not True):raise ValueError('original witness changed')
            return v
        except (ValueError,TypeError,KeyError) as error:raise ConceptStorageUnavailable('original Genesis intent corrupt') from error

    def check_metadata(self,kind,command,request,metadata):
        if kind=='DECISION':
            if metadata!={}:raise ValueError('closed decision metadata required')
            return
        if type(metadata) is not dict or set(metadata)!={'target'}:raise ValueError('original target metadata required')
        t=metadata['target']
        if type(t) is not dict or set(t)!={'id','label','target','expires_at','blocking_open_points'} or t['id']!=command['target_id'] or any(t[k]!=request[k] for k in ('target','expires_at','blocking_open_points')):raise ValueError('original target metadata changed')
        if not isinstance(t['label'],str) or not 1<=len(t['label'])<=120 or any(ord(c)<32 for c in t['label']):raise ValueError('original target label required')

    def freeze(self,scope,identity,kind,command,binding,request,metadata=None):
        self.check(scope,identity,kind,command,binding,request)
        metadata={} if metadata is None else metadata
        self.check_metadata(kind,command,request,metadata)
        key=digest({'concept_id':identity,'command':command,'binding':binding,'kind':kind})
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE');present=self._schema(db)
                    concept=db.execute('SELECT revision FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if concept is None:raise FileNotFoundError('concept not found')
                    if present:
                        prior=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone()
                        if prior is not None:
                            value=self._original(db,prior,scope,identity)
                            if value['command']!=command or value['binding']!=binding or value['kind']!=kind or value['request']!=request or value['metadata']!=metadata:raise ConversationConflict('original Genesis operation changed')
                            return value
                    if db.execute('SELECT 1 FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone():raise ConversationConflict('operation already allocated')
                    if concept['revision']!=command['expected_concept_revision'] or lifecycle_for(self.base,db,identity)=='ARCHIVED':raise ConversationConflict('concept changed or archived')
                    if (present and db.execute('SELECT count(*) FROM '+TABLE).fetchone()[0]>=256) or db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]>=4096:raise ConceptStorageUnavailable('Genesis history capacity')
                    value={'kind':kind,'command':command,'binding':binding,'request':request,'request_digest':wire.peer_digest(request),'metadata':metadata};raw=canonical(value)
                    if len(raw)>192000:raise ValueError('Genesis intent byte limit')
                    self._schema(db,write=True);record_digest=digest(value)
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?,?,?,?,?,?)',(*scope,identity,command['operation_id'],key,raw.decode(),record_digest))
                    witness={WITNESS:1,'concept_id':identity,'operation_id':command['operation_id'],'record_digest':record_digest}
                    db.execute('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',(*scope,command['operation_id'],key,canonical(witness).decode()))
                    return json.loads(raw)
            finally:db.close()

    def list(self,scope,identity):
        self.concepts.get(scope,identity)
        with self.base.lock:
            db=self.concepts._connect()
            try:
                present=self._schema(db)
                rows=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? ORDER BY rowid',(*scope,identity)).fetchall() if present else []
                witness=db.execute("SELECT operation_id FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND json_extract(response,'$.genesis_intent_version')=1 AND json_extract(response,'$.concept_id')=?",(*scope,identity)).fetchall()
                if {x['operation_id'] for x in rows}!={x['operation_id'] for x in witness}:raise ConceptStorageUnavailable('original Genesis rows lost')
                return [self._original(db,x,scope,identity) for x in rows]
            finally:db.close()

    def get(self,scope,identity,operation):
        for value in self.list(scope,identity):
            if value['command']['operation_id']==operation:return value
        raise FileNotFoundError('original Genesis intent not found')

    def admit_transport(self,scope,identity,operation):
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    if not self._schema(db):raise ConceptStorageUnavailable('original Genesis intent not initialized')
                    row=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=?',(*scope,identity,operation)).fetchone()
                    if row is None:raise ConceptStorageUnavailable('original Genesis intent lost')
                    value=self._original(db,row,scope,identity)
                    prior=db.execute('SELECT response FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone();witness=json.loads(prior['response'])
                    if witness.get('transport_admitted'):return False
                    current=db.execute('SELECT revision FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if current is None or current['revision']!=value['command']['expected_concept_revision'] or lifecycle_for(self.base,db,identity)=='ARCHIVED':raise ConversationConflict('concept changed before Genesis send')
                    witness['transport_admitted']=True
                    db.execute('UPDATE project_concept_operations_v1 SET response=? WHERE actor_id=? AND context_id=? AND operation_id=?',(canonical(witness).decode(),*scope,operation));return True
            finally:db.close()
