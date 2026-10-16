import unittest,tempfile,os,json
from pathlib import Path
from workspace_control.service import initialize,Service
from workspace_control.concept_adoption_intents import ConceptAdoptionIntents,AdoptionSourceRejected,TABLE,MARKER
from workspace_control.project_concept_library import ProjectConceptLibrary
from workspace_control.project_concepts import ConceptStorageUnavailable
from workspace_control.conversations import ConversationConflict

class ConceptAdoptionIntentTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);os.chmod(self.root,0o700);initialize(self.root);self.service=Service(self.root)
        self.token=self.service.conversations.issue_grant('alice','context');self.scope=('alice','context');self.store=self.service.project_concepts
        self.source=self.store.save(self.scope,{'title':'Saved idea','notes':'Declared purpose','operation_id':'1'*32,'expected_revision':0})
        self.journal=ConceptAdoptionIntents(self.store);self.command={'operation_id':'2'*32,'expected_revision':1,'requested_artifacts':['docs/product/VISION.md','docs/architecture/ARCHITECTURE.md','docs/roadmap/ROADMAP.md'],'mappings':[{'artifact_path':'docs/product/VISION.md','source_path':'docs/RICHTING.md','choice':'LINK_EXISTING'}]}
        self.binding={'id':'own-binding','actor_id':'alice','context_id':'context','concept_id':self.source['id'],'instance_id':'producer-instance','dossier_id':'private-dossier','audience':'workspace-server','producer_source':'cd483fd9b17a96d0deac0f0264ab6fc32c75e778','principal_id':'peer-alice','pairing_id':'selected','identity':{'status':'PROVISIONAL_REFERENCE','project_id':'explicit-product','repository_id':'explicit-core','authority_repository_id':'explicit-core','owner_reference':'explicit-owner'},'source_options':['docs/RICHTING.md']}
    def tearDown(self):self.service.close();self.temp.cleanup()
    def freeze(self,command=None,binding=None):
        with self.store.authorized(self.token) as scope:return self.journal.freeze(scope,self.source['id'],command or self.command,binding or self.binding)
    def test_original_request_same_after_restart_and_new_revision(self):
        value=self.freeze();self.assertEqual(value['state'],'ORIGINAL_REQUEST_CAPTURED');self.assertEqual(value,self.freeze())
        updated=self.store.save(self.scope,{'title':'Changed saved idea','notes':'Later description','operation_id':'3'*32,'expected_revision':1},identity=self.source['id'])
        self.assertEqual(value,self.freeze())
        second=self.freeze(dict(self.command,operation_id='4'*32,expected_revision=2));self.assertEqual(second['request']['input']['bootstrap_input']['identity'],value['request']['input']['bootstrap_input']['identity']);self.assertNotEqual(second['request_digest'],value['request_digest'])
        with Service(self.root) as restarted:
            journal=ConceptAdoptionIntents(restarted.project_concepts)
            with restarted.project_concepts.authorized(self.token) as scope:self.assertEqual(journal.get(scope,self.source['id'],self.command['operation_id']),value)
        self.assertEqual(self.store.get(self.scope,self.source['id']),updated)
    def test_conflict_foreign_actor_binding_and_actual_revocation(self):
        value=self.freeze()
        with self.assertRaises(ConversationConflict):self.freeze(dict(self.command,requested_artifacts=['docs/product/VISION.md']))
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

    def test_one_dispatch_only_and_unknown_never_means_absent(self):
        value=self.freeze();operation=self.command['operation_id']
        self.assertTrue(self.journal.claim_dispatch(self.scope,self.source['id'],operation))
        self.assertFalse(self.journal.claim_dispatch(self.scope,self.source['id'],operation))
        with Service(self.root) as restarted:
            self.assertFalse(ConceptAdoptionIntents(restarted.project_concepts).claim_dispatch(self.scope,self.source['id'],operation))
        self.assertNotIn('inventory',value['request']['input'])
        self.assertEqual(value['mapping']['unknown_fields'],['users','non_goals','constraints'])
        self.assertEqual(value['request']['input']['mappings'][0]['source_path'],'docs/RICHTING.md')
    def test_arbitrary_paths_and_changed_owner_identity_refused(self):
        for choices in [[{'artifact_path':'docs/product/VISION.md','source_path':'/private/foreign','choice':'LINK_EXISTING'}],[{'artifact_path':'docs/product/VISION.md','source_path':'docs/RICHTING.md','choice':'PROPOSE_REPLACEMENT'}]]:
            with self.assertRaises(ValueError):self.freeze(dict(self.command,mappings=choices))

    def test_definitive_source_rejection_has_no_allocated_intent_and_old_revision_stays_original(self):
        original=self.freeze()
        self.store.save(self.scope,{'title':'Later revision','notes':'Later description','operation_id':'3'*32,'expected_revision':1},identity=self.source['id'])
        rejected=dict(self.command,operation_id='4'*32)
        with self.assertRaises(AdoptionSourceRejected):self.freeze(rejected)
        with self.assertRaises(FileNotFoundError):self.journal.get(self.scope,self.source['id'],rejected['operation_id'])
        self.assertEqual(self.freeze(),original)
        self.assertEqual(len(self.journal.list(self.scope,self.source['id'])),1)
        admitted=self.freeze(dict(rejected,expected_revision=2))
        self.assertEqual(admitted['mapping']['source']['revision'],2)
