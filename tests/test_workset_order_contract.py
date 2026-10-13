"""Causal corruption checks against actual synthetic producer wire fixture."""
from copy import deepcopy
from pathlib import Path
import json
import unittest
from workspace_control import workset_order_contract as wire
from workspace_control.worklist_peer import WorklistError

FIXTURE = json.loads((Path(__file__).parent/'fixtures/workset-order-wire.json').read_text())


class OrderWireTests(unittest.TestCase):
    def setUp(self):
        self.cap = deepcopy(FIXTURE['capability'])
        self.current = deepcopy(FIXTURE['current'])
        self.preview = deepcopy(FIXTURE['preview'])
        p=self.preview['package'];self.key=p['workset_id']
        self.binding={'forge_instance_id':p['instance_id'],'forge_project_id':p['project_id'],'repository_id':p['repository_id'],'actor_id':self.current['current']['scope']['principal_id'],'installation_id':self.current['current']['installation_id'],'worksets':self.cap['worksets'],'permissions':self.cap['permissions'],'expires_at':self.cap['expires_at'],'maximum_amendments':self.cap['maximum_amendments']}

    def test_recorded_current_and_canonical_preview(self):
        self.assertEqual(wire.current(self.current,self.binding,self.key),self.current)
        self.assertEqual(wire.preview(self.preview,self.binding,self.key,self.preview['package']['proposed_order']),self.preview)

    def test_package_digest_prefix_membership_subject_revision_and_projection_guard(self):
        alterations=[lambda x:x.update(package_digest='sha256:'+'a'*64),lambda x:x['package'].update(fixed_prefix=0),lambda x:x['package'].update(workset_id='foreign'),lambda x:x['package']['subjects'][0].update(subject_revision='sha256:'+'0'*64),lambda x:x['current']['members'][0].update(title='forged title'),lambda x:x['current']['members'][1].update(dependencies=[x['current']['members'][2]['candidate_id']])]
        for alter in alterations:
            bad=deepcopy(self.preview);alter(bad)
            if bad['package_digest'] != 'sha256:'+'a'*64:bad['package_digest']=wire.digest(bad['package'])
            with self.subTest(alter=alter),self.assertRaises(WorklistError):wire.preview(bad,self.binding,self.key,bad['package']['proposed_order'])

    def test_exact_original_confirm_and_same_operation_receipt(self):
        p=self.preview['package'];request={'contract_version':wire.CONTRACT,'operation_id':'same-original-operation',**{k:p[k] for k in ['instance_id','project_id','repository_id','workset_id']},'package_digest':self.preview['package_digest'],'package':p,'reason':'Own synthetic order choice','confirm':True}
        self.assertEqual(wire.command(request,self.binding,self.key),request)
        for key,value in [('instance_id','foreign'),('workset_id','foreign'),('confirm',False),('package_digest','sha256:'+'0'*64)]:
            bad={**request,key:value}
            with self.assertRaises(WorklistError):wire.command(bad,self.binding,self.key)
        result={'contract_version':wire.CONTRACT,'operation_id':request['operation_id'],'state':'PENDING','original_request':request,'original_receipt':None,'canonical_decisions_observed':{},'current':self.current,'read_only':True,'additional_model_calls':0,'execution_started':False}
        self.assertEqual(wire.operation(result,self.binding,self.key,request['operation_id'],request),result)
        bad=deepcopy(result);bad['original_request']['reason']='Different intention'
        with self.assertRaises(WorklistError):wire.operation(bad,self.binding,self.key,request['operation_id'],request)


if __name__=='__main__':unittest.main()
