"""Owner-only finite Genesis pairings, separated from original content rights."""
from contextlib import contextmanager,ExitStack
from datetime import datetime,timezone,timedelta
import fcntl
import os
import re
import secrets
from .concept_baseline_peer import ConceptBaselinePeer
from .genesis_intents import GenesisIntents,BINDING
from .service import _private_json,_regular_private
from .worklist_peer import WorklistReadTransport,WorklistError
from .conversations import ConversationConflict
from .project_concept_library import ProjectConceptLibrary
from .advisory_http import request
from . import genesis_wire as wire

PREFIX='/v1/genesis-bootstrap'
PRODUCER_SOURCE='8ee60c8409b2c3801e70cf129f20f1ff1480d03b'
EXTRA={'endpoint','forge_token','expires_at','permissions','source_plan_ids','exact_plans','targets','kind'}


def timestamp(value):
    result=datetime.fromisoformat(value.replace('Z','+00:00'))
    if result.utcoffset() is None:raise ValueError('explicit finite timestamp required')
    return result


def opaque(value):return isinstance(value,str) and re.fullmatch('[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',value) is not None


class GenesisBinding(ConceptBaselinePeer):
    def __init__(self,root,root_fd,concepts,baselines,content):
        WorklistReadTransport.__init__(self,root,root_fd,namespace='genesis-bootstrap')
        self.concepts=concepts;self.baselines=baselines;self.content=content;self.intents=GenesisIntents(concepts)

    def descriptor(self,binding):return {k:binding[k] for k in BINDING}

    def _valid_record(self,value):
        try:
            if type(value) is not dict or set(value)!=BINDING|EXTRA or value['producer_source']!=PRODUCER_SOURCE:return False
            if any(not opaque(value[k]) for k in BINDING-{'human_binding','producer_source','actor_id','context_id'}):return False
            if any(not isinstance(value[k],str) or not 1<=len(value[k])<=120 or any(ord(c)<32 for c in value[k]) for k in ('actor_id','context_id')):return False
            if re.fullmatch('[0-9a-f]{32}',value['concept_id']) is None or re.fullmatch('[A-Za-z0-9_-]{64}',value['forge_token']) is None:return False
            from .forge_peer import _endpoint
            _endpoint(value['endpoint']);timestamp(value['expires_at'])
            permissions=value['permissions'];kind=value['kind']
            if kind not in ('PLAN','DECISION') or permissions!=sorted(set(permissions)) or 'READ' not in permissions or set(permissions)-({'READ','PREPARE'} if kind=='PLAN' else {'READ','DECIDE_EFFECT'}):return False
            if kind=='DECISION' and 'DECIDE_EFFECT' not in permissions:return False
            human=value['human_binding'];wire._check(human,wire.SCHEMA['$defs']['EffectDecision']['properties']['human_binding'],wire.SCHEMA['$defs'])
            if kind=='DECISION' and human['operator_id']!=value['principal_id']:return False
            sources=value['source_plan_ids'];plans=value['exact_plans'];targets=value['targets']
            if type(sources) is not list or not 1<=len(sources)<=8 or len(set(sources))!=len(sources) or not all(opaque(x) for x in sources):return False
            if type(plans) is not list or len(plans)>8 or bool(plans)!=(kind=='DECISION'):return False
            for p in plans:
                if set(p)!={'plan_id','plan_digest'} or not opaque(p['plan_id']) or re.fullmatch('[0-9a-f]{64}',p['plan_digest']) is None:return False
            if len({p['plan_id'] for p in plans})!=len(plans) or type(targets) is not list or len(targets)>8 or (kind=='DECISION' and targets):return False
            for t in targets:
                if set(t)!={'id','label','target','expires_at','blocking_open_points'} or not opaque(t['id']) or not isinstance(t['label'],str) or not 1<=len(t['label'])<=120 or any(ord(c)<32 for c in t['label']):return False
                if set(t['target'])!={'ep_instance_id','placement_ref','target_ref'} or not all(opaque(x) for x in t['target'].values()) or timestamp(t['expires_at'])>timestamp(value['expires_at']):return False
                if type(t['blocking_open_points']) is not list or len(t['blocking_open_points'])>32 or not all(isinstance(x,str) and 1<=len(x)<=1024 for x in t['blocking_open_points']):return False
            return len({t['id'] for t in targets})==len(targets)
        except (ValueError,TypeError,KeyError,WorklistError):return False

    def _bindings(self):
        try:document=_private_json(self.namespace+'-bindings.json',dir_fd=self.root_fd)
        except FileNotFoundError:
            try:_private_json(self.namespace+'-bindings-initialized.json',dir_fd=self.root_fd)
            except FileNotFoundError:return []
            raise WorklistError('INVALID_CONFIGURATION') from None
        except (ValueError,OSError,UnicodeError):raise WorklistError('INVALID_CONFIGURATION') from None
        if type(document) is not dict or set(document)!={'bindings'} or type(document['bindings']) is not list or len(document['bindings'])>100 or not all(self._valid_record(b) for b in document['bindings']):raise WorklistError('INVALID_CONFIGURATION')
        rows=document['bindings']
        if len({b['id'] for b in rows})!=len(rows):raise WorklistError('INVALID_CONFIGURATION')
        humans={}
        for b in rows:
            key=(b['instance_id'],b['principal_id'])
            if humans.setdefault(key,b['actor_id'])!=b['actor_id']:raise WorklistError('INVALID_CONFIGURATION')
        return rows

    def binding(self,scope,identity,*,kind='PLAN',plan=None,binding_id=None):
        source=self.baselines.binding(scope,identity)
        candidates=[b for b in self._bindings() if tuple(b[k] for k in ('actor_id','context_id','concept_id'))==(*scope,identity) and (b['id']==binding_id if binding_id is not None else b['kind']==kind and (kind=='PLAN' or plan in b['exact_plans']))]
        if len(candidates)!=1:raise WorklistError('DENIED')
        b=candidates[0]
        if timestamp(b['expires_at'])<=datetime.now(timezone.utc) or b['source_binding_id']!=source['id'] or b['source_principal_id']!=source['principal_id'] or any(b[k]!=source[k] for k in ('endpoint','instance_id','dossier_id','audience')):raise WorklistError('DENIED')
        return b

    def cap(self,binding,*,timeout=15,send_guard=None):
        if timestamp(binding['expires_at'])<=datetime.now(timezone.utc):raise WorklistError('DENIED')
        value=request(binding,'GET',PREFIX+'/capability',bootstrap_audience=binding['audience'],error_validator=wire.error,maximum_bytes=16384,timeout=timeout,absolute_timeout=True,send_guard=send_guard)
        return wire.capability(value,binding)

    def snapshot(self,draft,identity,expected=None,**selection):
        with self.concepts.authorized(draft) as scope:
            concept=ProjectConceptLibrary(self.concepts).read(scope,identity)
            b=self.binding(scope,identity,**({'binding_id':expected['id']} if expected is not None else selection))
            if expected is not None and b!=expected:raise WorklistError('DENIED')
            return scope,concept,b

    @contextmanager
    def _pairings_locked(self):
        first=self.baselines._locked()
        try:
            second=self._locked()
            try:yield
            finally:fcntl.flock(second,fcntl.LOCK_UN);os.close(second)
        finally:fcntl.flock(first,fcntl.LOCK_UN);os.close(first)

    @contextmanager
    def dispatch_guard(self,draft,identity,binding,revision=None):
        with self._pairings_locked(),ExitStack() as stack:
            scope=stack.enter_context(self.concepts.authorized(draft));current=ProjectConceptLibrary(self.concepts).read(scope,identity)
            if self.binding(scope,identity,binding_id=binding['id'])!=binding:raise WorklistError('DENIED')
            if revision is not None and (current['revision']!=revision or current['lifecycle']=='ARCHIVED'):raise ConversationConflict('concept changed before Genesis dispatch')
            yield

    def provision(self,config_file):
        config=_private_json(config_file)
        if set(config)!={'actor_id','context_id','concept_id','producer_source','receipt_file','token_file','targets','kind'} or config['producer_source']!=PRODUCER_SOURCE:raise ValueError('closed owner Genesis pairing required')
        if any(not os.path.isabs(config[k]) for k in ('receipt_file','token_file')):raise ValueError('private owner files required')
        scope=(config['actor_id'],config['context_id']);identity=config['concept_id'];self.concepts.get(scope,identity);source=self.baselines.binding(scope,identity)
        receipt=_private_json(config['receipt_file']);token=_regular_private(config['token_file']).strip()
        required={'grant_id','principal_id','instance_id','audience','proposal_principal_id','dossier_ids','source_plan_ids','permissions','exact_plans','purpose','human_binding','expires_at','state'}
        if set(receipt)!=required or receipt['state']!='ACTIVE' or receipt['purpose']!=wire.PURPOSE or source['dossier_id'] not in receipt['dossier_ids'] or receipt['proposal_principal_id']!=source['principal_id'] or any(receipt[k]!=source[k] for k in ('instance_id','audience')):raise PermissionError('separate exact Genesis receipt required')
        b={k:source[k] for k in ('actor_id','context_id','concept_id','endpoint','instance_id','audience','dossier_id')}
        b.update({k:receipt[k] for k in ('principal_id','grant_id','human_binding','expires_at','permissions','source_plan_ids','exact_plans')})
        b.update(id=secrets.token_hex(16),source_binding_id=source['id'],source_principal_id=source['principal_id'],forge_token=token,producer_source=PRODUCER_SOURCE,kind=config['kind'],targets=config['targets'])
        if not self._valid_record(b) or not datetime.now(timezone.utc)<timestamp(b['expires_at'])<=datetime.now(timezone.utc)+timedelta(days=30):raise ValueError('invalid finite Genesis pairing')
        self.cap(b)
        with self._pairings_locked():
            self.concepts.get(scope,identity)
            if self.baselines.binding(scope,identity)!=source:raise WorklistError('DENIED')
            rows=self._bindings()
            if len(rows)>=100 or any(tuple(x[k] for k in ('actor_id','context_id','concept_id','kind'))==(*scope,identity,b['kind']) and (b['kind']=='PLAN' or any(p in x['exact_plans'] for p in b['exact_plans'])) for x in rows):raise ConversationConflict('Genesis pairing already exists')
            if any(x['principal_id']==b['principal_id'] and x['instance_id']==b['instance_id'] and x['actor_id']!=b['actor_id'] for x in rows):raise PermissionError('human already mapped to another actor')
            self._write_bindings([*rows,b])
        return {'binding_id':b['id'],'concept_id':identity,'producer_source':PRODUCER_SOURCE,'kind':b['kind']}
