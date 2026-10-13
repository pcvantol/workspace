"""Consume the actual published R52 prepare/read candidate without a renderer.

The final qualified producer pin is owned by the trusted pairing, never inferred
from an arbitrary response or treated as positive capability by itself.
"""
import hashlib
import json
import re
from pathlib import Path,PurePosixPath
from .concept_baseline_mapping import canonical
from .advisory_contract import _check
from .worklist_peer import WorklistError

CONTRACT='forge-project-proposal-http/v1'
MAXIMUM_BYTES=1100000
MANIFEST=json.loads(Path(__file__).with_name('project-concept-baseline-manifest-v1.json').read_text())
RENDERER_PIN='a7a16db4d735d9411ff3a3c7997d8aff82be2d4b6f2059aa56bf250b7e104536'


def require(condition):
    if not condition:raise WorklistError('INVALID_RESPONSE')


def peer_digest(value):return hashlib.sha256(canonical(value)+b'\n').hexdigest()


def path_safe(value):
    require(isinstance(value,str) and 1<=len(value)<=512 and value.isascii() and all(ord(c)>=32 for c in value))
    path=PurePosixPath(value)
    require(not path.is_absolute() and str(path)==value and '\\' not in value and not any(part in ('.','..','.git') for part in path.parts))


def capability(value,binding):
    require(type(value) is dict and set(value)=={'contract_version','capability_id','support','instance_id','principal_id','audience','dossier_ids','permissions','proposal_kinds','limits','operations','decisions','apply','project_registration'})
    require(value['contract_version']==CONTRACT and value['capability_id']=='PROJECT_PROPOSAL_PREPARE_READ_V1' and value['support']=='SUPPORTED_PROPOSAL_ONLY')
    for key in ('instance_id','principal_id','audience'):
        if value[key]!=binding[key]:raise WorklistError('DENIED')
    require(type(value['dossier_ids']) is list and 1<=len(value['dossier_ids'])<=8 and len(set(value['dossier_ids']))==len(value['dossier_ids']))
    if binding['dossier_id'] not in value['dossier_ids']:raise WorklistError('DENIED')
    require(value['permissions'] in (['READ'],['PREPARE','READ']) and type(value['proposal_kinds']) is list and 'pb-render/1.0' in value['proposal_kinds'])
    require(all(kind in ('pb-render/1.0','pb-adoption-preview/1.0') for kind in value['proposal_kinds']))
    require(value['decisions'] is False and value['apply'] is False and value['project_registration'] is False)
    limits=value['limits'];require(type(limits) is dict and set(limits)=={'request_bytes','result_bytes','artifacts','records_per_dossier','global_records','store_bytes'})
    require(limits['request_bytes']==262144 and limits['result_bytes']==1048576 and limits['artifacts']==64 and type(limits['records_per_dossier']) is int and 1<=limits['records_per_dossier']<=8 and limits['global_records']==64 and limits['store_bytes']==16777216)
    expected=['GET /v1/onboarding/capability']+(['POST /v1/onboarding/plans'] if 'PREPARE' in value['permissions'] else [])+['GET /v1/onboarding/plans/{plan_id}?dossier_id={dossier_id}','GET /v1/onboarding/intents/{operation_id}?dossier_id={dossier_id}']
    require(value['operations']==expected)
    return value


def _result(value,binding,original_request):
    require(type(value) is dict and set(value)=={'contract_version','instance_id','principal_id','audience','dossier_id','operation_id','plan_id','proposal_kind','request_digest','record_digest','result','read_only_result','approval','registration'})
    require(value['contract_version']==CONTRACT and value['proposal_kind']=='pb-render/1.0' and value['read_only_result'] is True and value['approval']=='NOT_PERFORMED' and value['registration']=='NOT_PERFORMED')
    for key in ('instance_id','principal_id','audience','dossier_id'):
        if value[key]!=binding[key]:raise WorklistError('DENIED')
    require(value['operation_id']==original_request['operation_id'] and value['request_digest']==peer_digest(original_request))
    identity='proposal-'+peer_digest([binding['instance_id'],binding['principal_id'],binding['audience'],binding['dossier_id'],value['operation_id']])[:32]
    require(value['plan_id']==identity)
    packet=value['result'];require(type(packet) is dict and set(packet)=={'state','original_contract_version','input_digest','summary','artifacts','result_digest','observations','repository_quality'})
    require(packet['state']=='PROPOSED_NOT_APPROVED' and packet['original_contract_version']=='pb-render/1.0' and packet['input_digest']==peer_digest(original_request['input']) and packet['observations']=='SUPPLIED_UNVERIFIED' and packet['repository_quality']=='NOT_ASSESSED')
    require(isinstance(packet['summary'],str) and len(packet['summary'].encode())<=131072 and type(packet['artifacts']) is list and 1<=len(packet['artifacts'])<=64)
    require(packet['result_digest']==peer_digest(packet['artifacts']) and len(canonical(packet))+1<=1048576)
    inventory={}
    for artifact in packet['artifacts']:
        require(type(artifact) is dict and set(artifact)=={'path','mode','sha256','content'})
        path_safe(artifact['path']);require(artifact['mode']==420 and type(artifact['mode']) is int and isinstance(artifact['content'],str))
        raw=artifact['content'].encode();require(len(raw)<=131072 and hashlib.sha256(raw).hexdigest()==artifact['sha256'])
        require(artifact['path'] not in inventory);inventory[artifact['path']]=artifact
    require(list(inventory)==sorted(inventory) and 'engineering/bootstrap-manifest.json' in inventory)
    manifest=json.loads(inventory['engineering/bootstrap-manifest.json']['content']);_check(manifest,MANIFEST,{})
    require(manifest['input_digest']==packet['input_digest'] and manifest['renderer_source_digest']==RENDERER_PIN)
    require(manifest['manifest_digest']==peer_digest({k:v for k,v in manifest.items() if k!='manifest_digest'}))
    require({row['relative_path'] for row in manifest['artifacts']}==set(inventory)-{'engineering/bootstrap-manifest.json'})
    for row in manifest['artifacts']:
        item=inventory[row['relative_path']];require(row['expected_after_digest']==item['sha256'] and row['bytes']==len(item['content'].encode()) and row['input_digest']==packet['input_digest'])
    original={key:value[key] for key in ('plan_id','instance_id','principal_id','audience','dossier_id','operation_id','proposal_kind','request_digest')}
    original.update(input=original_request['input'],result=packet)
    require(value['record_digest']==peer_digest(original))
    return value


def error(value,kind='error'):
    require(type(value) is dict and set(value)=={'contract_version','error'} and value['contract_version']==CONTRACT and type(value['error']) is dict and set(value['error'])=={'code'})
    require(isinstance(value['error']['code'],str) and re.fullmatch('PROPOSAL_[A-Z_]{1,80}',value['error']['code']) is not None)


def result(value,binding,original_request):
    try:return _result(value,binding,original_request)
    except WorklistError:raise
    except (ValueError,TypeError,KeyError,UnicodeError,RecursionError):raise WorklistError('INVALID_RESPONSE') from None
