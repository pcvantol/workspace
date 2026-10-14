"""Own normalized IPC only. No guessed EP URL/auth or producer fallback."""
import json
import re
import sqlite3
from .project_links import LinkConflict, LinkExpired, ProducerUnavailable
from .service import _unique_json_object


def route(handler, service, target, method):
    identity = r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}'
    match = re.fullmatch(r'/v1/project-links/(access|projects|'+identity+r'/(?:inspect|open|link))', target)
    if match is None:
        return handler._reply(400, {'error': 'INVALID_PROJECT_LINK_PATH'})
    if not handler._pinned_auth():
        return
    tokens = handler.headers.get_all('X-Workspace-Project-Grant', [])
    if len(tokens) != 1 or not tokens[0] or len(tokens[0]) > 4096:
        return handler._reply(403, {'error': 'PROJECT_LINK_VIEWER_REQUIRED'})
    parts = match[1].split('/')
    try:
        original_scope=service.project_links._scope(tokens[0])
        epochs=handler.headers.get_all('X-Workspace-Project-Binding',[])
        if parts!=['access'] and epochs!=[original_scope.epoch]:
            raise PermissionError('original project binding required')
        if method == 'GET':
            if handler.headers.get('Content-Length', '0') != '0' or handler.headers.get_all('Transfer-Encoding', []):
                raise ValueError('GET body forbidden')
            if parts == ['access']:
                result = service.project_links.access(tokens[0]) | {'workspace_instance_id':service.instance_id}
            elif parts == ['projects']:
                result = service.project_links.discover(tokens[0],expected=original_scope)
            elif parts[-1] == 'inspect':
                result = service.project_links.inspect(tokens[0], parts[0],expected=original_scope)
            elif parts[-1] == 'open':
                result = service.project_links.open(tokens[0], parts[0],expected=original_scope)
            else:
                return handler._reply(405, {'error': 'METHOD_NOT_ALLOWED'})
        elif method == 'POST' and parts[-1] == 'link':
            lengths = handler.headers.get_all('Content-Length', [])
            if (len(lengths) != 1 or not lengths[0].isdigit() or not 1 <= int(lengths[0]) <= 4096
                    or handler.headers.get_all('Transfer-Encoding', [])
                    or handler.headers.get('Content-Type') != 'application/json'):
                raise ValueError('invalid link body framing')
            fields = json.loads(handler.rfile.read(int(lengths[0])), object_pairs_hook=_unique_json_object)
            if not isinstance(fields, dict) or set(fields) != {'expected_revision', 'authority_id', 'operation_id'}:
                raise ValueError('invalid link mutation')
            result = service.project_links.link(tokens[0], parts[0], fields['expected_revision'], fields['operation_id'], authority_id=fields['authority_id'],expected=original_scope)
        else:
            return handler._reply(405, {'error': 'METHOD_NOT_ALLOWED'})
        service.project_links._scope(tokens[0],original_scope)
        authorization=getattr(service.project_links.gateway,'authorization',None)
        if not callable(authorization):raise ProducerUnavailable('unqualified publication fence')
        with authorization(tokens[0],original_scope):
            service.project_links._scope(tokens[0],original_scope)
            return handler._reply(200, result)
    except ProducerUnavailable:
        return handler._reply(503, {'error': 'PROJECT_LINK_PRODUCER_UNBOUND'})
    except LinkExpired:
        return handler._reply(403, {'error': 'PROJECT_LINK_ACCESS_EXPIRED'})
    except PermissionError:
        return handler._reply(403, {'error': 'PROJECT_LINK_ACCESS_DENIED'})
    except LinkConflict:
        return handler._reply(409, {'error': 'PROJECT_LINK_SOURCE_CONFLICT'})
    except FileNotFoundError:
        return handler._reply(404, {'error': 'PROJECT_LINK_NOT_FOUND'})
    except (ValueError, TypeError, RecursionError):
        return handler._reply(400, {'error': 'PROJECT_LINK_INVALID'})
    except ConnectionError:
        return handler._reply(503, {'error': 'PROJECT_LINK_UNAVAILABLE'})
    except (OSError, sqlite3.Error):
        return handler._reply(503, {'error': 'PROJECT_LINK_UNAVAILABLE'})
