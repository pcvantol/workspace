"""Closed EP progress data projection; no phase engine or execution authority."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from .advisory_contract import _check
from .worklist_peer import WorklistError

SCHEMA_BYTES=Path(__file__).with_name('execution-progress-v1.json').read_bytes()
SCHEMA_SHA256='ac4ccc1c43c02742dc6ad15e642fadc6456844f8a1a3e7425275f67d247b7d89'
if hashlib.sha256(SCHEMA_BYTES).hexdigest()!=SCHEMA_SHA256:raise RuntimeError('progress schema projection changed')
SCHEMA=json.loads(SCHEMA_BYTES)
MAXIMUM_BYTES=524288
CANDIDATE_SOURCE='bc441c0f4825fc5de7f68b06feffcc97e53af6d5'
PRODUCER_VERSION='2.3.122'

class ProgressError(Exception):
    def __init__(self,code,status=503):self.code=code;self.status=status;super().__init__(code)

def require(condition,code='INVALID_RESPONSE',status=503):
    if not condition:raise ProgressError(code,status)

def identifier(value):
    require(isinstance(value,str) and re.fullmatch('[A-Za-z0-9][A-Za-z0-9._:-]{0,127}',value) is not None,'INVALID_REQUEST',400)
    return value

def snapshot(value):
    require(isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value) is not None,'INVALID_REQUEST',400)
    return value

def date(value):
    try:
        result=datetime.fromisoformat(value.replace('Z','+00:00'))
        require(result.utcoffset() is not None)
        return result
    except (ValueError,TypeError,AttributeError):raise ProgressError('INVALID_RESPONSE') from None

def validate(value,binding,mission,run=None,expected=None):
    try:_check(value,SCHEMA['oneOf'][0],{})
    except WorklistError:raise ProgressError('INVALID_RESPONSE') from None
    require(type(value['business_mutations']) is int and value['business_mutations']==0)
    require(value['producer_version']==PRODUCER_VERSION,'UNSUPPORTED',422)
    require(value['instance_id']==binding['instance_id'] and value['selection']==binding['selection'],'DENIED',403)
    require(value['selected_mission_id']==mission and value['selected_run_id']==run,'DENIED',403)
    require(value['completeness']==('EXACT_RUN' if run else 'COMPLETE_WITHIN_KNOWN_SCOPED_SUBMISSIONS'))
    if expected is not None:require(value['snapshot_id']==expected,'SNAPSHOT_CONFLICT',409)
    records=value['records'];seen=set();runs=set()
    if run is not None:require(len(records)==1,'INVALID_RESPONSE')
    for row in records:
        require(row['project_id']==binding['selection']['project_id'] and row['repository_id'] in binding['selection']['repository_ids'] and row['producer_id']==binding['producer_id'] and row['mission_id']==mission,'DENIED',403)
        require(row['submission_id'] not in seen);seen.add(row['submission_id'])
        if row['run_id'] is not None:
            require(row['run_id'] not in runs);runs.add(row['run_id'])
        if run is not None:require(row['run_id']==run,'DENIED',403)
        require(row['result']['qualification']['run_qualification']!='QUALIFIED' or row['result']['technical_outcome']=='COMPLETE')
        description=row['description']
        require((row['description_status']=='AVAILABLE')==(description is not None))
        if description is not None:
            require(not any(c in description for c in '/\\') and all(ord(c)>=32 for c in description) and re.search(r'bearer\s+|api[_-]?key\s*[:=]|password\s*[:=]|sk-[A-Za-z0-9]',description,re.I) is None,'UNSAFE_SOURCE')
    return value

def error(value,status):
    try:_check(value,SCHEMA['oneOf'][1],{})
    except WorklistError:raise ProgressError('INVALID_RESPONSE') from None
    code={400:'INVALID_REQUEST',401:'DENIED',403:'DENIED',404:'RUN_NOT_FOUND',409:'SNAPSHOT_CONFLICT',422:'UNSUPPORTED',500:'SOURCE_CORRUPT',503:'UNAVAILABLE'}.get(status)
    require(code is not None)
    if status==409:
        source=value['error']
        if source in ('PROGRESS_SNAPSHOT_CONFLICT','PROGRESS_SOURCE_CONFLICT'):code='SNAPSHOT_CONFLICT'
        elif source.endswith('_LIMIT'):code='UNAVAILABLE'
        elif source.endswith('_CONFLICT') or source=='PROGRESS_ROOT_UNAVAILABLE':code='SOURCE_CORRUPT'
        else:raise ProgressError('INVALID_RESPONSE')
    raise ProgressError(code,status)
