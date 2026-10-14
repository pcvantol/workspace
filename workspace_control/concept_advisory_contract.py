"""Consumer checks for the exact R53 candidate schema, not producer authority.

Storage integrity is a producer-private seal. Only authenticated scoped HTTP
readback can supply authority; shape/hash checks never authenticate that seal.
"""
import json
from pathlib import Path
from .advisory_contract import _check, _safe
from .concept_advisory_mapping import CONTRACT, peer_digest
from .worklist_peer import WorklistError

SCHEMA = json.loads(Path(__file__).with_name('concept-advisory-v1.json').read_text())
SCOPE = ('instance_id', 'principal_id', 'audience', 'dossier_id', 'conversation_id')


def invalid():
    raise WorklistError('INVALID_RESPONSE')


def validate(value, kind):
    schema = SCHEMA['$defs'][kind]
    # Shared checker supports union-only schemas. This envelope additionally
    # requires the complete closed object AND exactly one transport discriminator.
    if kind == 'TurnResponse':
        _check(value, {k: v for k, v in schema.items() if k != 'oneOf'}, SCHEMA['$defs'])
        if ('recorded' in value) == ('read_only' in value):
            invalid()
    else:
        _check(value, schema, SCHEMA['$defs'])
    return value


def scope(value, binding, keys=SCOPE):
    if any(value[key] != binding[key] for key in keys):
        raise WorklistError('DENIED')


def request(value, binding):
    validate(value, 'Request')
    scope(value, binding, ('instance_id', 'dossier_id', 'conversation_id'))
    if (value['briefing']['concept_id'] != binding['concept_id'] or
            value['transfer_policy_digest'] != binding['transfer_policy_digest']):
        raise WorklistError('DENIED')
    texts = [value['message'], *value['briefing']['fields'].values()]
    if (value['briefing_digest'] != peer_digest(value['briefing']) or
            any(t is not None and (not t.strip() or not _safe(t)) for t in texts) or
            len(json.dumps(value, ensure_ascii=True).encode()) > 32768):
        invalid()
    return value


def turn(value, binding, prior=(), expected=None):
    validate(value, 'Turn')
    scope(value, binding, ('principal_id', 'audience'))
    r = request(value['request'], binding)
    if (value['request_digest'] != peer_digest(r) or
            value['revision'] != r['expected_revision'] + 1 or
            (expected is not None and r != expected)):
        invalid()
    refs = value['context']['evidence_references']
    required = {'briefing:' + r['briefing_digest'], 'turn:' + r['turn_id']}
    allowed = required | {'turn:' + t['request']['turn_id'] for t in prior if t['status'] == 'COMPLETE'}
    if len(refs) != len(set(refs)) or not required <= set(refs) <= allowed:
        invalid()
    outcome = value['outcome']
    if value['status'] == 'COMPLETE' and (outcome is None or outcome['output'] is None or
            outcome['execution'] != 'CONFIRMED' or outcome['error_code'] is not None):
        invalid()
    if outcome is None:
        return value
    output = outcome['output']
    if output is None:
        if outcome['result_digest'] is not None:
            invalid()
        return value
    if value['status'] != 'COMPLETE':
        invalid()
    for key in ('contract_version', 'briefing_digest', 'advisor_kind', 'language'):
        if output[key] != r[key]:
            invalid()
    if (output['request_digest'] != value['request_digest'] or
            outcome['result_digest'] != peer_digest(output) or
            len(json.dumps(output, ensure_ascii=True).encode()) > 32768):
        invalid()
    texts = [output['answer'], *output['questions'], *output['assumptions']]
    fields = set()
    for change in output['changes']:
        field = change['field']
        sources = change['references']
        if (field in fields or change['before'] != r['briefing']['fields'][field] or
                len(sources) != len(set(sources)) or not set(sources) <= set(refs)):
            invalid()
        fields.add(field)
        texts.extend((change['proposed'], change['reason']))
    if any(not text.strip() or not _safe(text) for text in texts):
        invalid()
    usage = outcome['usage']
    if usage is not None and any(usage[k + '_tokens'] > value['provider'][k + '_token_bound'] for k in ('input', 'output')):
        invalid()
    return value


def response(value, kind, binding, *, expected=None, prior=()):
    if kind not in ('Error', 'TurnResponse', 'History'):
        raise ValueError('unsupported consumer response kind')
    validate(value, kind)
    if kind == 'Error':
        return value
    scope(value, binding)
    if kind == 'TurnResponse':
        turn(value['original_turn'], binding, prior, expected)
    elif kind == 'History':
        turns = value['turns']
        if value['revision'] != len(turns):
            invalid()
        seen_operations, seen_turns = set(), set()
        for index, item in enumerate(turns):
            r = item['request']
            if (r['expected_revision'] != index or r['operation_id'] in seen_operations or
                    r['turn_id'] in seen_turns):
                invalid()
            turn(item, binding, turns[:index])
            seen_operations.add(r['operation_id']); seen_turns.add(r['turn_id'])
    return value
