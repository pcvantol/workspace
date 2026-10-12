"""Small authenticated own project-concept HTTP projection."""
import json
import re
import sqlite3
from .conversations import ConversationConflict
from .project_concepts import ConceptStorageUnavailable


def handle(handler, service):
    path = handler.path
    if not path.startswith('/v1/project-concepts'):
        return False
    match = re.fullmatch(r'/v1/project-concepts(?:/([0-9a-f]{32}))?',path)
    if match is None:
        handler._reply(400,{'error':'INVALID_PATH'}); return True
    if not handler._pinned_auth():
        return True
    grants = handler.headers.get_all('X-Workspace-Draft-Grant',[])
    if len(grants)!=1 or re.fullmatch(r'[A-Za-z0-9_-]{43}',grants[0]) is None:
        handler._reply(403,{'error':'CONCEPT_ACCESS_DENIED'}); return True
    identity = match[1]; body = None
    if handler.command not in ('GET','POST','PATCH') or (handler.command=='POST' and identity is not None) or (handler.command=='PATCH' and identity is None):
        handler._reply(405,{'error':'METHOD_NOT_ALLOWED'}); return True
    if handler.command != 'GET':
        sizes=handler.headers.get_all('Content-Length',[])
        if len(sizes)!=1 or not sizes[0].isdecimal() or not 1<=int(sizes[0])<=64000 or handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Type','').split(';')[0].lower()!='application/json':
            handler._reply(400,{'error':'INVALID_BODY'}); return True
        try:
            def unique(pairs):
                value={}
                for key,item in pairs:
                    if key in value:raise ValueError('duplicate key')
                    value[key]=item
                return value
            body=json.loads(handler.rfile.read(int(sizes[0])),object_pairs_hook=unique)
        except (ValueError,UnicodeError,RecursionError):
            handler._reply(400,{'error':'INVALID_BODY'}); return True
    elif handler.headers.get('Transfer-Encoding') or handler.headers.get('Content-Length','0')!='0':
        handler._reply(400,{'error':'INVALID_BODY'}); return True
    try:
        # Same existing actor/context grant; no EP or catalogue prerequisite.
        # Keep existing cross-process revoke fence through storage AND publication.
        with service.project_concepts.authorized(grants[0]) as scope:
            if handler.command=='GET':
                value=service.project_concepts.get(scope,identity) if identity else service.project_concepts.list(scope)
            else:
                value=service.project_concepts.save(scope,body,identity=identity)
            handler._reply(201 if handler.command=='POST' else 200,value)
    except PermissionError:
        handler._reply(403,{'error':'CONCEPT_ACCESS_DENIED'})
    except ConversationConflict:
        handler._reply(409,{'error':'CONCEPT_CONFLICT'})
    except FileNotFoundError:
        handler._reply(404,{'error':'CONCEPT_NOT_FOUND'})
    except ConceptStorageUnavailable:
        handler._reply(503,{'error':'CONCEPT_STORAGE_UNAVAILABLE'})
    except ValueError:
        handler._reply(400 if body is not None else 503,{'error':'CONCEPT_INVALID_OR_UNAVAILABLE'})
    except (OSError,sqlite3.Error):
        handler._reply(503,{'error':'CONCEPT_STORAGE_UNAVAILABLE'})
    return True
