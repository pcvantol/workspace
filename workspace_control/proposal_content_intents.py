"""Immutable human decision commands in the existing private concept database.

The operation witness shares the own action namespace; loss is never empty
history. This captures intent, never an authoritative local approval state.
"""
import json
import os
from .concept_baseline_mapping import canonical,digest
from .concept_baseline_intents import COLUMNS
from .project_concepts import ID,ConceptStorageUnavailable
from .project_concept_library import lifecycle_for
from .conversations import ConversationConflict
from .service import _private_json
from . import proposal_content_wire as wire

TABLE='proposal_content_intents_v1'
MARKER='proposal-content-intents-schema-v1.json'
COMMAND={'operation_id','source_operation_id','expected_concept_revision','selection_digest','role','decision','reason','acknowledged_open_points'}
BINDING={'id','actor_id','context_id','concept_id','instance_id','principal_id','audience','dossier_id','producer_source','source_binding_id','source_principal_id','grant_id','human_binding'}

class ProposalContentIntents:
    def __init__(self,concepts):self.concepts=concepts;self.base=concepts.base

    def _schema(self,db,write=False):
        try:marker=_private_json(MARKER,dir_fd=self.base.root_fd)
        except FileNotFoundError:marker=None
        except (ValueError,OSError,UnicodeError) as error:raise ConceptStorageUnavailable('decision allocation unavailable') from error
        if marker is not None and (marker!={'schema_version':1} or type(marker.get('schema_version')) is not int):raise ConceptStorageUnavailable('decision schema incompatible')
        exists=db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(TABLE,)).fetchone() is not None
        witness=db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE json_extract(response,'$.content_intent_version')=1 LIMIT 1").fetchone() is not None
        if exists:
            if marker is None or {r[1] for r in db.execute('PRAGMA table_info('+TABLE+')')}!=COLUMNS:raise ConceptStorageUnavailable('decision allocation incomplete')
        elif marker is not None or witness:raise ConceptStorageUnavailable('initialized decision requests lost')
        elif write:
            db.execute('CREATE TABLE '+TABLE+' (actor_id TEXT NOT NULL,context_id TEXT NOT NULL,concept_id TEXT NOT NULL,operation_id TEXT NOT NULL,command_digest TEXT NOT NULL,record TEXT NOT NULL,record_digest TEXT NOT NULL,PRIMARY KEY(actor_id,context_id,operation_id))')
            fd=os.open(MARKER,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.base.root_fd)
            with os.fdopen(fd,'w') as stream:
                json.dump({'schema_version':1},stream);stream.flush();os.fsync(stream.fileno())
            os.fsync(self.base.root_fd);exists=True
        return exists

    def _original(self,db,row,scope,identity,operation):
        try:
            raw=row['record'];value=json.loads(raw);binding=value['binding'];command=value['command'];request=value['request']
            if len(raw.encode())>192000 or set(value)!={'state','binding','command','request','open_points'} or value['state']!='ORIGINAL_DECISION_CAPTURED' or digest(value)!=row['record_digest']:raise ValueError('integrity')
            if set(binding)!=BINDING or set(command)!=COMMAND or (binding['actor_id'],binding['context_id'],binding['concept_id'])!=(*scope,identity) or row['concept_id']!=identity or request['operation_id']!=operation or command['operation_id']!=operation:raise ValueError('identity')
            wire.decision_request(request)
            if any(request[k]!=command[k] for k in ('role','decision','reason','acknowledged_open_points')) or request['instance_id']!=binding['instance_id'] or request['dossier_id']!=binding['dossier_id'] or request['subject']['proposal_principal_id']!=binding['source_principal_id']:raise ValueError('original subject')
            key=digest({'concept_id':identity,'command':command,'binding':binding})
            witness=db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()
            expected={'content_intent_version':1,'concept_id':identity,'operation_id':operation,'record_digest':row['record_digest']}
            if row['command_digest']!=key or witness is None or witness['request_digest']!=key:raise ValueError('witness')
            receipt=json.loads(witness['response'])
            if type(receipt) is not dict or set(receipt)-set(expected)-{'transport_admitted','rejection'} or any(receipt.get(k)!=v for k,v in expected.items()):raise ValueError('witness receipt')
            if 'transport_admitted' in receipt and receipt['transport_admitted'] is not True:raise ValueError('transport receipt')
            if 'rejection' in receipt and receipt['rejection'] not in ('CONTENT_DECISION_STALE','OWN_CONCEPT_STALE_BEFORE_TRANSPORT'):raise ValueError('rejection receipt')
            if receipt.get('rejection')=='OWN_CONCEPT_STALE_BEFORE_TRANSPORT' and receipt.get('transport_admitted'):raise ValueError('uncertain transport is not rejected')
            return value
        except (ValueError,TypeError,KeyError) as error:raise ConceptStorageUnavailable('original decision corrupt') from error

    def freeze(self,scope,identity,command,binding,request,open_points):
        if type(command) is not dict or set(command)!=COMMAND or any(not isinstance(command[k],str) or ID.fullmatch(command[k]) is None for k in ('operation_id','source_operation_id')):raise ValueError('invalid decision command')
        if type(command['expected_concept_revision']) is not int or not 1<=command['expected_concept_revision']<=1000001 or not isinstance(command['selection_digest'],str) or len(command['selection_digest'])!=64:raise ValueError('invalid original selection')
        if set(binding)!=BINDING or (binding['actor_id'],binding['context_id'],binding['concept_id'])!=(*scope,identity):raise PermissionError('decision binding denied')
        wire.decision_request(request)
        acknowledged=request['acknowledged_open_points']
        if (request['decision']=='APPROVE_CONTENT' and acknowledged!=open_points) or any(point not in open_points for point in acknowledged):raise ValueError('original open-point acknowledgment required before capture')
        if request['operation_id']!=command['operation_id'] or any(request[k]!=command[k] for k in ('role','decision','reason','acknowledged_open_points')):raise ValueError('decision changed')
        key=digest({'concept_id':identity,'command':command,'binding':binding})
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE');present=self._schema(db)
                    current=db.execute('SELECT revision FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if current is None:raise FileNotFoundError('concept not found')
                    if present:
                        prior=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone()
                        if prior is not None:
                            if prior['command_digest']!=key:raise ConversationConflict('original decision changed')
                            return self._original(db,prior,scope,identity,command['operation_id'])
                    if db.execute('SELECT 1 FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone():raise ConversationConflict('operation already allocated')
                    if current['revision']!=command['expected_concept_revision'] or lifecycle_for(self.base,db,identity)=='ARCHIVED':raise ConversationConflict('concept changed or archived')
                    if db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]>=4096 or (present and db.execute('SELECT count(*) FROM '+TABLE).fetchone()[0]>=256):raise ConceptStorageUnavailable('decision intent capacity')
                    value={'state':'ORIGINAL_DECISION_CAPTURED','binding':binding,'command':command,'request':request,'open_points':open_points};raw=canonical(value)
                    if len(raw)>192000:raise ValueError('original decision byte capacity')
                    self._schema(db,write=True);record_digest=digest(value)
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?,?,?,?,?,?)',(*scope,identity,command['operation_id'],key,raw.decode(),record_digest))
                    witness={'content_intent_version':1,'concept_id':identity,'operation_id':command['operation_id'],'record_digest':record_digest}
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
                witnesses=db.execute("SELECT operation_id FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND json_extract(response,'$.content_intent_version')=1 AND json_extract(response,'$.concept_id')=?",(*scope,identity)).fetchall()
                if {r['operation_id'] for r in witnesses}!={r['operation_id'] for r in rows}:raise ConceptStorageUnavailable('original decision rows lost')
                return [self._original(db,row,scope,identity,row['operation_id']) for row in rows]
            finally:db.close()

    def get(self,scope,identity,operation):
        for value in self.list(scope,identity):
            if value['request']['operation_id']==operation:return value
        raise FileNotFoundError('original decision not found')

    def reject(self,scope,identity,operation):
        # Only the caller's genuine authenticated R54 stale409 can reach here.
        # Preserve the entire immutable original and its allocation witness.
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    if not self._schema(db):raise ConceptStorageUnavailable('decision allocation lost')
                    row=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=?',(*scope,identity,operation)).fetchone()
                    if row is None:raise ConceptStorageUnavailable('original decision lost')
                    self._original(db,row,scope,identity,operation)
                    witness=json.loads(db.execute('SELECT response FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()['response'])
                    witness['rejection']='CONTENT_DECISION_STALE'
                    db.execute('UPDATE project_concept_operations_v1 SET response=? WHERE actor_id=? AND context_id=? AND operation_id=?',(canonical(witness).decode(),*scope,operation))
            finally:db.close()

    def rejections(self,scope,identity):
        # Validate original rows/witnesses before using terminal dispositions.
        self.list(scope,identity)
        with self.base.lock:
            db=self.concepts._connect()
            try:
                rows=db.execute("SELECT operation_id FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND json_extract(response,'$.content_intent_version')=1 AND json_extract(response,'$.concept_id')=? AND json_extract(response,'$.rejection') IN ('CONTENT_DECISION_STALE','OWN_CONCEPT_STALE_BEFORE_TRANSPORT')",(*scope,identity)).fetchall()
                return {r['operation_id'] for r in rows}
            finally:db.close()

    def admit_transport(self,scope,identity,operation):
        # Called after healthy original404 under current own dispatch authority.
        # Never retire an operation already admitted to transport: absence may
        # race an in-flight original. Preserve that uncertainty across crashes.
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    if not self._schema(db):raise ConceptStorageUnavailable('decision allocation lost')
                    row=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=?',(*scope,identity,operation)).fetchone()
                    if row is None:raise ConceptStorageUnavailable('original decision lost')
                    original=self._original(db,row,scope,identity,operation)
                    witness=json.loads(db.execute('SELECT response FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()['response'])
                    current=db.execute('SELECT revision FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if current is None:raise FileNotFoundError('concept not found')
                    stale=current['revision']!=original['command']['expected_concept_revision'] or lifecycle_for(self.base,db,identity)=='ARCHIVED'
                    if stale:
                        if not witness.get('transport_admitted'):witness['rejection']='OWN_CONCEPT_STALE_BEFORE_TRANSPORT'
                    elif 'rejection' not in witness:witness['transport_admitted']=True
                    db.execute('UPDATE project_concept_operations_v1 SET response=? WHERE actor_id=? AND context_id=? AND operation_id=?',(canonical(witness).decode(),*scope,operation))
                    return not stale and 'rejection' not in witness
            finally:db.close()
