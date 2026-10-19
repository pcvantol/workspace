"""Exact R56 consumer integrity checks; no rendering or execution authority."""
import hashlib
import json
from pathlib import Path
from .advisory_contract import _check
from .concept_baseline_mapping import canonical
from .concept_baseline_wire import require,peer_digest
from .worklist_peer import WorklistError

CONTRACT='forge-genesis-bootstrap-effect-plan/v1'
PROFILE='CREATE_GENESIS_LOCAL/1.0'
PURPOSE='GENESIS_BOOTSTRAP_EFFECT_ONLY/1.0'
SCHEMA=json.loads(Path(__file__).with_name('genesis-bootstrap-v1.json').read_text())
EFFECTS=SCHEMA['$defs']['PlanRequest']['properties']['effects']['const']
MAXIMUM_BYTES=1100000


def validate(value,kind):
    _check(value,SCHEMA['$defs'][kind],SCHEMA['$defs'])
    return value


def error(value,kind='error'):return validate(value,'ErrorResponse')


def capability(value,binding):
    validate(value,'Capability')
    if any(value[k]!=binding[k] for k in ('instance_id','principal_id','audience')) or binding['dossier_id'] not in value['dossier_ids']:raise WorklistError('DENIED')
    require(value['permissions']==binding['permissions'] and value['source_plan_ids']==binding['source_plan_ids'])
    return value


def request(value,kind):
    validate(value,'PlanRequest' if kind=='PLAN' else 'EffectRequest')
    require(len(canonical(value))<=65536)
    revision='plan' if kind=='PLAN' else 'decision'
    require(bool(value['previous_'+revision+'_id'])==(value['expected_'+revision+'_revision']>0))
    if kind=='PLAN':require(value['source_plan_id']==value['source_subject']['plan_id'])
    else:require(bool(value['reason'].strip()) and all(ord(c)>=32 or c in '\n\t' for c in value['reason']))
    return value


def plan(value,source,subject):
    validate(value,'Plan')
    require(value['plan_digest']==peer_digest({k:v for k,v in value.items() if k!='plan_digest'}))
    require(value['source_subject']==subject and value['documents']['bundle_digest']==source['result']['result_digest'])
    files=value['documents']['files'];original=source['result']['artifacts']
    require(len(files)==len(original)==37 and len({f['path'] for f in files})==37)
    for actual,expected in zip(files,original):
        raw=actual['content'].encode('utf-8')
        require({k:actual[k] for k in ('path','mode','sha256','content')}==expected)
        require(actual['bytes']==len(raw) and actual['sha256']==hashlib.sha256(raw).hexdigest() and actual['expected_before']=='ABSENT')
    return value


def response(value,binding,source,subject,*,expected=None,original_plan=None):
    validate(value,'Response')
    if any(value[k]!=binding[k] for k in ('instance_id','principal_id','audience','dossier_id')):raise WorklistError('DENIED')
    p=plan(value['plan'],source,subject)
    require(all(p[k]==binding[k] for k in ('instance_id','audience','dossier_id')))
    if original_plan is not None:require(p==original_plan)
    history=value['effect_history'];require(value['effect_decision_revision']==len(history) and len({d['decision_id'] for d in history})==len(history))
    previous=None
    for index,decision in enumerate(history,1):
        req={k:decision[k] for k in SCHEMA['$defs']['EffectRequest']['required']}
        request(req,'DECISION')
        require(decision['decision_revision']==index and req['expected_decision_revision']==index-1 and req['previous_decision_id']==previous)
        require(req['plan_id']==p['plan_id'] and req['plan_digest']==p['plan_digest'] and req['instance_id']==p['instance_id'] and req['dossier_id']==p['dossier_id'])
        require(decision['audience']==binding['audience'] and decision['principal_id']==decision['human_binding']['operator_id'])
        require(decision['request_digest']==peer_digest(req) and decision['decision_digest']==peer_digest({k:v for k,v in decision.items() if k!='decision_digest'}))
        previous=decision['decision_id']
    require(value['effect_decision_eligible']==(not value['inapplicability_reasons']))
    if value['effect_decision_currently_applicable']:require(value['effect_decision_eligible'] and bool(history) and history[-1]['decision']=='APPROVE_EFFECT')
    if expected is not None:
        kind='PLAN' if 'source_subject' in expected else 'DECISION';request(expected,kind)
        if kind=='PLAN':
            require(p['request_digest']==peer_digest(expected) and p['operation_id']==expected['operation_id'])
            require(p['source_subject']==expected['source_subject'] and all(p['target'][k]==v for k,v in expected['target'].items()))
            require(p['expires_at']==expected['expires_at'] and p['plan_revision']==expected['expected_plan_revision']+1 and p['previous_plan_id']==expected['previous_plan_id'])
        else:
            original=value['original_decision'];require(original is not None and original in history)
            require(all(original[k]==v for k,v in expected.items()) and original['principal_id']==binding['principal_id'] and original['grant_id']==binding['grant_id'] and original['human_binding']==binding['human_binding'])
    return value
