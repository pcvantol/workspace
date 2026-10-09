"""Closed producer concept preview; no approval authority from generated content."""
import json
from pathlib import Path
from .advisory_contract import _check, _safe, digest, scope
from .worklist_peer import WorklistError

CONTRACT = 'forge-chat-first-mission/v1'
SCHEMA = json.loads(Path(__file__).with_name('mission-concepts-v1.json').read_text())
LIST_FIELDS = ('scope', 'exclusions', 'acceptance_criteria', 'architecture_choices', 'risks', 'dependencies', 'questions')


def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind], SCHEMA['$defs'])
    return value


def definition(value, allowed_dependencies=None):
    validate({'contract_version': CONTRACT, 'request_digest': 'sha256:'+'0'*64, 'definition': value}, 'output')
    texts = [value[k] for k in ('title', 'objective', 'business_value', 'expected_result', 'change_summary')]
    for key in LIST_FIELDS:
        if len(value[key]) != len(set(value[key])):
            raise WorklistError('INVALID_RESPONSE')
        texts.extend(value[key])
    if not all(text.strip() and _safe(text) for text in texts):
        raise WorklistError('INVALID_RESPONSE')
    if allowed_dependencies is not None and not set(value['dependencies']) <= set(allowed_dependencies):
        raise WorklistError('INVALID_RESPONSE')
    if (not value['scope'] or not value['acceptance_criteria'] or any(len(t.strip()) < 20 for t in value['acceptance_criteria'])) and not value['questions']:
        raise WorklistError('INVALID_RESPONSE')
    return value


def request(value, binding, conversation):
    try:
        validate(value, 'request'); scope(value, binding)
        if conversation not in binding['conversation_ids'] or value['conversation_id'] != conversation:
            raise WorklistError('DENIED')
        if len({s['source_id'] for s in value['selected_sources']}) != len(value['selected_sources']):
            raise WorklistError('INVALID_REQUEST')
    except WorklistError as error:
        if error.state == 'DENIED':
            raise
        raise WorklistError('INVALID_REQUEST') from None
    return value


def turn(value, binding, conversation):
    validate(value, 'turn_record'); request(value['request'], binding, conversation)
    context = value['context']; scope(context, binding)
    if digest(value['request']) != value['request_digest'] or digest(context) != value['request']['context_revision'] or context['selected_sources'] != value['request']['selected_sources']:
        raise WorklistError('INVALID_RESPONSE')
    outcome = value['outcome']
    if outcome is not None:
        if outcome['execution'] != value['execution']:
            raise WorklistError('INVALID_RESPONSE')
        output = outcome['output']
        if output is not None:
            definition(output['definition'], context['concept_dependency_references'])
            if output['request_digest'] != value['request_digest'] or digest(output) != outcome['result_digest']:
                raise WorklistError('INVALID_RESPONSE')
        if value['status'] == 'COMPLETE' and (output is None or outcome['execution'] != 'CONFIRMED' or outcome['error_code'] is not None or outcome['usage_status'] != 'OBSERVED' or outcome['usage'] is None or outcome['usage']['input_tokens'] > value['provider']['input_token_bound'] or outcome['usage']['output_tokens'] > value['provider']['output_token_bound']):
            raise WorklistError('INVALID_RESPONSE')
    elif value['status'] == 'COMPLETE':
        raise WorklistError('INVALID_RESPONSE')
    return value


def response(value, kind, binding, conversation=None, expected=None, *, cursor=0, snapshot=None):
    validate(value, kind)
    if kind == 'capability':
        scope(value, binding); scope(value['context'], binding)
        if set(value['conversation_ids']) != set(binding['conversation_ids']) or digest(value['context']) != value['context_revision']:
            raise WorklistError('INVALID_RESPONSE')
    elif kind == 'history':
        scope(value['scope'], binding)
        if value['conversation_id'] != conversation or len({t['request']['turn_id'] for t in value['turns']}) != len(value['turns']):
            raise WorklistError('INVALID_RESPONSE')
        for record in value['turns']:
            turn(record, binding, conversation)
    elif kind == 'catalog':
        scope(value['scope'], binding)
        if snapshot is not None and snapshot != value['snapshot_revision'] or len({i['object_id'] for i in value['items']}) != len(value['items']):
            raise WorklistError('INVALID_RESPONSE')
        for item in value['items']:
            definition(item['definition'])
            if (item['conversation_id'] not in binding['conversation_ids'] or digest(item['definition']) != item['definition_digest'] or item['title'] != item['definition']['title'] or item['summary'] != item['definition']['expected_result'] or item['questions'] != item['definition']['questions'] or item['revision'] > item['conversation_revision']):
                raise WorklistError('INVALID_RESPONSE')
        if value['next_cursor'] is not None and value['next_cursor'] != cursor + len(value['items']):
            raise WorklistError('INVALID_RESPONSE')
        if cursor == 0 and value['next_cursor'] is None and digest(value['items']) != value['snapshot_revision']:
            raise WorklistError('INVALID_RESPONSE')
    else:
        record = turn(value['original_turn'], binding, conversation)
        if expected is not None and record['request'] != expected or value['current_revision'] < record['request']['expected_revision'] + 1:
            raise WorklistError('INVALID_RESPONSE')
    return value


def frozen_package(value, binding, conversation, *, expected_digest=None):
    validate(value, 'frozen_package');source=value['source'];scope(source,binding)
    if conversation not in binding['conversation_ids'] or source['conversation_id'] != conversation:
        raise WorklistError('DENIED')
    principal=binding['forge_instance_id']+':'+binding['actor_id']
    if value['authority']['principal_reference'] != principal or expected_digest is not None and digest(value) != expected_digest:
        raise WorklistError('INVALID_RESPONSE')
    d=definition(value['definition']);candidate=value['candidate'];preview=value['mission_preview'];planning=value['planning'];effects=value['consequences']
    if (digest(candidate) != value['subject_revision'] or candidate['title'] != d['title'] or candidate['objective'] != d['objective'] or
        set(candidate['acceptance_criteria']) != set(d['acceptance_criteria']) or set(candidate['dependencies']) != set(d['dependencies']) or
        not {'EXCLUDED: '+item for item in d['exclusions']} <= set(candidate['architecture_constraints']) or
        effects['repository_effect'] != candidate['effect_policy'] or effects['exclusions'] != d['exclusions'] or effects['risks'] != d['risks'] or
        preview['candidate_id'] != candidate['id'] or preview['title'] != candidate['title'] or preview['business_value'] != d['business_value'] or
        digest(preview) != planning['mission_spec_digest'] or planning['provenance_revision'] != value['subject_revision'] or
        planning['effect_policy'] != candidate['effect_policy'] or planning['human_gates'] != effects['human_gates']):
        raise WorklistError('INVALID_RESPONSE')
    return value


def prepared(value, binding, conversation, *, revision=None, expected_definition=None):
    validate(value, 'prepared_complete' if value.get('package') is not None else 'prepared_incomplete')
    definition(value['definition'])
    if revision is not None and value['revision'] != revision or expected_definition is not None and value['definition'] != expected_definition:
        raise WorklistError('INVALID_RESPONSE')
    if value['package'] is not None:
        package=frozen_package(value['package'],binding,conversation,expected_digest=value['package_digest'])
        if package['definition'] != value['definition'] or package['source']['revision'] != value['revision'] or package['source']['object_id'] != value['object_id']:
            raise WorklistError('INVALID_RESPONSE')
    return value


def compound(value, binding, conversation, *, expected_digest=None, operation=None, frozen=None):
    response_kind='compound_operation' if 'frozen_package' in value else 'compound_result'
    validate(value,response_kind)
    package=frozen_package(value['frozen_package'] if response_kind=='compound_operation' else frozen,binding,conversation,expected_digest=value['package_digest'])
    if expected_digest is not None and value['package_digest'] != expected_digest or operation is not None and value['operation_id'] != operation:
        raise WorklistError('INVALID_RESPONSE')
    original=value['original_registration'];candidate=package['candidate'];authority=package['authority']
    if original is not None and (original['candidate'] != candidate or original['source'] != package['source'] or original['principal_reference'] != authority['principal_reference'] or original['candidate_digest'] != digest(candidate)):
        raise WorklistError('INVALID_RESPONSE')
    decisions=[]
    for key,kind in [('business_decision','BUSINESS'),('architecture_decision','ARCHITECTURE')]:
        decision=value[key]
        if decision is None:continue
        if (decision['kind'] != kind or decision['candidate_id'] != candidate['id'] or decision['subject_revision'] != package['subject_revision'] or
            decision['principal_reference'] != authority['principal_reference'] or decision['operator_id'] != authority['signer']['operator_id'] or
            decision['installation_id'] != authority['signer']['installation_id'] or decision['operator_binding_version'] != authority['signer']['operator_binding_version'] or
            digest(decision['canonical_decision']) != decision['canonical_decision_digest'] or digest(decision['lifecycle_evidence']) != decision['lifecycle_evidence_digest']):
            raise WorklistError('INVALID_RESPONSE')
        decisions.append(decision['decision_id'])
    if len(decisions) != len(set(decisions)) or value['candidate_id'] != candidate['id']:
        raise WorklistError('INVALID_RESPONSE')
    complete=response_kind=='compound_result' or value['state']=='COMPLETE'
    if complete and (original is None or len(decisions)!=2 or value['mission_id'] is None):
        raise WorklistError('INVALID_RESPONSE')
    return value
