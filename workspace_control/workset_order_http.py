"""Closed native order routes; own and producer authority fence every publication."""
import re
from .worklist_peer import WorklistError
from .workset_release_http import _body
from . import workset_order_contract as wire

PREFIX = '/v1/workset-orders'
IDENTIFIER = r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}'


def route(handler, service, method):
    path = handler.path
    if not (path == PREFIX or path.startswith(PREFIX + '/')):
        return False
    suffix = path[len(PREFIX):]
    valid = (method == 'GET' and re.fullmatch(r'(?:|/capability|/' + IDENTIFIER + r'(?:/operations/' + IDENTIFIER + r')?)', suffix)
             or method == 'POST' and re.fullmatch('/' + IDENTIFIER + '/(?:preview|confirm)', suffix))
    if not valid:
        handler._reply(400, {'error': 'ORDER_INVALID_PATH'}); return True
    if not handler._pinned_auth():
        return True
    scope = handler._conversation_scope()
    if scope is None:
        return True
    tokens = handler.headers.get_all('X-Workspace-Order-Grant', [])
    if len(tokens) != 1:
        handler._reply(403, {'error': 'ORDER_DENIED'}); return True
    try:
        draft = handler.headers.get_all('X-Workspace-Draft-Grant')[0]
        transport = service.workset_orders
        binding = transport.access(tokens[0])
        with service.conversations.forward_grant(draft, scope), transport.gate(binding, scope) as cap:
            parts = suffix.strip('/').split('/')
            if method == 'GET':
                if suffix == '':
                    result = {'consumer_contract': 'workspace-workset-order-access/v1', 'binding_id': binding['id'],
                              'actor_id': binding['actor_id'], 'workspace_project_id': binding['workspace_project_id'],
                              'installation_id': binding['installation_id'], 'producer_source': wire.PIN, 'producer_version': '2.15.0', **cap}
                elif suffix == '/capability': result = cap
                elif len(parts) == 1: result = transport.current(binding, parts[0])
                else: result = transport.operation(binding, parts[0], parts[2])
            else:
                body = _body(handler)
                result = (transport.preview(binding, parts[0], body) if parts[1] == 'preview'
                          else transport.confirm(binding, parts[0], body))
            transport.capability(binding)
            handler._reply(200, result)
    except PermissionError:
        handler._reply(403, {'error': 'ORDER_DENIED'})
    except WorklistError as error:
        state = error.state
        code = (403 if state in ('DENIED', 'ORDER_SCOPE_DENIED') else
                404 if state == 'ORDER_OPERATION_UNKNOWN' else
                409 if state.endswith(('CONFLICT', 'STALE', 'CHANGED', 'PENDING', 'EXHAUSTED', 'ELIGIBLE', 'UNAVAILABLE')) else
                400 if state in ('INVALID_REQUEST', 'ORDER_REQUEST_INVALID') else 503)
        handler._reply(code, {'error': state})
    except (OSError, ValueError, TypeError, KeyError):
        handler._reply(503, {'error': 'ORDER_UNAVAILABLE'})
    return True
