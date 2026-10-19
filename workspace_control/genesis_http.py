"""Closed own authenticated Genesis consumer routes; no apply endpoint."""
import re
import sqlite3
from .concept_baseline_http import protected_reply
from .workset_release_http import _body
from .worklist_peer import WorklistError
from .conversations import ConversationConflict
from .project_concepts import ConceptStorageUnavailable


def route(handler,service):
    if not handler.path.startswith('/v1/concept-genesis'):return False
    match=re.fullmatch(r'/v1/concept-genesis/([0-9a-f]{32})/(plans|decisions|access/([0-9a-f]{32})|operations/([0-9a-f]{32})|decision-access/([0-9a-f]{32}))',handler.path)
    if match is None:handler._reply(400,{'error':'GENESIS_INVALID_PATH'});return True
    identity,action,source,operation,decision_plan=match.groups()
    if handler.command not in ('GET','POST') or (handler.command=='POST')!=(action in ('plans','decisions')):
        handler._reply(405,{'error':'METHOD_NOT_ALLOWED'});return True
    if not handler._pinned_auth():return True
    grants=handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'DENIED'});return True
    draft=grants[0];peer=service.genesis
    try:
        if handler.command=='GET' and (handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0'):raise ValueError('GET body')
        if source:value=peer.access(draft,identity,source)
        elif operation:value=peer.read(draft,identity,operation)
        elif decision_plan:value=peer.decision_access(draft,identity,decision_plan)
        elif action=='plans':value=peer.prepare(draft,identity,_body(handler))
        else:value=peer.decide(draft,identity,_body(handler))
        with peer.concepts.authorized(draft) as scope:binding=peer.binding(scope,identity,binding_id=value['binding_id'])
        if action=='decisions' and value['result']['original_decision']['decision']=='APPROVE_EFFECT':
            # Recheck the same local target at every protected publication chunk;
            # historical GETs remain readable with an explicit obsolete-target fact.
            class Publication:
                cap=peer.cap
                def dispatch_guard(self,draft,identity,binding):return peer.positive_guard(draft,identity,binding,value['operation_id'])
            publisher=Publication()
        else:publisher=peer
        protected_reply(handler,service,draft,identity,binding,value,peer=publisher)
    except (PermissionError,WorklistError) as error:
        code=getattr(error,'state','DENIED');peer_status=getattr(error,'http_status',None)
        status=403 if code in ('DENIED','UNAUTHORIZED','GENESIS_SCOPE_DENIED') else 404 if code=='GENESIS_NOT_FOUND' and peer_status==404 else 409 if peer_status==409 and code in ('GENESIS_OPERATION_CONFLICT','GENESIS_PLAN_STALE','GENESIS_SOURCE_CHANGED','GENESIS_EFFECT_STALE','GENESIS_EFFECT_INAPPLICABLE','GENESIS_EXACT_PLAN_REQUIRED','GENESIS_PLAN_EXPIRY','GENESIS_TARGET_STALE') else 503
        handler._reply(status,{'error':code})
    except FileNotFoundError:handler._reply(404,{'error':'GENESIS_OWN_NOT_FOUND'})
    except ConversationConflict:handler._reply(409,{'error':'GENESIS_CONFLICT'})
    except (ConceptStorageUnavailable,sqlite3.Error):handler._reply(503,{'error':'GENESIS_STORAGE_UNAVAILABLE'})
    except ValueError:handler._reply(400 if handler.command=='POST' else 503,{'error':'GENESIS_INVALID_OR_UNAVAILABLE'})
    except (OSError,KeyError,TypeError):handler._reply(503,{'error':'GENESIS_UNAVAILABLE'})
    return True
