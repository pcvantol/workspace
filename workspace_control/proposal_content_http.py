"""Closed proposal decision routes; current own authority and R54 publication."""
import re
import sqlite3
from .concept_baseline_http import protected_reply
from .conversations import ConversationConflict
from .project_concepts import ConceptStorageUnavailable
from .worklist_peer import WorklistError
from .workset_release_http import _body

def route(handler,service):
    if not handler.path.startswith('/v1/proposal-content'):return False
    match=re.fullmatch(r'/v1/proposal-content/([0-9a-f]{32})/(decisions|proposals/([0-9a-f]{32})|operations/([0-9a-f]{32}))',handler.path)
    if match is None:handler._reply(400,{'error':'CONTENT_INVALID_PATH'});return True
    identity,action,source_operation,operation=match.groups()
    if handler.command not in ('GET','POST') or (handler.command=='POST')!=(action=='decisions'):
        handler._reply(405,{'error':'METHOD_NOT_ALLOWED'});return True
    if not handler._pinned_auth():return True
    grants=handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'DENIED'});return True
    draft=grants[0];peer=service.proposal_content
    try:
        if handler.command=='GET' and (handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0'):raise ValueError('GET body')
        _,_,binding=peer.snapshot(draft,identity)
        if source_operation:value=peer.read_proposal(draft,identity,source_operation,expected=binding)
        elif operation:value=peer.read(draft,identity,operation,expected=binding)
        else:value=peer.decide(draft,identity,_body(handler),expected=binding)
        protected_reply(handler,service,draft,identity,binding,value,peer=peer)
    except (PermissionError,WorklistError) as error:
        code=getattr(error,'state','DENIED')
        status=403 if code in ('DENIED','UNAUTHORIZED','CONTENT_DENIED') else 404 if code=='CONTENT_NOT_FOUND' and getattr(error,'http_status',None)==404 else 409 if code in ('CONTENT_DECISION_STALE','CONTENT_SUBJECT_CHANGED','CONTENT_OPERATION_CONFLICT','CONTENT_DECISION_CAPACITY','CONTENT_STORAGE_CAPACITY','CONTENT_OPEN_POINTS_UNACKNOWLEDGED') else 503
        handler._reply(status,{'error':code})
    except FileNotFoundError:handler._reply(404,{'error':'CONTENT_OWN_NOT_FOUND'})
    except ConversationConflict:handler._reply(409,{'error':'CONTENT_CONFLICT'})
    except (ConceptStorageUnavailable,sqlite3.Error):handler._reply(503,{'error':'CONTENT_STORAGE_UNAVAILABLE'})
    except ValueError:handler._reply(400 if handler.command=='POST' else 503,{'error':'CONTENT_INVALID_OR_UNAVAILABLE'})
    except (OSError,KeyError,TypeError):handler._reply(503,{'error':'CONTENT_UNAVAILABLE'})
    return True
