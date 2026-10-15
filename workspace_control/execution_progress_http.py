"""Closed own progress GET surface, original scope and guarded publication."""
import re
from urllib.parse import urlsplit,parse_qs
from .execution_progress_wire import ProgressError,require,identifier,snapshot
from .worklist_peer import WorklistError
from .concept_baseline_http import protected_reply


def route(handler,service):
    if not handler.path.startswith('/v1/execution-progress'):return False
    try:
        p=urlsplit(handler.path);ident=r'[A-Za-z0-9][A-Za-z0-9._:-]{0,127}'
        match=re.fullmatch('/v1/execution-progress/('+ident+')/(overview|runs/('+ident+'))',p.path)
        require(match is not None and not p.fragment,'INVALID_REQUEST',400)
        require(handler.command=='GET','METHOD_NOT_ALLOWED',405)
        if not handler._pinned_auth():return True
        require(not handler.headers.get_all('Transfer-Encoding',[]) and handler.headers.get_all('Content-Length',[]) in ([],['0']),'INVALID_REQUEST',400)
        query=parse_qs(p.query,keep_blank_values=True,strict_parsing=True)
        require(set(query) in ({'mission_id'},{'mission_id','expected_snapshot'}) and all(len(v)==1 for v in query.values()),'INVALID_REQUEST',400)
        mission=identifier(query['mission_id'][0]);expected=query.get('expected_snapshot',[None])[0]
        if expected is not None:snapshot(expected)
        drafts=handler.headers.get_all('X-Workspace-Draft-Grant',[]);activities=handler.headers.get_all('X-Workspace-Activity-Grant',[]);epochs=handler.headers.get_all('X-Workspace-Execution-Binding',[])
        require(len(drafts)==len(activities)==1 and len(epochs)<=1,'DENIED',403)
        workset,_,run=match.groups()
        if run is not None:require(len(epochs)==1 and expected is not None,'INVALID_REQUEST',400)
        value,publication=service.execution_progress.fetch(drafts[0],activities[0],workset,mission,run,expected,epochs[0] if epochs else None)
        protected_reply(handler,service,drafts[0],workset,publication.binding,value,peer=publication)
    except ProgressError as e:handler._reply(e.status,{'error':'EXECUTION_PROGRESS_'+e.code})
    except PermissionError:handler._reply(403,{'error':'EXECUTION_PROGRESS_DENIED'})
    except WorklistError as e:
        code,status=('DENIED',403) if e.state=='DENIED' else ('UNSUPPORTED',422) if e.state=='UNSUPPORTED' else ('SOURCE_CORRUPT',503) if e.state in ('INVALID_RESPONSE','INVALID_CONFIGURATION') else ('UNAVAILABLE',503)
        handler._reply(status,{'error':'EXECUTION_PROGRESS_'+code})
    except (ValueError,KeyError,TypeError):handler._reply(400,{'error':'EXECUTION_PROGRESS_INVALID_REQUEST'})
    except OSError:handler._reply(503,{'error':'EXECUTION_PROGRESS_UNAVAILABLE'})
    return True
