"""Additive briefing overlay in the existing concept database.

The resolver is a trusted Server adapter, never supplied by an HTTP caller. It
must read the exact authorized Forge result; this module defines no peer wire.
No peer wait is held under own authorization or SQLite locks.
"""
import json
import os
import re
from .concept_briefing import VERSION, initial, source, validate, changes
from .concept_baseline_mapping import canonical, digest
from .conversations import ConversationConflict, _now
from .project_concepts import ConceptStorageUnavailable, ID
from .project_concept_library import lifecycle_for
from .service import _private_json

TABLE = 'concept_briefings_v1'
MARKER = 'concept-briefings-schema-v1.json'
COLUMNS = {'concept_id', 'fields', 'fields_digest', 'provenance', 'provenance_digest'}
LIMIT = 256


class ConceptBriefingStore:
    def __init__(self, store):
        self.store = store
        self.base = store.base

    def _schema(self, db, *, write=False):
        try:
            marker = _private_json(MARKER, dir_fd=self.base.root_fd)
        except FileNotFoundError:
            marker = None
        except (OSError, ValueError, UnicodeError) as error:
            raise ConceptStorageUnavailable('briefing allocation unavailable') from error
        if marker is not None and (marker != {'briefing_version': VERSION}):
            raise ConceptStorageUnavailable('incompatible briefing allocation')
        exists = db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (TABLE,)).fetchone() is not None
        witness = db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE json_extract(response,'$.briefing_version')=? LIMIT 1", (VERSION,)).fetchone() is not None
        if (exists and marker is None) or (not exists and (marker is not None or witness)):
            raise ConceptStorageUnavailable('initialized briefing source lost')
        if exists:
            if {row[1] for row in db.execute('PRAGMA table_info('+TABLE+')')} != COLUMNS:
                raise ConceptStorageUnavailable('incompatible briefing schema')
            if db.execute('SELECT 1 FROM '+TABLE+' b LEFT JOIN project_concepts_v1 c ON c.id=b.concept_id WHERE c.id IS NULL LIMIT 1').fetchone():
                raise ConceptStorageUnavailable('orphan briefing')
        elif write:
            db.execute('CREATE TABLE '+TABLE+' (concept_id TEXT PRIMARY KEY,fields TEXT NOT NULL,fields_digest TEXT NOT NULL,provenance TEXT NOT NULL,provenance_digest TEXT NOT NULL)')
            fd = os.open(MARKER, os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW, 0o600, dir_fd=self.base.root_fd)
            with os.fdopen(fd, 'w') as stream:
                json.dump({'briefing_version': VERSION}, stream)
                stream.flush(); os.fsync(stream.fileno())
            os.fsync(self.base.root_fd)
            exists = True
        return exists

    def _read(self, db, scope, identity):
        row = db.execute('SELECT * FROM project_concepts_v1 WHERE id=? AND actor_id=? AND context_id=?', (identity, *scope)).fetchone()
        if row is None:
            raise FileNotFoundError('concept not found')
        concept = self.store._record(row)
        present = self._schema(db)
        overlay = db.execute('SELECT * FROM '+TABLE+' WHERE concept_id=?', (identity,)).fetchone() if present else None
        if overlay is None:
            witness=db.execute("SELECT 1 FROM project_concept_operations_v1 WHERE json_extract(response,'$.briefing_version')=? AND json_extract(response,'$.concept.id')=? LIMIT 1",(VERSION,identity)).fetchone()
            if witness is not None:
                raise ConceptStorageUnavailable('initialized concept briefing row lost')
            fields, provenance = initial(concept), None
        else:
            try:
                fields = validate(json.loads(overlay['fields']))
                provenance = json.loads(overlay['provenance'])
                if digest({'fields':fields,'provenance':provenance}) != overlay['fields_digest'] or digest(provenance) != overlay['provenance_digest'] or type(provenance) is not dict or set(provenance)!={'own_binding','producer_reference'}:
                    raise ValueError('briefing integrity')
                binding=provenance['own_binding']
                if type(binding) is not dict or set(binding)!={'concept_id','actor_id','context_id','adopted_revision','operation_id'} or (binding['concept_id'],binding['actor_id'],binding['context_id'])!=(identity,*scope) or type(binding['adopted_revision']) is not int or not 2<=binding['adopted_revision']<=concept['revision'] or not isinstance(binding['operation_id'],str) or ID.fullmatch(binding['operation_id']) is None:
                    raise ValueError('briefing ownership binding')
            except (ValueError, TypeError) as error:
                raise ConceptStorageUnavailable('briefing corrupt') from error
            # Manual title edits remain authoritative; no model overwrite.
            fields['name'] = concept['title']
        return source(concept, fields) | {'accepted_from': provenance,
                                          'lifecycle': lifecycle_for(self.base, db, identity)}

    def read(self, scope, identity):
        with self.base.lock:
            db = self.store._connect()
            try:
                return self._read(db, scope, identity)
            finally:
                db.close()

    def _receipt(self, db, scope, identity, command, key):
        row = db.execute('SELECT * FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=? AND operation_id=?', (*scope, command['operation_id'])).fetchone()
        if row is None:
            return None
        if row['request_digest'] != key:
            raise ConversationConflict('original adoption changed')
        try:
            if len(row['response'].encode())>128000:raise ValueError('receipt size')
            result = json.loads(row['response'])
            expected=result.pop('receipt_digest')
            if digest(result)!=expected or set(result)!={'briefing_version','concept','fields','source_digest','accepted_from','lifecycle','adoption'}:
                raise ValueError('receipt integrity')
            concept=result['concept'];adoption=result['adoption']
            if result['briefing_version']!=VERSION or concept['id']!=identity or (concept['actor_id'],concept['context_id'])!=tuple(scope) or type(concept['revision']) is not int or concept['revision']!=command['expected_revision']+1 or adoption!={'operation_id':command['operation_id'],'kind':'USER_ACCEPTED_PROPOSAL_NOT_APPROVAL','producer_reference':result['accepted_from']} or result['source_digest']!=source(concept,result['fields'])['source_digest'] or result['lifecycle']!='ACTIVE':
                raise ValueError('receipt binding')
            result['receipt_digest']=expected
            return result
        except (ValueError,KeyError,TypeError,AttributeError) as error:
            raise ConceptStorageUnavailable('adoption receipt corrupt') from error

    def adopt(self, grant, identity, command, resolve):
        if not isinstance(identity, str) or ID.fullmatch(identity) is None or type(command) is not dict or set(command) != {'operation_id', 'expected_revision', 'result_reference', 'displayed_change_digest'}:
            raise ValueError('invalid adoption command')
        if not isinstance(command['operation_id'], str) or ID.fullmatch(command['operation_id']) is None or type(command['expected_revision']) is not int or not 1 <= command['expected_revision'] <= 1000000:
            raise ValueError('invalid adoption identity')
        if not isinstance(command['result_reference'], str) or re.fullmatch('[A-Za-z0-9._:-]{1,256}', command['result_reference']) is None or not isinstance(command['displayed_change_digest'], str) or re.fullmatch('[0-9a-f]{64}', command['displayed_change_digest']) is None:
            raise ValueError('invalid adoption reference')
        key = digest({'kind': VERSION, 'concept_id': identity, 'command': command})
        with self.store.authorized(grant) as scope, self.base.lock:
            db = self.store._connect()
            try:
                current = self._read(db, scope, identity)
                original = self._receipt(db, scope, identity, command, key)
                if original is not None:
                    return original
                if current['lifecycle'] == 'ARCHIVED' or current['concept']['revision'] != command['expected_revision']:
                    raise ConversationConflict('restore or reload concept before adoption')
            finally:
                db.close()
        # Resolver must check actual producer authority and return a validated
        # Server-owned result. Neither supplied text nor its hash is authority.
        verified = resolve(scope, identity, command['result_reference'])
        if type(verified) is not dict or set(verified) != {'source_digest', 'changes', 'producer_reference'} or verified['source_digest'] != current['source_digest']:
            raise ConversationConflict('proposal source changed')
        if digest(verified['changes']) != command['displayed_change_digest']:
            raise ConversationConflict('displayed proposal changed')
        after = changes(current['fields'], verified['changes'])
        producer_reference = verified['producer_reference']
        if type(producer_reference) is not dict or not producer_reference or len(canonical(producer_reference)) > 8192:
            raise ValueError('invalid producer provenance')
        provenance={'own_binding':{'concept_id':identity,'actor_id':scope[0],'context_id':scope[1],'adopted_revision':command['expected_revision']+1,'operation_id':command['operation_id']},'producer_reference':producer_reference}
        # Admission uses the existing renderer-input validator, never a second
        # renderer or model. Random provisional references are validation-only.
        from .concept_baseline_mapping import map_concept, provisional_references
        candidate=dict(current['concept'],title=after['name'],revision=command['expected_revision']+1,
                       briefing={'fields':after,'accepted_from':provenance})
        choice='x'*4096 if len(candidate['notes'])>4096 and not after['purpose'].strip() else None
        map_concept(candidate,scope,provisional_references(),choice)
        with self.store.authorized(grant) as fresh_scope, self.base.lock:
            if fresh_scope != scope:
                raise PermissionError('adoption scope changed')
            db = self.store._connect(write=True)
            try:
                with db:
                    db.execute('BEGIN IMMEDIATE')
                    present = self._schema(db)
                    original = self._receipt(db, scope, identity, command, key)
                    if original is not None:
                        return original
                    fresh = self._read(db, scope, identity)
                    if fresh['source_digest'] != current['source_digest'] or fresh['lifecycle'] == 'ARCHIVED':
                        raise ConversationConflict('concept changed during proposal read')
                    if db.execute('SELECT count(*) FROM project_concept_operations_v1 WHERE actor_id=? AND context_id=?', scope).fetchone()[0] >= 4096:
                        raise ConceptStorageUnavailable('adoption receipt capacity')
                    if present and db.execute('SELECT count(*) FROM '+TABLE).fetchone()[0] >= LIMIT and db.execute('SELECT 1 FROM '+TABLE+' WHERE concept_id=?', (identity,)).fetchone() is None:
                        raise ConceptStorageUnavailable('briefing capacity')
                    if db.execute("SELECT count(*) FROM project_concept_operations_v1 WHERE json_extract(response,'$.briefing_version')=?",(VERSION,)).fetchone()[0]>=256:
                        raise ConceptStorageUnavailable('briefing original receipt capacity')
                    self._schema(db, write=True)
                    db.execute('UPDATE project_concepts_v1 SET title=?,revision=revision+1,updated_at=? WHERE id=? AND actor_id=? AND context_id=? AND revision=?', (after['name'], _now(), identity, *scope, command['expected_revision']))
                    db.execute('INSERT INTO '+TABLE+' VALUES (?,?,?,?,?) ON CONFLICT(concept_id) DO UPDATE SET fields=excluded.fields,fields_digest=excluded.fields_digest,provenance=excluded.provenance,provenance_digest=excluded.provenance_digest', (identity, canonical(after).decode(), digest({'fields':after,'provenance':provenance}), canonical(provenance).decode(), digest(provenance)))
                    result = self._read(db, scope, identity)
                    result['adoption'] = {'operation_id': command['operation_id'], 'kind': 'USER_ACCEPTED_PROPOSAL_NOT_APPROVAL', 'producer_reference': provenance}
                    result['receipt_digest']=digest(result)
                    if len(canonical(result))>128000:raise ValueError('adoption record byte capacity')
                    db.execute('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)', (*scope, command['operation_id'], key, canonical(result).decode()))
                    return result
            finally:
                db.close()
