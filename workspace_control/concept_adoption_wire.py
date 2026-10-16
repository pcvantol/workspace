"""Exact R55 schema and integrity checks; no rendering or source inference."""
import hashlib
import json
from pathlib import Path
from .advisory_contract import _check
from .concept_baseline_mapping import canonical
from .concept_baseline_wire import peer_digest,unique_object,path_safe,require
from .worklist_peer import WorklistError
CONTRACT='forge-ep-inspection-adoption-preview/v1'
KIND='ep-inspection-adoption-preview/1.0'
FORGE='cd483fd9b17a96d0deac0f0264ab6fc32c75e778'
EP='f3b56303b561a7193965f4aa41fd8da744a8c1c2'
SCHEMA=json.loads(Path(__file__).with_name('inspection-adoptions-v1.json').read_text())
PROPOSAL=json.loads(Path(__file__).with_name('inspection-adoption-proposal-v1.json').read_text())
MAXIMUM_BYTES=1100000

def check(value,kind):
    _check(value,SCHEMA['$defs'][kind],SCHEMA['$defs']);return value

def bound(value,binding,keys):
    if any(value[k]!=binding[k] for k in keys):raise WorklistError('DENIED')

def capability(value,binding):
    check(value,'Capability');bound(value,binding,('instance_id','principal_id','audience','pairing_id'))
    if binding['dossier_id'] not in value['dossier_ids']:raise WorklistError('DENIED')
    require(len(set(value['permissions']))==len(value['permissions']) and value['permissions']==binding['permissions'])
    require(value['limits']['per_dossier']==binding['maximum_records'])
    return value

def error(value,kind='error'):
    check(value,'Error')

def result(value,binding,original):
    try:
        check(value,'Response');bound(value,binding,('instance_id','principal_id','audience','dossier_id','pairing_id'))
        require(value['operation_id']==original['operation_id'] and value['request_digest']==peer_digest(original))
        packet=value['result']
        if value['state']=='PREPARING':require(packet is None);return value
        require(packet is not None and packet['input_digest']==peer_digest(original['input']))
        artifacts=packet['artifacts'];require(packet['result_digest']==peer_digest(artifacts))
        require({a['path'] for a in artifacts}=={'README.md','proposal.json'})
        for artifact in artifacts:
            require(hashlib.sha256(artifact['content'].encode()).hexdigest()==artifact['sha256'])
        proposal=json.loads(next(a['content'] for a in artifacts if a['path']=='proposal.json'),object_pairs_hook=unique_object)
        _check(proposal,PROPOSAL,{})
        require(proposal['proposal_digest']==peer_digest({k:v for k,v in proposal.items() if k!='proposal_digest'}))
        require(proposal['input_digest']==packet['input_digest'])
        require(proposal['source_observation']==packet['source_binding'])
        for item in proposal['entries']:
            path_safe(item['artifact_path'])
        return value
    except WorklistError:raise
    except (ValueError,KeyError,TypeError,UnicodeError,RecursionError):raise WorklistError('INVALID_RESPONSE') from None
