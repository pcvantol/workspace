"""Closed own activity read entrypoints; both local authority fences cover publication."""
import re
from .worklist_peer import WorklistError

PREFIX='/v1/workset-activity'


def route(handler,service):
    path=handler.path
    if not (path==PREFIX or path.startswith(PREFIX+'/')):return False
    if not re.fullmatch(PREFIX+r'(?:/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}/(?:pages(?:/[A-Za-z0-9_.-]{1,32768})?|events/[0-9a-f]{64}))?',path):
        handler._reply(400,{'error':'INVALID_ACTIVITY_PATH'});return True
    if not handler._pinned_auth():return True
    scope=handler._conversation_scope()
    if scope is None:return True
    grants=handler.headers.get_all('X-Workspace-Activity-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'ACTIVITY_DENIED'});return True
    try:
        draft=handler.headers.get_all('X-Workspace-Draft-Grant')[0]
        binding=service.activities.access(grants[0])
        with service.conversations.forward_grant(draft,scope),service.activities.gate(binding,scope) as cap:
            if path==PREFIX:result=service.activities.metadata(binding,cap)
            else:
                parts=path[len(PREFIX)+1:].split('/')
                result=service.activities.read(binding,parts[0],cursor=parts[2] if len(parts)==3 and parts[1]=='pages' else None,event=parts[2] if parts[1]=='events' else None)
            from .workset_activity_contract import capability
            capability(service.activities._request(binding),binding)
            handler._reply(200,result)
    except PermissionError:handler._reply(403,{'error':'ACTIVITY_DENIED'})
    except WorklistError as error:
        code=403 if error.state in ('DENIED','ACTIVITY_SCOPE_DENIED') else 409 if error.state=='RESYNC_REQUIRED' else 404 if error.state in ('UNSUPPORTED','EVENT_UNAVAILABLE','ACTIVITY_ROUTE_MISSING') else 400 if error.state in ('INVALID_REQUEST','ACTIVITY_REQUEST_INVALID') else 503
        handler._reply(code,{'error':error.state if error.state.startswith('ACTIVITY_') else 'ACTIVITY_'+error.state})
    except (OSError,ValueError,KeyError,TypeError):handler._reply(503,{'error':'ACTIVITY_UNAVAILABLE'})
    return True
