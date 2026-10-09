"""Actual source HTTP examples plus consumer negatives; final installed evidence pending."""
import json
from copy import deepcopy
from pathlib import Path
import unittest
from workspace_control import mission_contract as w
from workspace_control.worklist_peer import WorklistError


class MissionApprovalContractTests(unittest.TestCase):
    def setUp(self):
        self.root=Path(__file__).parent/'fixtures/mission-concepts-source'
        self.prepared=self.read('prepared-complete.json');self.package=self.prepared['package']
        s=self.package['source'];self.conversation=s['conversation_id']
        self.binding={'forge_instance_id':s['instance_id'],'forge_project_id':s['project_id'],'repository_id':s['repository_id'],'actor_id':self.package['authority']['principal_reference'].split(':',1)[1],'conversation_ids':[self.conversation]}
    def read(self,name):return json.loads((self.root/name).read_text())
    def testActualPackageMeaningDigestAndScopedOriginal(self):
        self.assertEqual(w.prepared(self.prepared,self.binding,self.conversation,revision=2,expected_definition=self.prepared['definition']),self.prepared)
        incomplete=self.read('prepared-incomplete.json');w.prepared(incomplete,self.binding,self.conversation)
        for modify in [lambda p:p['package']['candidate'].update(title='different'),lambda p:p['package']['authority'].update(principal_reference='foreign:actor'),lambda p:p['package']['source'].update(conversation_id='foreign'),lambda p:p['package']['consequences'].update(exclusions=[]),lambda p:p.update(package_digest='sha256:'+'0'*64),lambda p:p.update(definition={**p['definition'],'objective':'unrelated'})]:
            bad=deepcopy(self.prepared);modify(bad)
            with self.assertRaises(WorklistError):w.prepared(bad,self.binding,self.conversation)
        with self.assertRaises(WorklistError):w.prepared(self.prepared,self.binding,self.conversation,revision=99)
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
