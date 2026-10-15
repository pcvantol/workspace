"""Pinned own HTTP routes; no client-selectable peer, grant or provider."""
import re
import sqlite3
from .concept_baseline_http import protected_reply
from .concept_briefing_store import ConceptBriefingStore
from .conversations import ConversationConflict
from .project_concepts import ConceptStorageUnavailable
from .worklist_peer import WorklistError
from .workset_release_http import _body


def route(handler,service):
    if not handler.path.startswith('/v1/concept-chats'):return False
    match=re.fullmatch(r'/v1/concept-chats/([0-9a-f]{32})/(access|briefing|history|turns|adopt|operations/([0-9a-f]{32}))',handler.path)
    if match is None:handler._reply(400,{'error':'CHAT_INVALID_PATH'});return True
    identity,action,operation=match.groups()
    if handler.command not in ('GET','POST') or (handler.command=='POST')!=(action in ('turns','adopt')):
        handler._reply(405,{'error':'METHOD_NOT_ALLOWED'});return True
    if not handler._pinned_auth():return True
    grants=handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'DENIED'});return True
    draft=grants[0];peer=service.concept_chats
    try:
        if handler.command=='GET' and (handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0'):raise ValueError('GET body')
        if action=='briefing':
            # Own-only read works without any model/transfer grant or peer call.
            with service.project_concepts.authorized(draft) as scope:
                value=ConceptBriefingStore(service.project_concepts).read(scope,identity)
                handler._reply(200,value)
            return True
        _,_,binding=peer.snapshot(draft,identity)
        if action=='access':value=peer.access(draft,identity,expected=binding)
        elif action=='history':value=peer.history(draft,identity,expected=binding)
        elif operation:value=peer.read(draft,identity,operation,expected=binding)
        elif action=='turns':value=peer.send(draft,identity,_body(handler),expected=binding)
        else:value=peer.adopt(draft,identity,_body(handler),expected=binding)
        protected_reply(handler,service,draft,identity,binding,value,peer=peer)
    except (PermissionError,WorklistError) as error:
        code=getattr(error,'state','DENIED')
        status=403 if code in ('DENIED','UNAUTHORIZED') else 404 if code=='CONCEPT_TURN_NOT_FOUND' and getattr(error,'http_status',None)==404 else 409 if code in ('CONCEPT_REVISION_CONFLICT','CONCEPT_IDEMPOTENCY_CONFLICT','CONCEPT_TURN_LIMIT','CONCEPT_QUOTA_EXHAUSTED','CONVERSATION_STALE','BRIEFING_STALE','TURN_ID_REUSED','OPERATION_CONTENT_CONFLICT','INVOCATION_UNRESOLVED') else 503
        handler._reply(status,{'error':code})
    except FileNotFoundError:handler._reply(404,{'error':'CHAT_NOT_FOUND'})
    except ConversationConflict:handler._reply(409,{'error':'CHAT_CONFLICT'})
    except (ConceptStorageUnavailable,sqlite3.Error):handler._reply(503,{'error':'CHAT_STORAGE_UNAVAILABLE'})
    except ValueError:handler._reply(400 if handler.command=='POST' else 503,{'error':'CHAT_INVALID_OR_UNAVAILABLE'})
    except (OSError,KeyError,TypeError):handler._reply(503,{'error':'CHAT_UNAVAILABLE'})
    return True
