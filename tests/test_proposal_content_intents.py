"""Own durable intent tests; synthetic inputs do not qualify Forge runtime."""
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from workspace_control.service import initialize,Service
from workspace_control.proposal_content_intents import ProposalContentIntents,TABLE,MARKER
from workspace_control.project_concept_library import ProjectConceptLibrary
from workspace_control.project_concepts import ConceptStorageUnavailable
from workspace_control.conversations import ConversationConflict
import test_proposal_content_wire as fixtures

class ContentIntentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.root.chmod(0o700);initialize(self.root);self.service=Service(self.root)
        self.scope=('alice','own');self.token=self.service.conversations.issue_grant(*self.scope);self.store=self.service.project_concepts
        self.concept=self.store.save(self.scope,{'title':'Saved idea','notes':'Declared purpose','operation_id':'a'*32,'expected_revision':0});self.id=self.concept['id'];self.journal=ProposalContentIntents(self.store)
        fixture=fixtures.ContentWireTests();fixture.setUp();self.request=fixture.append();self.request['operation_id']='b'*32;self.points=fixture.points
        self.binding={k:v for k,v in fixture.binding.items() if k not in ('permissions','roles')}
        self.binding.update(id='decision-pair',actor_id='alice',context_id='own',concept_id=self.id,producer_source='d'*40,source_binding_id='source-pair',source_principal_id='source-owner')
        self.command={'operation_id':'b'*32,'source_operation_id':'c'*32,'expected_concept_revision':1,'selection_digest':'d'*64,**{k:self.request[k] for k in ('role','decision','reason','acknowledged_open_points')}}
    def tearDown(self):self.service.close();self.temp.cleanup()
    def freeze(self,command=None,binding=None,request=None):
        with self.store.authorized(self.token) as scope:return self.journal.freeze(scope,self.id,command or self.command,binding or self.binding,request or self.request,self.points)
    def test_original_durable_after_reopen_without_changing_subject_or_command(self):
        original=self.freeze();self.assertEqual(self.freeze(),original)
        with Service(self.root) as restarted:self.assertEqual(ProposalContentIntents(restarted.project_concepts).get(self.scope,self.id,'b'*32),original)
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,selection_digest='e'*64))
        self.store.save(self.scope,{'title':'Later','notes':'Not original','operation_id':'e'*32,'expected_revision':1},identity=self.id)
        self.assertEqual(self.freeze(),original)
        with self.assertRaises(FileNotFoundError):self.journal.get(('bob','own'),self.id,'b'*32)
        with self.assertRaises(FileNotFoundError):self.journal.get(self.scope,self.id,'f'*32)
    def test_stale_archived_changed_body_and_wrong_actor_reject(self):
        with self.assertRaises(PermissionError):self.freeze(binding=dict(self.binding,actor_id='bob'))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,extra=True))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,operation_id='bad'))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,expected_concept_revision=True))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,reason='Changed'))
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,expected_concept_revision=2))
        ProjectConceptLibrary(self.store).move(self.scope,self.id,{'operation_id':'e'*32,'expected_revision':1,'lifecycle':'ARCHIVED'})
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,expected_concept_revision=2))
        self.service.conversations.revoke_grants(*self.scope)
        with self.assertRaises(PermissionError):self.freeze()
    def test_tamper_and_allocation_loss_never_reset_original(self):
        self.freeze()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('UPDATE '+TABLE+' SET record=?',(json.dumps({'changed':True}),))
        with self.assertRaises(ConceptStorageUnavailable):self.journal.get(self.scope,self.id,'b'*32)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DROP TABLE '+TABLE)
        with self.assertRaises(ConceptStorageUnavailable):self.freeze()
        (self.root/MARKER).unlink()
        with self.assertRaises(ConceptStorageUnavailable):self.freeze()
    def test_row_witness_and_marker_loss_reject(self):
        self.freeze()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DELETE FROM '+TABLE)
        with self.assertRaises(ConceptStorageUnavailable):self.journal.list(self.scope,self.id)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DROP TABLE '+TABLE)
        with self.assertRaises(ConceptStorageUnavailable):self.journal.list(self.scope,self.id)
    def test_operation_namespace_and_invalid_original_request(self):
        command=dict(self.command,operation_id='a'*32);request=dict(self.request,operation_id='a'*32)
        with self.assertRaises(ConversationConflict):self.freeze(command=command,request=request)
        with self.assertRaises(ValueError):self.freeze(request=dict(self.request,operation_id='f'*32))
        self.freeze();(self.root/MARKER).write_text('{"schema_version":true}')
        with self.assertRaises(ConceptStorageUnavailable):self.journal.list(self.scope,self.id)

    def test_transport_admission_prevents_false_absence_disposition(self):
        original=self.freeze();self.assertTrue(self.journal.admit_transport(self.scope,self.id,'b'*32))
        self.store.save(self.scope,{'title':'Later','notes':'Changed after transport admission','operation_id':'e'*32,'expected_revision':1},identity=self.id)
        self.assertFalse(self.journal.admit_transport(self.scope,self.id,'b'*32));self.assertEqual(self.journal.rejections(self.scope,self.id),set());self.assertEqual(self.journal.get(self.scope,self.id,'b'*32),original)
