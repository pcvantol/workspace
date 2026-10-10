"""Pinned workset-release consumer validation; Forge retains all authority."""
from datetime import datetime, timezone
import json
from pathlib import Path

from .advisory_contract import _check, digest, scope
from .worklist_peer import WorklistError

CONTRACT = 'forge-approved-workset-release/v1'
SCHEMA = json.loads(Path(__file__).with_name('approved-workset-release-v1.json').read_text())


def require(condition, state='INVALID_RESPONSE'):
    if not condition:
        raise WorklistError(state)


def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind], SCHEMA['$defs'])
    return value


def _unique_subjects(subjects):
    require(len({item['candidate_id'] for item in subjects}) == len(subjects))


def _future(value):
    return datetime.fromisoformat(value.replace('Z', '+00:00')) > datetime.now(timezone.utc)


def capability(value, binding):
    validate(value, 'capability')
    scope(value['scope'], binding)
    require(value['principal_id'] == binding['actor_id'], 'DENIED')
    _unique_subjects(value['subjects'])
    permissions = value['permissions']
    require(len(set(permissions)) == len(permissions) and 'READ' in permissions)
    require(not value['release_supported'] or 'RELEASE' in permissions)
    require(not value['disarm_supported'] or 'DISARM' in permissions)
    require(_future(value['expires_at']), 'DENIED')
    return value


def selection(value, admitted=None):
    validate(value, 'selection')
    _unique_subjects(value['subjects'])
    require(value['maximum_activations'] <= len(value['subjects']))
    if admitted is not None:
        require(all(item in admitted['subjects'] for item in value['subjects']), 'DENIED')
        require(value['maximum_activations'] <= admitted['limits']['maximum_activations'], 'DENIED')
        require(datetime.fromisoformat(value['expires_at'].replace('Z', '+00:00')) <=
                datetime.fromisoformat(admitted['expires_at'].replace('Z', '+00:00')), 'DENIED')
    return value


def command(value, binding, admitted=None):
    try:
        validate(value, 'request')
        selection(value['selection'], admitted)
        require((value['intent'] == 'release' and value['expected_revision'] is None) or
                (value['intent'] == 'disarm' and type(value['expected_revision']) is int and
                 value['expected_revision'] >= 1))
    except WorklistError as error:
        if error.state == 'DENIED':
            raise
        raise WorklistError('INVALID_REQUEST') from None
    return value


def package(value, binding, expected=None):
    validate(value, 'package')
    scope(value['scope'], binding)
    require(value['principal_reference'] == binding['forge_instance_id'] + ':' + binding['actor_id'], 'DENIED')
    selection(value['selection'])
    if expected is not None:
        require(value['selection'] == expected)
    actual = [{'candidate_id': s['candidate_id'], 'subject_revision': s['subject_revision']}
              for s in value['subjects']]
    require(actual == value['selection']['subjects'])
    definition = value['definition']
    require(definition['workset_id'] == 'released-' + value['release_key'][7:47])
    require(definition['expires_at'] == value['selection']['expires_at'])
    require(definition['maximum_activations'] == value['selection']['maximum_activations'])
    require([{'candidate_id': m['candidate_id'], 'subject_revision': m['subject_revision']}
             for m in definition['members']] == actual)
    return value


def prepared(value, binding, expected):
    validate(value, 'prepared')
    package(value['package'], binding, expected)
    _subject_proofs(value['package'], binding)
    _semantic_key(value['package'])
    require(value['gaps'] == value['package']['gaps'])
    require(value['package_digest'] == digest(value['package']))
    require(not value['release_supported'] or not value['gaps'])
    return value


def _canonical(value):
    import hashlib
    return 'sha256:' + hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                                separators=(',', ':')).encode()).hexdigest()


def _subject_proofs(value, binding):
    signer = value['operator_binding']
    for subject, member in zip(value['subjects'], value['definition']['members']):
        scope(subject['source'], binding)
        require(subject['mission']['candidate_id'] == subject['candidate_id'])
        require(member['mission'] == subject['mission'] and member['planning'] == subject['planning'])
        require(member['dependencies'] == [d['candidate_id'] for d in subject['dependency_bindings']])
        require(member['progression_policy']['mode'] == value['selection']['progression_mode'])
        require(member['progression_policy']['higher_scope_obligations'] == subject['planning']['human_gates'])
        decisions = subject['candidate_decisions']
        require(decisions['business']['decision_id'] != decisions['architecture']['decision_id'])
        for key, kind in [('business', 'BUSINESS'), ('architecture', 'ARCHITECTURE')]:
            decision = decisions[key]
            require(decision['kind'] == kind and decision['candidate_id'] == subject['candidate_id'])
            require(decision['subject_revision'] == subject['subject_revision'])
            require(decision['principal_reference'] == value['principal_reference'])
            require(all(decision[k] == signer[k] for k in signer))
            require(digest(decision['canonical_decision']) == decision['canonical_decision_digest'])
            require(_canonical(decision['lifecycle_evidence']) == decision['lifecycle_evidence_digest'])
            _decision_join(decision, subject, kind, signer)


def _decision_join(receipt, subject, kind, signer):
    canonical = receipt['canonical_decision']
    evidence = receipt['lifecycle_evidence']
    require(canonical['decision_id'] == receipt['decision_id'])
    require(canonical['subject_id'] == subject['candidate_id'] and
            canonical['subject_revision'] == subject['subject_revision'])
    require(canonical['capability'] == kind + '_APPROVAL' and canonical['decision'] == 'approved')
    require(all(canonical[k] == signer[k] for k in ('installation_id', 'operator_id')))
    require(evidence['actor'] == 'primary_operator' and evidence['kind'] == kind.lower() + '_decision')
    require(evidence['occurred_at'] == receipt['admitted_at'] and evidence['rationale'] == receipt['rationale'])
    require({subject['candidate_id'], subject['subject_revision'], receipt['decision_id']}.issubset(evidence['references']))
    require(sorted(canonical['gates']) == sorted(subject['planning']['human_gates']))
    if kind == 'ARCHITECTURE':
        require(canonical['evidence']['planning_digest'] == digest(subject['planning']))


def _semantic_key(value):
    semantic = {**value['scope'], 'principal_reference': value['principal_reference'],
                'selection': value['selection'], 'members': value['definition']['members'],
                'operator_binding': value['operator_binding'], 'candidate_decisions':
                [{k: s['candidate_decisions'][k]['canonical_decision_digest']
                  for k in ('business', 'architecture')} for s in value['subjects']]}
    require(value['release_key'] == digest(semantic))


def operation(value, binding, expected=None, operation_id=None):
    from .worklist_contract import validate_projection
    validate(value, 'operation')
    packet = package(value['frozen_package'], binding)
    _subject_proofs(packet, binding)
    _semantic_key(packet)
    require(value['package_digest'] == digest(packet))
    request = command(value['original_request'], binding)
    require(request['operation_id'] == value['operation_id'])
    require(request['selection'] == packet['selection'] and request['package_digest'] == value['package_digest'])
    require(expected is None or request == expected)
    require(operation_id is None or value['operation_id'] == operation_id)
    require(value['workset_id'] == packet['definition']['workset_id'])
    record = value['original_receipt']
    if value['state'] == 'PENDING':
        require(record is None)
    else:
        require(record is not None and value['current'] is not None)
        _receipt(record, packet, request)
    if value['current'] is not None:
        current = validate_projection(value['current'], binding, value['workset_id'])
        require(current['membership_revision'] == _canonical(packet['definition']))
        require([(i['candidate_id'], i['subject_revision']) for i in current['items']] ==
                [(s['candidate_id'], s['subject_revision']) for s in packet['subjects']])
    return value


def _receipt(record, packet, request):
    require(record['intent'] == request['intent'] and record['package_digest'] == digest(packet))
    require(record['principal_reference'] == packet['principal_reference'])
    require(record['definition_digest'] == _canonical(packet['definition']))
    require(record['workset_id'] == packet['definition']['workset_id'])
    require(record['candidate_mission_ids'] == [s['mission_id'] for s in packet['subjects']])
    require(record['original_release'] == ('AUTO_WHEN_ELIGIBLE' if request['intent'] == 'release' else 'DISARMED'))
