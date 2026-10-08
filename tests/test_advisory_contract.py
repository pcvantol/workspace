"""Consumer wire joins and negatives; deterministic synthetic units, not installed proof."""
from copy import deepcopy
import unittest
from workspace_control import advisory_contract as w
from workspace_control.worklist_peer import WorklistError

B={'forge_instance_id':'forge-one','forge_project_id':'project-one','repository_id':'repo-one','conversation_ids':['a'*32]}
def capability():
 context={'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','dataset_generation':1,'included_sources':['selected'],'selected_sources':[],'missing_sources':['Vision','Portfolio'],'freshness':'CURRENT_CONFIGURED_BINDING','evidence_references':['project:one'],'limitations':['No live repository head proof.']}
 return {'contract_version':w.CONTRACT,'supported_modes':['BUSINESS','ARCHITECTURE'],'unsupported':['UX','APPLY'],'project_id':'project-one','repository_id':'repo-one','instance_id':'forge-one','conversation_ids':['a'*32],'context':context,'context_revision':w.digest(context),'maximum_turns':8,'available_sources':[],'max_concurrent_invocations_per_instance':1,'cancel_request_supported':True,'provider_stop_supported':False,'retained_principal_consumed_turns':0,'live_model_quality':'NOT_QUALIFIED','unknown_usage':'NOT_REPORTED_AND_NOT_ACCEPTED_AS_BOUND_PROOF','read_only':True}
def request():
 cap=capability();return {'contract_version':w.CONTRACT,'turn_id':'turn-one','instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','conversation_id':'a'*32,'advisor_kind':'BUSINESS','objective':'Value, café and constraints.','expected_revision':0,'context_revision':cap['context_revision'],'selected_sources':[]}
def record():
 r=request();h=w.digest(r);output={'contract_version':w.CONTRACT,'request_digest':h,'advisor_kind':'BUSINESS','summary':'Synthetic bounded advice.','alternatives':['Smaller scope.'],'questions':['Which criterion?'],'suggestions':['Review constraints.'],'evidence_references':['project:one'],'applied':False}
 diag={'classification':'COMPLETED_VALID','process_started':True,'exception_type':None,'errno':None,'timed_out':False,'elapsed_milliseconds':3,'returncode':0,'error_category':None,'terminal_events':['turn.completed']}
 provider={'provider_id':'provider-one','requested_model':None,'requested_profile':None,'requested_effort':'NOT_CONFIGURED','policy_digest':'sha256:'+'1'*64,'generation_digest':'sha256:'+'2'*64,'configuration_revision':1,'input_token_bound':1000,'context_token_bound':2000,'output_token_bound':1000}
 outcome={'execution':'CONFIRMED','diagnostic':diag,'usage':{'input_tokens':100,'output_tokens':60},'usage_status':'OBSERVED','observed_model':'NOT_REPORTED','observed_effort':'NOT_REPORTED','output':output,'result_digest':w.digest(output),'error_code':None}
 return {'request':r,'request_digest':h,'session_id':'session-one','invocation_id':'inv-one','context':capability()['context'],'provider':provider,'status':'COMPLETE','lifecycle':['CREATED','PREPARED','REASONING','REVIEW','COMPLETE'],'execution':'CONFIRMED','outcome':outcome,'admitted_at':'2026-10-08T06:00:00Z','grant_id':'grant-one','consumption':1}
class AdvisoryContractTests(unittest.TestCase):
 def testClosedTypesBoundsScopeAndUnicodeDigest(self):
  self.assertEqual(w.response(capability(),'capability',B),capability());w.request(request(),B,'a'*32)
  for field,v in [('extra',True),('maximum_turns',True),('context_revision','bad'),('read_only',1),('supported_modes',['UX']),('conversation_ids',[]),('instance_id','other')]:
   d=capability();d[field]=v
   with self.assertRaises(WorklistError):w.response(d,'capability',B)
  for obj in ['', 'x'*1001]:
   d=request();d['objective']=obj
   with self.assertRaises(WorklistError):w.request(d,B,'a'*32)
  with self.assertRaises(WorklistError):w.request(request(),B,'b'*32)
  d=request();d['selected_sources']=[{'source_id':'same','version':'sha256:'+'a'*64}]*2
  with self.assertRaises(WorklistError):w.request(d,B,'a'*32)
  self.assertIn('sha256:',w.digest(request()))
 def testOriginalCurrentAndResultProvenanceCannotInventCompletion(self):
  r=record();env={'contract_version':w.CONTRACT,'read_only':True,'original_turn':r,'current_revision':4}
  w.response(env,'turn',B,'a'*32,r['request'])
  for mutation in [lambda d:d['original_turn']['outcome']['output'].update(summary='<script>bad</script>'),lambda d:d['original_turn']['outcome'].update(usage_status='NOT_REPORTED',usage=None),lambda d:d['original_turn'].update(request_digest='sha256:'+'0'*64),lambda d:d.update(current_revision=0),lambda d:d['original_turn']['outcome'].update(result_digest='sha256:'+'0'*64),lambda d:d['original_turn']['context'].update(selected_sources=[{'source_id':'other','version':'sha256:'+'a'*64}])]:
   bad=deepcopy(env);mutation(bad)
   with self.assertRaises(WorklistError):w.response(bad,'turn',B,'a'*32)
  hist={'contract_version':w.CONTRACT,'conversation_id':'a'*32,'scope':{k:r['request'][k] for k in ['instance_id','project_id','repository_id']},'revision':4,'turns':[r],'next_cursor':None,'consumed_turns':1,'maximum_turns':8,'retention':'PRIVATE_RETAINED_NO_AUTOMATIC_DELETE','read_only':True}
  w.response(hist,'history',B,'a'*32);hist['turns']*=2
  with self.assertRaises(WorklistError):w.response(hist,'history',B,'a'*32)
  self.assertFalse(w._safe('password=hidden'));self.assertFalse(w._safe('https://user:password@host/'))
  diag=record()['outcome']['diagnostic'];diag['returncode']=-9;w.validate(diag,'diagnostic')
if __name__=='__main__':unittest.main()
