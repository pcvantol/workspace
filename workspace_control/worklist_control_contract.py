"""Closed consumer validation of the selected Forge hold capability, never authority."""
import hashlib
import json

from .review_peer import _digest, _id
from .worklist_contract import _integer, _timestamp, validate_projection
from .worklist_peer import WorklistError, _shape

REQUEST = 'forge-worklist-control-request/v1'
READBACK = 'forge-worklist-control-readback/v1'
RECEIPT = 'forge-worklist-control-receipt/v1'
REQUEST_KEYS = {'contract_version', 'operation_id', 'intent', 'instance_id', 'workset_id',
                'definition_revision', 'expected_revision', 'hold_operation_id',
                'expected_hold_revision', 'reason_code'}
CURRENT_KEYS = {'instance_id', 'workset_id', 'definition_revision', 'workset_revision',
                'control_revision', 'held', 'hold', 'hold_provenance', 'admitted_mission_ids',
                'boundary', 'ongoing_work_cancelled', 'observed_at'}


def require(condition):
    if not condition:
        raise WorklistError('INVALID_RESPONSE')


def request_digest(value):
    return 'sha256:' + hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                                separators=(',', ':')).encode()).hexdigest()


def validate_request(value, binding, workset):
    _shape(value, REQUEST_KEYS)
    require(value['contract_version'] == REQUEST and value['instance_id'] == binding['forge_instance_id']
            and value['workset_id'] == workset and workset in binding['workset_ids']
            and _id(value['operation_id']) and _digest(value['definition_revision'])
            and _integer(value['expected_revision'], 1)
            and value['reason_code'] in ('USER_REQUEST', 'TEMPORARY_WAIT'))
    if value['intent'] == 'hold':
        require(value['hold_operation_id'] is None and value['expected_hold_revision'] is None)
    else:
        require(value['intent'] == 'unhold' and _id(value['hold_operation_id'])
                and _integer(value['expected_hold_revision'], 1))
    return value


def validate_current(value, binding, workset):
    _shape(value, CURRENT_KEYS)
    require(value['instance_id'] == binding['forge_instance_id'] and value['workset_id'] == workset
            and _digest(value['definition_revision']) and _integer(value['workset_revision'], 1)
            and _integer(value['control_revision']) and type(value['held']) is bool
            and value['boundary'] == 'FUTURE_ADMISSION_ONLY' and value['ongoing_work_cancelled'] is False
            and _timestamp(value['observed_at']))
    ids = value['admitted_mission_ids']
    require(isinstance(ids, list) and len(ids) <= 64 and all(_id(x) for x in ids) and len(set(ids)) == len(ids))
    hold = value['hold']
    if hold is None:
        require((not value['held'] and value['hold_provenance'] == 'NONE') or
                (value['held'] and value['hold_provenance'] == 'LEGACY_UNKNOWN'))
    else:
        _shape(hold, {'operation_id', 'control_revision', 'reason_code', 'owned_by_principal'})
        require(value['held'] and value['hold_provenance'] == 'RECORDED' and _id(hold['operation_id'])
                and _integer(hold['control_revision'], 1) and hold['control_revision'] <= value['control_revision']
                and hold['reason_code'] in ('USER_REQUEST', 'TEMPORARY_WAIT', 'OWNER_REQUEST')
                and type(hold['owned_by_principal']) is bool)
    return value


def validate_receipt(value, binding, workset, expected=None):
    _shape(value, {'contract_version', 'operation_id', 'principal_id', 'grant_id', 'request',
                   'request_digest', 'outcome', 'effect', 'only_target_hold_removed'})
    require(value['contract_version'] == RECEIPT and value['outcome'] == 'APPLIED'
            and value['principal_id'] == binding['actor_id'] and _id(value['grant_id']))
    request = validate_request(value['request'], binding, workset)
    require(value['operation_id'] == request['operation_id']
            and value['request_digest'] == request_digest(request)
            and (expected is None or request == expected))
    effect = validate_current(value['effect'], binding, workset)
    require(effect['definition_revision'] == request['definition_revision']
            and effect['workset_revision'] == request['expected_revision'] + 2)
    if request['intent'] == 'hold':
        require(effect['held'] and effect['hold'] is not None
                and effect['hold']['operation_id'] == request['operation_id']
                and effect['hold']['control_revision'] == effect['control_revision']
                and effect['hold']['owned_by_principal'] is True
                and effect['hold']['reason_code'] == request['reason_code']
                and value['only_target_hold_removed'] is None)
    else:
        require(not effect['held'] and effect['hold'] is None
                and value['only_target_hold_removed'] == request['hold_operation_id'])
    return value


def validate_readback(value, binding, workset, operation=None, expected=None):
    _shape(value, {'contract_version', 'principal_id', 'read_only', 'operation', 'current', 'worklist'})
    require(value['contract_version'] == READBACK and value['principal_id'] == binding['actor_id']
            and value['read_only'] is True and workset in binding['workset_ids'])
    current = validate_current(value['current'], binding, workset)
    projection = validate_projection(value['worklist'], binding, workset)
    require(current['workset_revision'] == projection['workset_revision'])
    known_missions = {item['mission_id'] for item in projection['items'] if item['mission_id'] is not None}
    require(set(current['admitted_mission_ids']).issubset(known_missions))
    record = value['operation']
    if operation is None:
        require(record is None)
    else:
        _shape(record, {'state', 'original_receipt', 'operation_id', 'execution_known'})
        require(record['operation_id'] == operation and type(record['execution_known']) is bool)
        if record['state'] == 'PENDING':
            require(record['original_receipt'] is None and record['execution_known'] is False)
        else:
            require(record['state'] == 'APPLIED' and record['execution_known'] is True)
            receipt = validate_receipt(record['original_receipt'], binding, workset, expected)
            require(receipt['operation_id'] == operation
                    and current['workset_revision'] >= receipt['effect']['workset_revision'])
    return value


def validate_result(value, binding, workset, request):
    _shape(value, {'contract_version', 'original_receipt', 'recorded', 'current_readback'})
    require(value['contract_version'] == READBACK and type(value['recorded']) is bool)
    receipt = validate_receipt(value['original_receipt'], binding, workset, request)
    current = validate_readback(value['current_readback'], binding, workset,
                                request['operation_id'], request)
    require(current['operation']['original_receipt'] == receipt)
    return value
