"""Native Genesis plan/decision transport; Forge retains all decision authority."""
from datetime import datetime,timezone
from .genesis_binding import GenesisBinding,PREFIX,timestamp
from .genesis_intents import PLAN_COMMAND,DECISION_COMMAND
from .concept_baseline_mapping import digest
from .proposal_content_wire import original_subject
from .advisory_http import request
from .worklist_peer import WorklistError
from .conversations import ConversationConflict
from . import genesis_wire as wire

CONTRACT='workspace-genesis-plan-decision/1'

class GenesisPeer(GenesisBinding):
    def _call(self,draft,identity,binding,method,path,body=None,*,revision=None):
        return request(binding,method,PREFIX+path,body,bootstrap_audience=binding['audience'],error_validator=wire.error,maximum_bytes=wire.MAXIMUM_BYTES,timeout=15,absolute_timeout=True,send_guard=lambda:self.dispatch_guard(draft,identity,binding,revision))

    def _cap(self,draft,identity,binding):return self.cap(binding,send_guard=lambda:self.dispatch_guard(draft,identity,binding))

    def _source(self,draft,identity,binding,operation):
        scope,concept,_=self.snapshot(draft,identity,binding);source=self.baselines.binding(scope,identity)
        with self.dispatch_guard(draft,identity,binding):intent=self.baselines.intents.get(scope,identity,operation)
        if intent['binding']!=self.baselines.descriptor(source):raise WorklistError('DENIED')
        packet=self.baselines.fetch(source,intent,draft=draft,identity=identity)
        subject=original_subject(packet,intent['request'])
        if subject['plan_id'] not in binding['source_plan_ids']:raise WorklistError('DENIED')
        return concept,intent,packet,subject

    def _envelope(self,draft,identity,binding):
        self._cap(draft,identity,binding);scope,concept,_=self.snapshot(draft,identity,binding)
        return {'contract_version':CONTRACT,'actor_id':scope[0],'context_id':scope[1],'concept_id':identity,'binding_id':binding['id'],'producer_source':binding['producer_source'],'expires_at':binding['expires_at'],'current_revision':concept['revision']}

    def _read(self,draft,identity,binding,intent):
        if intent['binding']!=self.descriptor(binding):raise WorklistError('DENIED')
        _,source,packet,subject=self._source(draft,identity,binding,intent['command']['source_operation_id'])
        leaf='intents' if intent['kind']=='PLAN' else 'decision-intents'
        value=self._call(draft,identity,binding,'GET','/'+leaf+'/'+intent['command']['operation_id']+'?dossier_id='+binding['dossier_id'])
        wire.response(value,binding,packet,subject,expected=intent['request'])
        envelope=self._envelope(draft,identity,binding)
        return envelope|{'operation_id':intent['command']['operation_id'],'kind':intent['kind'],'source_operation_id':intent['command']['source_operation_id'],'source_revision':source['mapping']['source']['revision'],'result':value}

    def _records(self,draft,identity,binding,source_operation):
        scope,_,_=self.snapshot(draft,identity,binding)
        with self.dispatch_guard(draft,identity,binding):local=self.intents.list(scope,identity)
        return [v for v in local if v['command']['source_operation_id']==source_operation]

    def access(self,draft,identity,source_operation,*,expected=None):
        scope,concept,binding=self.snapshot(draft,identity,expected);self._cap(draft,identity,binding)
        _,source,packet,subject=self._source(draft,identity,binding,source_operation)
        content=self.content.read_proposal(draft,identity,source_operation)['decision']
        if content['subject']!=subject:raise WorklistError('INVALID_RESPONSE')
        records=self._records(draft,identity,binding,source_operation);plans=[];pending=[]
        for intent in records:
            if intent['kind']!='PLAN':continue
            try:plans.append(self._read(draft,identity,binding,intent))
            except WorklistError as error:
                if error.state!='GENESIS_NOT_FOUND' or error.http_status!=404:raise
                pending.append(intent['command']['operation_id'])
        latest=max(plans,key=lambda v:v['result']['plan']['plan_revision']) if plans else None
        target_list=[{'id':t['id'],'label':t['label']} for t in binding['targets'] if timestamp(t['expires_at'])>datetime.now(timezone.utc)]
        selection=digest({'binding':self.descriptor(binding),'source_operation_id':source_operation,'source_subject':subject,'source_revision':source['mapping']['source']['revision'],'current_revision':concept['revision'],'content_revision':content['decision_revision'],'targets':binding['targets'],'latest_plan_digest':latest['result']['plan']['plan_digest'] if latest else None})
        return self._envelope(draft,identity,binding)|{'source_operation_id':source_operation,'source_revision':source['mapping']['source']['revision'],'source_title':source['mapping']['source']['title'],'content':content,'selection_digest':selection,'targets':target_list,'can_plan':'PREPARE' in binding['permissions'] and concept['lifecycle']!='ARCHIVED' and source['mapping']['source']['revision']==concept['revision'] and bool(target_list) and not pending,'pending_plan_operations':pending,'plans':[{'operation_id':v['operation_id'],'plan_id':v['result']['plan']['plan_id'],'plan_revision':v['result']['plan']['plan_revision']} for v in plans],'latest':latest}

    def read(self,draft,identity,operation,*,expected=None):
        scope,_,binding=self.snapshot(draft,identity,expected)
        with self.dispatch_guard(draft,identity,binding):intent=self.intents.get(scope,identity,operation)
        actual=self.binding(scope,identity,binding_id=intent['binding']['id'])
        self._cap(draft,identity,actual)
        return self._read(draft,identity,actual,intent)

    def _recover_or_send(self,draft,identity,binding,intent):
        try:return self._read(draft,identity,binding,intent)
        except WorklistError as error:
            if error.state!='GENESIS_NOT_FOUND' or error.http_status!=404:raise
        scope,_,_=self.snapshot(draft,identity,binding)
        with self.dispatch_guard(draft,identity,binding,revision=intent['command']['expected_concept_revision']):admitted=self.intents.admit_transport(scope,identity,intent['command']['operation_id'])
        if not admitted:raise ConversationConflict('original dispatch uncertain; original reads only')
        leaf='/plans' if intent['kind']=='PLAN' else '/decisions'
        self._call(draft,identity,binding,'POST',leaf,intent['request'],revision=intent['command']['expected_concept_revision'])
        # Ordinary original GET, not a locally authoritative success flag.
        return self._read(draft,identity,binding,intent)

    def prepare(self,draft,identity,command,*,expected=None):
        if type(command) is not dict or set(command)!=PLAN_COMMAND:raise ValueError('closed Genesis plan command required')
        scope,concept,binding=self.snapshot(draft,identity,expected);cap=self._cap(draft,identity,binding)
        if 'PREPARE' not in cap['permissions']:raise WorklistError('DENIED')
        with self.dispatch_guard(draft,identity,binding):
            try:intent=self.intents.get(scope,identity,command['operation_id'])
            except FileNotFoundError:intent=None
        if intent is not None:
            if intent['command']!=command or intent['kind']!='PLAN':raise ConversationConflict('original Genesis plan changed')
            return self._recover_or_send(draft,identity,binding,intent)
        access=self.access(draft,identity,command['source_operation_id'],expected=binding)
        if command['selection_digest']!=access['selection_digest'] or command['expected_concept_revision']!=concept['revision'] or not access['can_plan']:raise ConversationConflict('reload original source and target selection')
        targets=[t for t in binding['targets'] if t['id']==command['target_id'] and timestamp(t['expires_at'])>datetime.now(timezone.utc)]
        if len(targets)!=1:raise ConversationConflict('configured target changed or expired')
        target=targets[0];prior=access['latest']['result']['plan'] if access['latest'] else None
        req={'contract_version':wire.CONTRACT,'instance_id':binding['instance_id'],'dossier_id':binding['dossier_id'],'operation_id':command['operation_id'],'source_plan_id':access['content']['subject']['plan_id'],'source_subject':access['content']['subject'],'expected_content_revision':access['content']['decision_revision'],'target':target['target'],'effects':wire.EFFECTS,'expires_at':target['expires_at'],'expected_plan_revision':prior['plan_revision'] if prior else 0,'previous_plan_id':prior['plan_id'] if prior else None,'blocking_open_points':target['blocking_open_points']}
        with self.dispatch_guard(draft,identity,binding,revision=concept['revision']):intent=self.intents.freeze(scope,identity,'PLAN',command,self.descriptor(binding),req)
        return self._recover_or_send(draft,identity,binding,intent)

    def decision_access(self,draft,identity,plan_operation):
        original=self.read(draft,identity,plan_operation);p=original['result']['plan'];scope,_,_=self.snapshot(draft,identity)
        try:b=self.binding(scope,identity,kind='DECISION',plan={'plan_id':p['plan_id'],'plan_digest':p['plan_digest']})
        except WorklistError as error:
            if error.state!='DENIED':raise
            return original|{'can_decide':False,'decision_access':'ACCESS_REQUIRED','selection_digest':None}
        self._cap(draft,identity,b)
        _,_,packet,subject=self._source(draft,identity,b,original['source_operation_id'])
        value=self._call(draft,identity,b,'GET','/plans/'+p['plan_id']+'?dossier_id='+b['dossier_id'])
        wire.response(value,b,packet,subject,original_plan=p)
        view=self._envelope(draft,identity,b)|{k:original[k] for k in ('operation_id','kind','source_operation_id','source_revision')}
        selection=digest({'binding':self.descriptor(b),'current_revision':view['current_revision'],'plan_digest':p['plan_digest'],'effect_decision_revision':value['effect_decision_revision'],'previous_decision_id':value['effect_history'][-1]['decision_id'] if value['effect_history'] else None,'eligible':value['effect_decision_eligible']})
        return view|{'result':value,'can_decide':view['current_revision']==view['source_revision'],'decision_access':'FINITE_EXACT_PLAN','selection_digest':selection}

    def decide(self,draft,identity,command,*,expected=None):
        if type(command) is not dict or set(command)!=DECISION_COMMAND:raise ValueError('closed explicit effect decision required')
        scope,_,_=self.snapshot(draft,identity,expected)
        try:intent=self.intents.get(scope,identity,command['operation_id'])
        except FileNotFoundError:intent=None
        if intent is not None:
            if intent['kind']!='DECISION' or intent['command']!=command:raise ConversationConflict('original effect decision changed')
            binding=self.binding(scope,identity,binding_id=intent['binding']['id']);self._cap(draft,identity,binding)
            return self._recover_or_send(draft,identity,binding,intent)
        view=self.decision_access(draft,identity,command['plan_operation_id'])
        if not view['can_decide']:raise WorklistError('DENIED')
        if command['source_operation_id']!=view['source_operation_id'] or command['expected_concept_revision']!=view['current_revision'] or command['selection_digest']!=view['selection_digest']:raise ConversationConflict('exact Genesis plan selection changed')
        value=view['result'];p=value['plan'];binding=self.binding(scope,identity,binding_id=view['binding_id'])
        if command['decision']=='APPROVE_EFFECT' and not value['effect_decision_eligible']:raise ConversationConflict('Genesis positive effect decision blocked')
        history=value['effect_history'];req={'contract_version':wire.CONTRACT,'instance_id':binding['instance_id'],'dossier_id':binding['dossier_id'],'operation_id':command['operation_id'],'plan_id':p['plan_id'],'plan_digest':p['plan_digest'],'purpose':wire.PURPOSE,'decision':command['decision'],'reason':command['reason'],'expected_decision_revision':value['effect_decision_revision'],'previous_decision_id':history[-1]['decision_id'] if history else None}
        with self.dispatch_guard(draft,identity,binding,revision=view['current_revision']):intent=self.intents.freeze(scope,identity,'DECISION',command,self.descriptor(binding),req)
        return self._recover_or_send(draft,identity,binding,intent)
