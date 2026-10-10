"""Closed release HTTP surface with separate draft and release authorization."""
import json
import re
from .worklist_peer import WorklistError

PREFIX = '/v1/workset-releases'
ROUTES = {'access': 'GET', 'capability': 'GET', 'prepare': 'POST', 'commands': 'POST'}


def valid_path(path, method):
    if method == 'GET':
        return path in (PREFIX + '/access', PREFIX + '/capability') or re.fullmatch(
            PREFIX + r'/operations/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}', path) is not None
    return method == 'POST' and path in (PREFIX + '/prepare', PREFIX + '/commands')


def _body(handler):
    lengths = handler.headers.get_all('Content-Length', [])
    types = handler.headers.get_all('Content-Type', [])
    if (len(lengths) != 1 or not lengths[0].isdecimal() or not 1 <= int(lengths[0]) <= 65536 or
            handler.headers.get_all('Transfer-Encoding', []) or len(types) != 1 or
            types[0].split(';', 1)[0].lower() != 'application/json'):
        raise WorklistError('INVALID_REQUEST')
    from .service import _unique_json_object
    try:
        return json.loads(handler.rfile.read(int(lengths[0])), object_pairs_hook=_unique_json_object)
    except (ValueError, UnicodeError, RecursionError):
        raise WorklistError('INVALID_REQUEST') from None


def _status(state):
    if state in ('DENIED', 'RELEASE_SCOPE_DENIED'):
        return 403
    if state in ('NOT_FOUND', 'RELEASE_OPERATION_NOT_FOUND'):
        return 404
    if state in ('CONFLICT', 'RELEASE_CONFLICT', 'RELEASE_BUSY', 'RELEASE_ALLOWANCE_EXHAUSTED', 'RELEASE_WORKSET_HELD'):
        return 409
    return 400 if state == 'INVALID_REQUEST' else 503


def route(handler, service, path, method):
    if not valid_path(path, method):
        return handler._reply(400, {'error': 'INVALID_PATH'})
    if not handler._pinned_auth():
        return
    scope = handler._conversation_scope()
    if scope is None:
        return
    grants = handler.headers.get_all('X-Workspace-Workset-Release-Grant', [])
    if len(grants) != 1:
        return handler._reply(403, {'error': 'WORKSET_RELEASE_DENIED'})
    try:
        draft = handler.headers.get_all('X-Workspace-Draft-Grant')[0]
        transport = service.workset_releases
        binding = transport.access(grants[0])
        transport.bound(binding, scope)
        if method == 'GET':
            result = _read(transport, binding, scope, path)
        else:
            body = _body(handler)
            authority = service.advisory_forward_scope(draft, scope)
            result = (transport.prepare(binding, body, authority=authority) if path.endswith('/prepare')
                      else transport.submit(binding, body, authority=authority))
        if transport.access(grants[0]) != binding:
            raise WorklistError('DENIED')
        if service.conversation_scope(draft) != scope:
            raise PermissionError('release scope changed')
    except PermissionError:
        return handler._reply(403, {'error': 'WORKSET_RELEASE_DENIED'})
    except WorklistError as error:
        return handler._reply(_status(error.state), {'error': 'WORKSET_RELEASE_' + error.state})
    except (OSError, ValueError, UnicodeError):
        return handler._reply(503, {'error': 'WORKSET_RELEASE_UNAVAILABLE'})
    return handler._reply(200, result)


def _read(transport, binding, scope, path):
    if path.endswith('/access'):
        return transport.metadata(binding, scope)
    if path.endswith('/capability'):
        return transport.capability(binding)
    return transport.operation(binding, path.rsplit('/', 1)[1])
