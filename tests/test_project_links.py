"""SYNTHETIC normalized gateway tests. Not EP wire/installed qualification."""
import copy
from contextlib import contextmanager
import threading
from dataclasses import replace
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from workspace_control.conversations import ConversationStore
from workspace_control.project_links import (LinkConflict, LinkScope, ProducerUnavailable,
    ProjectLinks, ProjectLinkStore, identifier, timestamp, validate_topology)


class FixtureGateway:
    def __init__(self):
        self.access = LinkScope('actor', 'ep-test', frozenset(['atlas']), '2040-01-01T00:00:00Z', 'epoch-1')
        self.authority_lock = threading.RLock()
        self.projects = [{'id':'atlas','name':'Atlas'}]; self.reads = 0; self.deny_after_read = False
        self.value = {'peer_id': 'ep-test', 'project_id': 'atlas', 'name': 'Atlas',
            'authority_repository_id': 'core', 'revision': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'observed_at': '2026-10-12T00:00:00Z',
            'repositories': [{'id': 'core', 'name': 'Core', 'role': 'authority', 'available_attachments': 2},
                {'id': 'client', 'name': 'Client', 'role': 'child', 'available_attachments': 0}]}
    def scope(self, token):
        if token != 'synthetic-viewer' or self.deny_after_read and self.reads:
            raise PermissionError('synthetic access denied')
        return self.access
    @contextmanager
    def authorization(self, token, expected):
        with self.authority_lock:
            if self.scope(token) != expected:
                raise PermissionError('synthetic scope changed')
            yield
    def discover(self, scope):
        self.reads += 1
        return copy.deepcopy(self.projects)
    def topology(self, scope, project):
        self.reads += 1
        return copy.deepcopy(self.value)


class ProjectLinksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        os.chmod(self.root, 0o700); self.fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        self.conversations = ConversationStore(self.root, self.fd)
        self.gateway = FixtureGateway(); self.links = ProjectLinks(self.conversations, self.gateway)
    def tearDown(self):
        os.close(self.fd); self.temp.cleanup()
    def test_short_route_multiple_attachments_and_dedup_survive_restart(self):
        self.assertEqual(self.links.discover('synthetic-viewer')['state'], 'AVAILABLE')
        topology = self.links.inspect('synthetic-viewer', 'atlas')
        self.assertEqual(len(topology['repositories']), 2)
        for operation in ['same', 'same', 'independent-double-click']:
            self.assertEqual(self.links.link('synthetic-viewer', 'atlas', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', operation, authority_id='core')['state'], 'REFERENCE_SAVED')
        restarted = ProjectLinks(ConversationStore(self.root, self.fd), self.gateway)
        opened = restarted.open('synthetic-viewer', 'atlas')
        self.assertEqual(opened['engineering_readiness'], 'NOT_ASSESSED')
        self.assertEqual(len(restarted.store.identities(self.gateway.access)), 1)
        with sqlite3.connect(self.root/'conversations.sqlite3') as connection:
            self.assertEqual(connection.execute('SELECT count(*) FROM project_links').fetchone()[0], 1)
            self.assertEqual(connection.execute('SELECT count(*) FROM project_link_operations').fetchone()[0], 2)
            columns = {row[1] for row in connection.execute('PRAGMA table_info(project_links)')}
            self.assertNotIn('name', columns)  # No protected engineering cache/second register.
    def test_full_canonical_identity_is_never_truncated_as_display_name(self):
        for identity in ['x'*121,'x'*128,'atlas..prod']:
            self.gateway.access=replace(self.gateway.access,project_ids=frozenset([identity]))
            self.gateway.projects=[{'id':identity,'name':identity}]
            self.gateway.value['project_id']=identity;self.gateway.value['name']=identity
            self.gateway.value['authority_repository_id']='r'*128
            self.gateway.value['repositories']=[{'id':'r'*128,'name':'r'*128,'role':'authority','available_attachments':None}]
            self.assertEqual(self.links.discover('synthetic-viewer')['projects'][0]['name'],identity)
            self.assertEqual(self.links.inspect('synthetic-viewer',identity)['project_id'],identity)

    def test_current_viewer_peer_project_expiry_and_changed_topology_guards(self):
        with self.assertRaises(ProducerUnavailable): ProjectLinks(self.conversations).discover('anything')
        with self.assertRaises(PermissionError): self.links.discover('wrong-viewer')
        with self.assertRaises(PermissionError): self.links.inspect('synthetic-viewer', 'other')
        with self.assertRaises(LinkConflict): self.links.link('synthetic-viewer', 'atlas', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'op', authority_id='core')
        with self.assertRaises(LinkConflict): self.links.link('synthetic-viewer', 'atlas', True, 'op', authority_id='core')
        self.links.link('synthetic-viewer', 'atlas', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'op', authority_id='core')
        self.gateway.value['revision'] = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        with self.assertRaises(LinkConflict): self.links.link('synthetic-viewer', 'atlas', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'op', authority_id='core')
        self.links.link('synthetic-viewer', 'atlas', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'different', authority_id='core')
        self.gateway.value['authority_repository_id'] = 'client'
        self.gateway.value['repositories'][0]['role'] = 'child'
        self.gateway.value['repositories'][1]['role'] = 'authority'
        with self.assertRaises(LinkConflict): self.links.open('synthetic-viewer', 'atlas')
        with self.assertRaises(LinkConflict): self.links.link('synthetic-viewer', 'atlas', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'binding-conflict', authority_id='core')
        self.gateway.access = replace(self.gateway.access, actor_id='other-viewer')
        with self.assertRaises(FileNotFoundError): self.links.open('synthetic-viewer', 'atlas')
        self.gateway.access = replace(self.gateway.access, expires_at='2020-01-01T00:00:00Z')
        with self.assertRaises(PermissionError): self.links.discover('synthetic-viewer')
    def test_denied_late_publication_and_bounded_discovery(self):
        self.gateway.deny_after_read = True
        with self.assertRaises(PermissionError): self.links.inspect('synthetic-viewer', 'atlas')
        with self.assertRaises(PermissionError): self.links.discover('synthetic-viewer')
        self.gateway.deny_after_read = False
        for projects in [None, [{'id':'atlas','name':'Atlas'}]*101, [{'id':'atlas','name':'Atlas'}]*2, [{}], [{'id':'outside','name':'Outside'}], [{'id':'atlas','name':''}]]:
            self.gateway.projects = projects
            with self.assertRaises((ValueError, PermissionError)): self.links.discover('synthetic-viewer')
        self.gateway.projects = []
        self.assertEqual(self.links.discover('synthetic-viewer')['state'], 'EMPTY')
        original = self.gateway.scope
        self.gateway.scope = lambda token: 'untyped'
        with self.assertRaises(ValueError): self.links.discover('synthetic-viewer')
        count = [0]
        def changing(token):
            count[0] += 1
            return replace(self.gateway.access, epoch='changed') if count[0] > 1 else self.gateway.access
        self.gateway.scope = changing
        with self.assertRaises(PermissionError): self.links.discover('synthetic-viewer')
        self.gateway.scope = original
    def test_revocation_at_actual_save_boundary_rolls_back_and_retains_prior_reference(self):
        self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','original',authority_id='core')
        original = self.links.store.record
        def revoke_before_save(*args, **kwargs):
            self.gateway.deny_after_read = True
            return original(*args, **kwargs)
        self.links.store.record = revoke_before_save
        with self.assertRaises(PermissionError):
            self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','revoked',authority_id='core')
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM project_links').fetchone()[0],1)
            self.assertEqual(db.execute('SELECT operation_id FROM project_link_operations').fetchall(),[('original',)])
        self.gateway.deny_after_read = False
        self.links.store.record = original
        # A changed scope after the SQL lock wait is not a captured-scope permit.
        checks = [0]
        def revoke_before_commit():
            checks[0] += 1
            if checks[0] == 2:
                raise PermissionError('synthetic revoke at commit')
        with self.assertRaises(PermissionError):
            original(self.gateway.access,self.gateway.value,'before-commit',authorize=revoke_before_commit)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM project_link_operations').fetchone()[0],1)
        # Gateways without an owning lifecycle fence cannot authorize a save.
        self.gateway.authorization = None
        with self.assertRaises(ProducerUnavailable):
            self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','no-fence',authority_id='core')
    def test_completed_and_lost_success_reopen_current_topology_without_new_mutation(self):
        self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','lost-success',authority_id='core')
        self.gateway.value['revision'] = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
        restarted = ProjectLinks(ConversationStore(self.root,self.fd),self.gateway)
        self.assertEqual(restarted.open('synthetic-viewer','atlas')['topology']['revision'],'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM project_links').fetchone()[0],1)
            self.assertEqual(db.execute('SELECT count(*) FROM project_link_operations').fetchone()[0],1)

    def test_normalized_topology_rejects_forged_identity_and_ambiguous_sources(self):
        value = self.gateway.value; scope = self.gateway.access
        for key, invalid in [('peer_id','wrong'), ('project_id','wrong'), ('name',''), ('name','x\n'),
                ('name','x'*129), ('authority_repository_id','a/b'), ('revision',True), ('revision',0),
                ('observed_at','not-a-date'), ('repositories',[]), ('repositories',None)]:
            raw = copy.deepcopy(value); raw[key] = invalid
            with self.assertRaises((ValueError,LinkConflict)): validate_topology(raw,scope,'atlas')
        for raw in [None, value|{'extra':'no'}, {'project_id':'atlas'}]:
            with self.assertRaises(ValueError): validate_topology(raw,scope,'atlas')
        for key, invalid in [('id','a/b'), ('name',''), ('name','x\n'), ('name','x'*129),
                ('role','unknown'), ('available_attachments',True), ('available_attachments',-1), ('available_attachments',101)]:
            raw=copy.deepcopy(value);raw['repositories'][0][key]=invalid
            with self.assertRaises((ValueError,LinkConflict)):validate_topology(raw,scope,'atlas')
        for repositories in [[None], [value['repositories'][0]]*2, [value['repositories'][1]], value['repositories']*51]:
            raw=copy.deepcopy(value);raw['repositories']=repositories
            with self.assertRaises((ValueError,LinkConflict)):validate_topology(raw,scope,'atlas')
        for raw in [None,'',42,'bad/path']:
            with self.assertRaises(ValueError):identifier(raw)
        for raw in [None,'2026-10-12','bad']:
            with self.assertRaises(ValueError):timestamp(raw)
        for bad in [replace(scope,project_ids=['atlas']), replace(scope,project_ids=frozenset(['a/b'])),
                replace(scope,project_ids=frozenset(str(i) for i in range(101)))]:
            with self.assertRaises(ValueError):bad.require()
    def test_hidden_other_peer_records_original_intent_cap_and_private_store(self):
        self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','first', authority_id='core')
        self.assertEqual(self.links.store.identities(replace(self.gateway.access,peer_id='other')),[])
        self.assertEqual(self.links.store.identities(replace(self.gateway.access,project_ids=frozenset())),[])
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            db.executemany('INSERT INTO project_link_operations VALUES (?,?,?,?)', [('actor',str(i),'digest','atlas') for i in range(4095)])
        with self.assertRaises(ValueError):self.links.link('synthetic-viewer','atlas','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','over-limit', authority_id='core')
        os.chmod(self.root/'conversations.sqlite3',0o644)
        with self.assertRaises(ValueError):self.links.open('synthetic-viewer','atlas')

if __name__ == '__main__':unittest.main()
