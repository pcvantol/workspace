"""Closed R54 contract projection; Forge alone owns content decision authority.

Source contract13cd5d2 is a candidate until the owning qualified handoff arrives.
No local approval or generation is performed by these integrity checks.
"""
import json
from pathlib import Path
from .advisory_contract import _check
from .concept_baseline_wire import require,peer_digest,unique_object
from .concept_baseline_mapping import canonical
from .worklist_peer import WorklistError

CONTRACT='forge-project-proposal-content-decision/v1'
PROFILE='CONTENT_BASELINE_ONLY/1.0'
ROLES=['BUSINESS','ARCHITECTURE']
SCHEMA=json.loads(Path(__file__).with_name('proposal-content-decision-v1.json').read_text())
MAXIMUM_BYTES=1100000

def validate(value,kind):
    _check(value,SCHEMA['$defs'][kind],SCHEMA['$defs'])
    return value

def error(value,kind='error'):validate(value,'ErrorResponse')

def capability(value,binding):
    validate(value,'Capability')
    if any(value[k]!=binding[k] for k in ('instance_id','principal_id','audience')) or binding['dossier_id'] not in value['dossier_ids']:raise WorklistError('DENIED')
    require(value['permissions']==binding['permissions'] and value['roles']==binding['roles'])
    require('READ' in value['permissions'] and bool(value['roles'])==('DECIDE' in value['permissions']) and len(set(value['roles']))==len(value['roles']))
    return value

def original_subject(packet,request):
    # packet has already passed the existing complete R52 wire validation.
    manifest=json.loads(next(a['content'] for a in packet['result']['artifacts'] if a['path']=='engineering/bootstrap-manifest.json'),object_pairs_hook=unique_object)
    return {'plan_id':packet['plan_id'],'proposal_principal_id':packet['principal_id'],'proposal_kind':packet['proposal_kind'],
            'input_digest':packet['result']['input_digest'],'result_digest':packet['result']['result_digest'],'record_digest':packet['record_digest'],
            'manifest_digest':manifest['manifest_digest'],'baseline':request['input']['baseline'],'profile_id':PROFILE,
            'source_references':request['input']['source_references'],'concept_revision':None}

def decision_request(value):
    validate(value,'Request');require(len(canonical(value)+b'\n')<=65536)
    require(value['subject']['plan_id']==value['plan_id'] and bool(value['previous_decision_id'])==(value['expected_decision_revision']>0))
    require(bool(value['reason'].strip()) and all(ord(c)>=32 or c in '\n\t' for c in value['reason']))
    return value

def response(value,binding,subject,open_points,expected=None):
    validate(value,'Response')
    if any(value[k]!=binding[k] for k in ('instance_id','principal_id','audience','dossier_id')):raise WorklistError('DENIED')
    require(value['plan_id']==subject['plan_id'] and value['subject']==subject and value['open_points']==open_points)
    history=value['history'];require(value['decision_revision']==len(history) and len({r['decision_id'] for r in history})==len(history))
    previous=None;latest={}
    for index,record in enumerate(history,1):
        request=decision_request(record['request'])
        require(record['revision']==index and request['expected_decision_revision']==index-1 and request['previous_decision_id']==previous)
        require(request['instance_id']==binding['instance_id'] and request['dossier_id']==binding['dossier_id'] and request['subject']==subject and request['plan_id']==subject['plan_id'])
        require(record['audience']==binding['audience'] and record['principal_id']==record['human_binding']['operator_id'] and record['request_digest']==peer_digest(request))
        require(request['acknowledged_open_points']==open_points if request['decision']=='APPROVE_CONTENT' else all(point in open_points for point in request['acknowledged_open_points']))
        previous=record['decision_id'];latest[request['role']]=request['decision']
    # Reject inconsistent producer projections; never persist this calculation as approval.
    projected='CHANGES_REQUESTED' if 'REQUEST_CHANGES' in latest.values() else 'CONTENT_APPROVED' if all(latest.get(role)=='APPROVE_CONTENT' for role in ROLES) else 'DECISION_NEEDED'
    require(value['state']==projected)
    original=value['original_decision']
    if expected is None:require(original is None)
    else:
        require(original is not None and original in history and original['request']==expected and original['principal_id']==binding['principal_id'])
        require(original['human_binding']==binding['human_binding'] and original['grant_id']==binding['grant_id'])
    return value
