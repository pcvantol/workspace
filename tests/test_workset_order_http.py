"""Unit HTTP boundary proof; recorded producer packets are not installed acceptance."""
from copy import deepcopy
from datetime import datetime,timezone,timedelta
import json,secrets,tempfile,threading,unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from workspace_control.service import Service,initialize
from workspace_control.http import ThreadingHTTPServer,handler_for
from workspace_control.worklist_peer import WorklistError
from workspace_control import workset_order_contract as wire

F=Path(__file__).parent/'fixtures'
class OrderHTTPTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.root.chmod(0o700);initialize(self.root)
  self.service=Service(self.root);self.addCleanup(self.service.close);self.peer=self.service.workset_orders
  raw=json.loads((F/'workset-order-wire.json').read_text());self.cap={k:v for k,v in raw['capability'].items() if k in wire.SCHEMA['$defs']['capability']['properties']};self.cap['expires_at']=(datetime.now(timezone.utc)+timedelta(minutes=5)).isoformat()
  self.current=raw['current'];self.preview=raw['preview'];self.applied=json.loads((F/'workset-order-applied.json').read_text());self.failure=None;self.calls=[]
  self.key=self.current['workset_id'];self.actor=self.current['current']['scope']['principal_id'];self.project='order-project'
  self.receipt={'permissions':self.cap['permissions'],'state':'ACTIVE','profile_id':'solo','principal_id':self.actor,'instance_id':self.cap['scope']['instance_id'],'project_id':self.cap['scope']['project_id'],'repository_id':self.cap['scope']['repository_id'],'installation_id':self.current['current']['installation_id'],'worksets':self.cap['worksets'],'expires_at':self.cap['expires_at'],'maximum_amendments':self.cap['maximum_amendments']}
  self.receipt_file=self.root/'receipt';self.receipt_file.write_text(json.dumps(self.receipt));self.receipt_file.chmod(0o600)
  self.producer=self.root/'producer';self.producer.write_text(secrets.token_urlsafe(48));self.producer.chmod(0o600);self.client=self.root/'client'
  mocked=patch('workspace_control.workset_order_peer.request',side_effect=self.response);mocked.start();self.addCleanup(mocked.stop)
  self.created=self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.client));self.token=self.client.read_text().strip();self.binding=self.peer.access(self.token)
  (self.root/'projects.json').write_text(json.dumps({'source':'LOCAL','observed_at':datetime.now(timezone.utc).isoformat(),'partial':False,'projects':[{'id':self.project,'name':'Own order unit scope'}]}))
  (self.root/'projects.json').chmod(0o600)
  self.draft=self.service.issue_conversation_grant(self.actor,self.project)
  self.server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service));self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start();self.addCleanup(self.stop)
 def stop(self):self.server.shutdown();self.server.server_close();self.thread.join()
 def response(self,binding,method,path,body=None,**options):
  self.calls.append((method,path,deepcopy(body)))
  if self.failure:raise WorklistError(self.failure)
  if path.endswith('/capability'):return deepcopy(self.cap)
  if path.endswith('/preview'):return deepcopy(self.preview)
  if path.endswith('/confirm') or '/operations/' in path:return deepcopy(self.applied)
  return deepcopy(self.current)
 def call(self,suffix='',body=None,headers=None):
  req=Request('http://127.0.0.1:'+str(self.server.server_port)+'/v1/workset-orders'+suffix,data=None if body is None else json.dumps(body).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+self.service.token,'X-Workspace-Instance':self.service.instance_id,'X-Workspace-Draft-Grant':self.draft,'X-Workspace-Order-Grant':self.token,**(headers or {})},method='GET' if body is None else 'POST')
  try:
   with urlopen(req) as r:return r.status,json.load(r)
  except HTTPError as e:return e.code,json.load(e)
 def testClosedRoutesOwnScopeAndOriginalCommand(self):
  key='/'+self.key
  for path in ['', '/capability',key]:self.assertEqual(self.call(path)[0],200)
  self.assertEqual(self.call(key+'/preview',{'contract_version':wire.CONTRACT,'proposed_order':self.preview['package']['proposed_order']})[0],200)
  command=self.applied['original_request'];self.assertEqual(self.call(key+'/confirm',command)[0],200)
  self.assertEqual([body for method,path,body in self.calls if method=="POST" and path.endswith("/confirm")][-1],command)
  self.assertEqual(self.call(key+'/operations/'+command['operation_id'])[0],200)
  self.assertEqual(self.call('/foreign')[0],403)
  self.assertEqual(self.call('/foreign?x=1')[0],400)
  foreign=self.service.issue_conversation_grant('own-other',self.project)
  self.assertEqual(self.call(key,headers={'X-Workspace-Draft-Grant':foreign})[0],403)
  self.assertEqual(self.call(key,headers={'X-Workspace-Order-Grant':'x'*43})[0],403)
  self.assertEqual(self.call(key+'/confirm',{})[0],400)
  self.peer.revoke(self.created['binding_id']);self.assertEqual(self.call(key)[0],403)
 def testAuthorityErrorClassificationAndNoReadTokenPromotion(self):
  for state,status in [('DENIED',403),('ORDER_SCOPE_DENIED',403),('ORDER_OPERATION_UNKNOWN',404),('ORDER_PREVIEW_STALE',409),('ORDER_ALLOWANCE_EXHAUSTED',409),('INVALID_REQUEST',400),('UNAVAILABLE',409),('FUTURE',503)]:
   self.failure=state;self.assertEqual(self.call('/'+self.key)[0],status,(state,status))
  self.failure=None;self.cap['permissions']=['READ'];self.binding['permissions']=['READ']
  with self.assertRaises(WorklistError):self.peer.confirm(self.binding,self.key,self.applied['original_request'])
 def testOriginalAppliedReceiptMismatchCannotPublish(self):
  for field,value in [('package_digest','sha256:'+'0'*64),('order_revision',99),('consumed_activations',99),('applied_order',self.applied['original_receipt']['original_order'])]:
   corrupted=deepcopy(self.applied);corrupted['original_receipt'][field]=value
   with self.assertRaises(WorklistError):wire.operation(corrupted,self.binding,self.key,corrupted['operation_id'])
  self.applied['canonical_decisions_observed']={'business':'foreign','architecture':'foreign'}
  self.assertEqual(self.call('/'+self.key+'/operations/'+self.applied['operation_id'])[0],503)
 def testReceiptAndLocalBindingValidationRejectsBeforeIssuingConsumer(self):
  for field,value in [('profile_id','other'),('state','REVOKED'),('principal_id','foreign')]:
   bad={**self.receipt,field:value};self.receipt_file.write_text(json.dumps(bad))
   with self.assertRaises(WorklistError):self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.root/'other'))
  for field,value in [('maximum_amendments',17),('permissions',['READ','ADMIN']),('client_digest','bad'),('expires_at','bad')]:self.assertFalse(self.peer._valid_record({**self.binding,field:value}))
  self.assertFalse(self.peer._valid_record({}));self.assertFalse((self.root/'other').exists())
if __name__=='__main__':unittest.main()
