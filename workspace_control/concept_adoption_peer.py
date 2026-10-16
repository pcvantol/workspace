"""Finite owner-linked R55 consumer. All observed facts come only from original HTTP."""
from contextlib import contextmanager,ExitStack
from datetime import datetime,timezone
import fcntl,os,re,secrets,json,time
from .concept_baseline_peer import ConceptBaselinePeer
from .worklist_peer import WorklistReadTransport,WorklistError
from .service import _private_json,_regular_private
from .forge_peer import _endpoint
from .review_peer import _id
from .project_concept_library import ProjectConceptLibrary
from .concept_adoption_intents import ConceptAdoptionIntents,AdoptionArchivedRejected,BINDING
from .advisory_http import request
from . import concept_adoption_wire as wire
FIELDS=BINDING|{'endpoint','forge_token','expires_at','permissions','maximum_records','label'}

class ConceptAdoptionPeer(ConceptBaselinePeer):
    def __init__(self,root,root_fd,concepts):
        WorklistReadTransport.__init__(self,root,root_fd,namespace='concept-adoption');self.concepts=concepts;self.intents=ConceptAdoptionIntents(concepts)
    def _valid_record(self,v):
        try:
            if type(v) is not dict or set(v)!=FIELDS:return False
            if not all(_id(v[k]) for k in ('id','actor_id','principal_id','instance_id','audience','dossier_id','pairing_id')) or re.fullmatch('[0-9a-f]{32}',v['concept_id']) is None or v['producer_source']!=wire.FORGE:return False
            if not isinstance(v['context_id'],str) or not 1<=len(v['context_id'])<=120 or re.fullmatch('[A-Za-z0-9_-]{64}',v['forge_token']) is None:return False
            if not isinstance(v['label'],str) or not 1<=len(v['label'])<=120 or any(ord(c)<32 for c in v['label']):return False
            if type(v['identity']) is not dict or set(v['identity'])!={'status','project_id','repository_id','authority_repository_id','owner_reference'} or v['identity']['status'] not in ('PROVISIONAL_REFERENCE','OWNER_REGISTERED_REFERENCE') or v['identity']['authority_repository_id']!=v['identity']['repository_id']:return False
            if not isinstance(v['source_options'],list) or not 1<=len(v['source_options'])<=16 or len(set(v['source_options']))!=len(v['source_options']):return False
            for path in v['source_options']:
                wire.path_safe(path)
                if len(path)>256:return False
            for k in ('project_id','repository_id','authority_repository_id'):
                if not isinstance(v['identity'][k],str) or re.fullmatch('[a-z0-9][a-z0-9._-]{2,127}',v['identity'][k]) is None:return False
            owner=v['identity']['owner_reference']
            if not isinstance(owner,str) or not 1<=len(owner)<=256 or any(ord(c)<32 for c in owner):return False
            _endpoint(v['endpoint']);stamp=datetime.fromisoformat(v['expires_at'].replace('Z','+00:00'))
            return stamp.utcoffset() is not None and v['permissions'] in (['READ'],['PREPARE','READ']) and type(v['maximum_records']) is int and 1<=v['maximum_records']<=8
        except (KeyError,ValueError,TypeError,WorklistError):return False
    def _marker(self):
        try:value=_private_json(self.namespace+'-bindings-initialized.json',dir_fd=self.root_fd)
        except FileNotFoundError:return None
        except (OSError,ValueError,UnicodeError):raise WorklistError('INVALID_CONFIGURATION') from None
        if value!={'schema_version':1} or type(value.get('schema_version')) is not int:raise WorklistError('INVALID_CONFIGURATION')
        return value
    def _bindings(self):
        marker=self._marker()
        try:document=_private_json(self.namespace+'-bindings.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            if marker is None:return []
            raise WorklistError('INVALID_CONFIGURATION') from None
        except (OSError,ValueError,UnicodeError):raise WorklistError('INVALID_CONFIGURATION') from None
        if marker is None or type(document) is not dict or set(document)!={'bindings'} or type(document['bindings']) is not list or len(document['bindings'])>100 or not all(self._valid_record(b) for b in document['bindings']):raise WorklistError('INVALID_CONFIGURATION')
        rows=document['bindings']
        if len({b['id'] for b in rows})!=len(rows):raise WorklistError('INVALID_CONFIGURATION')
        return rows
    def _write_bindings(self,rows):
        # Validate both existing allocations before inherited atomic publication.
        # Only a genuinely pristine namespace may create its first marker.
        self._bindings()
        super()._write_bindings(rows)
    def _current(self,scope,identity,source):
        for b in self._bindings():
            if (b['actor_id'],b['context_id'],b['concept_id'],b['id'])==(*scope,identity,source):
                if datetime.fromisoformat(b['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise WorklistError('DENIED')
                return b
        raise WorklistError('DENIED')
    @contextmanager
    def dispatch_guard(self,draft,identity,binding):
        descriptor=self._locked()
        try:
            with ExitStack() as authority:
                try:
                    scope=authority.enter_context(self.concepts.authorized(draft));self.concepts.get(scope,identity)
                except PermissionError:raise WorklistError('DENIED') from None
                if self._current(scope,identity,binding['id'])!=binding:raise WorklistError('DENIED')
                yield
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
    def descriptor(self,binding):return {k:binding[k] for k in BINDING}
    def snapshot(self,draft,identity,source,expected=None):
        with self.concepts.authorized(draft) as scope:
            concept=ProjectConceptLibrary(self.concepts).read(scope,identity);binding=self._current(scope,identity,source)
            if expected is not None and binding!=expected:raise WorklistError('DENIED')
            return scope,concept,binding
    def _request(self,b,method,path,body=None,*,guard=None,timeout=15):
        return request(b,method,'/v1/inspection-adoptions/'+path,body,inspection_audience=b['audience'],error_validator=wire.error,maximum_bytes=wire.MAXIMUM_BYTES,send_guard=guard,timeout=timeout,success_statuses=(200,202),absolute_timeout=True)
    def cap(self,binding,*,timeout=15,send_guard=None):
        return wire.capability(self._request(binding,'GET','capability',guard=send_guard,timeout=timeout),binding)
    @contextmanager
    def sources_guard(self,draft,identity,value):
        descriptor=self._locked()
        try:
            with ExitStack() as authority:
                try:
                    scope=authority.enter_context(self.concepts.authorized(draft));self.concepts.get(scope,identity)
                except PermissionError:raise WorklistError('DENIED') from None
                rows=[b for b in self._bindings() if (b['actor_id'],b['context_id'],b['concept_id'])==(*scope,identity)]
                projected=[{'id':b['id'],'label':b['label'],'source_options':b['source_options'],'setup_metadata_not_observed':True,'can_prepare':'PREPARE' in b['permissions'],'expires_at':b['expires_at']} for b in rows]
                if projected!=value['sources'] or (value['actor_id'],value['context_id'])!=scope:raise WorklistError('DENIED')
                for b in rows:self._current(scope,identity,b['id'])
                yield
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
    def sources(self,draft,identity,timeout=3):
        with self.concepts.authorized(draft) as scope:
            self.concepts.get(scope,identity);rows=[b for b in self._bindings() if (b['actor_id'],b['context_id'],b['concept_id'])==(*scope,identity)]
        if len(rows)>8:raise WorklistError('INVALID_CONFIGURATION')
        values=[];deadline=time.monotonic()+timeout
        for b in rows:
            self.snapshot(draft,identity,b['id'],b)
            remaining=deadline-time.monotonic()
            if remaining<=0:raise WorklistError('UNAVAILABLE')
            self.cap(b,timeout=remaining,send_guard=lambda b=b:self.dispatch_guard(draft,identity,b))
            values.append({'id':b['id'],'label':b['label'],'source_options':b['source_options'],'setup_metadata_not_observed':True,'can_prepare':'PREPARE' in b['permissions'],'expires_at':b['expires_at']})
        with self.concepts.authorized(draft) as current:
            if current!=scope:raise WorklistError('DENIED')
            for b in rows:
                if self._current(scope,identity,b['id'])!=b:raise WorklistError('DENIED')
        return {'contract_version':'workspace-concept-adoption/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'sources':values}
    def access(self,draft,identity,source):
        scope,concept,b=self.snapshot(draft,identity,source);self.cap(b,send_guard=lambda:self.dispatch_guard(draft,identity,b))
        self.snapshot(draft,identity,source,b)
        return {'contract_version':'workspace-concept-adoption/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':b['id'],'producer_source':b['producer_source'],'source_revision':concept['revision'],'can_prepare':'PREPARE' in b['permissions'] and concept['lifecycle']!='ARCHIVED','expires_at':b['expires_at']}
    def provision(self,config_file):
        c=_private_json(config_file)
        if type(c) is not dict or set(c)!={'actor_id','context_id','concept_id','endpoint','dossier_id','label','identity','source_options','receipt_file','token_file'}:raise ValueError('closed owner pairing required')
        scope=(c['actor_id'],c['context_id']);self.concepts.get(scope,c['concept_id']);receipt=_private_json(c['receipt_file']);token=_regular_private(c['token_file']).strip()
        b={k:c[k] for k in ('actor_id','context_id','concept_id','endpoint','dossier_id','label','identity','source_options')}
        if receipt.get('state')!='ACTIVE' or c['dossier_id'] not in receipt['dossier_ids']:raise PermissionError('R55 grant scope denied')
        b.update({k:receipt[k] for k in ('instance_id','principal_id','audience','pairing_id','expires_at','permissions','maximum_records')});b.update(id=secrets.token_hex(16),forge_token=token,producer_source=wire.FORGE)
        if not self._valid_record(b):raise ValueError('invalid R55 pairing')
        self.cap(b)
        descriptor=self._locked()
        try:
            rows=self._bindings()
            if len(rows)>=100 or sum((r['actor_id'],r['context_id'],r['concept_id'])==(*scope,c['concept_id']) for r in rows)>=8:raise ValueError('pairing capacity')
            if datetime.fromisoformat(b['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise PermissionError('expired R55 grant')
            self._write_bindings([*rows,b])
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
        return {'binding_id':b['id'],'state':'OWNER_LINKED_SETUP_METADATA'}
    def history(self,draft,identity,source):
        scope,_,b=self.snapshot(draft,identity,source);self.cap(b,send_guard=lambda:self.dispatch_guard(draft,identity,b))
        with self.dispatch_guard(draft,identity,b):rows=self.intents.list(scope,identity)
        return {'operations':[{'operation_id':v['request']['operation_id'],'source_revision':v['mapping']['source']['revision']} for v in rows if v['binding']==self.descriptor(b)]}
    def fetch(self,draft,identity,b,intent,*,prepare=False,timeout=15):
        operation=intent['request']['operation_id'];guard=lambda:self.dispatch_guard(draft,identity,b)
        try:value=self._request(b,'GET','intents/'+operation+'?dossier_id='+b['dossier_id'],guard=guard,timeout=timeout)
        except WorklistError as error:
            if error.state!='INSPECTION_ADOPTION_NOT_FOUND' or getattr(error,'http_status',None)!=404 or not prepare:raise
            with guard():sent=self.intents.claim_dispatch((b['actor_id'],b['context_id']),identity,operation)
            if not sent:raise WorklistError('ADOPTION_ORIGINAL_PENDING') from None
            value=self._request(b,'POST','plans',intent['request'],guard=guard)
        return wire.result(value,b,intent['request'])
    def _publish(self,draft,identity,b,intent,value):
        scope,current,_=self.snapshot(draft,identity,b['id'],b);mapped=intent['mapping']
        proposal=None
        if value['result'] is not None:proposal=json.loads(next(a['content'] for a in value['result']['artifacts'] if a['path']=='proposal.json'))
        return {'contract_version':'workspace-concept-adoption/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':b['id'],'producer_source':wire.FORGE,'operation_id':intent['request']['operation_id'],'source_revision':mapped['source']['revision'],'current_revision':current['revision'],'source_digest':mapped['source_digest'],'proposal':value,'document':proposal}
    def prepare(self,draft,identity,source,command):
        scope,concept,b=self.snapshot(draft,identity,source);self.cap(b,send_guard=lambda:self.dispatch_guard(draft,identity,b))
        if 'PREPARE' not in b['permissions']:raise WorklistError('DENIED')
        if concept['lifecycle']=='ARCHIVED':
            # No permission or source boundary is loosened: never freeze/dispatch
            # on an archived source. Only an actual own original absence permits
            # the specific denied-before-capture receipt; prior/unknown remains DENIED.
            if not isinstance(command,dict) or not isinstance(command.get('operation_id'),str) or re.fullmatch('[0-9a-f]{32}',command['operation_id']) is None:raise ValueError('invalid operation')
            if type(command.get('expected_revision')) is not int or not 1<=command['expected_revision']<=concept['revision']:raise WorklistError('DENIED')
            with self.dispatch_guard(draft,identity,b):
                try:self.intents.get(scope,identity,command['operation_id'])
                except FileNotFoundError:raise AdoptionArchivedRejected('archived source denied before capture') from None
            raise WorklistError('DENIED')
        with self.dispatch_guard(draft,identity,b):intent=self.intents.freeze(scope,identity,command,self.descriptor(b))
        return self._publish(draft,identity,b,intent,self.fetch(draft,identity,b,intent,prepare=True))
    def read(self,draft,identity,source,operation,*,timeout=30):
        deadline=time.monotonic()+timeout
        scope,_,b=self.snapshot(draft,identity,source);self.cap(b,timeout=timeout,send_guard=lambda:self.dispatch_guard(draft,identity,b))
        with self.dispatch_guard(draft,identity,b):intent=self.intents.get(scope,identity,operation)
        if intent['binding']!=self.descriptor(b):raise WorklistError('DENIED')
        remaining=deadline-time.monotonic()
        if remaining<=0:raise WorklistError('UNAVAILABLE')
        value=self.fetch(draft,identity,b,intent,timeout=remaining)
        if time.monotonic()>=deadline:raise WorklistError('UNAVAILABLE')
        return self._publish(draft,identity,b,intent,value)
