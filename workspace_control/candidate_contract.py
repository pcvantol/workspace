"""Pinned closed Candidate wire and independently verified consumer correlations."""
import json
import re
from pathlib import Path
from .advisory_contract import _check, digest, scope, _safe
from .review_peer import _id, _time
from .worklist_peer import WorklistError

CONTRACT = 'forge-advisory-candidate/v1'
SCHEMA = json.loads(Path(__file__).with_name('advisory-candidate-v1.json').read_text())

def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind], SCHEMA['$defs'])
    return value

def source(value, turn_id=None):
    validate(value, 'source')
    if turn_id is not None and value['turn_id'] != turn_id: raise WorklistError('INVALID_RESPONSE')
    if not all(_id(value[k]) for k in ('turn_id','session_id','invocation_id')): raise WorklistError('INVALID_RESPONSE')
    if not _safe(value['advice_summary']) or len({s['source_id'] for s in value['selected_sources']})!=len(value['selected_sources']): raise WorklistError('INVALID_RESPONSE')
    return value

def fields(value):
    validate(value, 'fields')
    texts=[value[k] for k in ('title','objective','business_value','engineering_value','architectural_value','rationale')]
    for k in ('scope','exclusions','acceptance_criteria','architecture_constraints','dependencies'):
        a=value[k]
        if len(set(a))!=len(a): raise WorklistError('INVALID_REQUEST')
        texts.extend(a)
    if not value['scope'] or not value['acceptance_criteria'] or any(len(t.strip())<20 for t in value['acceptance_criteria']) or not all(t.strip() and _safe(t) for t in texts): raise WorklistError('INVALID_REQUEST')
    p=value['effect_policy']
    reserved={'.git','.github','.codex','.agents','.engineering','.ssh','.aws','.env','.gitconfig','.gitattributes','.gitmodules','agents.md','secrets','credentials'}
    for k in ('read_paths','write_paths'):
        paths=p[k]
        if len({t.lower() for t in paths})!=len(paths):raise WorklistError('INVALID_REQUEST')
        for t in paths:
            parts=t.rstrip('/').split('/')
            if re.fullmatch(r'[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*/?',t) is None or any(x in ('','.', '..') or x.lower() in reserved or x.lower().startswith('.env.') or x.endswith('.') for x in parts):raise WorklistError('INVALID_REQUEST')
    delivery={'READ_ONLY_ASSESSMENT':('EVIDENCE_ONLY',),'DOCUMENTATION_ONLY':('GIT',),'ARCHITECTURE_DESIGN_ONLY':('EVIDENCE_ONLY','GIT'),'BOUNDED_REPOSITORY_CHANGE':('GIT',)}
    if p['delivery'] not in delivery[p['mode']] or not p['read_paths'] or (bool(p['write_paths']) != (p['delivery']=='GIT')):raise WorklistError('INVALID_REQUEST')
    if p['mode'] in ('DOCUMENTATION_ONLY','ARCHITECTURE_DESIGN_ONLY') and any(t.endswith('/') or not t.endswith(('.md','.txt','.rst','.adoc','.mmd','.puml')) for t in p['write_paths']):raise WorklistError('INVALID_REQUEST')
    return value

def bound(value,b,c,proposal=None):
    scope(value,b)
    if value['conversation_id']!=c or c!=b['conversation_id']: raise WorklistError('DENIED')
    if proposal is not None and (value['proposal_id']!=proposal or proposal not in b['proposal_ids']): raise WorklistError('DENIED')

def request(value,kind,b,c,proposal=None):
    try:
        validate(value,kind);bound(value,b,c,value['proposal_id'])
        for k in ('instance_id','project_id','repository_id','conversation_id','proposal_id'):
            if not _id(value[k]):raise WorklistError('INVALID_REQUEST')
        if proposal is not None and value['proposal_id']!=proposal:raise WorklistError('DENIED')
        if kind=='proposal_request':
            if not _id(value['turn_id']) or not 0<=value['expected_revision']<=7:raise WorklistError('INVALID_REQUEST')
            fields(value['fields'])
        elif not _id(value['operation_id']):raise WorklistError('INVALID_REQUEST')
    except WorklistError as error:
        if error.state=='DENIED':raise
        raise WorklistError('INVALID_REQUEST') from None
    return value

def proposal(value,b,c,p,revision=None):
    validate(value,'proposal');bound(value,b,c,p);source(value['source']);fields(value['fields'])
    if value['principal_reference']!=b['forge_instance_id']+':'+b['actor_id'] or revision is not None and value['proposal_revision']!=revision or digest({k:v for k,v in value.items() if k!='proposal_digest'})!=value['proposal_digest']:raise WorklistError('INVALID_RESPONSE')
    return value

def registration(value,b,c,p,expected=None):
    validate(value,'registration');r=value['original_receipt'];cur=value['current']
    if r['principal_reference']!=b['forge_instance_id']+':'+b['actor_id'] or r['registration_key']!=digest([r['principal_reference'],b['forge_project_id'],b['repository_id'],c,p,r['proposal_revision']]) or not _id(r['operation_id']) or not _time(r['registered_at']):raise WorklistError('INVALID_RESPONSE')
    source(r['source'])
    for subject in (r,cur):
        candidate=subject['candidate']
        if subject['candidate_digest']!=digest(candidate) or not all(_safe(candidate[k]) for k in ('title','objective')):raise WorklistError('INVALID_RESPONSE')
    if cur['candidate']['id']!=r['candidate']['id'] or cur['candidate']['recommendation_id']!=r['recommendation_id'] or r['candidate']['recommendation_id']!=r['recommendation_id']:raise WorklistError('INVALID_RESPONSE')
    if not _safe(r['rationale']):raise WorklistError('INVALID_RESPONSE')
    if expected is not None and (r['proposal_digest']!=expected['proposal_digest'] or r['proposal_revision']!=expected['proposal_revision'] or r['source']['context_revision']!=expected['context_revision']):raise WorklistError('INVALID_RESPONSE')
    return value

def correlate(value, proposal):
    r=value['original_receipt'];f=proposal['fields']
    expected={k:f[k] for k in ('title','objective','scope','acceptance_criteria','dependencies','effect_policy')}
    expected['architecture_constraints']=[*f['architecture_constraints'],*['EXCLUDED: '+x for x in f['exclusions']]]
    actual={k:v for k,v in r['candidate'].items() if k not in ('id','recommendation_id')}
    if r['proposal_digest']!=proposal['proposal_digest'] or r['proposal_revision']!=proposal['proposal_revision'] or r['source']!=proposal['source'] or r['rationale']!=f['rationale'] or actual!=expected:raise WorklistError('INVALID_RESPONSE')
    return value

def response(value,kind,b,c=None,p=None,revision=None,expected=None):
    validate(value,kind)
    if kind=='capability':
        bound(value,b,b['conversation_id'])
        if value['proposal_ids']!=b['proposal_ids'] or len(set(value['proposal_ids']))!=len(value['proposal_ids']) or value['maximum_registrations']!=b['maximum_registrations']:raise WorklistError('INVALID_RESPONSE')
    elif kind=='source_read':source(value['source'],p)
    elif kind in ('saved','preview'):
        d=proposal(value['proposal'],b,c,p,revision)
        if expected is not None and (any(d[k]!=expected[k] for k in ('instance_id','project_id','repository_id','conversation_id','proposal_id')) or d['fields']!=expected['fields'] or d['source']['turn_id']!=expected['turn_id'] or d['source']['conversation_revision']!=expected['expected_conversation_revision'] or d['source']['context_revision']!=expected['context_revision']):raise WorklistError('INVALID_RESPONSE')
        if kind=='preview':
            if value['latest_revision']<d['proposal_revision']:raise WorklistError('INVALID_RESPONSE')
            if value['registration'] is not None:
                registration(value['registration'],b,c,p,{'proposal_digest':d['proposal_digest'],'proposal_revision':d['proposal_revision'],'context_revision':d['source']['context_revision']});correlate(value['registration'],d)
    elif kind=='registration':registration(value,b,c,p,expected)
    elif expected is not None and value['operation_id']!=expected:raise WorklistError('INVALID_RESPONSE')
    return value
