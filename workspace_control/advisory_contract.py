"""Closed pinned advisory wire projection and consumer-owned provenance checks."""
from datetime import datetime
from hashlib import sha256
import json
from pathlib import Path
import re
from .worklist_peer import WorklistError

CONTRACT = 'forge-advisory-conversation/v1'
SCHEMA = json.loads(Path(__file__).with_name('advisory-conversation-v1.json').read_text())

def digest(value):
    return 'sha256:' + sha256(json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode()).hexdigest()

def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind])
    return value

def _check(value, schema, definitions=None):
    definitions = SCHEMA['$defs'] if definitions is None else definitions
    if '$ref' in schema: return _check(value, definitions[schema['$ref'].rsplit('/', 1)[1]], definitions)
    for union in ('oneOf', 'anyOf'):
        if union in schema:
            matches = 0
            for option in schema[union]:
                try: _check(value, option, definitions); matches += 1
                except WorklistError: pass
            if not matches or (union == 'oneOf' and matches != 1): raise WorklistError('INVALID_RESPONSE')
            return
    expected = schema.get('type')
    types = {'object': dict, 'array': list, 'string': str, 'integer': int, 'boolean': bool, 'null': type(None)}
    if expected and type(value) is not types[expected]: raise WorklistError('INVALID_RESPONSE')
    if 'const' in schema and (type(value) is not type(schema['const']) or value != schema['const']): raise WorklistError('INVALID_RESPONSE')
    if 'enum' in schema and value not in schema['enum']: raise WorklistError('INVALID_RESPONSE')
    if isinstance(value, dict):
        props = schema.get('properties', {})
        if not set(schema.get('required', [])) <= set(value) or (schema.get('additionalProperties') is False and not set(value) <= set(props)): raise WorklistError('INVALID_RESPONSE')
        for key, item in value.items(): _check(item, props.get(key, {}), definitions)
    elif isinstance(value, list):
        if not schema.get('minItems', 0) <= len(value) <= schema.get('maxItems', 64): raise WorklistError('INVALID_RESPONSE')
        for item in value: _check(item, schema.get('items', {}), definitions)
    elif isinstance(value, str):
        if not schema.get('minLength', 0) <= len(value) <= schema.get('maxLength', 4096): raise WorklistError('INVALID_RESPONSE')
        if 'pattern' in schema and re.fullmatch(schema['pattern'], value) is None: raise WorklistError('INVALID_RESPONSE')
        if schema.get('format') == 'date-time':
            try:
                if len(value) > 64 or datetime.fromisoformat(value.replace('Z', '+00:00')).utcoffset() is None: raise ValueError()
            except ValueError: raise WorklistError('INVALID_RESPONSE') from None
    elif type(value) is int and not schema.get('minimum', -(2**63)) <= value <= schema.get('maximum', 2**63-1): raise WorklistError('INVALID_RESPONSE')

def scope(value, binding):
    if any(value[k] != binding[b] for k,b in [('instance_id','forge_instance_id'),('project_id','forge_project_id'),('repository_id','repository_id')]): raise WorklistError('DENIED')

def request(value, binding, conversation):
    try:
        validate(value, 'request'); scope(value, binding)
        if value['conversation_id'] != conversation or conversation not in binding['conversation_ids']: raise WorklistError('DENIED')
        if len({s['source_id'] for s in value['selected_sources']}) != len(value['selected_sources']): raise WorklistError('INVALID_REQUEST')
    except WorklistError as error:
        if error.state == 'DENIED': raise
        raise WorklistError('INVALID_REQUEST') from None
    return value

def _safe(text):
    return (all(ord(c) >= 32 or c in '\n\t' for c in text) and
            '<' not in text and '>' not in text and not re.search(r'https?://[^/\s]+:[^/\s]+@|(?:bearer\s+|api[_-]?key\s*[:=]|password\s*[:=]|sk-[A-Za-z0-9])', text, re.I))

def turn(value, binding, conversation):
    validate(value, 'turn_record'); request(value['request'], binding, conversation)
    if value['request_digest'] != digest(value['request']): raise WorklistError('INVALID_RESPONSE')
    context=value['context']; scope(context,binding)
    if context['selected_sources'] != value['request']['selected_sources'] or digest(context) != value['request']['context_revision']: raise WorklistError('INVALID_RESPONSE')
    outcome=value['outcome']
    if outcome is not None:
        if outcome['execution'] != value['execution']: raise WorklistError('INVALID_RESPONSE')
        output=outcome['output']
        if output is not None:
            texts=[output['summary'], *output['alternatives'], *output['questions'], *output['suggestions'], *output['evidence_references']]
            if (output['request_digest'] != value['request_digest'] or output['advisor_kind'] != value['request']['advisor_kind'] or
                outcome['result_digest'] != digest(output) or not all(_safe(t) for t in texts) or
                not set(output['evidence_references']) <= set(context['evidence_references'])): raise WorklistError('INVALID_RESPONSE')
        if value['status'] == 'COMPLETE' and (output is None or outcome['execution'] != 'CONFIRMED' or outcome['error_code'] is not None or
            outcome['usage_status'] != 'OBSERVED' or outcome['usage'] is None or outcome['usage']['input_tokens'] > value['provider']['input_token_bound'] or outcome['usage']['output_tokens'] > value['provider']['output_token_bound']): raise WorklistError('INVALID_RESPONSE')
    elif value['status'] == 'COMPLETE': raise WorklistError('INVALID_RESPONSE')
    return value

def response(value, kind, binding, conversation=None, expected=None):
    validate(value,kind)
    if kind == 'capability':
        scope(value,binding);scope(value['context'],binding)
        if set(value['conversation_ids']) != set(binding['conversation_ids']) or value['context_revision'] != digest(value['context']): raise WorklistError('INVALID_RESPONSE')
    elif kind == 'history':
        scope(value['scope'],binding)
        if value['conversation_id'] != conversation: raise WorklistError('INVALID_RESPONSE')
        ids=[t['request']['turn_id'] for t in value['turns']]
        if len(set(ids)) != len(ids): raise WorklistError('INVALID_RESPONSE')
        for item in value['turns']: turn(item,binding,conversation)
    else:
        record=turn(value['original_turn'],binding,conversation)
        if expected is not None and record['request'] != expected: raise WorklistError('INVALID_RESPONSE')
        if value['current_revision'] < record['request']['expected_revision'] + 1: raise WorklistError('INVALID_RESPONSE')
    return value
