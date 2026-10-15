"""Scoped R53 HTTP consumer; reads and adoption never invoke a provider."""
from datetime import datetime, timezone
import fcntl
import os
import re
import secrets
from .advisory_http import request
from .concept_baseline_peer import ConceptBaselinePeer
from .concept_baseline_mapping import digest
from .concept_chat_intents import ConceptChatIntents, BINDING
from .concept_briefing_store import ConceptBriefingStore
from .concept_briefing import changes as check_changes
from .conversations import ConversationConflict
from .forge_peer import _endpoint
from .service import _private_json, _regular_private
from .worklist_peer import WorklistReadTransport, WorklistError
from . import concept_advisory_contract as wire

CONTRACT='workspace-concept-chat/1'
EXTRA={'endpoint','forge_token','expires_at','permissions','maximum_turns','maximum_tokens','maximum_seconds','provider_id','dossier_ids','conversation_ids'}


class ConceptChatPeer(ConceptBaselinePeer):
    def __init__(self,root,root_fd,concepts):
        WorklistReadTransport.__init__(self,root,root_fd,namespace='concept-chat')
        self.concepts=concepts;self.intents=ConceptChatIntents(concepts);self.briefings=ConceptBriefingStore(concepts)

    def descriptor(self,binding):
        return {k:binding[k] for k in BINDING}

    def _valid_record(self,value):
        try:
            if type(value) is not dict or set(value)!=BINDING|EXTRA:return False
            for key in BINDING-{'producer_source','transfer_policy_digest','actor_id','context_id'}:
                if not isinstance(value[key],str) or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',value[key]) is None:return False
            if any(not isinstance(value[k],str) or not 1<=len(value[k])<=120 or any(ord(c)<32 for c in value[k]) for k in ('actor_id','context_id')):return False
            if re.fullmatch('[0-9a-f]{32}',value['concept_id']) is None or re.fullmatch('[0-9a-f]{40}',value['producer_source']) is None:return False
            if re.fullmatch('sha256:[0-9a-f]{64}',value['transfer_policy_digest']) is None or re.fullmatch('[A-Za-z0-9_-]{64}',value['forge_token']) is None:return False
            _endpoint(value['endpoint'])
            if datetime.fromisoformat(value['expires_at'].replace('Z','+00:00')).utcoffset() is None:return False
            if value['permissions'] not in (['READ'],['ADVISE','READ']):return False
            for key,limit in [('maximum_turns',8),('maximum_tokens',384000),('maximum_seconds',960)]:
                if type(value[key]) is not int or not 1<=value[key]<=limit:return False
            for key,selected in [('dossier_ids','dossier_id'),('conversation_ids','conversation_id')]:
                rows=value[key]
                if type(rows) is not list or not 1<=len(rows)<=8 or not all(isinstance(v,str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',v) for v in rows) or len(rows)!=len(set(rows)) or value[selected] not in rows:return False
            return isinstance(value['provider_id'],str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',value['provider_id']) is not None
        except (ValueError,TypeError,KeyError):return False

    def _call(self,binding,method,path,body=None,*,draft=None,identity=None,timeout=60):
        return request(binding,method,path,body,concept_audience=binding['audience'],
                       error_validator=lambda value,_:wire.validate(value,'Error'),maximum_bytes=1000000,
                       timeout=timeout,send_guard=None if draft is None else lambda:self.dispatch_guard(draft,identity,binding))

    def cap(self,binding,*,timeout=60,send_guard=None):
        if datetime.fromisoformat(binding['expires_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc):raise WorklistError('DENIED')
        value=request(binding,'GET','/v1/concept-advisory/capability',concept_audience=binding['audience'],error_validator=lambda v,_:wire.validate(v,'Error'),maximum_bytes=16384,timeout=timeout,send_guard=send_guard)
        wire.validate(value,'Capability');wire.scope(value,binding,('instance_id','principal_id','audience'))
        for key in ('permissions','dossier_ids','conversation_ids'):
            if len(value[key])!=len(set(value[key])) or set(value[key])!=set(binding[key]):raise WorklistError('DENIED')
        for key in ('maximum_turns','maximum_tokens','maximum_seconds'):
            if value[key]!=binding[key]:raise WorklistError('DENIED')
        provider=value['provider']
        if provider['provider_id']!=binding['provider_id'] or provider['transfer_policy_digest']!=binding['transfer_policy_digest']:raise WorklistError('DENIED')
        if set(value['supported_languages'])!={'en','nl','de','fr','es'} or len(value['supported_languages'])!=5 or set(value['briefing_fields'])!={'name','purpose','users','non_goals','constraints','open_questions'} or len(value['briefing_fields'])!=6:raise WorklistError('INVALID_RESPONSE')
        return value

    def provision(self,actor,context,identity,endpoint,dossier,conversation,producer_source,receipt_file,token_file):
        self.concepts.get((actor,context),identity);_endpoint(endpoint)
        if not all(os.path.isabs(p) for p in (receipt_file,token_file)):raise ValueError('private owner files required')
        receipt=_private_json(receipt_file);token=_regular_private(token_file).strip()
        required={'grant_id','principal_id','instance_id','audience','dossier_ids','conversation_ids','permissions','maximum_turns','maximum_tokens','maximum_seconds','provider_id','transfer_policy_digest','expires_at','state'}
        if type(receipt) is not dict or set(receipt)!=required or receipt['state']!='ACTIVE':raise ValueError('invalid concept advice grant')
        value={'id':secrets.token_hex(16),'actor_id':actor,'context_id':context,'concept_id':identity,'endpoint':endpoint,'forge_token':token,'dossier_id':dossier,'conversation_id':conversation,'producer_source':producer_source}
        value.update({k:receipt[k] for k in (BINDING|EXTRA)-set(value)})
        if not self._valid_record(value):raise ValueError('invalid bounded advice pairing')
        self.cap(value)
        lock=self._locked()
        try:
            rows=self._bindings()
            if len(rows)>=100 or any((v['actor_id'],v['context_id'],v['concept_id'])==(actor,context,identity) for v in rows):raise ConversationConflict('advice pairing exists or capacity')
            self._write_bindings([*rows,value])
        finally:fcntl.flock(lock,fcntl.LOCK_UN);os.close(lock)
        return {'binding_id':value['id'],'concept_id':identity,'producer_source':producer_source}

    def _access(self,draft,identity,binding):
        return self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))

    def _history(self,draft,identity,binding):
        value=self._call(binding,'GET','/v1/concept-advisory/history?dossier_id='+binding['dossier_id']+'&conversation_id='+binding['conversation_id'],draft=draft,identity=identity)
        wire.response(value,'History',binding)
        if len(value['turns'])>binding['maximum_turns']:raise WorklistError('INVALID_RESPONSE')
        return value

    def access(self,draft,identity,*,expected=None):
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self._access(draft,identity,binding)
        result=self.envelope(draft,identity,binding)
        result.update(source_revision=concept['revision'],can_advise='ADVISE' in cap['permissions'] and cap['transfer_authorized'] and concept['lifecycle']!='ARCHIVED',expires_at=binding['expires_at'],maximum_turns=cap['maximum_turns'],maximum_tokens=cap['maximum_tokens'],maximum_seconds=cap['maximum_seconds'],provider=cap['provider'],transfer_authorized=cap['transfer_authorized'])
        return result

    def envelope(self,draft,identity,binding):
        scope,_,_=self.snapshot(draft,identity,binding)
        return {'contract_version':CONTRACT,'actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':binding['id'],'producer_source':binding['producer_source']}

    def history(self,draft,identity,*,expected=None):
        _,_,binding=self.snapshot(draft,identity,expected);self._access(draft,identity,binding)
        history=self._history(draft,identity,binding)
        scope,_,_=self.snapshot(draft,identity,binding)
        with self.dispatch_guard(draft,identity,binding):local=self.intents.list(scope,identity)
        known={v['request']['operation_id']:v for v in history['turns']}
        operations=[]
        for intent in local:
            if intent['binding']!=self.descriptor(binding):continue
            command=intent['command'];actual=known.get(command['operation_id'])
            if actual is not None and actual['request']!=intent['mapping']['request']:raise WorklistError('INVALID_RESPONSE')
            operations.append({'operation_id':command['operation_id'],'command':command,'state':actual['status'] if actual else 'PRODUCER_NOT_OBSERVED'})
        self._access(draft,identity,binding)
        return self.envelope(draft,identity,binding)|{'history':history,'local_operations':operations}

    def _original(self,draft,identity,binding,intent,history):
        r=intent['mapping']['request']
        value=self._call(binding,'GET','/v1/concept-advisory/intents/'+r['operation_id']+'?dossier_id='+binding['dossier_id']+'&conversation_id='+binding['conversation_id'],draft=draft,identity=identity)
        prior=[v for v in history['turns'] if v['revision']<=r['expected_revision']]
        wire.response(value,'TurnResponse',binding,expected=r,prior=prior)
        return value

    def read(self,draft,identity,operation,*,expected=None):
        scope,_,binding=self.snapshot(draft,identity,expected);self._access(draft,identity,binding)
        with self.dispatch_guard(draft,identity,binding):intent=self.intents.get(scope,identity,operation)
        if intent['binding']!=self.descriptor(binding):raise WorklistError('DENIED')
        history=self._history(draft,identity,binding)
        value=self._original(draft,identity,binding,intent,history)
        return self.publish(draft,identity,binding,intent,value)

    def send(self,draft,identity,command,*,expected=None):
        if type(command) is not dict:raise ValueError('closed chat command required')
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self._access(draft,identity,binding)
        if 'ADVISE' not in cap['permissions'] or not cap['transfer_authorized'] or concept['lifecycle']=='ARCHIVED':raise WorklistError('DENIED')
        history=self._history(draft,identity,binding)
        with self.dispatch_guard(draft,identity,binding):
            try:intent=self.intents.get(scope,identity,command.get('operation_id'))
            except FileNotFoundError:
                recorded={v['request']['operation_id'] for v in history['turns']}
                local=self.intents.list(scope,identity)
                if any(v['binding']==self.descriptor(binding) and v['command']['operation_id'] not in recorded for v in local) or any(v['status'] in ('PENDING','UNCERTAIN') for v in history['turns']):raise ConversationConflict('recover original turn before new advice')
                intent=self.intents.freeze(scope,identity,command,self.descriptor(binding),history['revision'])
            if intent['binding']!=self.descriptor(binding) or intent['command']!=command:raise ConversationConflict('original request changed')
        try:value=self._original(draft,identity,binding,intent,history)
        except WorklistError as error:
            if error.state!='CONCEPT_TURN_NOT_FOUND' or error.http_status!=404:raise
            if history['revision']!=intent['peer_revision'] or any(v['status'] in ('PENDING','UNCERTAIN') for v in history['turns']):raise ConversationConflict('original conversation changed')
            # Exactly one original POST; transport loss is resolved by authenticated
            # original reads. No catch/retry/new operation on ambiguous outcomes.
            value=self._call(binding,'POST','/v1/concept-advisory/turns',intent['mapping']['request'],draft=draft,identity=identity)
            wire.response(value,'TurnResponse',binding,expected=intent['mapping']['request'],prior=history['turns'])
        return self.publish(draft,identity,binding,intent,value)

    def publish(self,draft,identity,binding,intent,value):
        self._access(draft,identity,binding);result=self.envelope(draft,identity,binding)
        turn=value['original_turn'];proposal=None
        if turn['status']=='COMPLETE' and turn['outcome']['output']['changes']:
            fields=intent['mapping']['own_source']['fields'];mapped=[]
            for change in turn['outcome']['output']['changes']:
                after=change['proposed']
                if change['field']=='open_questions':after=after.split('\n')
                mapped.append({'field':change['field'],'before':fields[change['field']],'after':after,'reason':change['reason']})
            try:check_changes(fields,mapped);adoptable=True
            except ValueError:adoptable=False
            proposal={'source_digest':intent['mapping']['own_source_digest'],'changes':mapped,'displayed_change_digest':digest(mapped),'result_reference':intent['command']['operation_id'],'adoptable':adoptable}
        return result|{'operation_id':intent['command']['operation_id'],'source_revision':intent['command']['expected_concept_revision'],'turn':turn,'proposal':proposal}

    def adopt(self,draft,identity,command,*,expected=None):
        _,_,binding=self.snapshot(draft,identity,expected);self._access(draft,identity,binding)
        def resolve(scope,concept,reference):
            actual=self.read(draft,concept,reference,expected=binding)
            proposal=actual['proposal']
            if proposal is None or not proposal['adoptable']:raise ConversationConflict('no complete proposal')
            return {'source_digest':proposal['source_digest'],'changes':proposal['changes'],'producer_reference':{'producer_source':binding['producer_source'],'instance_id':binding['instance_id'],'dossier_id':binding['dossier_id'],'conversation_id':binding['conversation_id'],'operation_id':reference,'turn_id':actual['turn']['request']['turn_id'],'request_digest':actual['turn']['request_digest'],'result_digest':actual['turn']['outcome']['result_digest'],'qualification':'MODEL_SUGGESTION_USER_ACCEPTED_NOT_APPROVAL'}}
        result=self.briefings.adopt(draft,identity,command,resolve)
        self._access(draft,identity,binding);self.snapshot(draft,identity,binding)
        return result
