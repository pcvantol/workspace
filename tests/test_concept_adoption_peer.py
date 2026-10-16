import unittest,json,hashlib,time,os
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
  return {**{k:b[k] for k in ['instance_id','principal_id','audience','dossier_id','pairing_id']},'contract_version':wire.CONTRACT,'operation_id':intent['request']['operation_id'],'plan_id':'inspection-proposal-'+hashlib.sha256(wire.canonical([b[k] for k in ('instance_id','principal_id','audience','dossier_id')]+[intent['request']['operation_id']])+b'\n').hexdigest()[:32],'request_digest':wire.peer_digest(intent['request']),'state':'PREPARING','result':None,'proposal_kind':wire.KIND,'original_intent':True,'approval':'NOT_PERFORMED','registration':'NOT_PERFORMED'}
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

 def test_binding_marker_loss_corruption_refuses_read_and_write_without_repair(self):
  peer,b,_=self.configured();marker=self.root/'concept-adoption-bindings-initialized.json'
  original=marker.read_bytes();bindings=(self.root/'concept-adoption-bindings.json').read_bytes()
  for damage in [None,{}, {'schema_version':2},{'schema_version':True}]:
   if damage is None:marker.unlink(missing_ok=True)
   else:marker.write_text(json.dumps(damage))
   with self.assertRaises(WorklistError):peer._bindings()
   with self.assertRaises(WorklistError):peer._write_bindings([b])
   self.assertEqual((self.root/'concept-adoption-bindings.json').read_bytes(),bindings)
   self.assertEqual(marker.exists(),damage is not None)
   marker.write_bytes(original);os.chmod(marker,0o600)
  self.assertEqual(peer._bindings(),[b])
 def test_original_plan_identity_mismatch_rejected_even_with_correct_scope_and_digest(self):
  peer,b,intent=self.configured();packet=self.pending(b,intent)
  wire.result(packet,b,intent['request']);packet['plan_id']='inspection-proposal-'+'0'*32
  with self.assertRaises(WorklistError):wire.result(packet,b,intent['request'])
 def test_read_budget_consumed_by_capability_cannot_start_original_get(self):
  peer,b,intent=self.configured()
  with patch.object(peer,'cap',side_effect=lambda *a,**kw:time.sleep(.02)),patch.object(peer,'fetch') as fetch:
   with self.assertRaises(WorklistError) as error:peer.read(self.token,self.source['id'],b['id'],self.command['operation_id'],timeout=.001)
   self.assertEqual(error.exception.state,'UNAVAILABLE');fetch.assert_not_called()

 def test_absolute_transport_deadline_interrupts_dripping_headers_or_body(self):
  import threading,time
  from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
  from workspace_control.advisory_http import request
  for drip_headers in (False,True):
   class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
     payload=b'{"value":"'+b'x'*100+b'"}'
     try:
      self.send_response(200)
      if drip_headers:
       self.wfile.write(b'X-Drip: ');self.wfile.flush()
       for _ in range(100):self.wfile.write(b'x');self.wfile.flush();time.sleep(.03)
       self.wfile.write(b'\r\n')
      self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)));self.end_headers()
      for byte in payload:self.wfile.write(bytes([byte]));self.wfile.flush();time.sleep(.03)
     except (OSError,BrokenPipeError):pass
   server=ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever);thread.start()
   start=time.monotonic()
   try:
    with self.assertRaises(WorklistError) as error:request({'endpoint':'http://127.0.0.1:'+str(server.server_port),'forge_token':'T'*64},'GET','/source-only',inspection_audience='workspace',timeout=.15,absolute_timeout=True)
    self.assertEqual(error.exception.state,'UNAVAILABLE');self.assertLess(time.monotonic()-start,.8)
   finally:server.shutdown();server.server_close();thread.join()
