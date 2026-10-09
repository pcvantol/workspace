"""Actual source HTTP examples plus consumer negatives; final installed evidence pending."""
import json
from copy import deepcopy
from pathlib import Path
import unittest
from workspace_control import mission_contract as w
from workspace_control.worklist_peer import WorklistError


class MissionApprovalContractTests(unittest.TestCase):
    def setUp(self):
        self.root=Path(__file__).parent/'fixtures/mission-installed-481b2f6'
        self.prepared=self.read('prepared-complete.json');self.package=self.prepared['package']
        s=self.package['source'];self.conversation=s['conversation_id']
        self.binding={'forge_instance_id':s['instance_id'],'forge_project_id':s['project_id'],'repository_id':s['repository_id'],'actor_id':self.package['authority']['principal_reference'].split(':',1)[1],'conversation_ids':[self.conversation]}
    def read(self,name):
        aliases={'prepared-complete.json':'natural-prepared-complete.json','prepared-incomplete.json':'natural-prepared-incomplete.json','compound-result.json':'natural-compound-result.json','operation-current.json':'natural-operation-current.json','operation-after-refinement.json':'natural-operation-superseded.json','prepared-dependent.json':'dependency-prepared-dependent.json','compound-dependent.json':'dependency-compound-result.json','catalog-directed-dependency.json':'dependency-catalog-dependency.json','context-with-predecessor.json':'dependency-focused-context.json'}
        coherent={'prepared-dependent.json':'B-prepared.json','compound-dependent.json':'B-compound.json','catalog-directed-dependency.json':'catalog-A-B.json','context-with-predecessor.json':'B-focused-context-before-turn.json','B-original-turn.json':'B-original-turn.json','catalog-history-after-A2.json':'catalog-history-after-A2.json'}
        if name in coherent:return json.loads((self.root.parent/'mission-installed-b-481b2f6'/coherent[name]).read_text())
        return json.loads((self.root/aliases.get(name,name)).read_text())
    def testActualPackageMeaningDigestAndScopedOriginal(self):
        self.assertEqual(w.prepared(self.prepared,self.binding,self.conversation,revision=2,expected_definition=self.prepared['definition']),self.prepared)
        incomplete=self.read('prepared-incomplete.json');w.prepared(incomplete,self.binding,self.conversation)
        for modify in [lambda p:p['package']['candidate'].update(title='different'),lambda p:p['package']['authority'].update(principal_reference='foreign:actor'),lambda p:p['package']['source'].update(conversation_id='foreign'),lambda p:p['package']['consequences'].update(exclusions=[]),lambda p:p.update(package_digest='sha256:'+'0'*64),lambda p:p.update(definition={**p['definition'],'objective':'unrelated'})]:
            bad=deepcopy(self.prepared);modify(bad)
            with self.assertRaises(WorklistError):w.prepared(bad,self.binding,self.conversation)
        with self.assertRaises(WorklistError):w.prepared(self.prepared,self.binding,self.conversation,revision=99)
    def testActualDirectedDependencyAndVersionBoundPacketRejectDifferentMeaning(self):
        p=self.read('prepared-dependent.json');source=p['package']['source'];binding={**self.binding,'forge_instance_id':source['instance_id'],'conversation_ids':['foundation','portal']}
        w.prepared(p,binding,'portal')
        catalog=self.read('catalog-directed-dependency.json');w.response(catalog,'catalog',binding)
        context=self.read('context-with-predecessor.json');w.response(context,'concept_context',binding,'portal')
        edge=catalog['items'][1]['edges'][0]
        self.assertEqual(edge['subject_revision'],p['package']['dependency_bindings'][0]['subject_revision'])
        self.assertEqual(edge['reason'],p['definition']['dependency_reasons'][edge['candidate_id']])
        approved=self.read('compound-dependent.json');w.compound(approved,binding,'portal',frozen=p['package'])
        self.assertIn('DEPENDENCY_NOT_PROVEN',approved['current']['blockers']);self.assertFalse(approved['current']['execution_ready'])
        bad=deepcopy(approved);bad['current']['subject_revision']='sha256:'+'0'*64
        with self.assertRaises(WorklistError):w.compound(bad,binding,'portal',frozen=p['package'])
        for key in ['reason','candidate_id','target_object_id']:
            bad=deepcopy(catalog);bad['items'][1]['edges'][0][key]='Other meaning than the frozen package.' if key=='reason' else 'foreign'
            bad['snapshot_revision']=w.digest(bad['items'])
            with self.assertRaises(WorklistError):w.response(bad,'catalog',binding)
        bad=deepcopy(p);bad['package']['dependency_bindings'][0]['reason']='Other meaning than the frozen package.';bad['package_digest']=w.digest(bad['package'])
        with self.assertRaises(WorklistError):w.prepared(bad,binding,'portal')

    def testRehashedCanonicalEvidenceCannotChangeActualReceiptSubjectOrSigner(self):
        for key,value in [('subject_id','foreign'),('subject_revision','sha256:'+'0'*64),('operator_id','foreign'),('installation_id','foreign'),('capability','ARCHITECTURE_APPROVAL'),('decision_id','foreign')]:
            bad=self.read('operation-current.json');receipt=bad['business_decision'];receipt['canonical_decision'][key]=value;receipt['canonical_decision_digest']=w.digest(receipt['canonical_decision'])
            with self.assertRaises(WorklistError):w.compound(bad,self.binding,self.conversation)
        bad=self.read('operation-current.json');receipt=bad['architecture_decision'];receipt['lifecycle_evidence']['recommendation_id']='foreign';receipt['lifecycle_evidence_digest']=w.digest(receipt['lifecycle_evidence'])
        with self.assertRaises(WorklistError):w.compound(bad,self.binding,self.conversation)

    def testTwoCanonicalDecisionsAndSupersededReadbackRemainDistinctFromReady(self):
        for name in ['compound-result.json','operation-current.json','operation-after-refinement.json']:
            value=self.read(name)
            self.assertEqual(w.compound(value,self.binding,self.conversation,expected_digest=self.prepared['package_digest'],frozen=self.package),value)
        old=self.read('operation-after-refinement.json')
        self.assertEqual(old['state'],'COMPLETE');self.assertFalse(old['source_fresh']);self.assertEqual(old['current_definition_state'],'SUPERSEDED')
        self.assertFalse(old['execution_started'])
        for modify in [lambda v:v['business_decision'].update(kind='ARCHITECTURE'),lambda v:v['architecture_decision'].update(candidate_id='foreign'),lambda v:v['business_decision'].update(operator_id='foreign'),lambda v:v.update(package_digest='sha256:'+'0'*64),lambda v:v['original_registration']['candidate'].update(title='unseen'),lambda v:v.update(mission_id=None),lambda v:v.update(architecture_decision=None),lambda v:v['business_decision'].update(canonical_decision_digest='sha256:'+'0'*64)]:
            bad=self.read('operation-current.json');modify(bad)
            with self.assertRaises(WorklistError):w.compound(bad,self.binding,self.conversation,frozen=self.package)
        with self.assertRaises(WorklistError):w.compound(self.read('operation-current.json'),self.binding,self.conversation,operation='foreign')


if __name__=='__main__':unittest.main()
