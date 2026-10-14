"""Original chat requests captured in existing concept SQLite before transport.

Only own request metadata is stored here. There is no provider call or accepted
producer output path until the exact R53 result contract is validated.
"""
import json
import os
import re
from .concept_baseline_mapping import canonical,digest
from .concept_advisory_mapping import prepare
from .concept_briefing_store import ConceptBriefingStore
from .project_concepts import ID,ConceptStorageUnavailable
from .conversations import ConversationConflict
from .service import _private_json

TABLE='concept_chat_intents_v1'
MARKER='concept-chat-intents-schema-v1.json'
COLUMNS={'actor_id','context_id','concept_id','operation_id','command_digest','record','record_digest'}
BINDING={'id','actor_id','context_id','concept_id','instance_id','principal_id','audience','dossier_id','conversation_id','producer_source','transfer_policy_digest'}
COMMAND={'operation_id','turn_id','expected_concept_revision','role','language','message'}


class ConceptChatIntents:
    def __init__(self,concepts):
        self.concepts=concepts;self.base=concepts.base

    def _schema(self,db,*,write=False):
        try:marker=_private_json(MARKER,dir_fd=self.base.root_fd)
        except FileNotFoundError:marker=None
        except (ValueError,OSError,UnicodeError) as error:raise ConceptStorageUnavailable('chat allocation unavailable') from error
        if marker is not None and (marker!={'schema_version':1} or type(marker.get('schema_version')) is not int):
            raise ConceptStorageUnavailable('chat allocation incompatible')
        exists=db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",(TABLE,)).fetchone() is not None
        history=db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE json_extract(response,'$.chat_intent_version')=1 LIMIT 1").fetchone() is not None
        if exists:
            if marker is None or {row[1] for row in db.execute('PRAGMA table_info('+TABLE+')')}!=COLUMNS:
                raise ConceptStorageUnavailable('chat allocation incomplete')
        elif marker is not None or history:
            raise ConceptStorageUnavailable('initialized chat requests lost')
        elif write:
            db.execute('CREATE TABLE '+TABLE+' (actor_id TEXT NOT NULL,context_id TEXT NOT NULL,concept_id TEXT NOT NULL,operation_id TEXT NOT NULL,command_digest TEXT NOT NULL,record TEXT NOT NULL,record_digest TEXT NOT NULL,PRIMARY KEY(actor_id,context_id,operation_id))')
            fd=os.open(MARKER,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.base.root_fd)
            with os.fdopen(fd,'w') as stream:
                json.dump({'schema_version':1},stream);stream.flush();os.fsync(stream.fileno())
            os.fsync(self.base.root_fd)
            exists=True
        return exists

    @staticmethod
    def _mapping(snapshot,command,binding,peer_revision):
        return prepare(snapshot,instance=binding['instance_id'],dossier=binding['dossier_id'],
                       conversation=binding['conversation_id'],operation=command['operation_id'],
                       turn=command['turn_id'],expected_revision=peer_revision,role=command['role'],
                       language=command['language'],message=command['message'],
                       transfer_digest=binding['transfer_policy_digest'])

    def _original(self,db,row,scope,identity,operation):
        try:
            raw=row['record'];value=json.loads(raw)
            if len(raw.encode())>192000 or digest(value)!=row['record_digest'] or set(value)!={'state','binding','command','peer_revision','mapping'} or value['state']!='ORIGINAL_TURN_CAPTURED':
                raise ValueError('chat record integrity')
            binding=value['binding'];command=value['command']
            if set(binding)!=BINDING or set(command)!=COMMAND or (binding['actor_id'],binding['context_id'],binding['concept_id'])!=(*scope,identity) or command['operation_id']!=operation or row['concept_id']!=identity:
                raise ValueError('chat original binding')
            source=value['mapping']['own_source']['concept']
            if (source['id'],source['actor_id'],source['context_id'],source['revision'])!=(identity,*scope,command['expected_concept_revision']) or self._mapping(value['mapping']['own_source'],command,binding,value['peer_revision'])!=value['mapping']:
                raise ValueError('chat original source')
            key=digest({'concept_id':identity,'command':command,'binding':binding,'peer_revision':value['peer_revision']})
            witness=db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()
            expected={'chat_intent_version':1,'concept_id':identity,'operation_id':operation,'record_digest':row['record_digest']}
            if row['command_digest']!=key or witness is None or witness['request_digest']!=key or json.loads(witness['response'])!=expected:
                raise ValueError('chat original witness')
            return value
        except (ValueError,KeyError,TypeError) as error:
            raise ConceptStorageUnavailable('chat original corrupt') from error

    def freeze(self,scope,identity,command,binding,peer_revision):
        if not isinstance(identity,str) or ID.fullmatch(identity) is None or type(command) is not dict or set(command)!=COMMAND:
            raise ValueError('invalid chat command')
        if any(not isinstance(command[key],str) or ID.fullmatch(command[key]) is None for key in ('operation_id','turn_id')) or type(command['expected_concept_revision']) is not int or not 1<=command['expected_concept_revision']<=1000001:
            raise ValueError('invalid original chat identity')
        if type(binding) is not dict or set(binding)!=BINDING or (binding['actor_id'],binding['context_id'],binding['concept_id'])!=(*scope,identity):
            raise PermissionError('chat source binding denied')
        if any(not isinstance(value,str) or not 1<=len(value)<=256 or any(ord(c)<32 for c in value) for value in binding.values()) or re.fullmatch('[0-9a-f]{40}',binding['producer_source']) is None:
            raise ValueError('invalid configured chat binding')
        if type(peer_revision) is not int or not 0<=peer_revision<=1000000:
            raise ValueError('invalid peer revision')
        key=digest({'concept_id':identity,'command':command,'binding':binding,'peer_revision':peer_revision})
        with self.base.lock:
            db=self.concepts._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    present=self._schema(db)
                    snapshot=ConceptBriefingStore(self.concepts)._read(db,scope,identity)
                    if present:
                        prior=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone()
                        if prior is not None:
                            if prior['command_digest']!=key:raise ConversationConflict('original chat request changed')
                            return self._original(db,prior,scope,identity,command['operation_id'])
                    witness=db.execute('SELECT response FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,command['operation_id'])).fetchone()
                    if witness is not None:
                        if json.loads(witness['response']).get('chat_intent_version')==1:raise ConceptStorageUnavailable('original chat row lost')
                        raise ConversationConflict('operation already belongs to another own action')
                    if db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]>=4096:
                        raise ConceptStorageUnavailable('own operation capacity')
                    if snapshot['lifecycle']=='ARCHIVED' or snapshot['concept']['revision']!=command['expected_concept_revision']:
                        raise ConversationConflict('restore or reload idea before chatting')
                    if present and db.execute('SELECT count(*) FROM '+TABLE).fetchone()[0]>=256:
                        raise ConceptStorageUnavailable('chat original capacity')
                    mapping=self._mapping(snapshot,command,binding,peer_revision)
                    value={'state':'ORIGINAL_TURN_CAPTURED','binding':binding,'command':command,'peer_revision':peer_revision,'mapping':mapping}
                    raw=canonical(value)
                    if len(raw)>192000:raise ValueError('chat original byte capacity')
                    self._schema(db,write=True)
                    record_digest=digest(value)
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?,?,?,?,?,?)',(*scope,identity,command['operation_id'],key,raw.decode(),record_digest))
                    witness={'chat_intent_version':1,'concept_id':identity,'operation_id':command['operation_id'],'record_digest':record_digest}
                    db.execute('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',(*scope,command['operation_id'],key,canonical(witness).decode()))
                    return json.loads(raw)
            finally:db.close()

    def get(self,scope,identity,operation):
        with self.base.lock:
            db=self.concepts._connect()
            try:
                self.concepts.get(scope,identity)
                if self._schema(db):
                    row=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? AND operation_id=?',(*scope,identity,operation)).fetchone()
                    if row is not None:return self._original(db,row,scope,identity,operation)
                witness=db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=? AND json_extract(response,'$.chat_intent_version')=1",(*scope,operation)).fetchone()
                if witness is not None:raise ConceptStorageUnavailable('original chat row lost')
                raise FileNotFoundError('original chat request not found')
            finally:db.close()

    def list(self,scope,identity):
        with self.base.lock:
            db=self.concepts._connect()
            try:
                self.concepts.get(scope,identity)
                present=self._schema(db)
                rows=db.execute('SELECT * FROM '+TABLE+' WHERE actor_id=? AND context_id=? AND concept_id=? ORDER BY operation_id',(*scope,identity)).fetchall() if present else []
                result=[self._original(db,row,scope,identity,row['operation_id']) for row in rows]
                witnesses=db.execute("SELECT operation_id FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND json_extract(response,'$.chat_intent_version')=1 AND json_extract(response,'$.concept_id')=?",(*scope,identity)).fetchall()
                if {row['operation_id'] for row in witnesses}!={row['operation_id'] for row in rows}:raise ConceptStorageUnavailable('original chat rows lost')
                return result
            finally:db.close()
