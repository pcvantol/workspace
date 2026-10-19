"""Source-only consumers of the actual immutable qualified R56 fixture."""
import copy,json,unittest
from pathlib import Path
from workspace_control import genesis_wire as wire
from workspace_control.concept_baseline_wire import peer_digest

class GenesisWireTests(unittest.TestCase):
    def setUp(self):
        self.plan=json.loads((Path(__file__).parent/'fixtures/genesis/original-plan.json').read_text())
        self.source={'result':{'result_digest':self.plan['documents']['bundle_digest'],'artifacts':[{k:f[k] for k in ('path','mode','sha256','content')} for f in self.plan['documents']['files']]}}
    def test_qualified_original_document_bytes_and_non_authority(self):
        self.assertEqual(wire.plan(self.plan,self.source,self.plan['source_subject']),self.plan)
        self.assertFalse(self.plan['execution_authorized']);self.assertEqual(self.plan['state'],'EP_ADMISSION_REQUIRED')
    def test_honest_non_authority_fields_cannot_be_lifted(self):
        for key,value in [('execution_authorized',True),('identity_state','RESERVED'),('project_readiness','READY'),('target_write','PERFORMED'),('ep_credential','ISSUED')]:
            with self.subTest(key=key):
                p=copy.deepcopy(self.plan);p[key]=value;p['plan_digest']=peer_digest({k:v for k,v in p.items() if k!='plan_digest'})
                with self.assertRaises(ValueError):wire.plan(p,self.source,self.plan['source_subject'])
    def test_rehashed_changed_original_bytes_still_fail(self):
        p=copy.deepcopy(self.plan);p['documents']['files'][0]['content']+='forged';p['plan_digest']=peer_digest({k:v for k,v in p.items() if k!='plan_digest'})
        with self.assertRaises(Exception):wire.plan(p,self.source,self.plan['source_subject'])
    def test_changed_source_digest_or_subject_fails(self):
        for subject in ({},self.plan['source_subject']|{'plan_id':'foreign'}):
            with self.assertRaises(Exception):wire.plan(self.plan,self.source,subject)
    def test_closed_plan_and_required_separate_effect_purpose(self):
        req={'contract_version':wire.CONTRACT,'instance_id':'i','dossier_id':'d','operation_id':'o','plan_id':'p','plan_digest':'a'*64,'purpose':wire.PURPOSE,'decision':'APPROVE_EFFECT','reason':'Explicit synthetic technical decision','expected_decision_revision':0,'previous_decision_id':None}
        self.assertEqual(wire.request(req,'DECISION'),req)
        for altered in (req|{'purpose':'CONTENT_BASELINE_ONLY/1.0'},req|{'reason':' '},req|{'previous_decision_id':'invented'},req|{'apply':True}):
            with self.assertRaises(Exception):wire.request(altered,'DECISION')

if __name__=='__main__':unittest.main()
