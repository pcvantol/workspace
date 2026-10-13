import unittest,tempfile,os,json
from pathlib import Path
from workspace_control.service import initialize,Service
from workspace_control.concept_baseline_intents import ConceptBaselineIntents,TABLE,MARKER
from workspace_control.project_concept_library import ProjectConceptLibrary
from workspace_control.project_concepts import ConceptStorageUnavailable
from workspace_control.conversations import ConversationConflict

class ConceptBaselineIntentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);os.chmod(self.root,0o700);initialize(self.root);self.service=Service(self.root)
        self.token=self.service.conversations.issue_grant('alice','context');self.scope=('alice','context');self.store=self.service.project_concepts
        self.source=self.store.save(self.scope,{'title':'Saved idea','notes':'Declared purpose','operation_id':'1'*32,'expected_revision':0})
        self.journal=ConceptBaselineIntents(self.store);self.command={'operation_id':'2'*32,'expected_revision':1,'description':None}
        self.binding={'id':'own-binding','actor_id':'alice','context_id':'context','concept_id':self.source['id'],'instance_id':'producer-instance','dossier_id':'private-dossier','audience':'workspace-server','producer_source':'a'*40,'principal_id':'peer-alice'}
    def tearDown(self):self.service.close();self.temp.cleanup()
    def freeze(self,command=None,binding=None):
        with self.store.authorized(self.token) as scope:return self.journal.freeze(scope,self.source['id'],command or self.command,binding or self.binding)
    def test_original_request_same_after_restart_and_new_revision(self):
        value=self.freeze();self.assertEqual(value['state'],'ORIGINAL_REQUEST_CAPTURED');self.assertEqual(value,self.freeze())
        updated=self.store.save(self.scope,{'title':'Changed saved idea','notes':'Later description','operation_id':'3'*32,'expected_revision':1},identity=self.source['id'])
        self.assertEqual(value,self.freeze())
        second=self.freeze(dict(self.command,operation_id='4'*32,expected_revision=2));self.assertEqual(second['references'],value['references']);self.assertNotEqual(second['request_digest'],value['request_digest'])
        with Service(self.root) as restarted:
            journal=ConceptBaselineIntents(restarted.project_concepts)
            with restarted.project_concepts.authorized(self.token) as scope:self.assertEqual(journal.get(scope,self.source['id'],self.command['operation_id']),value)
        self.assertEqual(self.store.get(self.scope,self.source['id']),updated)
    def test_conflict_foreign_actor_binding_and_actual_revocation(self):
        value=self.freeze()
        with self.assertRaises(ConversationConflict):self.freeze(dict(self.command,description='Different choice'))
        with self.assertRaises(PermissionError):self.freeze(binding=dict(self.binding,actor_id='bob'))
        with self.assertRaises(FileNotFoundError):self.journal.get(('bob','context'),self.source['id'],self.command['operation_id'])
        self.service.conversations.revoke_grants('alice','context')
        with self.assertRaises(PermissionError):self.freeze()
        self.assertEqual(value['mapping']['source']['notes'],'Declared purpose')
    def test_archive_new_prepare_blocked_historical_unchanged(self):
        value=self.freeze();library=ProjectConceptLibrary(self.store)
        library.move(self.scope,self.source['id'],{'operation_id':'3'*32,'expected_revision':1,'lifecycle':'ARCHIVED'})
        with self.assertRaises(ConversationConflict):self.freeze(dict(self.command,operation_id='4'*32,expected_revision=2))
        self.assertEqual(value,self.journal.get(self.scope,self.source['id'],self.command['operation_id']))
        with self.assertRaises(ConversationConflict):self.freeze(dict(self.command,operation_id='5'*32,expected_revision=1))
    def test_corrupt_or_missing_initialized_store_not_empty_replacement(self):
        self.freeze();db=self.store._connect(write=True)
        with db:db.execute('UPDATE '+TABLE+' SET record=?',(json.dumps({'unexpected':'tampered'}),))
        db.close()
        with self.assertRaises(ConceptStorageUnavailable):self.journal.get(self.scope,self.source['id'],self.command['operation_id'])
        db=self.store._connect(write=True)
        with db:db.execute('DROP TABLE '+TABLE)
        db.close()
        with self.assertRaises(ConceptStorageUnavailable):self.freeze(dict(self.command,operation_id='4'*32))
        self.assertEqual(self.store.get(self.scope,self.source['id']),self.source)
