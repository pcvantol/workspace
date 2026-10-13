"""Exact pinned finite-order consumer; canonical packages remain Forge-owned."""
from datetime import datetime, timezone
from pathlib import Path
import json
from .advisory_contract import _check, digest, scope
from .worklist_peer import WorklistError

CONTRACT = 'forge-workset-order/v1'
BASE = '/v1/approved-workset-orders'
PIN = '989132660997909e74800ddc8648be11262be8d4'
SCHEMA = json.loads(Path(__file__).with_name('workset-order-v1.json').read_text())


def require(condition, state='INVALID_RESPONSE'):
    if not condition:
        raise WorklistError(state)


def validate(value, kind):
    _check(value, SCHEMA['$defs'][kind], SCHEMA['$defs'])
    return value


def capability(value, binding):
    validate(value, 'capability')
    scope(value['scope'], binding)
    require(value['worksets'] == binding['worksets'], 'DENIED')
    require(value['permissions'] == binding['permissions'], 'DENIED')
    require(value['expires_at'] == binding['expires_at'], 'DENIED')
    require(datetime.fromisoformat(value['expires_at'].replace('Z', '+00:00')) > datetime.now(timezone.utc), 'DENIED')
    require(value['maximum_amendments'] == binding['maximum_amendments'], 'DENIED')
    require(value['remaining_amendments'] == max(0, value['maximum_amendments'] - value['consumed_amendments']))
    require(value['required_roles'] == ['business_owner', 'platform_architect'])
    require(not value['reorder_supported'] or 'REORDER' in value['permissions'])
    return value


def current(value, binding, workset):
    validate(value, 'current')
    projection = value['current']
    ordered = projection['contract_version'] == 'forge-workspace-worklist/v2'
    if not ordered:
        from .worklist_contract import validate_projection
        validate_projection(projection, binding, workset)
        require(value['order_revision'] == 0)
    require(projection['instance_id'] == binding['forge_instance_id'] and projection['installation_id'] == binding['installation_id'], 'DENIED')
    require(projection['scope']['principal_id'] == binding['actor_id'] and projection['scope']['workset_id'] == workset, 'DENIED')
    require(value['workset_id'] == workset, 'DENIED')
    subject = {'workset_id': workset, 'definition_digest': projection['membership_revision']}
    require(subject in binding['worksets'], 'DENIED')
    order = value['current_order']
    require(len(set(order)) == len(order))
    require([m['candidate_id'] for m in value['members']] == order)
    if ordered:
        require(value['order_revision'] == projection['order_revision'])
        require(value['order_digest'] == projection['order_digest'])
        require(order == projection['effective_order'])
    else:
        require(order == [i['candidate_id'] for i in sorted(projection['items'], key=lambda i: i['committed_order'])])
    require(0 <= value['fixed_prefix'] <= len(order))
    items = {i['candidate_id']: i for i in projection['items']}
    require(set(items) == set(order))
    for index, member in enumerate(value['members']):
        item = items[member['candidate_id']]
        require(member['position'] == index + 1)
        require(member['remaining_position'] == (index - value['fixed_prefix'] + 1 if index >= value['fixed_prefix'] else None))
        require(member['title'] == item['title'] and member['dependencies'] == item['dependencies'])
        require(all(dep in order[:index] for dep in member['dependencies']))
        require(not member['claimed'] or index < value['fixed_prefix'])
    return value


def preview(value, binding, workset, proposed):
    validate(value, 'preview')
    now = current(value['current'], binding, workset)
    package = value['package']
    scope(package, binding)
    require(package['workset_id'] == workset, 'DENIED')
    require(package['definition_digest'] == now['current']['membership_revision'], 'DENIED')
    require(value['package_digest'] == digest(package))
    require(package['proposed_order'] == proposed and set(proposed) == set(now['current_order']))
    require(len(set(proposed)) == len(proposed) and proposed != now['current_order'])
    require(package['current_order'] == now['current_order'])
    require(package['fixed_prefix'] == now['fixed_prefix'])
    require(proposed[:now['fixed_prefix']] == now['current_order'][:now['fixed_prefix']])
    require(package['workset_revision'] == now['current']['workset_revision'])
    require(package['order_revision'] == now['order_revision'] and package['previous_order_digest'] == now['order_digest'])
    members = {m['candidate_id']: m for m in now['members']}
    for index, candidate in enumerate(proposed):
        require(all(d in proposed[:index] for d in members[candidate]['dependencies']))
    expected = {i['candidate_id']: i['subject_revision'] for i in now['current']['items']}
    require({s['candidate_id']: s['subject_revision'] for s in package['subjects']} == expected)
    require(len(package['subjects']) == len(expected))
    for kind, order in [('current', package['current_order']), ('proposed', proposed)]:
        require(value['display_orders'][kind] == [{'position': i + 1, 'candidate_id': c, 'title': members[c]['title']} for i, c in enumerate(order)])
    require(not value['reorder_supported'] or 'REORDER' in binding['permissions'])
    return value


def command(value, binding, workset):
    validate(value, 'request')
    scope(value, binding)
    scope(value['package'], binding)
    require(value['workset_id'] == value['package']['workset_id'] == workset, 'DENIED')
    require({'workset_id': workset, 'definition_digest': value['package']['definition_digest']} in binding['worksets'], 'DENIED')
    require(value['package_digest'] == digest(value['package']), 'INVALID_REQUEST')
    return value


def operation(value, binding, workset, identifier, expected=None):
    validate(value, 'operation')
    command(value['original_request'], binding, workset)
    require(value['operation_id'] == value['original_request']['operation_id'] == identifier)
    if expected is not None:
        require(value['original_request'] == expected, 'ORIGINAL_ORDER_INTENT_CONFLICT')
    current(value['current'], binding, workset)
    receipt = value['original_receipt']
    if value['state'] == 'APPLIED':
        require(receipt is not None)
        request = value['original_request']
        require(receipt['operation_id'] == identifier and receipt['workset_id'] == workset)
        require(receipt['package_digest'] == request['package_digest'])
        require(receipt['original_order'] == request['package']['current_order'])
        require(receipt['applied_order'] == request['package']['proposed_order'])
        require(receipt['fixed_prefix'] == request['package']['fixed_prefix'])
        require(receipt['order_revision'] == request['package']['order_revision'] + 1)
        require(receipt['consumed_activations'] == request['package']['consumed_activations'])
        require(set(receipt['decisions']) == {'business', 'architecture'})
        require(receipt['decisions'] == value['canonical_decisions_observed'])
    return value
