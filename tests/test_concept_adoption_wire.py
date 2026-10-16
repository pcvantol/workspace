import copy,hashlib,json,unittest
from pathlib import Path
from workspace_control import concept_adoption_wire as wire
from workspace_control.worklist_peer import WorklistError
class AdoptionWireTests(unittest.TestCase):
 def test_exact_published_assets(self):
  for name,digest in [('inspection-adoptions-v1.json','911e57ba708b9de151f69a59a105ce782c50bb8900c0cb4ecef91e2b7b2f0155'),('inspection-adoption-proposal-v1.json','f865bd322b34408a681ce107f842ba3cd7f2f43436aa8d0436ffc66631cf1c90')]:
   self.assertEqual(hashlib.sha256(Path(wire.__file__).with_name(name).read_bytes()).hexdigest(),digest)
 def test_capability_is_current_scope_not_source_observation(self):
  b=dict(instance_id='forge',principal_id='owner',audience='workspace',pairing_id='existing',dossier_id='dossier',permissions=['PREPARE','READ'],maximum_records=8)
  v={**{k:b[k] for k in ('instance_id','principal_id','audience','pairing_id')},'contract_version':wire.CONTRACT,'permissions':b['permissions'],'dossier_ids':['dossier'],'proposal_kind':wire.KIND,'producer_revision':wire.EP,'current_peer_access':'CHECKED_BY_ORIGINAL_GET_AT_PREPARE_AND_READ','limits':dict(request_bytes=262144,result_bytes=1048576,global_records=64,per_dossier=8),'apply':False,'inspection_post':False}
  self.assertEqual(wire.capability(v,b),v)
  for change in [dict(audience='foreign'),dict(pairing_id='foreign'),dict(dossier_ids=['other']),dict(apply=True),dict(producer_revision='x'*40),dict(unexpected=True)]:
   with self.assertRaises(WorklistError):wire.capability({**v,**change},b)
 def test_pending_original_never_means_completed_or_applied(self):
  b=dict(instance_id='forge',principal_id='owner',audience='workspace',pairing_id='existing',dossier_id='dossier')
  request={'operation_id':'original'}
  v={**b,'contract_version':wire.CONTRACT,'operation_id':'original','plan_id':'plan-original','request_digest':wire.peer_digest(request),'state':'PREPARING','result':None,'proposal_kind':wire.KIND,'original_intent':True,'approval':'NOT_PERFORMED','registration':'NOT_PERFORMED'}
  self.assertEqual(wire.result(v,b,request),v)
  for change in [dict(operation_id='new'),dict(request_digest='0'*64),dict(state='PREPARED'),dict(approval='APPROVED')]:
   with self.assertRaises(WorklistError):wire.result({**v,**change},b,request)
