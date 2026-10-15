"""Owning SQLite/authority tests; resolver is a labeled contract double, not R53 proof."""
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from workspace_control.service import Service, initialize
from workspace_control.concept_briefing_store import ConceptBriefingStore, MARKER
from workspace_control.concept_baseline_mapping import digest
from workspace_control.conversations import ConversationConflict
from workspace_control.project_concept_library import ProjectConceptLibrary
from workspace_control.project_concepts import ConceptStorageUnavailable

class ConceptBriefingStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name);self.root.chmod(0o700)
        initialize(self.root);self.service=Service(self.root);self.store=ConceptBriefingStore(self.service.project_concepts)
        self.grant=self.service.conversations.issue_grant('alice','own');self.scope=('alice','own')
        self.concept=self.service.project_concepts.save(self.scope,{'title':'Idee','notes':'Alle oorspronkelijke notities','operation_id':'a'*32,'expected_revision':0})
        self.id=self.concept['id'];self.change=[{'field':'users','before':'','after':'Vrijwilligers','reason':'Expliciet besproken voorbeeld.'}]
        self.command={'operation_id':'b'*32,'expected_revision':1,'result_reference':'test-turn:1','displayed_change_digest':digest(self.change)}
    def tearDown(self):
        self.service.close();self.temp.cleanup()
    def resolve(self,*args):
        return {'source_digest':self.store.read(self.scope,self.id)['source_digest'],'changes':self.change,'producer_reference':{'kind':'LABELED_UNIT_CONTRACT_DOUBLE','turn':'test-turn:1'}}
    def adopt(self,**kw):
        return self.store.adopt(self.grant,self.id,kw.get('command',self.command),kw.get('resolve',self.resolve))
    def test_existing_store_read_is_nonmutating_and_adoption_exactly_once(self):
        old=self.store.read(self.scope,self.id);self.assertIsNone(old['accepted_from']);self.assertFalse((self.root/MARKER).exists())
        result=self.adopt();self.assertEqual(result['concept']['revision'],2);self.assertEqual(result['fields']['users'],'Vrijwilligers')
        self.assertEqual(result['concept']['notes'],self.concept['notes']);self.assertIn('NOT_APPROVAL',result['adoption']['kind'])
        self.assertEqual(self.adopt(resolve=lambda *a:self.fail('replay resolved again')),result)
        with Service(self.root) as restarted:
            other=ConceptBriefingStore(restarted.project_concepts)
            self.assertEqual(other.adopt(self.grant,self.id,self.command,lambda *a:self.fail('restart replay resolved')),result)
            self.assertEqual(other.read(self.scope,self.id)['fields']['users'],'Vrijwilligers')
        with self.assertRaises(ConversationConflict):self.adopt(command=dict(self.command,result_reference='changed'))
    def test_resolver_runs_outside_own_lock_and_late_revoke_denies(self):
        def revoke(*args):
            value=self.resolve();self.service.conversations.revoke_grants('alice','own');return value
        with self.assertRaises(PermissionError):self.adopt(resolve=revoke)
        self.assertEqual(self.service.project_concepts.get(self.scope,self.id)['revision'],1)
    def test_tamper_actor_stale_archive_and_pending_edit(self):
        with self.assertRaises(FileNotFoundError):self.store.read(('bob','own'),self.id)
        with self.assertRaises(ConversationConflict):self.adopt(command=dict(self.command,expected_revision=2))
        with self.assertRaises(ConversationConflict):self.adopt(command=dict(self.command,displayed_change_digest='0'*64))
        with self.assertRaises(ConversationConflict):self.adopt(resolve=lambda *a:dict(self.resolve(),source_digest='0'*64))
        def edited(*args):
            result=self.resolve();self.service.project_concepts.save(self.scope,{'title':'Handmatig','notes':self.concept['notes'],'operation_id':'c'*32,'expected_revision':1},identity=self.id);return result
        with self.assertRaises(ConversationConflict):self.adopt(resolve=edited)
        self.assertEqual(self.service.project_concepts.get(self.scope,self.id)['revision'],2)
        ProjectConceptLibrary(self.service.project_concepts).move(self.scope,self.id,{'operation_id':'d'*32,'expected_revision':2,'lifecycle':'ARCHIVED'})
        with self.assertRaises(ConversationConflict):self.adopt(command=dict(self.command,expected_revision=3))
    def test_missing_marker_table_corrupt_fields_fail_closed(self):
        self.adopt();marker=self.root/MARKER;original=marker.read_bytes();marker.unlink()
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(self.scope,self.id)
        marker.write_bytes(original);marker.chmod(0o600)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute("UPDATE concept_briefings_v1 SET fields='{}'")
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(self.scope,self.id)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DROP TABLE concept_briefings_v1')
        marker.unlink()
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(self.scope,self.id)
    def test_closed_command_validation(self):
        for command in [{},dict(self.command,extra=True),dict(self.command,expected_revision=True),dict(self.command,operation_id='bad'),dict(self.command,result_reference='../x'),dict(self.command,displayed_change_digest='bad')]:
            with self.assertRaises(ValueError):self.adopt(command=command)
        with self.assertRaises(ValueError):self.adopt(resolve=lambda *a:dict(self.resolve(),producer_reference={}))

    def test_accepted_briefing_maps_new_baseline_without_changing_old_bytes(self):
        from workspace_control.concept_baseline_mapping import map_concept, provisional_references
        refs=provisional_references()
        old=map_concept(self.concept,self.scope,refs)
        result=self.adopt()
        saved=self.service.project_concepts.get(self.scope,self.id)
        saved['briefing']={'fields':result['fields'],'accepted_from':result['accepted_from']}
        updated=map_concept(saved,self.scope,refs)
        self.assertEqual(updated['input']['product']['users'],'Vrijwilligers')
        self.assertNotIn('users',updated['unknown_fields'])
        self.assertIn('constraints',updated['unknown_fields'])
        self.assertEqual(updated['source']['notes'],self.concept['notes'])
        self.assertEqual(map_concept(updated['source'],self.scope,refs),updated)
        self.assertEqual(map_concept(self.concept,self.scope,refs),old)
        self.assertNotEqual(updated['input_digest'],old['input_digest'])
        changed=dict(saved,briefing={'fields':dict(result['fields'],name='Other'),'accepted_from':result['accepted_from']})
        with self.assertRaises(ValueError):map_concept(changed,self.scope,refs)
        changed=dict(saved,briefing={'fields':result['fields'],'accepted_from':{}})
        with self.assertRaises(ValueError):map_concept(changed,self.scope,refs)

    def test_actual_baseline_intent_freezes_accepted_briefing_and_old_remains(self):
        from workspace_control.concept_baseline_intents import ConceptBaselineIntents
        journal=ConceptBaselineIntents(self.service.project_concepts)
        binding={'id':'own','actor_id':'alice','context_id':'own','concept_id':self.id,'instance_id':'instance','dossier_id':'dossier','audience':'workspace','producer_source':'a'*40,'principal_id':'alice'}
        command={'operation_id':'c'*32,'expected_revision':1,'description':None}
        old=journal.freeze(self.scope,self.id,command,binding)
        self.adopt()
        new=journal.freeze(self.scope,self.id,dict(command,operation_id='d'*32,expected_revision=2),binding)
        self.assertEqual(new['request']['input']['product']['users'],'Vrijwilligers')
        self.assertEqual(journal.get(self.scope,self.id,'c'*32),old)
        self.assertEqual(journal.get(self.scope,self.id,'d'*32),new)
        self.assertEqual(old['request']['input']['product']['users'],'Not supplied in this project concept.')
    def test_long_notes_keep_explicit_accepted_purpose_without_truncation(self):
        from workspace_control.concept_baseline_mapping import map_concept,provisional_references
        self.service.project_concepts.save(self.scope,{'title':'Idee','notes':'n'*10000,'operation_id':'c'*32,'expected_revision':1},identity=self.id)
        self.change=[{'field':'purpose','before':'','after':'Expliciet kort doel','reason':'Gebruiker wil dit.'}]
        command=dict(self.command,expected_revision=2,displayed_change_digest=digest(self.change))
        result=self.adopt(command=command)
        saved=result['concept'] | {'briefing':{'fields':result['fields'],'accepted_from':result['accepted_from']}}
        mapped=map_concept(saved,self.scope,provisional_references())
        self.assertEqual(mapped['input']['product']['purpose'],'Expliciet kort doel')
        self.assertEqual(mapped['source']['notes'],'n'*10000)

    def test_missing_individual_adopted_row_is_not_an_unknown_replacement(self):
        from workspace_control.concept_baseline_intents import ConceptBaselineIntents
        self.adopt()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:db.execute('DELETE FROM concept_briefings_v1 WHERE concept_id=?',(self.id,))
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(self.scope,self.id)
        with self.assertRaises(ConceptStorageUnavailable):self.adopt()
    def test_corrupt_original_receipt_fails_closed(self):
        original=self.adopt()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            changed=json.loads(json.dumps(original));changed['fields']['users']='CORRUPTED'
            db.execute('UPDATE project_concept_operations_v1 SET response=? WHERE operation_id=?',(json.dumps(changed),self.command['operation_id']))
        with self.assertRaises(ConceptStorageUnavailable):self.adopt()
    def test_question_capacity_rejected_before_concept_revision_change(self):
        self.change=[{'field':'open_questions','before':[],'after':['Question '+str(i) for i in range(30)],'reason':'Explicit questions'}]
        with self.assertRaises(ValueError):self.adopt(command=dict(self.command,displayed_change_digest=digest(self.change)))
        self.assertEqual(self.service.project_concepts.get(self.scope,self.id)['revision'],1)

    def test_transplant_to_another_concept_is_unavailable(self):
        self.adopt()
        other=self.service.project_concepts.save(('bob','other'),{'title':'Other','notes':'Own notes','operation_id':'f'*32,'expected_revision':0})
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            db.execute('UPDATE concept_briefings_v1 SET concept_id=? WHERE concept_id=?',(other['id'],self.id))
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(('bob','other'),other['id'])
    def test_other_thread_can_use_own_store_while_resolver_waits(self):
        import threading
        began=threading.Event();release=threading.Event();done=[]
        def resolve(*args):
            value=self.resolve();began.set();self.assertTrue(release.wait(2));return value
        def adopt():
            try:done.append(self.adopt(resolve=resolve))
            except BaseException as error:done.append(error)
        thread=threading.Thread(target=adopt);thread.start()
        try:
            self.assertTrue(began.wait(2))
            self.assertEqual(self.service.project_concepts.get(self.scope,self.id)['revision'],1)
        finally:release.set();thread.join(3)
        self.assertFalse(thread.is_alive());self.assertEqual(done[0]['concept']['revision'],2)

    def test_partial_fields_and_digest_transplant_is_unavailable(self):
        self.adopt()
        other=self.service.project_concepts.save(self.scope,{'title':'Other','notes':'Own notes','operation_id':'f'*32,'expected_revision':0})
        self.id=other['id'];self.change=[{'field':'users','before':'','after':'Different audience','reason':'Other user intention'}]
        self.command=dict(self.command,operation_id='e'*32,displayed_change_digest=digest(self.change))
        self.adopt()
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            fields,key=db.execute('SELECT fields,fields_digest FROM concept_briefings_v1 WHERE concept_id=?',(self.concept['id'],)).fetchone()
            db.execute('UPDATE concept_briefings_v1 SET fields=?,fields_digest=? WHERE concept_id=?',(fields,key,self.id))
        with self.assertRaises(ConceptStorageUnavailable):self.store.read(self.scope,self.id)
    def test_actual_r50_multibyte_and_unknown_sentinel_admission_before_commit(self):
        for questions in [[('🌱'*1020)+str(i) for i in range(20)],['Question '+str(i) for i in range(29)]]:
            self.change=[{'field':'open_questions','before':[],'after':questions,'reason':'Explicit questions'}]
            if len(questions)==29:
                self.change.extend({'field':field,'before':self.store.read(self.scope,self.id)['fields'][field],'after':'Not supplied in this project concept.','reason':'Explicitly unknown'} for field in ['purpose','users','non_goals','constraints'])
            with self.assertRaises(ValueError):self.adopt(command=dict(self.command,displayed_change_digest=digest(self.change)))
            self.assertEqual(self.service.project_concepts.get(self.scope,self.id)['revision'],1)
