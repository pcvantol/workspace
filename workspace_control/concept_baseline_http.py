"""Closed own concept routes and bounded revocation-aware private publication."""
import fcntl
import json
import os
import re
import sqlite3
import select
import time
from .worklist_peer import WorklistError
from .workset_release_http import _body
from .project_concepts import ConceptStorageUnavailable
from .conversations import ConversationConflict

PREFIX='/v1/concept-baselines/'


def protected_reply(handler,service,draft,identity,binding,value,*,peer=None):
    peer=service.concept_baselines if peer is None else peer
    # Waiting for peer/writability is always outside own authorization locks.
    payload=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()
    if len(payload)>1150000:raise WorklistError('INVALID_RESPONSE')
    header=("HTTP/1.0 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: "+str(len(payload))+"\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\n\r\n").encode()
    data=header+payload;offset=0;deadline=time.monotonic()+5;connection=handler.connection
    old_timeout=connection.gettimeout();connection.setblocking(False);handler.close_connection=True
    try:
        while offset<len(data):
            if time.monotonic()>=deadline:raise WorklistError('UNAVAILABLE')
            if not select.select([], [connection], [], min(.1,max(0,deadline-time.monotonic())))[1]:continue
            peer.cap(binding,timeout=max(.001,deadline-time.monotonic()),send_guard=lambda:peer.dispatch_guard(draft,identity,binding))
            if time.monotonic()>=deadline:raise WorklistError('UNAVAILABLE')
            descriptor=peer._locked()
            try:
                with service.project_concepts.authorized(draft) as scope:
                    service.project_concepts.get(scope,identity)
                    if peer.binding(scope,identity)!=binding:raise WorklistError('DENIED')
                    if time.monotonic()>=deadline:raise WorklistError('UNAVAILABLE')
                    try:sent=connection.send(data[offset:offset+65536])
                    except BlockingIOError:continue
                    if sent<=0:raise WorklistError('UNAVAILABLE')
                    offset+=sent
            finally:fcntl.flock(descriptor,fcntl.LOCK_UN);os.close(descriptor)
    except Exception:
        # Partial protected JSON cannot become a new successful native result.
        if offset:handler.close_connection=True;return
        raise
    finally:connection.settimeout(old_timeout)


def route(handler,service):
    if not handler.path.startswith('/v1/concept-baselines'):return False
    match=re.fullmatch(PREFIX+r'([0-9a-f]{32})/(access|prepare|operations|operations/([0-9a-f]{32}))',handler.path)
    if match is None:handler._reply(400,{'error':'BASELINE_INVALID_PATH'});return True
    identity,action,operation=match.groups()
    if (handler.command=='GET' and action=='prepare') or (handler.command=='POST' and action!='prepare') or handler.command not in ('GET','POST'):
        handler._reply(405,{'error':'METHOD_NOT_ALLOWED'});return True
    if not handler._pinned_auth():return True
    grants=handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1:handler._reply(403,{'error':'BASELINE_DENIED'});return True
    draft=grants[0]
    try:
        _,_,binding=service.concept_baselines.snapshot(draft,identity)
        if handler.command=='GET':
            if handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0':raise ValueError('GET body')
            if action=='access':value=service.concept_baselines.access(draft,identity,expected=binding)
            elif action=='operations':value=service.concept_baselines.history(draft,identity,expected=binding)
            else:value=service.concept_baselines.read(draft,identity,operation,expected=binding)
        else:value=service.concept_baselines.prepare(draft,identity,_body(handler),expected=binding)
        protected_reply(handler,service,draft,identity,binding,value)
    except (PermissionError,WorklistError) as error:
        code=getattr(error,'state','DENIED')
        status=403 if code in ('DENIED','UNAUTHORIZED') else 404 if code=='PROPOSAL_NOT_FOUND' else 409 if code in ('PROPOSAL_IDEMPOTENCY_CONFLICT','PROPOSAL_CAPACITY_EXHAUSTED') else 503
        handler._reply(status,{'error':code})
    except FileNotFoundError:handler._reply(404,{'error':'BASELINE_NOT_FOUND'})
    except ConversationConflict:handler._reply(409,{'error':'BASELINE_CONFLICT'})
    except (ConceptStorageUnavailable,sqlite3.Error):handler._reply(503,{'error':'BASELINE_STORAGE_UNAVAILABLE'})
    except ValueError:handler._reply(400 if handler.command=='POST' else 503,{'error':'BASELINE_INVALID_OR_UNAVAILABLE'})
    except (OSError,KeyError,TypeError):handler._reply(503,{'error':'BASELINE_UNAVAILABLE'})
    return True
