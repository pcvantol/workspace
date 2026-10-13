"""Pinned activity wire and cross-response identity; no cursor decoding or authority."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
from .advisory_contract import _check
from .worklist_peer import WorklistError

CONTRACT = 'forge-workset-activity/v1'
PIN = '989132660997909e74800ddc8648be11262be8d4'
SCHEMA = json.loads(Path(__file__).with_name('workset-activity-v1.json').read_text())
BASE = '/v1/approved-workset-activity'


def require(ok, state='INVALID_RESPONSE'):
    if not ok: raise WorklistError(state)


def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind], SCHEMA['$defs'])
    return value


def future(value):
    if not isinstance(value,str):return False
    try: return datetime.fromisoformat(value.replace('Z','+00:00')) > datetime.now(timezone.utc)
    except (TypeError, ValueError): return False


def capability(value, binding):
    validate(value, 'capability')
    require(value['scope'] == {k:binding[b] for k,b in [('instance_id','forge_instance_id'),('project_id','forge_project_id'),('repository_id','repository_id')]}, 'DENIED')
    require(value['worksets'] == binding['worksets'] and value['expires_at'] == binding['expires_at'], 'DENIED')
    require(len(value['worksets'])>0 and len({x['workset_id'] for x in value['worksets']})==len(value['worksets']))
    require(future(value['expires_at']), 'DENIED')
    require(value['supported'], 'UNSUPPORTED')
    return value


def event(value, workset):
    validate(value, 'event')
    reference=value['source_reference']
    require(reference['url'] == BASE+'/'+workset+'/events/'+value['event_id'])
    require((value['time_status']=='UNKNOWN') == (value['occurred_at'] is None))
    if value['occurred_at'] is not None:
        try: require(datetime.fromisoformat(value['occurred_at'].replace('Z','+00:00')).utcoffset() is not None)
        except ValueError: raise WorklistError('INVALID_RESPONSE') from None
    return value


def read(value, kind, binding, workset, identity=None):
    validate(value,kind);require(value['workset_id']==workset,'DENIED')
    events=value['events'] if kind=='page' else [value['event']]
    require(len({e['event_id'] for e in events})==len(events))
    for e in events:event(e,workset)
    if kind=='detail':
        require(value['event']['event_id']==identity,'DENIED');return value
    current=value['current'];scope=current['scope']
    subject=next((w for w in binding['worksets'] if w['workset_id']==workset),None)
    require(subject is not None,'DENIED')
    require(current['instance_id']==binding['forge_instance_id'] and current['installation_id']==binding['installation_id'] and scope['principal_id']==binding['actor_id'] and scope['workset_id']==workset and current['membership_revision']==subject['definition_digest'] and current['selector_revision']==subject['definition_digest'],'DENIED')
    from .worklist_contract import SNAPSHOT_FIELDS
    fields=SNAPSHOT_FIELDS + (('order_revision','order_digest','original_order','effective_order','order_blocking_reasons') if current['contract_version'].endswith('/v2') else ())
    digest='sha256:'+hashlib.sha256(json.dumps({k:current[k] for k in fields},sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    require(current['snapshot_revision']==digest)
    require(len({i['candidate_id'] for i in current['items']})==len(current['items']))
    require(bool(value['cursor']) and re.fullmatch(r'[A-Za-z0-9_.-]{1,32768}',value['cursor']) is not None)
    require(not value['has_more'] or bool(events))
    return value
