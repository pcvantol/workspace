"""Workspace-only project ideas in the existing private draft database.

Pairing scope is the existing Workspace actor/context, never an EP identity.
No peer calls, project registration, provider or engineering effect exists here.
"""
from contextlib import contextmanager
import hashlib
import json
import os
from .service import _private_json
import re
import secrets
import sqlite3
from .conversations import ConversationConflict, _now, _text

ID = re.compile(r'[0-9a-f]{32}\Z')
FIELDS = {'title', 'notes', 'operation_id', 'expected_revision'}
COLUMNS = {'id','actor_id','context_id','title','notes','revision','created_at','updated_at'}


class ConceptStorageUnavailable(ValueError):
    """Existing concept storage is unavailable; never initialize a replacement."""


class ProjectConceptStore:
    def __init__(self, conversations):
        self.base = conversations

    @contextmanager
    def authorized(self, token):
        scope = self.base.scope(token)
        with self.base.forward_grant(token, scope):
            yield scope
            if self.base.scope(token) != scope:
                raise PermissionError('concept scope changed')

    def _connect(self, *, write=False):
        # Read absence is empty, never bootstraps or replaces a failed store.
        from .project_concept_library import preflight, schema
        preflight(self.base)
        try:
            marker = _private_json('project-concepts-schema-v1.json', dir_fd=self.base.root_fd)
        except FileNotFoundError:
            marker = None
        except (ValueError, OSError, UnicodeError) as error:
            raise ConceptStorageUnavailable('concept allocation unavailable') from error
        if marker is not None and (not isinstance(marker,dict) or set(marker) != {'schema_version'} or type(marker['schema_version']) is not int or marker['schema_version'] != 1):
            raise ConceptStorageUnavailable('incompatible concept allocation')
        existing = (self.base.root / 'conversations.sqlite3').exists()
        if not existing and marker is not None:
            raise ConceptStorageUnavailable('initialized concept source lost')
        if not existing and not write:
            raise FileNotFoundError('concept store not yet created')
        try:
            db = self.base._connect(create=not existing and write, read_only=not write, existing_only=True)
        except (ValueError, OSError, sqlite3.Error) as error:
            raise ConceptStorageUnavailable('invalid existing private store') from error
        try:
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            schema(self.base,db)
            if 'project_concepts_v1' in tables:
                columns = {row[1] for row in db.execute('PRAGMA table_info(project_concepts_v1)')}
                if columns != COLUMNS:
                    raise ConceptStorageUnavailable('incompatible concept schema')
                if 'project_concept_operations_v1' not in tables or {row[1] for row in db.execute('PRAGMA table_info(project_concept_operations_v1)')} != {'actor_id','context_id','operation_id','request_digest','response'}:
                    raise ConceptStorageUnavailable('incomplete concept schema')
            elif 'project_concept_operations_v1' in tables:
                raise ConceptStorageUnavailable('incomplete concept schema')
            elif marker is not None:
                raise ConceptStorageUnavailable('initialized concept schema lost')
            elif write:
                with db:
                    db.execute('''CREATE TABLE project_concepts_v1 (
                        id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, context_id TEXT NOT NULL,
                        title TEXT NOT NULL, notes TEXT NOT NULL, revision INTEGER NOT NULL,
                        created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''')
                    db.execute('''CREATE TABLE project_concept_operations_v1 (
                        actor_id TEXT NOT NULL, context_id TEXT NOT NULL, operation_id TEXT NOT NULL,
                        request_digest TEXT NOT NULL, response TEXT NOT NULL,
                        PRIMARY KEY(actor_id,context_id,operation_id))''')
            else:
                raise FileNotFoundError('concept store not yet created')
            if write and marker is None:
                descriptor = os.open('project-concepts-schema-v1.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=self.base.root_fd)
                with os.fdopen(descriptor,'w') as stream:
                    json.dump({'schema_version':1},stream); stream.flush(); os.fsync(stream.fileno())
                os.fsync(self.base.root_fd)
            return db
        except Exception:
            db.close()
            raise

    @staticmethod
    def _record(row):
        return dict(row) | {'state':'CONCEPT_NOT_CONFIGURED'}

    def list(self, scope):
        with self.base.lock:
            try:
                db = self._connect()
            except FileNotFoundError:
                return {'actor_id':scope[0], 'context_id':scope[1], 'concepts':[]}
            try:
                rows = db.execute('SELECT id,actor_id,context_id,title,revision,created_at,updated_at FROM project_concepts_v1 WHERE actor_id=? AND context_id=? ORDER BY updated_at DESC,id LIMIT 501',scope).fetchall()
                if len(rows) > 500:
                    raise ValueError('concept inventory limit')
                return {'actor_id':scope[0], 'context_id':scope[1], 'concepts':[self._record(row) for row in rows]}
            finally:
                db.close()

    def get(self, scope, identity):
        if not isinstance(identity,str) or ID.fullmatch(identity) is None:
            raise FileNotFoundError('concept not found')
        with self.base.lock:
            db = self._connect()
            try:
                row = db.execute('SELECT * FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                if row is None:
                    raise FileNotFoundError('concept not found')
                return self._record(row)
            finally:
                db.close()

    def save(self, scope, fields, *, identity=None):
        if not isinstance(fields,dict) or set(fields) != FIELDS:
            raise ValueError('invalid concept fields')
        title = _text(fields['title'],120,required=True)
        notes = _text(fields['notes'],10000)
        operation = fields['operation_id']; revision = fields['expected_revision']
        if (not isinstance(operation,str) or ID.fullmatch(operation) is None or
                type(revision) is not int or revision < 0 or revision > 1000000 or
                (identity is None and revision != 0) or (identity is not None and (ID.fullmatch(identity) is None or revision < 1))):
            raise ValueError('invalid concept operation')
        digest = hashlib.sha256(json.dumps({'id':identity,**fields},sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        with self.base.lock:
            db = self._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    prior = db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,operation)).fetchone()
                    if prior is not None:
                        if prior['request_digest'] != digest:
                            raise ConversationConflict('original concept request changed')
                        return json.loads(prior['response'])
                    count = db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]
                    if count >= 4096:
                        raise ValueError('concept receipt limit')
                    stamp = _now()
                    if identity is None:
                        count = db.execute('SELECT count(*) FROM project_concepts_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]
                        if count >= 500:
                            raise ValueError('concept limit')
                        identity = secrets.token_hex(16)
                        db.execute('INSERT INTO project_concepts_v1 VALUES (?,?,?,?,?,?,?,?)',(identity,*scope,title,notes,1,stamp,stamp))
                    else:
                        from .project_concept_library import lifecycle_for
                        if db.execute('SELECT 1 FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone() is not None and lifecycle_for(self.base,db,identity) == 'ARCHIVED':
                            raise ConversationConflict('restore archived concept before editing')
                        cursor = db.execute('UPDATE project_concepts_v1 SET title=?,notes=?,revision=revision+1,updated_at=? WHERE id=? AND actor_id=? AND context_id=? AND revision=?',(title,notes,stamp,identity,*scope,revision))
                        if cursor.rowcount != 1:
                            exists = db.execute('SELECT 1 FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                            if exists is None:
                                raise FileNotFoundError('concept not found')
                            raise ConversationConflict('concept revision changed')
                    result = self._record(db.execute('SELECT * FROM project_concepts_v1 WHERE id=?',(identity,)).fetchone())
                    db.execute('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',(*scope,operation,digest,json.dumps(result,ensure_ascii=False)))
                    return result
            finally:
                db.close()
