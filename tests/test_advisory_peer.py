"""Real Workspace HTTP/auth/storage with a declared external producer unit fixture."""
from contextlib import redirect_stdout
from copy import deepcopy
from datetime import datetime,timezone
from hashlib import sha256
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
from threading import Thread,Event
from urllib.request import Request,urlopen
from urllib.error import HTTPError
import io,json,secrets,tempfile,unittest
from workspace_control.service import initialize,Service
from workspace_control.http import handler_for,advisory_openapi_contract
from workspace_control.cli import main
from workspace_control import advisory_contract as w
from workspace_control.worklist_peer import WorklistError
from tests.test_advisory_contract import capability,record

class AdvisoryPeerTests(unittest.TestCase):
 def setUp(self):
  temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name);self.root.chmod(0o700);initialize(self.root)
  stamp=datetime.now(timezone.utc).isoformat()
  (self.root/'projects.json').write_text(json.dumps({'source':'LOCAL','observed_at':stamp,'projects':[{'id':'ws-project','name':'Synthetic project'}]}));(self.root/'projects.json').chmod(0o600)
  self.ws=Service(self.root);self.addCleanup(self.ws.close);self.error=None;self.bad=False;self.requests=[];self.turns={};self.revision=0;self.read_entered=Event();self.read_release=Event();self.delay_path=None;self.body_authorized=Event()
  self.owner_tokens={};self.client={};self.proof={};self.drafts={};self.conversations={}
  for actor in ['alice','bob']:
   self.drafts[actor]=self.ws.issue_conversation_grant(actor,'ws-project')
   self.conversations[actor]=self.ws.conversations.create((actor,'ws-project'),{'title':'Synthetic '+actor,'focus':'Bounded advice','mode':'BUSINESS','draft':'Synthetic unsent text.','request_id':secrets.token_hex(16)})['id']
   self.owner_tokens[actor]=secrets.token_urlsafe(48)
  owner=self
  class Producer(BaseHTTPRequestHandler):
   def log_message(self,*args):pass
   def route(self):
    actor=next((a for a,t in owner.owner_tokens.items() if self.headers.get('Authorization')=='Bearer '+t),None)
    owner.requests.append((self.command,self.path))
    if self.command=="GET" and self.path==owner.delay_path:
     owner.read_entered.set();assert owner.read_release.wait(4)
    code=owner.error or (200 if actor else 403);value={}
    conv=owner.conversations.get(actor,'unknown')
    if code!=200:value={'contract_version':w.CONTRACT,'error':{'code':'TURN_BUDGET_EXHAUSTED' if code==409 else 'ADVISORY_SOURCE_UNAVAILABLE'}}
    elif self.path.startswith('/v1/advisory/capability'):
     value=capability();value['conversation_ids']=[conv]
    elif self.command=='POST' and self.path.endswith('/cancel'):
     r=deepcopy(next(iter(owner.turns.values())));r['status']='CANCEL_REQUESTED';r['execution']='MAY_HAVE_HAPPENED';r['outcome']=None
     value={'contract_version':w.CONTRACT,'original_turn':r,'current_revision':owner.revision,'provider_stopped':False,'cancel_request_recorded':True}
    elif self.command=='POST':
     body=json.loads(self.rfile.read(int(self.headers['Content-Length'])));r=record();r['request']=body;r['request_digest']=w.digest(body);r['grant_id']='grant-'+actor;r['outcome']['output']['request_digest']=r['request_digest'];r['outcome']['output']['advisor_kind']=body['advisor_kind'];r['outcome']['result_digest']=w.digest(r['outcome']['output']);owner.turns[body['turn_id']]=r;owner.revision+=1
     value={'contract_version':w.CONTRACT,'original_turn':r,'current_revision':owner.revision,'recorded':True}
    elif '/turns/' in self.path:
     turn=self.path.rsplit('/',1)[1]
     if turn not in owner.turns:code=404;value={'contract_version':w.CONTRACT,'error':{'code':'ADVISORY_NOT_FOUND'}}
     else:value={'contract_version':w.CONTRACT,'original_turn':owner.turns[turn],'current_revision':owner.revision,'read_only':True}
    else:
     value={'contract_version':w.CONTRACT,'conversation_id':conv,'scope':{'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one'},'revision':owner.revision,'turns':list(owner.turns.values())[:4],'next_cursor':None,'consumed_turns':len(owner.turns),'maximum_turns':8,'retention':'PRIVATE_RETAINED_NO_AUTOMATIC_DELETE','read_only':True}
    if owner.bad and 'original_turn' in value:
     value['original_turn']=deepcopy(value['original_turn']);out=value['original_turn']['outcome']['output'];out['summary']='<script>unsafe</script>';value['original_turn']['outcome']['result_digest']=w.digest(out)
    raw=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
   do_GET=route;do_POST=route
  self.fg=ThreadingHTTPServer(('127.0.0.1',0),Producer);thread=Thread(target=self.fg.serve_forever,daemon=True);thread.start();self.addCleanup(self.fg.server_close);self.addCleanup(thread.join,2);self.addCleanup(self.fg.shutdown);self.endpoint='http://127.0.0.1:'+str(self.fg.server_port)
  for actor in ['alice','bob']:
   token=self.root/(actor+'.forge');token.write_text(self.owner_tokens[actor]);token.chmod(0o600)
   proof={'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','principal_id':actor,'conversation_ids':[self.conversations[actor]],'grant_id':'grant-'+actor,'maximum_turns':8,'expires_at':'2026-10-09T00:00:00Z','state':'ACTIVE','token_sha256':sha256(self.owner_tokens[actor].encode()).hexdigest()}
   file=self.root/(actor+'.proof');file.write_text(json.dumps(proof));file.chmod(0o600);self.proof[actor]=file
   client=self.root/(actor+'.client');self.ws.provision_advisory(actor,'ws-project',self.endpoint,str(file),str(token),str(client));self.client[actor]=client.read_text().strip()
  base=handler_for(self.ws)
  class Observed(base):
   def _conversation_scope(self):
    value=super()._conversation_scope()
    if value is not None:owner.body_authorized.set()
    return value
  self.http=ThreadingHTTPServer(('127.0.0.1',0),Observed);thread=Thread(target=self.http.serve_forever,daemon=True);thread.start();self.addCleanup(self.http.server_close);self.addCleanup(thread.join,2);self.addCleanup(self.http.shutdown)
 def call(self,path,method='GET',body=None,actor='alice',headers=None):
  h={'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,'X-Workspace-Draft-Grant':self.drafts[actor],'X-Workspace-Advisory-Grant':self.client[actor],'Content-Type':'application/json'};h.update(headers or {})
  try:
   with urlopen(Request('http://127.0.0.1:'+str(self.http.server_port)+path,headers=h,method=method,data=None if body is None else json.dumps(body).encode()),timeout=5) as r:return r.status,json.load(r)
  except HTTPError as e:
   try:return e.code,json.load(e)
   finally:e.close()
 def testScopeRoutesTurnsCursorCancelAndNoReadGeneration(self):
  c=self.conversations['alice'];base='/v1/advisory/'+c
  self.assertEqual(self.call('/v1/advisory/access')[1]['actor_id'],'alice');self.assertEqual(self.call('/v1/advisory/capability')[0],200);self.assertEqual(self.call(base+'?cursor=0&limit=4')[0],200)
  self.assertTrue(all(method=='GET' for method,_ in self.requests))
  r=record()['request'];r['conversation_id']=c
  self.assertEqual(self.call(base+'/turns','POST',r)[0],200);self.assertEqual(self.call(base+'/turns/turn-one')[0],200)
  self.assertEqual(self.call(base+'?cursor=0&limit=4')[1]['turns'][0]['request']['objective'],r['objective'])
  cancel={'contract_version':w.CONTRACT,'expected_revision':1,'request_digest':w.digest(r)};self.assertFalse(self.call(base+'/turns/turn-one/cancel','POST',cancel)[1]['provider_stopped'])
  self.assertEqual(self.call(base,actor='bob')[0],403);self.assertEqual(self.call(base,headers={'X-Workspace-Advisory-Grant':self.client['bob']})[0],403)
  self.assertEqual(self.call(base,headers={'X-Workspace-Advisory-Grant':self.drafts['alice']})[0],403)
  self.assertEqual(self.call(base+'?limit=5')[0],400);self.assertEqual(self.call(base+'?cursor=0&cursor=1')[0],400)
  self.assertEqual(self.call('/v1/advisory/capability?source_id=one')[0],400)
  self.assertEqual(self.call('/v1/advisory/capability?source_id=one&source_version=sha256%3A'+'a'*64)[0],200)
  self.assertEqual(self.call(base+'/turns/unknown')[0],404)
  self.bad=True;self.assertEqual(self.call(base+'/turns/turn-one')[0],503);self.bad=False
  self.error=409;self.assertEqual(self.call('/v1/advisory/capability')[1]['error'],'TURN_BUDGET_EXHAUSTED');self.error=503;self.assertEqual(self.call(base)[0],503)
  self.assertEqual(self.call('/v1/advisory/openapi.json')[0],200);self.assertIn('x-forge-wire-schema',advisory_openapi_contract())
 def testRevocationWhileReadingBodyForwardsNoSubmitOrCancel(self):
  import socket,http.client
  c=self.conversations['alice'];base='/v1/advisory/'+c
  for path,body in [(base+'/turns',{**record()['request'],'conversation_id':c}),(base+'/turns/turn-one/cancel',{'contract_version':w.CONTRACT,'expected_revision':1,'request_digest':w.digest(record()['request'])})]:
   self.drafts['alice']=self.ws.issue_conversation_grant('alice','ws-project');self.body_authorized.clear()
   payload=json.dumps(body).encode();before=len([x for x in self.requests if x[0]=='POST'])
   headers={'Host':'127.0.0.1:'+str(self.http.server_port),'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,'X-Workspace-Draft-Grant':self.drafts['alice'],'X-Workspace-Advisory-Grant':self.client['alice'],'Content-Type':'application/json','Content-Length':str(len(payload))}
   with socket.create_connection(self.http.server_address,timeout=5) as sock:
    sock.sendall(('POST '+path+' HTTP/1.1\r\n'+''.join(k+': '+v+'\r\n' for k,v in headers.items())+'\r\n').encode())
    self.assertTrue(self.body_authorized.wait(3));self.ws.revoke_conversation_grants('alice','ws-project');sock.sendall(payload)
    response=http.client.HTTPResponse(sock);response.begin();self.assertEqual(response.status,403);response.read();response.close()
   self.assertEqual(len([x for x in self.requests if x[0]=='POST']),before)
 def testBindingAndDraftRevocationDuringDelayedHistoryDenyResponse(self):
  from concurrent.futures import ThreadPoolExecutor
  c=self.conversations['alice'];self.delay_path='/v1/advisory/'+c+'?cursor=0&limit=4'
  binding=self.ws.advisory.access(self.client['alice'])
  with ThreadPoolExecutor(max_workers=1) as pool:
   response=pool.submit(self.call,self.delay_path)
   try:
    self.assertTrue(self.read_entered.wait(3));self.ws.revoke_advisory(binding['id'])
   finally:self.read_release.set()
   self.assertEqual(response.result(timeout=5)[0],403)
  self.delay_path='/v1/advisory/'+self.conversations['bob']+'?cursor=0&limit=4'
  self.read_entered.clear();self.read_release.clear()
  with ThreadPoolExecutor(max_workers=1) as pool:
   response=pool.submit(self.call,self.delay_path,actor='bob')
   try:
    self.assertTrue(self.read_entered.wait(3));self.ws.revoke_conversation_grants('bob','ws-project')
   finally:self.read_release.set()
   self.assertEqual(response.result(timeout=5)[0],403)
 def testOwnerReceiptBindingCliRevocationAndInvalidInputs(self):
  peer=self.ws.advisory;binding=peer.access(self.client['alice']);self.ws.revoke_advisory(binding['id'])
  args=['--root',str(self.root),'advisory-bind-issue','--actor','alice','--project','ws-project','--forge-endpoint',self.endpoint,'--forge-grant-receipt-file',str(self.proof['alice']),'--forge-token-file',str(self.root/'alice.forge'),'--client-token-file',str(self.root/'new-client')]
  stream=io.StringIO()
  with redirect_stdout(stream):self.assertEqual(main(args),0)
  issued=json.loads(stream.getvalue());self.assertNotIn(self.owner_tokens['alice'],stream.getvalue())
  with redirect_stdout(io.StringIO()):main(['--root',str(self.root),'advisory-bind-revoke','--binding-id',issued['binding_id']])
  self.assertEqual(self.call('/v1/advisory/access')[0],403)
  proof=json.loads(self.proof['alice'].read_text());proof['token_sha256']='0'*64;self.proof['alice'].write_text(json.dumps(proof))
  with self.assertRaises(ValueError):self.ws.provision_advisory('alice','ws-project',self.endpoint,str(self.proof['alice']),str(self.root/'alice.forge'),str(self.root/'deny-client'))
  with self.assertRaises(ValueError):self.ws.provision_advisory('alice','foreign',self.endpoint,'relative','relative','relative')
  self.assertFalse(peer._valid_record({'id':'bad'}))
  with self.assertRaises(WorklistError):peer.history(binding,self.conversations['alice'],9,4)
  with self.assertRaises(WorklistError):peer.capability(binding,[{}]*3)
  with self.assertRaises(WorklistError):peer.turn(binding,self.conversations['alice'],'../bad')
if __name__=='__main__':unittest.main()
