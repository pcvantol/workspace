"""Explicit consumer unit fixtures; installed qualification uses the real pinned producer."""
from copy import deepcopy
import unittest
from workspace_control import candidate_contract as w
from workspace_control.worklist_peer import WorklistError

B={'forge_instance_id':'forge-one','forge_project_id':'project-one','repository_id':'repo-one','actor_id':'alice','conversation_id':'a'*32,'proposal_ids':['proposal-one','proposal-two'],'maximum_registrations':2}
def source():
 return {'turn_id':'turn-one','session_id':'session-one','invocation_id':'inv-one','request_digest':'sha256:'+'1'*64,'result_digest':'sha256:'+'2'*64,'context_revision':'sha256:'+'3'*64,'advisor_kind':'BUSINESS','conversation_revision':1,'selected_sources':[],'evidence_references':['project:one'],'advice_summary':'Synthetic validated advice; user input remains separate.'}
def fields():
 return {'title':'Synthetic proposal café','objective':'A bounded assessment','business_value':'Explicit usefulness','engineering_value':'Explicit verification','architectural_value':'Explicit boundary','rationale':'Explicit user reasoning','confidence':65,'scope':['Only assess the documented boundary'],'exclusions':['No implementation'],'acceptance_criteria':['The evidence names every inspected boundary and limitation.'],'architecture_constraints':['Use existing contracts'],'dependencies':[],'effect_policy':{'contract_version':'1.0','mode':'READ_ONLY_ASSESSMENT','delivery':'EVIDENCE_ONLY','read_paths':['docs/'],'write_paths':[]}}
def request():
 return {'contract_version':w.CONTRACT,'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','conversation_id':'a'*32,'proposal_id':'proposal-one','turn_id':'turn-one','expected_revision':0,'expected_conversation_revision':1,'context_revision':source()['context_revision'],'fields':fields()}
def proposal(revision=1):
 r=request();d={k:v for k,v in r.items() if k not in ('turn_id','expected_revision','expected_conversation_revision','context_revision')};d.update(principal_reference='forge-one:alice',proposal_revision=revision,source=source(),field_origins={'fields':'EXPLICIT_USER','source.advice_summary':'VALIDATED_ADVICE'});d['proposal_digest']=w.digest(d);return d
def candidate():
 f=fields();return {'id':'candidate-one','recommendation_id':'recommendation-one',**{k:f[k] for k in ('title','objective','scope','acceptance_criteria','dependencies','effect_policy')},'architecture_constraints':[*f['architecture_constraints'],*['EXCLUDED: '+v for v in f['exclusions']]]}
def registration_request():
 r=request();return {k:v for k,v in r.items() if k not in ('fields','turn_id','expected_revision')}|{'operation_id':'operation-one','proposal_revision':1,'proposal_digest':proposal()['proposal_digest'],'confirm':True}
def registration():
 p=proposal();can=candidate();r={'contract_version':w.CONTRACT,'operation_id':'operation-one','principal_reference':'forge-one:alice','registration_key':w.digest(['forge-one:alice','project-one','repo-one','a'*32,'proposal-one',1]),'proposal_digest':p['proposal_digest'],'proposal_revision':1,'source':source(),'candidate':can,'recommendation_id':'recommendation-one','candidate_digest':w.digest(can),'recommendation_digest':'sha256:'+'4'*64,'registered_at':'2026-10-08T14:00:00Z','status_at_registration':'RECOMMENDED','rationale':fields()['rationale']};return {'contract_version':w.CONTRACT,'recorded':True,'original_receipt':r,'current':{'candidate':deepcopy(can),'candidate_digest':w.digest(can),'recommendation_status':'RECOMMENDED','conversation_revision':1,'source_fresh':True,'mission_allocation':False}}
def capability():
 return {'contract_version':w.CONTRACT,'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','conversation_id':'a'*32,'proposal_ids':B['proposal_ids'],'maximum_registrations':2,'registration_authority':'CANDIDATE_ONLY_NO_APPROVAL_OR_EXECUTION','additional_model_calls':0,'maximum_proposals_per_instance':64,'maximum_revisions_per_proposal':8,'read_only':True}
def preview():
 return {'contract_version':w.CONTRACT,'proposal':proposal(),'latest_revision':1,'candidate_preview':candidate(),'registration':None,'read_only':True}
class CandidateContractTests(unittest.TestCase):
 def reject(self,fn,base,mutations):
  for mutate in mutations:
   d=deepcopy(base);mutate(d)
   with self.assertRaises(WorklistError):fn(d)
 def testExplicitFieldsClosedRequestsAndFiniteCapabilities(self):
  w.response(capability(),'capability',B);w.request(request(),'proposal_request',B,'a'*32);w.request(registration_request(),'registration_request',B,'a'*32,'proposal-one')
  self.reject(lambda d:w.request(d,'proposal_request',B,'a'*32),request(),[lambda d:d.update(actor='alice'),lambda d:d.update(instance_id='other'),lambda d:d.update(proposal_id='foreign'),lambda d:d.update(turn_id='../bad'),lambda d:d.update(expected_revision=8),lambda d:d['fields'].update(confidence=True),lambda d:d.update(expected_revision=True)])
  self.reject(w.fields,fields(),[lambda d:d.update(scope=[]),lambda d:d.update(acceptance_criteria=['yes']),lambda d:d.update(dependencies=['same','same']),lambda d:d.update(title='<script>'),lambda d:d['effect_policy'].update(read_paths=['../private']),lambda d:d['effect_policy'].update(read_paths=['/private']),lambda d:d['effect_policy'].update(read_paths=['C:\\secret']),lambda d:d['effect_policy'].update(write_paths=['src/a.py']),lambda d:d['effect_policy'].update(mode='DOCUMENTATION_ONLY',delivery='GIT',write_paths=['docs/'])])
  self.reject(lambda d:w.response(d,'capability',B),capability(),[lambda d:d.update(proposal_ids=['proposal-one']),lambda d:d.update(maximum_registrations=3),lambda d:d.update(additional_model_calls=1),lambda d:d.update(conversation_id='b'*32)])
  self.reject(lambda d:w.request(d,'registration_request',B,'a'*32),registration_request(),[lambda d:d.update(confirm=False),lambda d:d.update(operation_id='bad/ID')])
 def testSourceProposalAndFrozenSaveCorrelation(self):
  w.response({'contract_version':w.CONTRACT,'source':source(),'read_only':True},'source_read',B,'a'*32,'turn-one')
  self.reject(lambda d:w.source(d,'turn-one'),source(),[lambda d:d.update(turn_id='wrong'),lambda d:d.update(session_id='bad/ID'),lambda d:d.update(advice_summary='password=secret'),lambda d:d.update(selected_sources=[{'source_id':'same','version':'sha256:'+'0'*64}]*2)])
  saved={'contract_version':w.CONTRACT,'proposal':proposal(),'registered':False,'additional_model_calls':0}
  w.response(saved,'saved',B,'a'*32,'proposal-one',1,request())
  self.reject(lambda d:w.response(d,'saved',B,'a'*32,'proposal-one',1,request()),saved,[lambda d:d['proposal'].update(principal_reference='forge-one:bob'),lambda d:d['proposal'].update(proposal_revision=2),lambda d:d['proposal'].update(proposal_digest='sha256:'+'0'*64)])
  r=request();r['fields']['title']='other'
  with self.assertRaises(WorklistError):w.response(saved,'saved',B,'a'*32,'proposal-one',1,r)
  p=preview();w.response(p,'preview',B,'a'*32,'proposal-one',1);p['registration']=registration();w.response(p,'preview',B,'a'*32,'proposal-one',1)
  p['latest_revision']=0
  with self.assertRaises(WorklistError):w.response(p,'preview',B,'a'*32,'proposal-one',1)
 def testOriginalReceiptAndCurrentReadbackCannotBeForged(self):
  w.response(registration(),'registration',B,'a'*32,'proposal-one',expected=registration_request())
  self.reject(lambda d:w.response(d,'registration',B,'a'*32,'proposal-one',expected=registration_request()),registration(),[lambda d:d['original_receipt'].update(registration_key='sha256:'+'0'*64),lambda d:d['original_receipt'].update(operation_id='bad/ID'),lambda d:d['original_receipt'].update(registered_at='bad'),lambda d:d['original_receipt'].update(proposal_digest='sha256:'+'0'*64),lambda d:d['original_receipt'].update(rationale='<bad>'),lambda d:d['current']['candidate'].update(title='changed without digest'),lambda d:d['current'].update(candidate_digest='sha256:'+'0'*64),lambda d:d['original_receipt'].update(recommendation_id='wrong')])
  d=registration();d['current']['candidate']['id']='other';d['current']['candidate_digest']=w.digest(d['current']['candidate'])
  with self.assertRaises(WorklistError):w.registration(d,B,'a'*32,'proposal-one')
  d=registration();d['current']['candidate']['objective']='Current changed independently';d['current']['candidate_digest']=w.digest(d['current']['candidate']);d['current'].update(recommendation_status='SUPERSEDED',source_fresh=False);w.registration(d,B,'a'*32,'proposal-one')
  p={'contract_version':w.CONTRACT,'state':'PENDING','operation_id':'operation-one','read_only':True};w.response(p,'pending',B,'a'*32,'proposal-one',expected='operation-one')
  with self.assertRaises(WorklistError):w.response(p,'pending',B,expected='other')
if __name__=='__main__':unittest.main()
