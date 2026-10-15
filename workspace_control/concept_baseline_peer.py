"""Actual R52 HTTP adapter; own actor/concept authority remains independent.

Only explicit local owner pairing reads a private finite peer receipt/token.
Ordinary product requests never issue grants or select a dossier/peer identity.
"""
from contextlib import contextmanager,ExitStack
from datetime import datetime,timezone
import os
import re
import secrets
import fcntl
from .advisory_http import request
from .forge_peer import _endpoint
from .review_peer import _id
from .service import _regular_private,_private_json
from .worklist_peer import WorklistReadTransport,WorklistError
from .concept_baseline_intents import ConceptBaselineIntents,BINDING
from .project_concept_library import ProjectConceptLibrary
from . import concept_baseline_wire as wire

FIELDS=BINDING|{'endpoint','forge_token','expires_at','permissions','maximum_records'}

class ConceptBaselinePeer(WorklistReadTransport):
    def __init__(self,root,root_fd,concepts):
        super().__init__(root,root_fd,namespace='concept-baseline');self.concepts=concepts;self.intents=ConceptBaselineIntents(concepts)

    def _valid_record(self,value):
        if type(value) is not dict or set(value)!=FIELDS:return False
        try:
            if not all(_id(value[k]) for k in ('id','actor_id','principal_id','instance_id','audience','dossier_id')) or re.fullmatch('[0-9a-f]{32}',value['concept_id']) is None or re.fullmatch('[0-9a-f]{40}',value['producer_source']) is None:return False
            if not isinstance(value['context_id'],str) or not 1<=len(value['context_id'])<=120 or not isinstance(value['forge_token'],str) or re.fullmatch('[A-Za-z0-9_-]{64}',value['forge_token']) is None:return False
            _endpoint(value['endpoint']);stamp=datetime.fromisoformat(value['expires_at'].replace('Z','+00:00'))
            if stamp.utcoffset() is None or value['permissions'] not in (['READ'],['PREPARE','READ']) or type(value['maximum_records']) is not int or not 1<=value['maximum_records']<=8:return False
            return True
        except (ValueError,TypeError,KeyError):return False

    def _bindings(self):
        try:document=_private_json(self.namespace+'-bindings.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            try:_private_json(self.namespace+'-bindings-initialized.json',dir_fd=self.root_fd)
            except FileNotFoundError:return []
            raise WorklistError('INVALID_CONFIGURATION') from None
        except (ValueError,OSError,UnicodeError):raise WorklistError('INVALID_CONFIGURATION') from None
        if type(document) is not dict or set(document)!={'bindings'} or type(document['bindings']) is not list or len(document['bindings'])>100 or not all(self._valid_record(b) for b in document['bindings']):raise WorklistError('INVALID_CONFIGURATION')
        rows=document['bindings']
        for key in (lambda b:b['id'],lambda b:(b['actor_id'],b['context_id'],b['concept_id'])):
            if len({key(b) for b in rows})!=len(rows):raise WorklistError('INVALID_CONFIGURATION')
        return rows

    def _write_bindings(self,rows):
        # A retained allocation marker forbids default-empty replacement after loss.
        try:_private_json(self.namespace+'-bindings-initialized.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            fd=os.open(self.namespace+'-bindings-initialized.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.root_fd)
            with os.fdopen(fd,'w') as stream:
                stream.write('{"schema_version":1}');stream.flush();os.fsync(stream.fileno())
            os.fsync(self.root_fd)
        super()._write_bindings(rows)

    @contextmanager
    def dispatch_guard(self,draft,identity,binding):
        descriptor=self._locked()
        try:
            with ExitStack() as authority:
                try:
                    scope=authority.enter_context(self.concepts.authorized(draft))
                    self.concepts.get(scope,identity)
                except PermissionError:raise WorklistError('DENIED') from None
                if self.binding(scope,identity)!=binding:raise WorklistError('DENIED')
                yield
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)

    def binding(self,scope,identity):
        for value in self._bindings():
            if (value['actor_id'],value['context_id'],value['concept_id'])==(*scope,identity):
                if datetime.fromisoformat(value['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise WorklistError('DENIED')
                return value
        raise WorklistError('DENIED')

    def descriptor(self,binding):return {k:binding[k] for k in BINDING}

    def cap(self,binding,*,timeout=60,send_guard=None):
        value=request(binding,'GET','/v1/onboarding/capability',error_validator=wire.error,maximum_bytes=16384,proposal_audience=binding['audience'],timeout=timeout,send_guard=send_guard)
        wire.capability(value,binding)
        if value['permissions']!=binding['permissions'] or value['limits']['records_per_dossier']!=binding['maximum_records']:raise WorklistError('DENIED')
        return value

    def snapshot(self,draft,identity,expected=None):
        with self.concepts.authorized(draft) as scope:
            concept=ProjectConceptLibrary(self.concepts).read(scope,identity);binding=self.binding(scope,identity)
            if expected is not None and binding!=expected:raise WorklistError('DENIED')
            return scope,concept,binding

    def access(self,draft,identity,*,expected=None):
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding));self.snapshot(draft,identity,binding)
        return {'contract_version':'workspace-concept-baseline/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':binding['id'],'producer_source':binding['producer_source'],'source_revision':concept['revision'],'document_language':'en','can_prepare':'PREPARE' in cap['permissions'] and concept['lifecycle']!='ARCHIVED','expires_at':binding['expires_at']}

    def provision(self,actor,context,identity,endpoint,dossier,producer_source,receipt_file,token_file):
        # CLI/owner only; no endpoint/receipt/grant fields in product requests.
        scope=(actor,context);self.concepts.get(scope,identity);_endpoint(endpoint)
        if not _id(dossier) or re.fullmatch('[0-9a-f]{40}',producer_source) is None or not all(os.path.isabs(p) for p in (receipt_file,token_file)):raise ValueError('invalid proposal pairing')
        receipt=_private_json(receipt_file);token=_regular_private(token_file).strip()
        if receipt['state']!='ACTIVE' or dossier not in receipt['dossier_ids'] or 'pb-render/1.0' not in receipt['kinds']:raise PermissionError('proposal receipt denied')
        binding={'id':secrets.token_hex(16),'actor_id':actor,'context_id':context,'concept_id':identity,'endpoint':endpoint,'forge_token':token,'instance_id':receipt['instance_id'],'principal_id':receipt['principal_id'],'audience':receipt['audience'],'dossier_id':dossier,'expires_at':receipt['expires_at'],'permissions':receipt['permissions'],'maximum_records':receipt['maximum_records'],'producer_source':producer_source}
        if not self._valid_record(binding):raise ValueError('invalid proposal receipt')
        self.cap(binding)
        if datetime.fromisoformat(binding['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise PermissionError('expired proposal receipt')
        descriptor=self._locked()
        try:
            rows=self._bindings()
            if len(rows)>=100 or any((b['actor_id'],b['context_id'],b['concept_id'])==(actor,context,identity) for b in rows):raise ValueError('proposal pairing conflict or capacity')
            self._write_bindings([*rows,binding])
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
        return {'binding_id':binding['id'],'concept_id':identity,'producer_source':producer_source}

    def revoke(self,identity):
        descriptor=self._locked()
        try:
            before=self._bindings();after=[b for b in before if b['id']!=identity]
            if len(after)==len(before):raise FileNotFoundError('proposal pairing not found')
            self._write_bindings(after)
        finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
        return {'binding_id':identity,'state':'REVOKED'}

    def fetch(self,binding,intent,*,prepare=False,draft=None,identity=None):
        target='/v1/onboarding/intents/'+intent['request']['operation_id']+'?dossier_id='+binding['dossier_id']
        try:value=request(binding,'GET',target,error_validator=wire.error,maximum_bytes=wire.MAXIMUM_BYTES,proposal_audience=binding['audience'],send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        except WorklistError as error:
            if error.state!='PROPOSAL_NOT_FOUND' or not prepare:raise
            value=request(binding,'POST','/v1/onboarding/plans',intent['request'],error_validator=wire.error,maximum_bytes=wire.MAXIMUM_BYTES,proposal_audience=binding['audience'],send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        return wire.result(value,binding,intent['request'])

    def history(self,draft,identity,*,expected=None):
        scope,_,binding=self.snapshot(draft,identity,expected);self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        with self.dispatch_guard(draft,identity,binding):
            intents=self.intents.list(scope,identity)
        return {'contract_version':'workspace-concept-baseline/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':binding['id'],'producer_source':binding['producer_source'],'operations':[{'operation_id':v['request']['operation_id'],'source_revision':v['mapping']['source']['revision']} for v in intents if v['binding']==self.descriptor(binding)]}

    def prepare(self,draft,identity,command,*,expected=None):
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        if 'PREPARE' not in cap['permissions'] or concept['lifecycle']=='ARCHIVED':raise WorklistError('DENIED')
        with self.concepts.authorized(draft) as current:
            if current!=scope or self.binding(scope,identity)!=binding:raise WorklistError('DENIED')
            intent=self.intents.freeze(scope,identity,command,self.descriptor(binding))
        # No own authority/pairing/SQLite lock spans the peer computation/wait.
        value=self.fetch(binding,intent,prepare=True,draft=draft,identity=identity)
        return self.publish(draft,identity,binding,intent,value)

    def read(self,draft,identity,operation,*,expected=None):
        scope,_,binding=self.snapshot(draft,identity,expected);self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        with self.concepts.authorized(draft) as current:
            if current!=scope:raise WorklistError('DENIED')
            intent=self.intents.get(scope,identity,operation)
        if intent['binding']!=self.descriptor(binding):raise WorklistError('DENIED')
        value=self.fetch(binding,intent,draft=draft,identity=identity)
        return self.publish(draft,identity,binding,intent,value)

    def publish(self,draft,identity,binding,intent,value):
        self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding));scope,current,_=self.snapshot(draft,identity,binding)
        return {'contract_version':'workspace-concept-baseline/1','actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'operation_id':intent['request']['operation_id'],'source_revision':intent['mapping']['source']['revision'],'current_revision':current['revision'],'source_digest':intent['mapping']['source_digest'],'producer_source':binding['producer_source'],'binding_id':binding['id'],'unknown_fields':intent['mapping']['unknown_fields'],'source_product':intent['mapping']['input']['product'],'proposal':value,'status':'PROPOSAL_PROJECT_NOT_CONFIGURED'}
