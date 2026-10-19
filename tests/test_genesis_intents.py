"""Real SQLite intent/recovery fences; no producer runtime acceptance claim."""
import json,tempfile,unittest
from pathlib import Path
from workspace_control.service import Service,initialize
from workspace_control.genesis_intents import GenesisIntents,TABLE,MARKER,BINDING
from workspace_control.project_concepts import ConceptStorageUnavailable
from workspace_control.conversations import ConversationConflict
from workspace_control import genesis_wire as wire

class GenesisIntentTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.root.chmod(0o700);initialize(self.root);self.service=Service(self.root)
        self.scope=('alice','own');self.token=self.service.conversations.issue_grant(*self.scope);self.store=self.service.project_concepts
        c=self.store.save(self.scope,{'title':'Saved idea','notes':'Original notes','operation_id':'a'*32,'expected_revision':0});self.identity=c['id'];self.journal=self.service.genesis.intents
        self.binding={k:'synthetic' for k in BINDING};self.binding.update(actor_id='alice',context_id='own',concept_id=self.identity,instance_id='instance',dossier_id='dossier',source_principal_id='source',human_binding={'operator_id':'human','operator_binding_version':1,'installation_id':'i'})
        self.command={'operation_id':'b'*32,'source_operation_id':'c'*32,'expected_concept_revision':1,'selection_digest':'d'*64,'plan_operation_id':'e'*32,'decision':'APPROVE_EFFECT','reason':'Explicit synthetic effect decision'}
        self.request={'contract_version':wire.CONTRACT,'instance_id':'instance','dossier_id':'dossier','operation_id':'b'*32,'plan_id':'plan','plan_digest':'f'*64,'purpose':wire.PURPOSE,'decision':'APPROVE_EFFECT','reason':self.command['reason'],'expected_decision_revision':0,'previous_decision_id':None}
    def tearDown(self):self.service.close();self.tmp.cleanup()
    def freeze(self,command=None,binding=None,request=None):return self.journal.freeze(self.scope,self.identity,'DECISION',command or self.command,binding or self.binding,request or self.request)
    def test_original_persisted_and_restart_and_replay_no_second_intent(self):
        original=self.freeze();self.assertEqual(self.freeze(),original)
        with Service(self.root) as server:self.assertEqual(server.genesis.intents.get(self.scope,self.identity,'b'*32),original)
        self.assertEqual(len(self.journal.list(self.scope,self.identity)),1)
        with self.assertRaises(ConversationConflict):self.freeze(command=self.command|{'selection_digest':'f'*64})
        self.store.save(self.scope,{'title':'Edited','notes':'Later notes','operation_id':'9'*32,'expected_revision':1},identity=self.identity)
        self.assertEqual(self.freeze(),original)
        with self.assertRaises(FileNotFoundError):self.journal.get(('bob','own'),self.identity,'b'*32)
    def test_durable_admission_once_and_restart(self):
        self.freeze();self.assertTrue(self.journal.admit_transport(self.scope,self.identity,'b'*32));self.assertFalse(self.journal.admit_transport(self.scope,self.identity,'b'*32))
        with Service(self.root) as server:self.assertFalse(server.genesis.intents.admit_transport(self.scope,self.identity,'b'*32))
    def test_changed_request_never_reuses_id(self):
        self.freeze()
        with self.assertRaises(ConversationConflict):self.freeze(request=self.request|{'plan_digest':'a'*64})
        with self.assertRaises(ValueError):self.freeze(request=self.request|{'decision':'REQUEST_CHANGES'})
    def test_closed_commands_scope_and_separate_purpose(self):
        for changed in (self.command|{'extra':True},self.command|{'operation_id':'bad'},self.command|{'expected_concept_revision':True},self.command|{'selection_digest':'x'}):
            with self.assertRaises(ValueError):self.freeze(command=changed)
        with self.assertRaises(PermissionError):self.freeze(binding=self.binding|{'actor_id':'bob'})
        with self.assertRaises(Exception):self.freeze(request=self.request|{'purpose':'CONTENT_BASELINE_ONLY/1.0'})
    def test_shared_operation_namespace_prevents_collision(self):
        self.store.save(self.scope,{'title':'Edited','notes':'Later','operation_id':'b'*32,'expected_revision':1},identity=self.identity)
        with self.assertRaises(ConversationConflict):self.freeze()
    def test_stale_concept_prevents_capture_or_admission(self):
        self.freeze();self.store.save(self.scope,{'title':'Edited','notes':'Later','operation_id':'9'*32,'expected_revision':1},identity=self.identity)
        with self.assertRaises(ConversationConflict):self.journal.admit_transport(self.scope,self.identity,'b'*32)
        with self.assertRaises(ConversationConflict):self.freeze(command=self.command|{'operation_id':'8'*32},request=self.request|{'operation_id':'8'*32})
    def test_initialized_table_loss_is_503_not_empty_and_exact_restoration(self):
        original=self.freeze();db=self.store._connect(write=True);db.execute('ALTER TABLE '+TABLE+' RENAME TO saved_genesis');db.commit();db.close()
        with self.assertRaises(ConceptStorageUnavailable):self.journal.list(self.scope,self.identity)
        db=self.store._connect(write=True);db.execute('ALTER TABLE saved_genesis RENAME TO '+TABLE);db.commit();db.close()
        self.assertEqual(self.journal.get(self.scope,self.identity,'b'*32),original)
    def test_missing_rows_or_witnesses_and_corrupt_record_fail_closed(self):
        self.freeze();db=self.store._connect(write=True);db.execute('UPDATE '+TABLE+" SET record_digest='corrupt'");db.commit();db.close()
        with self.assertRaises(ConceptStorageUnavailable):self.journal.get(self.scope,self.identity,'b'*32)
    def test_lost_marker_and_missing_operation_not_healthy_empty(self):
        self.freeze();(self.root/MARKER).unlink()
        with self.assertRaises(ConceptStorageUnavailable):self.journal.list(self.scope,self.identity)
    def test_healthy_initial_empty_and_absent_operation(self):
        self.assertEqual(self.journal.list(self.scope,self.identity),[])
        with self.assertRaises(FileNotFoundError):self.journal.get(self.scope,self.identity,'b'*32)
        with self.assertRaises(ConceptStorageUnavailable):self.journal.admit_transport(self.scope,self.identity,'b'*32)

if __name__=='__main__':unittest.main()
