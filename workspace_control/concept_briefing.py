"""Workspace briefing values, distinct from model advice and human approval.

This is an owning normalized shape, not a proposed Forge wire contract.
Only a trusted Server adapter may resolve a real authorized producer result.
"""
from .concept_baseline_mapping import digest, text

VERSION = 'workspace-concept-briefing/1'
FIELDS = {'name', 'purpose', 'users', 'non_goals', 'constraints', 'open_questions'}
TEXT_LIMITS = {'name': 120, 'purpose': 4096, 'users': 4096,
               'non_goals': 4096, 'constraints': 4096}


def validate(fields):
    if type(fields) is not dict or set(fields) != FIELDS:
        raise ValueError('invalid briefing fields')
    result = {key: text(fields[key], limit, blank=key != 'name')
              for key, limit in TEXT_LIMITS.items()}
    questions = fields['open_questions']
    if type(questions) is not list or len(questions) > 32:
        raise ValueError('invalid briefing questions')
    if len(questions) + sum(not result[key].strip() for key in ('purpose','users','non_goals','constraints')) > 32:
        raise ValueError('briefing and unknown questions exceed baseline capacity')
    result['open_questions'] = [text(value, 1024) for value in questions]
    if len(set(result['open_questions'])) != len(questions):
        raise ValueError('duplicate briefing question')
    return result


def initial(concept):
    # Long notes remain intact in the concept. A shorter purpose is an explicit
    # user choice in the existing baseline route, never a silent truncation.
    return validate({'name': concept['title'],
                     'purpose': concept['notes'] if len(concept['notes']) <= 4096 else '',
                     'users': '', 'non_goals': '', 'constraints': '',
                     'open_questions': []})


def source(concept, briefing):
    fields = validate(briefing)
    snapshot = {key: concept[key] for key in
                ('id', 'actor_id', 'context_id', 'revision', 'title', 'notes', 'state')}
    return {'briefing_version': VERSION, 'concept': snapshot, 'fields': fields,
            'source_digest': digest({'concept': snapshot, 'fields': fields})}


def changes(before, proposal):
    """Validate the complete displayed finite change set without inference."""
    before = validate(before)
    if type(proposal) is not list or not 1 <= len(proposal) <= len(FIELDS):
        raise ValueError('invalid briefing changes')
    result = dict(before)
    seen = set()
    for change in proposal:
        if type(change) is not dict or set(change) != {'field', 'before', 'after', 'reason'}:
            raise ValueError('invalid briefing change')
        field = change['field']
        if not isinstance(field, str) or field not in FIELDS or field in seen:
            raise ValueError('duplicate or unknown briefing field')
        seen.add(field)
        text(change['reason'], 2048)
        if change['before'] != before[field] or change['after'] == change['before']:
            raise ValueError('changed briefing before-context')
        result[field] = change['after']
    return validate(result)
