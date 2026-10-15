"""R54 HTTP decisions over exact original R52 bytes and separate human rights."""
from datetime import datetime,timezone,timedelta
import fcntl
import os
import re
import secrets
from contextlib import contextmanager,ExitStack
from .advisory_http import request
from .concept_baseline_peer import ConceptBaselinePeer
from .concept_baseline_mapping import digest
from .proposal_content_intents import ProposalContentIntents,BINDING,COMMAND
from .project_concept_library import ProjectConceptLibrary
from .service import _private_json,_regular_private
from .worklist_peer import WorklistReadTransport,WorklistError
from .conversations import ConversationConflict
from . import proposal_content_wire as wire

PREFIX='/v1/project-proposal-decisions'
CONTRACT='workspace-proposal-content-decision/1'
EXTRA={'endpoint','forge_token','expires_at','permissions','roles'}

class ProposalContentPeer(ConceptBaselinePeer):
    def __init__(self,root,root_fd,concepts,baselines):
        WorklistReadTransport.__init__(self,root,root_fd,namespace='proposal-content')
        self.concepts=concepts;self.baselines=baselines;self.intents=ProposalContentIntents(concepts)

    def descriptor(self,binding):return {k:binding[k] for k in BINDING}

    def _valid_record(self,value):
        try:
            if type(value) is not dict or set(value)!=BINDING|EXTRA:return False
            if any(not isinstance(value[k],str) or re.fullmatch('[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',value[k]) is None for k in BINDING-{'human_binding','producer_source','context_id','actor_id'}):return False
            if any(not isinstance(value[k],str) or not 1<=len(value[k])<=120 or any(ord(c)<32 for c in value[k]) for k in ('actor_id','context_id')):return False
            if re.fullmatch('[0-9a-f]{32}',value['concept_id']) is None or re.fullmatch('[0-9a-f]{40}',value['producer_source']) is None or re.fullmatch('[A-Za-z0-9_-]{64}',value['forge_token']) is None:return False
            from .forge_peer import _endpoint
            _endpoint(value['endpoint']);expiry=datetime.fromisoformat(value['expires_at'].replace('Z','+00:00'))
            if expiry.utcoffset() is None or value['permissions'] not in (['READ'],['DECIDE','READ']):return False
            roles=value['roles']
            if type(roles) is not list or roles!=sorted(set(roles)) or any(r not in wire.ROLES for r in roles) or bool(roles)!=('DECIDE' in value['permissions']):return False
            human=value['human_binding'];wire._check(human,wire.SCHEMA['$defs']['Decision']['properties']['human_binding'],wire.SCHEMA['$defs'])
            return human['operator_id']==value['principal_id']
        except (ValueError,TypeError,KeyError,WorklistError):return False

    def _bindings(self):
        rows=super()._bindings()
        humans={}
        for row in rows:
            key=(row['instance_id'],row['principal_id']);prior=humans.setdefault(key,row['actor_id'])
            if prior!=row['actor_id']:raise WorklistError('INVALID_CONFIGURATION')
        return rows

    def binding(self,scope,identity):
        binding=super().binding(scope,identity);source=self.baselines.binding(scope,identity)
        if any(binding[k]!=source[k] for k in ('endpoint','instance_id','dossier_id','audience','producer_source')) or binding['source_binding_id']!=source['id'] or binding['source_principal_id']!=source['principal_id']:raise WorklistError('DENIED')
        return binding

    def cap(self,binding,*,timeout=60,send_guard=None):
        if datetime.fromisoformat(binding['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise WorklistError('DENIED')
        value=request(binding,'GET',PREFIX+'/capability',content_audience=binding['audience'],error_validator=wire.error,maximum_bytes=16384,timeout=timeout,send_guard=send_guard)
        return wire.capability(value,binding)

    def provision(self,actor,context,identity,human_principal,receipt_file,token_file):
        # Explicit owner mapping, never inferred from a read token or chat role.
        scope=(actor,context);self.concepts.get(scope,identity);source=self.baselines.binding(scope,identity)
        if not all(os.path.isabs(p) for p in (receipt_file,token_file)):raise ValueError('private owner files required')
        receipt=_private_json(receipt_file);token=_regular_private(token_file).strip()
        required={'grant_id','principal_id','instance_id','audience','proposal_principal_id','dossier_ids','permissions','roles','profile_id','human_binding','expires_at','state'}
        if type(receipt) is not dict or set(receipt)!=required or receipt['state']!='ACTIVE' or receipt['profile_id']!=wire.PROFILE or receipt['principal_id']!=human_principal:raise ValueError('explicit human receipt required')
        if any(receipt[k]!=source[k] for k in ('instance_id','audience')) or source['dossier_id'] not in receipt['dossier_ids'] or receipt['proposal_principal_id']!=source['principal_id']:raise PermissionError('original proposal owner mismatch')
        binding={k:source[k] for k in ('actor_id','context_id','concept_id','endpoint','instance_id','audience','dossier_id','producer_source')}
        binding.update({k:receipt[k] for k in ('principal_id','grant_id','human_binding','expires_at','permissions','roles')})
        binding.update(id=secrets.token_hex(16),source_binding_id=source['id'],source_principal_id=source['principal_id'],forge_token=token)
        if not self._valid_record(binding):raise ValueError('invalid decision receipt')
        if datetime.fromisoformat(binding['expires_at'].replace('Z','+00:00'))>datetime.now(timezone.utc)+timedelta(days=30):raise ValueError('finite decision grant required')
        self.cap(binding)
        lock=self._locked()
        try:
            self.concepts.get(scope,identity)
            if self.baselines.binding(scope,identity)!=source:raise PermissionError('source pairing changed')
            rows=self._bindings()
            if len(rows)>=100 or any((b['actor_id'],b['context_id'],b['concept_id'])==(*scope,identity) for b in rows):raise ConversationConflict('decision pairing exists or capacity')
            if any(b['instance_id']==binding['instance_id'] and b['principal_id']==human_principal and b['actor_id']!=actor for b in rows):raise PermissionError('human already mapped to another actor')
            self._write_bindings([*rows,binding])
        finally:fcntl.flock(lock,fcntl.LOCK_UN);os.close(lock)
        return {'binding_id':binding['id'],'concept_id':identity,'producer_source':binding['producer_source']}

    @contextmanager
    def _pairings_locked(self):
        # Stable order: original source pairing, then human decision pairing.
        source_lock=self.baselines._locked()
        try:
            own_lock=self._locked()
            try:yield
            finally:fcntl.flock(own_lock,fcntl.LOCK_UN);os.close(own_lock)
        finally:fcntl.flock(source_lock,fcntl.LOCK_UN);os.close(source_lock)

    @contextmanager
    def dispatch_guard(self,draft,identity,binding):
        with self._pairings_locked(),ExitStack() as authority:
            try:
                scope=authority.enter_context(self.concepts.authorized(draft))
                self.concepts.get(scope,identity)
            except PermissionError:raise WorklistError('DENIED') from None
            if self.binding(scope,identity)!=binding:raise WorklistError('DENIED')
            yield

    @contextmanager
    def decision_guard(self,draft,identity,binding,revision):
        with self._pairings_locked(),ExitStack() as authority:
            try:
                scope=authority.enter_context(self.concepts.authorized(draft))
                current=ProjectConceptLibrary(self.concepts).read(scope,identity)
            except PermissionError:raise WorklistError('DENIED') from None
            if self.binding(scope,identity)!=binding:raise WorklistError('DENIED')
            if current['revision']!=revision or current['lifecycle']=='ARCHIVED':raise ConversationConflict('concept changed before decision send')
            yield

    def _call(self,draft,identity,binding,method,path,body=None,*,revision=None):
        return request(binding,method,PREFIX+path,body,content_audience=binding['audience'],error_validator=wire.error,maximum_bytes=wire.MAXIMUM_BYTES,send_guard=(lambda:self.dispatch_guard(draft,identity,binding)) if revision is None else (lambda:self.decision_guard(draft,identity,binding,revision)))

    def _source(self,draft,identity,binding,operation):
        scope,concept,_=self.snapshot(draft,identity,binding)
        source=self.baselines.binding(scope,identity)
        with self.dispatch_guard(draft,identity,binding):intent=self.baselines.intents.get(scope,identity,operation)
        if intent['binding']!=self.baselines.descriptor(source):raise WorklistError('DENIED')
        packet=self.baselines.fetch(source,intent,draft=draft,identity=identity)
        return concept,intent,wire.original_subject(packet,intent['request']),intent['request']['input']['product']['open_questions']

    def _envelope(self,draft,identity,binding,source_operation,value,source_revision):
        self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding));scope,current,_=self.snapshot(draft,identity,binding)
        selection=digest({'binding':self.descriptor(binding),'source_operation_id':source_operation,'current_revision':current['revision'],'subject':value['subject'],'decision_revision':value['decision_revision'],'previous_decision_id':value['history'][-1]['decision_id'] if value['history'] else None})
        with self.dispatch_guard(draft,identity,binding):local=self.intents.list(scope,identity)
        rejected=self.intents.rejections(scope,identity)
        pending=[{'operation_id':v['command']['operation_id'],'command':v['command']} for v in local if v['binding']==self.descriptor(binding) and v['command']['source_operation_id']==source_operation and v['request']['operation_id'] not in rejected and v['request']['operation_id'] not in {r['request']['operation_id'] for r in value['history']}]
        return {'contract_version':CONTRACT,'actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':binding['id'],'producer_source':binding['producer_source'],'source_operation_id':source_operation,'source_revision':source_revision,'current_revision':current['revision'],'selection_digest':selection,'permissions':binding['permissions'],'roles':binding['roles'],'expires_at':binding['expires_at'],'human_binding':binding['human_binding'],'pending_operations':pending,'rejected_operations':sorted(rejected),'decision':value}

    def read_proposal(self,draft,identity,source_operation,*,expected=None):
        _,_,binding=self.snapshot(draft,identity,expected);self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        _,intent,subject,points=self._source(draft,identity,binding,source_operation)
        value=self._call(draft,identity,binding,'GET','/proposals/'+subject['plan_id']+'?dossier_id='+binding['dossier_id'])
        wire.response(value,binding,subject,points)
        return self._envelope(draft,identity,binding,source_operation,value,intent['mapping']['source']['revision'])

    def read(self,draft,identity,operation,*,expected=None):
        scope,_,binding=self.snapshot(draft,identity,expected);self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        with self.dispatch_guard(draft,identity,binding):
            try:intent=self.intents.get(scope,identity,operation)
            except FileNotFoundError:raise WorklistError('CONTENT_OWN_INTENT_NOT_FOUND',http_status=404) from None
        if intent['binding']!=self.descriptor(binding):raise WorklistError('DENIED')
        _,source,subject,points=self._source(draft,identity,binding,intent['command']['source_operation_id'])
        if subject!=intent['request']['subject'] or points!=intent['open_points']:raise WorklistError('INVALID_RESPONSE')
        value=self._call(draft,identity,binding,'GET','/intents/'+operation+'?dossier_id='+binding['dossier_id'])
        wire.response(value,binding,subject,points,intent['request'])
        return self._envelope(draft,identity,binding,intent['command']['source_operation_id'],value,source['mapping']['source']['revision'])

    def decide(self,draft,identity,command,*,expected=None):
        if type(command) is not dict or set(command)!=COMMAND:raise ValueError('closed decision command required')
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))
        if 'DECIDE' not in cap['permissions'] or command['role'] not in cap['roles'] or concept['lifecycle']=='ARCHIVED':raise WorklistError('DENIED')
        with self.dispatch_guard(draft,identity,binding):
            try:intent=self.intents.get(scope,identity,command['operation_id'])
            except FileNotFoundError:intent=None
        if intent is None:
            current=self.read_proposal(draft,identity,command['source_operation_id'],expected=binding)
            if command['selection_digest']!=current['selection_digest'] or command['expected_concept_revision']!=current['current_revision'] or current['pending_operations']:raise ConversationConflict('reload exact proposal or recover original decision')
            value=current['decision'];history=value['history']
            if len(history)>=8:raise WorklistError('CONTENT_DECISION_CAPACITY',http_status=409)
            request_value={'contract_version':wire.CONTRACT,'instance_id':binding['instance_id'],'dossier_id':binding['dossier_id'],'operation_id':command['operation_id'],'plan_id':value['plan_id'],'subject':value['subject'],'profile_id':wire.PROFILE,'role':command['role'],'decision':command['decision'],'expected_decision_revision':value['decision_revision'],'previous_decision_id':history[-1]['decision_id'] if history else None,**{k:command[k] for k in ('reason','acknowledged_open_points')}}
            with self.dispatch_guard(draft,identity,binding):intent=self.intents.freeze(scope,identity,command,self.descriptor(binding),request_value,value['open_points'])
        elif intent['command']!=command or intent['binding']!=self.descriptor(binding):raise ConversationConflict('original decision changed')
        if command['operation_id'] in self.intents.rejections(scope,identity):raise ConversationConflict('original decision definitively rejected; review fresh proposal')
        # Recovery always asks for the original before any exact-original POST.
        try:return self.read(draft,identity,command['operation_id'],expected=binding)
        except WorklistError as error:
            if error.state!='CONTENT_NOT_FOUND' or getattr(error,'http_status',None)!=404:raise
        with self.dispatch_guard(draft,identity,binding):admitted=self.intents.admit_transport(scope,identity,command['operation_id'])
        if not admitted:raise ConversationConflict('review exact proposal again; original preserved')
        try:value=self._call(draft,identity,binding,'POST','/decisions',intent['request'],revision=command['expected_concept_revision'])
        except WorklistError as error:
            if error.state=='CONTENT_DECISION_STALE' and getattr(error,'http_status',None)==409:
                with self.dispatch_guard(draft,identity,binding):self.intents.reject(scope,identity,command['operation_id'])
            raise
        wire.response(value,binding,intent['request']['subject'],intent['open_points'],intent['request'])
        source=self.baselines.intents.get(scope,identity,command['source_operation_id'])
        return self._envelope(draft,identity,binding,command['source_operation_id'],value,source['mapping']['source']['revision'])
