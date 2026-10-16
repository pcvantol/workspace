"""Bounded immutable proposal intents in the existing own concept database.

No Forge call or proposal generation occurs here. Callers use current own grant
fences only around these short local commits, never around peer computation.
"""
import json
import os
import re
import sqlite3
from .concept_baseline_mapping import map_concept,provisional_references,digest,canonical
from .project_concepts import ConceptStorageUnavailable,ID
from .project_concept_library import lifecycle_for
from .conversations import ConversationConflict
from .service import _private_json

TABLE='concept_adoption_intents_v1'
MARKER='concept-adoption-intents-schema-v1.json'
LIMIT=256
RECORD_BYTES=192000
COLUMNS={'actor_id','context_id','concept_id','operation_id','command_digest','record','record_digest','dispatched'}
BINDING={'id','actor_id','context_id','concept_id','instance_id','dossier_id','audience','producer_source','principal_id','pairing_id','identity','source_options'}

class ConceptAdoptionIntents:
    def __init__(self,store):self.store=store;self.base=store.base

    def _schema(self,db,write=False):
        try:marker=_private_json(MARKER,dir_fd=self.base.root_fd)
        except FileNotFoundError:marker=None
        except (ValueError,OSError,UnicodeError) as error:raise ConceptStorageUnavailable('proposal allocation unavailable') from error
        if marker is not None and (marker!={'schema_version':1} or type(marker.get('schema_version')) is not int):raise ConceptStorageUnavailable('proposal schema incompatible')
        exists=db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(TABLE,)).fetchone() is not None
        if exists:
            if marker is None or {r[1] for r in db.execute('PRAGMA table_info('+TABLE+')')}!=COLUMNS:raise ConceptStorageUnavailable('proposal allocation incomplete')
        elif marker is not None:raise ConceptStorageUnavailable('initialized proposal store lost')
        elif write:
            db.execute('CREATE TABLE '+TABLE+' (actor_id TEXT NOT NULL,context_id TEXT NOT NULL,concept_id TEXT NOT NULL,operation_id TEXT NOT NULL,command_digest TEXT NOT NULL,record TEXT NOT NULL,record_digest TEXT NOT NULL,dispatched INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(actor_id,context_id,operation_id))')
            descriptor=os.open(MARKER,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.base.root_fd)
            with os.fdopen(descriptor,'w') as stream:
                json.dump({'schema_version':1},stream);stream.flush();os.fsync(stream.fileno())
            os.fsync(self.base.root_fd)
            exists=True
        return exists

    def _original(self,row,scope,identity,operation):
        try:
            raw=row['record'];value=json.loads(raw)
            if len(raw.encode())>RECORD_BYTES or digest(value)!=row['record_digest'] or row['dispatched'] not in (0,1):raise ValueError('integrity')
            source=value['mapping']['source'];binding=value['binding'];request=value['request']
            from .concept_adoption_mapping import mapping,request_for
            if mapping(source,scope,binding,value['command'])!=value['mapping'] or request_for(value['mapping'],binding,operation)!=request:raise ValueError('original mapping changed')
            if row['command_digest']!=digest({'concept_id':identity,'command':value['command'],'binding':binding}):raise ValueError('command integrity')
            if source['id']!=identity or (source['actor_id'],source['context_id'])!=tuple(scope) or request['operation_id']!=operation or value['request_digest']!=digest(request):raise ValueError('binding')
            return value
        except (ValueError,TypeError,KeyError) as error:raise ConceptStorageUnavailable('adoption intent corrupt') from error

    def freeze(self,scope,identity,command,binding):
        if not isinstance(identity,str) or ID.fullmatch(identity) is None or type(command) is not dict or set(command)!={'operation_id','expected_revision','requested_artifacts','mappings'} or not isinstance(command['operation_id'],str) or ID.fullmatch(command['operation_id']) is None or type(command['expected_revision']) is not int or not 1<=command['expected_revision']<=1000001:raise ValueError('invalid proposal intent')
        if type(binding) is not dict or set(binding)!=BINDING or binding['actor_id']!=scope[0] or binding['context_id']!=scope[1] or binding['concept_id']!=identity:raise PermissionError('proposal binding denied')
        if any(not isinstance(binding[k],str) or not 1<=len(binding[k])<=256 or any(ord(c)<32 for c in binding[k]) for k in BINDING-{'identity','source_options'}):raise ValueError('invalid proposal binding')
        if re.fullmatch('[0-9a-f]{40}',binding['producer_source']) is None:raise ValueError('producer source required')
        operation=command['operation_id'];key=digest({'concept_id':identity,'command':command,'binding':binding})
        with self.base.lock:
            db=self.store._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    exists=self._schema(db)
                    current=db.execute('SELECT * FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if current is None:raise FileNotFoundError('concept not found')
                    if exists:
                        prior=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()
                        if prior is not None:
                            if prior['command_digest']!=key:raise ConversationConflict('original proposal request changed')
                            return self._original(prior,scope,identity,operation)
                    if lifecycle_for(self.base,db,identity)=='ARCHIVED':raise ConversationConflict('restore concept before preparing')
                    if current['revision']!=command['expected_revision']:raise ConversationConflict('concept revision changed')
                    source=self.store._record(current)
                    from .concept_briefing_store import ConceptBriefingStore
                    briefing=ConceptBriefingStore(self.store)._read(db,scope,identity)
                    if briefing['accepted_from'] is not None:
                        source['briefing']={'fields':briefing['fields'],'accepted_from':briefing['accepted_from']}
                    if exists and db.execute('SELECT count(*) FROM '+TABLE).fetchone()[0]>=LIMIT:raise ConceptStorageUnavailable('proposal history capacity')
                    from .concept_adoption_mapping import mapping,request_for
                    mapped=mapping(source,scope,binding,command)
                    request=request_for(mapped,binding,operation)
                    value={'schema_version':1,'state':'ORIGINAL_REQUEST_CAPTURED','binding':binding,'command':command,'mapping':mapped,'request':request,'request_digest':digest(request)}
                    raw=canonical(value)
                    if len(raw)>RECORD_BYTES:raise ValueError('proposal intent byte limit')
                    self._schema(db,write=True)
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?,?,?,?,?,?,?)',(*scope,identity,operation,key,raw.decode(),digest(value),0))
                    return value
            except sqlite3.Error as error:raise ConceptStorageUnavailable('proposal storage unavailable') from error
            finally:db.close()

    def get(self,scope,identity,operation):
        # Historical access is rechecked by the caller; current archiving/editing
        # never changes an old original request or implies another peer prepare.
        self.store.get(scope,identity)
        with self.base.lock:
            db=self.store._connect()
            try:
                if not self._schema(db):raise FileNotFoundError('proposal intent not found')
                row=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=?',(*scope,identity,operation)).fetchone()
                if row is None:raise FileNotFoundError('proposal intent not found')
                return self._original(row,scope,identity,operation)
            except sqlite3.Error as error:raise ConceptStorageUnavailable('proposal storage unavailable') from error
            finally:db.close()

    def list(self,scope,identity):
        self.store.get(scope,identity)
        with self.base.lock:
            db=self.store._connect()
            try:
                if not self._schema(db):return []
                rows=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? ORDER BY rowid',(*scope,identity)).fetchall()
                return [self._original(row,scope,identity,row['operation_id']) for row in rows]
            except sqlite3.Error as error:raise ConceptStorageUnavailable('proposal storage unavailable') from error
            finally:db.close()

    def claim_dispatch(self,scope,identity,operation):
        self.get(scope,identity,operation)
        with self.base.lock:
            db=self.store._connect(write=True)
            try:
                with db:
                    self._schema(db)
                    return db.execute('UPDATE '+TABLE+' SET dispatched=1 WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=? AND dispatched=0',(*scope,identity,operation)).rowcount==1
            except sqlite3.Error as error:raise ConceptStorageUnavailable('adoption dispatch unavailable') from error
            finally:db.close()
