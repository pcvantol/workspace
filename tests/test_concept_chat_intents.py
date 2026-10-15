"""Durable own original request only; no model/Forge runtime success claim."""
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest
from workspace_control.service import initialize,Service
from workspace_control.concept_chat_intents import ConceptChatIntents,TABLE,MARKER
from workspace_control.project_concept_library import ProjectConceptLibrary
from workspace_control.project_concepts import ConceptStorageUnavailable
from workspace_control.conversations import ConversationConflict

class ConceptChatIntentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.root.chmod(0o700);initialize(self.root);self.service=Service(self.root)
        self.scope=('alice','own');self.token=self.service.conversations.issue_grant(*self.scope);self.store=self.service.project_concepts
        self.concept=self.store.save(self.scope,{'title':'Saved idea','notes':'Declared purpose','operation_id':'a'*32,'expected_revision':0})
        self.id=self.concept['id'];self.journal=ConceptChatIntents(self.store)
        self.command={'operation_id':'b'*32,'turn_id':'c'*32,'expected_concept_revision':1,'role':'BUSINESS','language':'en','message':'Who is this for?'}
        self.binding={'id':'own-binding','actor_id':'alice','context_id':'own','concept_id':self.id,'instance_id':'producer-instance','principal_id':'peer-alice','audience':'workspace-advice','dossier_id':'private-dossier','conversation_id':'own-conversation','producer_source':'a'*40,'transfer_policy_digest':'sha256:'+'d'*64}
    def tearDown(self):self.service.close();self.temp.cleanup()
    def freeze(self,command=None,binding=None):
        with self.store.authorized(self.token) as scope:return self.journal.freeze(scope,self.id,command or self.command,binding or self.binding,0)
    def test_durable_original_before_transport_and_replay_after_service_reopen(self):
        value=self.freeze();self.assertEqual(value['state'],'ORIGINAL_TURN_CAPTURED');self.assertEqual(self.freeze(),value)
        self.store.save(self.scope,{'title':'Later idea','notes':'Later text','operation_id':'e'*32,'expected_revision':1},identity=self.id)
        self.assertEqual(self.freeze(),value)
        with Service(self.root) as restarted:
            journal=ConceptChatIntents(restarted.project_concepts)
            self.assertEqual(journal.get(self.scope,self.id,'b'*32),value)
        with self.assertRaises(ConversationConflict):self.freeze(dict(self.command,message='Different message'))
        with self.assertRaises(FileNotFoundError):self.journal.get(('bob','own'),self.id,'b'*32)
        with self.assertRaises(FileNotFoundError):self.journal.get(self.scope,self.id,'f'*32)
    def test_archive_stale_tamper_scope_and_revoke_prevent_new_turn(self):
        with self.assertRaises(PermissionError):self.freeze(binding=dict(self.binding,actor_id='bob'))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,turn_id='bad'))
        with self.assertRaises(ValueError):self.freeze(command=dict(self.command,unexpected=True))
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,expected_concept_revision=2))
        ProjectConceptLibrary(self.store).move(self.scope,self.id,{'operation_id':'e'*32,'expected_revision':1,'lifecycle':'ARCHIVED'})
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,expected_concept_revision=2))
        self.service.conversations.revoke_grants(*self.scope)
        with self.assertRaises(PermissionError):self.freeze()
    def test_initialized_missing_and_corrupt_request_never_become_new_turn(self):
        self.freeze()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('UPDATE '+TABLE+' SET record=?',(json.dumps({'changed':True}),))
        with self.assertRaises(ConceptStorageUnavailable):self.journal.get(self.scope,self.id,'b'*32)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DROP TABLE '+TABLE)
        with self.assertRaises(ConceptStorageUnavailable):self.freeze(command=dict(self.command,operation_id='e'*32))
        self.assertTrue((self.root/MARKER).is_file())

    def test_individual_and_combined_allocation_loss_cannot_reset_originals(self):
        self.freeze()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DELETE FROM '+TABLE)
        with self.assertRaises(ConceptStorageUnavailable):self.journal.get(self.scope,self.id,'b'*32)
        with self.assertRaises(ConceptStorageUnavailable):self.freeze()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DROP TABLE '+TABLE)
        (self.root/MARKER).unlink()
        with self.assertRaises(ConceptStorageUnavailable):self.freeze(command=dict(self.command,operation_id='e'*32))
    def test_operation_collision_never_reuses_another_concept_action(self):
        with self.assertRaises(ConversationConflict):self.freeze(command=dict(self.command,operation_id='a'*32))
