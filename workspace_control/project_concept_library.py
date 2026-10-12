"""Versioned own concept lifecycle overlay; explicit writes allocate, reads never migrate."""
import hashlib
import json
import os
import sqlite3
from .conversations import ConversationConflict, _now
from .project_concepts import ConceptStorageUnavailable, ID
from .service import _private_json

VERSION = 'project-concept-library/1'
TABLE = 'project_concept_lifecycle_v1'
MARKER = 'project-concept-library-schema-v1.json'


def schema(base, db, *, write=False):
    try:
        marker = _private_json(MARKER, dir_fd=base.root_fd)
    except FileNotFoundError:
        marker = None
    except (ValueError, OSError, UnicodeError) as error:
        raise ConceptStorageUnavailable('library allocation unavailable') from error
    if marker is not None and marker != {'library_version': VERSION}:
        raise ConceptStorageUnavailable('incompatible library allocation')
    exists = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (TABLE,)).fetchone() is not None
    if exists:
        if {r[1]:r[5] for r in db.execute('PRAGMA table_info('+TABLE+')')} != {'concept_id':1,'lifecycle':0}:
            raise ConceptStorageUnavailable('incompatible library schema')
        if db.execute('SELECT 1 FROM '+TABLE+' l LEFT JOIN project_concepts_v1 c ON c.id=l.concept_id WHERE c.id IS NULL OR l.lifecycle NOT IN (\'ACTIVE\',\'ARCHIVED\') LIMIT 1').fetchone():
            raise ConceptStorageUnavailable('invalid library source')
    elif marker is not None:
        raise ConceptStorageUnavailable('initialized library source lost')
    elif write:
        # Explicit authorized lifecycle-write allocation. Never invoked by a GET.
        with db:
            db.execute('CREATE TABLE '+TABLE+' (concept_id TEXT PRIMARY KEY, lifecycle TEXT NOT NULL CHECK(lifecycle IN (\'ACTIVE\',\'ARCHIVED\')))')
        exists = True
    if write and marker is None:
        fd = os.open(MARKER, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o600, dir_fd=base.root_fd)
        with os.fdopen(fd,'w') as stream:
            json.dump({'library_version':VERSION},stream); stream.flush(); os.fsync(stream.fileno())
        os.fsync(base.root_fd)
    return exists


def lifecycle_for(base, db, identity):
    if not schema(base, db):
        return 'ACTIVE'
    row = db.execute('SELECT lifecycle FROM '+TABLE+' WHERE concept_id=?',(identity,)).fetchone()
    return row[0] if row else 'ACTIVE'


class ProjectConceptLibrary:
    def __init__(self, store):
        self.store = store
        self.base = store.base

    def read(self, scope, identity=None):
        with self.base.lock:
            try:
                db = self.store._connect()
            except FileNotFoundError:
                if identity is not None:
                    raise
                return {'library_version':VERSION,'actor_id':scope[0],'context_id':scope[1],'concepts':[]}
            try:
                allocated = schema(self.base, db)
                columns = 'c.*' if identity else 'c.id,c.actor_id,c.context_id,c.title,c.revision,c.created_at,c.updated_at'
                lifecycle = "coalesce(l.lifecycle,'ACTIVE')" if allocated else "'ACTIVE'"
                join = ' LEFT JOIN '+TABLE+' l ON l.concept_id=c.id' if allocated else ''
                query = 'SELECT '+columns+','+lifecycle+' AS lifecycle FROM project_concepts_v1 c'+join+' WHERE c.actor_id=? AND c.context_id=?'
                args = scope
                if identity is not None:
                    query += ' AND c.id=?'; args = (*scope,identity)
                rows = db.execute(query+' ORDER BY c.updated_at DESC,c.id LIMIT 501',args).fetchall()
                if len(rows)>500:
                    raise ConceptStorageUnavailable('concept inventory limit')
                records = [self.store._record(row) | {'library_version':VERSION} for row in rows]
                if identity is not None:
                    if not records: raise FileNotFoundError('concept not found')
                    return records[0]
                return {'library_version':VERSION,'actor_id':scope[0],'context_id':scope[1],'concepts':records}
            finally:
                db.close()

    def move(self, scope, identity, fields):
        if (not isinstance(fields,dict) or set(fields)!={'operation_id','expected_revision','lifecycle'} or
                not isinstance(identity,str) or ID.fullmatch(identity) is None or
                not isinstance(fields.get('operation_id'),str) or ID.fullmatch(fields['operation_id']) is None or
                type(fields.get('expected_revision')) is not int or not 1<=fields['expected_revision']<=1000000 or
                fields.get('lifecycle') not in ('ACTIVE','ARCHIVED')):
            raise ValueError('invalid lifecycle intent')
        digest = hashlib.sha256(json.dumps({'library_version':VERSION,'id':identity,**fields},sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        with self.base.lock:
            db = self.store._connect(write=True)
            try:
                schema(self.base,db,write=True)
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    prior = db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?',(*scope,fields['operation_id'])).fetchone()
                    if prior is not None:
                        if prior['request_digest'] != digest: raise ConversationConflict('original library intent changed')
                        return json.loads(prior['response'])
                    row = db.execute('SELECT * FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?',(identity,*scope)).fetchone()
                    if row is None: raise FileNotFoundError('concept not found')
                    if lifecycle_for(self.base,db,identity)==fields['lifecycle']:
                        raise ConversationConflict('lifecycle already changed')
                    count = db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?',scope).fetchone()[0]
                    if count>=4096: raise ValueError('concept receipt limit')
                    changed = db.execute('UPDATE project_concepts_v1 SET revision=revision+1,updated_at=? WHERE id=? AND actor_id=? AND context_id=? AND revision=?',(_now(),identity,*scope,fields['expected_revision']))
                    if changed.rowcount!=1: raise ConversationConflict('concept revision changed')
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?) ON CONFLICT(concept_id) DO UPDATE SET lifecycle=excluded.lifecycle',(identity,fields['lifecycle']))
                    current = db.execute('SELECT * FROM project_concepts_v1 WHERE id=?',(identity,)).fetchone()
                    result = self.store._record(current) | {'library_version':VERSION,'lifecycle':fields['lifecycle']}
                    db.execute('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',(*scope,fields['operation_id'],digest,json.dumps(result,ensure_ascii=False)))
                    return result
            finally:
                db.close()
