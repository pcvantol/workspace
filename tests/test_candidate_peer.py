"""Real own Server/CLI/auth with an explicit external wire-unit producer fixture."""
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
from workspace_control.http import handler_for
from workspace_control.cli import main
from workspace_control import candidate_contract as w
from tests.test_candidate_contract import capability,source,proposal,registration,preview,request,registration_request

class CandidatePeerTests(unittest.TestCase):
 def setUp(self):
  temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name);self.root.chmod(0o700);initialize(self.root)
  (self.root/'projects.json').write_text(json.dumps({'source':'LOCAL','observed_at':datetime.now(timezone.utc).isoformat(),'projects':[{'id':'ws-project','name':'Synthetic'}]}));(self.root/'projects.json').chmod(0o600)
  self.ws=Service(self.root);self.addCleanup(self.ws.close)
  self.requests=[];self.error=None;self.error_code=None;self.bad=False;self.delay=None;self.entered=Event();self.release=Event();self.body_authorized=Event()
  self.tokens={};self.client={};self.drafts={};self.conversations={};self.files={}
  for actor in ['alice','bob']:
   self.drafts[actor]=self.ws.issue_conversation_grant(actor,'ws-project')
   self.conversations[actor]=self.ws.conversations.create((actor,'ws-project'),{'title':'Synthetic '+actor,'focus':'Bounded Candidate','mode':'BUSINESS','draft':'Unsent text','request_id':secrets.token_hex(16)})['id'];self.tokens[actor]=secrets.token_urlsafe(48)
  owner=self
  class Producer(BaseHTTPRequestHandler):
   def log_message(self,*args):pass
   def route(self):
    actor=next((a for a,t in owner.tokens.items() if self.headers.get('Authorization')=='Bearer '+t),None)
    owner.requests.append((self.command,self.path));conv=owner.conversations.get(actor,'unknown')
    code=owner.error or (200 if actor else 403)
    if self.path==owner.delay:owner.entered.set();assert owner.release.wait(5)
    if code!=200:value={'contract_version':w.CONTRACT,'error':{'code':owner.error_code or ('PROPOSAL_STALE' if code==409 else 'CANDIDATE_SUBJECT_NOT_FOUND' if code==404 else 'CANDIDATE_SOURCE_UNAVAILABLE')}}
    elif self.path.endswith('/capability'):value=capability();value['conversation_id']=conv
    elif '/source/' in self.path:value={'contract_version':w.CONTRACT,'source':source(),'read_only':True}
    elif self.command=='POST':
     body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
     if self.path.endswith('/registrations'):value=registration()
     else:value={'contract_version':w.CONTRACT,'proposal':proposal(body['expected_revision']+1),'registered':False,'additional_model_calls':0}
    elif '/registrations/' in self.path:
     value={'contract_version':w.CONTRACT,'state':'PENDING','operation_id':'pending-one','read_only':True} if self.path.endswith('pending-one') else registration()
    else:value=preview()
    def rebind(x):
     if isinstance(x,dict):
      if 'conversation_id' in x:x['conversation_id']=conv
      if 'principal_reference' in x:x['principal_reference']='forge-one:'+str(actor)
      for v in x.values():rebind(v)
      if 'proposal_digest' in x and 'fields' in x:x['proposal_digest']=w.digest({k:v for k,v in x.items() if k!='proposal_digest'})
     elif isinstance(x,list):
      for v in x:rebind(v)
    rebind(value)
    if 'original_receipt' in value:
     r=value['original_receipt'];r['registration_key']=w.digest(['forge-one:'+str(actor),'project-one','repo-one',conv,'proposal-one',1]);p=proposal();p['conversation_id']=conv;p['principal_reference']='forge-one:'+str(actor);r['proposal_digest']=w.digest({k:v for k,v in p.items() if k!='proposal_digest'})
    if owner.bad:value['unexpected']=True
    raw=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
   do_GET=route;do_POST=route
  self.fg=ThreadingHTTPServer(('127.0.0.1',0),Producer);self.serve(self.fg);self.endpoint='http://127.0.0.1:'+str(self.fg.server_port)
  for actor in ['alice','bob']:
   token=self.root/(actor+'.forge');token.write_text(self.tokens[actor]);token.chmod(0o600)
   proof={'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one','principal_id':actor,'conversation_id':self.conversations[actor],'proposal_ids':['proposal-one','proposal-two'],'grant_id':'candidate-'+actor,'maximum_registrations':2,'expires_at':'2026-10-09T00:00:00Z','state':'ACTIVE','token_sha256':sha256(self.tokens[actor].encode()).hexdigest()}
   file=self.root/(actor+'.proof');file.write_text(json.dumps(proof));file.chmod(0o600);client=self.root/(actor+'.client');self.files[actor]=(file,token,client)
   self.ws.provision_candidate(actor,'ws-project',self.endpoint,str(file),str(token),str(client));self.client[actor]=client.read_text().strip()
  base=handler_for(self.ws)
  class Observed(base):
   def _conversation_scope(self):
    value=super()._conversation_scope()
    if value is not None:owner.body_authorized.set()
    return value
  self.http=ThreadingHTTPServer(('127.0.0.1',0),Observed);self.serve(self.http)
 def serve(self,server):
  t=Thread(target=server.serve_forever,daemon=True);t.start();self.addCleanup(server.server_close);self.addCleanup(t.join,2);self.addCleanup(server.shutdown)
 def call(self,path,method='GET',body=None,actor='alice',headers=None):
  h={'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,'X-Workspace-Draft-Grant':self.drafts[actor],'X-Workspace-Candidate-Grant':self.client[actor],'Content-Type':'application/json'};h.update(headers or {})
  try:
   with urlopen(Request('http://127.0.0.1:'+str(self.http.server_port)+path,headers=h,method=method,data=None if body is None else json.dumps(body).encode()),timeout=7) as r:return r.status,json.load(r)
  except HTTPError as e:
   try:return e.code,json.load(e)
   finally:e.close()
 def testSeparateScopeSixRoutesExactSavesAndReadOnlyInspection(self):
  c=self.conversations['alice'];base='/v1/advisory-candidates/'+c
  self.assertEqual(self.call('/v1/advisory-candidates/access')[1]['actor_id'],'alice')
  self.assertEqual(self.call('/v1/advisory-candidates/capability')[0],200)
  self.assertEqual(self.call(base+'/source/turn-one')[0],200)
  p=self.call(base+'/proposals/proposal-one?revision=1');self.assertEqual(p[0],200)
  self.assertTrue(all(m=='GET' for m,_ in self.requests))
  r=request();r['conversation_id']=c;self.assertEqual(self.call(base+'/proposals','POST',r)[0],200)
  rr=registration_request();rr.update(conversation_id=c,proposal_digest=p[1]['proposal']['proposal_digest'])
  self.assertEqual(self.call(base+'/proposals/proposal-one/registrations','POST',rr)[0],200)
  self.assertEqual(self.call(base+'/proposals/proposal-one/registrations/operation-one')[0],200)
  self.assertEqual(self.call(base+'/proposals/proposal-one/registrations/pending-one')[1]['state'],'PENDING')
  for h in [{'X-Workspace-Candidate-Grant':self.client['bob']},{'X-Workspace-Candidate-Grant':self.drafts['alice']},{'X-Workspace-Draft-Grant':self.drafts['bob']}]:self.assertEqual(self.call(base+'/source/turn-one',headers=h)[0],403)
  self.assertEqual(self.call(base+'/source/turn-one',actor='bob')[0],403)
  for path in [base+'/source/bad%2fid',base+'/source/turn-one?extra=1',base+'/proposals/proposal-one?revision=1&revision=2',base+'/proposals/proposal-one',base+'/proposals/proposal-one?revision=x','/v1/advisory-candidates/capability?extra=1']:self.assertEqual(self.call(path)[0],400)
  self.assertEqual(self.call(base+'/proposals/foreign?revision=1')[0],403)
  self.assertEqual(self.call(base+'/proposals/proposal-one?revision=9')[0],400)
  rr['proposal_id']='proposal-two';self.assertEqual(self.call(base+'/proposals/proposal-one/registrations','POST',rr)[0],400)
  for code in [404,409,503]:
   self.error=code;self.assertEqual(self.call(base+'/source/turn-one')[0],code)
  self.error=409;self.error_code='CONVERSATION_BUSY';self.assertEqual(self.call(base+'/source/turn-one'),(409,{'error':'CONVERSATION_BUSY'}))
  self.error_code=None
  self.error=None;self.bad=True;self.assertEqual(self.call(base+'/source/turn-one')[0],503)
 def testOwnerReceiptTokenPrincipalAndPrivateFilesCannotInventGrant(self):
  file,token,client=self.files['alice'];p=json.loads(file.read_text())
  for field,value in [('principal_id','bob'),('token_sha256','0'*64),('state','REVOKED'),('proposal_ids',['proposal-one']*2),('maximum_registrations',True),('conversation_id',self.conversations['bob'])]:
   bad={**p,field:value};file.write_text(json.dumps(bad));out=self.root/'new.client'
   with self.assertRaises((ValueError,FileNotFoundError)):self.ws.provision_candidate('alice','ws-project',self.endpoint,str(file),str(token),str(out))
   self.assertFalse(out.exists())
  file.write_text(json.dumps(p));file.chmod(0o644)
  with self.assertRaises(ValueError):self.ws.provision_candidate('alice','ws-project',self.endpoint,str(file),str(token),str(self.root/'private.client'))
  file.chmod(0o600)
  for actor,project,path in [('bad/id','ws-project',str(file)),('alice','unknown',str(file)),('alice','ws-project','relative')]:
   with self.assertRaises(ValueError):self.ws.provision_candidate(actor,project,self.endpoint,path,str(token),str(self.root/'fail.client'))
  self.ws.revoke_candidate(self.ws.candidates.access(self.client['alice'])['id'])
  output=io.StringIO()
  with redirect_stdout(output):
   result=main(['--root',str(self.root),'candidate-bind-issue','--actor','alice','--project','ws-project','--forge-endpoint',self.endpoint,'--forge-grant-receipt-file',str(file),'--forge-token-file',str(token),'--client-token-file',str(self.root/'cli.client')])
  self.assertEqual(result,0);binding=json.loads(output.getvalue())
  with redirect_stdout(io.StringIO()):self.assertEqual(main(['--root',str(self.root),'candidate-bind-revoke','--binding-id',binding['binding_id']]),0)
 def testRevokeDuringDelayedBodyAndDelayedResult(self):
  import socket,http.client
  from concurrent.futures import ThreadPoolExecutor
  c=self.conversations['alice'];base='/v1/advisory-candidates/'+c
  for path,body in [(base+'/proposals',{**request(),'conversation_id':c}),(base+'/proposals/proposal-one/registrations',{**registration_request(),'conversation_id':c})]:
   self.drafts['alice']=self.ws.issue_conversation_grant('alice','ws-project');self.body_authorized.clear();payload=json.dumps(body).encode();before=sum(m=='POST' for m,_ in self.requests)
   h={'Host':'127.0.0.1:'+str(self.http.server_port),'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,'X-Workspace-Draft-Grant':self.drafts['alice'],'X-Workspace-Candidate-Grant':self.client['alice'],'Content-Type':'application/json','Content-Length':str(len(payload))}
   with socket.create_connection(self.http.server_address,timeout=7) as sock:
    sock.sendall(('POST '+path+' HTTP/1.1\r\n'+''.join(k+': '+v+'\r\n' for k,v in h.items())+'\r\n').encode());self.assertTrue(self.body_authorized.wait(3));self.ws.revoke_conversation_grants('alice','ws-project');sock.sendall(payload);r=http.client.HTTPResponse(sock);r.begin();self.assertEqual(r.status,403);r.read();r.close()
   self.assertEqual(sum(m=='POST' for m,_ in self.requests),before)
  self.drafts['alice']=self.ws.issue_conversation_grant('alice','ws-project');self.delay=base+'/source/turn-one'
  with ThreadPoolExecutor(max_workers=1) as pool:
   result=pool.submit(self.call,self.delay)
   try:self.assertTrue(self.entered.wait(3));self.ws.revoke_candidate(self.ws.candidates.access(self.client['alice'])['id'])
   finally:self.release.set()
   self.assertEqual(result.result()[0],403)
if __name__=='__main__':unittest.main()
