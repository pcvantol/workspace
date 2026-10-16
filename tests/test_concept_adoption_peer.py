import unittest,json
from unittest.mock import patch
import test_concept_adoption_intents as fixture
from workspace_control.worklist_peer import WorklistError
from workspace_control import concept_adoption_wire as wire

class ConceptAdoptionPeerTests(unittest.TestCase):
 setUp=fixture.ConceptAdoptionIntentTests.setUp
 tearDown=fixture.ConceptAdoptionIntentTests.tearDown
 freeze=fixture.ConceptAdoptionIntentTests.freeze
 def configured(self):
  peer=self.service.concept_adoptions
  b={**self.binding,'endpoint':'http://127.0.0.1:9999','forge_token':'T'*64,'expires_at':'2099-01-01T00:00:00+00:00','permissions':['PREPARE','READ'],'maximum_records':8,'label':'Owner setup only'}
  peer._write_bindings([b]);return peer,b,self.freeze()
 def pending(self,b,intent):
  return {**{k:b[k] for k in ['instance_id','principal_id','audience','dossier_id','pairing_id']},'contract_version':wire.CONTRACT,'operation_id':intent['request']['operation_id'],'plan_id':'pending-original','request_digest':wire.peer_digest(intent['request']),'state':'PREPARING','result':None,'proposal_kind':wire.KIND,'original_intent':True,'approval':'NOT_PERFORMED','registration':'NOT_PERFORMED'}
 def test_only_real_404_permits_first_dispatch_then_no_repost(self):
  peer,b,intent=self.configured();calls=[]
  def transport(binding,method,path,*args,**kw):
   calls.append(method)
   if method=='GET':raise WorklistError('INSPECTION_ADOPTION_NOT_FOUND',http_status=404)
   return self.pending(b,intent)
  with patch.object(peer,'_request',side_effect=transport):
   self.assertEqual(peer.fetch(self.token,self.source['id'],b,intent,prepare=True)['state'],'PREPARING')
   with self.assertRaises(WorklistError) as error:peer.fetch(self.token,self.source['id'],b,intent,prepare=True)
   self.assertEqual(error.exception.state,'ADOPTION_ORIGINAL_PENDING')
  self.assertEqual(calls,['GET','POST','GET'])
 def test_wrong_status_with_notfound_code_never_claims_or_posts(self):
  peer,b,intent=self.configured()
  for status in [403,409,503]:
   with patch.object(peer,'_request',side_effect=WorklistError('INSPECTION_ADOPTION_NOT_FOUND',http_status=status)) as mock:
    with self.assertRaises(WorklistError):peer.fetch(self.token,self.source['id'],b,intent,prepare=True)
    self.assertEqual(mock.call_count,1)
  self.assertTrue(peer.intents.claim_dispatch(self.scope,self.source['id'],self.command['operation_id']))
 def test_current_actor_revocation_is_denied_at_guard_entry(self):
  peer,b,intent=self.configured();self.service.conversations.revoke_grants(*self.scope)
  with self.assertRaises(WorklistError) as error:
   with peer.dispatch_guard(self.token,self.source['id'],b):self.fail('revoked actor entered')
  self.assertEqual(error.exception.state,'DENIED')
 def test_binding_revoke_expiry_and_lost_store_fail_closed(self):
  peer,b,intent=self.configured()
  with peer.dispatch_guard(self.token,self.source['id'],b):pass
  peer._write_bindings([{**b,'expires_at':'2000-01-01T00:00:00+00:00'}])
  with self.assertRaises(WorklistError):peer.snapshot(self.token,self.source['id'],b['id'])
  peer._write_bindings([b]);peer.revoke(b['id'])
  with self.assertRaises(WorklistError):peer.snapshot(self.token,self.source['id'],b['id'])
  (self.root/'concept-adoption-bindings.json').unlink()
  with self.assertRaises(WorklistError):peer.sources(self.token,self.source['id'])
