"""Closed concept adoption routes; current original EP GET before protected publication."""
import re,sqlite3,time
from types import SimpleNamespace
from .concept_baseline_http import protected_reply
from .workset_release_http import _body
from .worklist_peer import WorklistError
from .conversations import ConversationConflict
from .concept_adoption_intents import AdoptionSourceRejected
from .project_concepts import ConceptStorageUnavailable

def route(handler,service):
    if not handler.path.startswith('/v1/concept-adoptions'):return False
    m=re.fullmatch(r'/v1/concept-adoptions/([0-9a-f]{32})/(sources|([0-9a-f]{32})/(access|prepare|operations|operations/([0-9a-f]{32})))',handler.path)
    if m is None:handler._reply(400,{'error':'ADOPTION_INVALID_PATH'});return True
    identity,action,source,part,operation=m.groups()
    if handler.command not in ('GET','POST') or (handler.command=='POST')!=(part=='prepare'):handler._reply(405,{'error':'METHOD_NOT_ALLOWED'});return True
    if not handler._pinned_auth():return True
    grants=handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'DENIED'});return True
    draft=grants[0];peer=service.concept_adoptions
    try:
        if handler.command=='GET' and (handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0'):raise ValueError('GET body')
        if action=='sources':
            value=peer.sources(draft,identity)
            # Only setup metadata, still current own/peer authority-fenced.
            def sources_cap(b,**kw):
                if peer.sources(draft,identity,timeout=kw.get('timeout',3))!=value:raise WorklistError('DENIED')
            protected_reply(handler,service,draft,identity,value,value,peer=SimpleNamespace(cap=sources_cap,dispatch_guard=lambda *args:peer.sources_guard(draft,identity,value)))
            return True
        _,_,binding=peer.snapshot(draft,identity,source)
        if part=='prepare':value=peer.prepare(draft,identity,source,_body(handler))
        elif part=='access':value=peer.access(draft,identity,source)
        elif part=='operations':value=peer.history(draft,identity,source)
        else:value=peer.read(draft,identity,source,operation)
        def publication_cap(b,**kw):
            deadline=time.monotonic()+kw.get('timeout',5)
            peer.cap(b,**kw)
            if 'proposal' in value:
                remaining=deadline-time.monotonic()
                if remaining<=0:raise WorklistError('UNAVAILABLE')
                current=peer.read(draft,identity,source,value['operation_id'],timeout=remaining)
                if current!=value:raise WorklistError('CONFLICT')
        protected_reply(handler,service,draft,identity,binding,value,peer=SimpleNamespace(cap=publication_cap,dispatch_guard=peer.dispatch_guard))
    except (PermissionError,WorklistError) as error:
        code=getattr(error,'state','DENIED');status=403 if code in ('DENIED','UNAUTHORIZED') else 404 if code=='INSPECTION_ADOPTION_NOT_FOUND' and getattr(error,'http_status',None)==404 else 409 if 'CONFLICT' in code or 'CAPACITY' in code else 503
        handler._reply(status,{'error':code})
    except FileNotFoundError:handler._reply(404,{'error':'ADOPTION_NOT_FOUND'})
    except AdoptionSourceRejected:handler._reply(409,{'error':'ADOPTION_SOURCE_REJECTED_BEFORE_CAPTURE'})
    except ConversationConflict:handler._reply(409,{'error':'ADOPTION_CONFLICT'})
    except (ConceptStorageUnavailable,sqlite3.Error):handler._reply(503,{'error':'ADOPTION_STORAGE_UNAVAILABLE'})
    except ValueError:handler._reply(400 if handler.command=='POST' else 503,{'error':'ADOPTION_INVALID_OR_UNAVAILABLE'})
    except (OSError,KeyError,TypeError):handler._reply(503,{'error':'ADOPTION_UNAVAILABLE'})
    return True
