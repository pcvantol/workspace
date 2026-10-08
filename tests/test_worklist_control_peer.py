"""Scoped consumer ingress/auth/transport source tests, not installed Forge qualification."""
from copy import deepcopy
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler
import http.client
import io
import json
import os
from pathlib import Path
import secrets
import tempfile
from threading import Thread
import unittest
from unittest.mock import patch

from tests.test_worklist_control_contract import current, request, receipt, readback
from tests.test_worklist_contract import seal
from workspace_control.cli import main
from workspace_control.http import ThreadingHTTPServer, handler_for, worklist_control_openapi_contract
from workspace_control.service import initialize, Service
from workspace_control.worklist_control_peer import WorklistControlTransport, control_request
from workspace_control.worklist_peer import WorklistError

class ControlPeerTests(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        self.root=Path(temp.name);self.root.chmod(0o700);initialize(self.root)
        self.ws=Service(self.root);self.addCleanup(self.ws.close)
        self.tokens={secrets.token_urlsafe(32):('actor-a','workset-a'),secrets.token_urlsafe(32):('actor-b','workset-b')}
        self.calls=[];self.revoked=set();self.error=None;self.corrupt=False;self.applied={}
        owner=self
        class Peer(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def answer(self):
                token=self.headers.get('Authorization','').removeprefix('Bearer ')
                owner.calls.append((self.command,self.path))
                code=owner.error or (403 if token in owner.revoked else 200)
                actor,workset=owner.tokens.get(token,('unknown','unknown'))
                if token not in owner.tokens or self.path.split('/')[3]!=workset:code=403
                body={'error':'private source detail must not escape'}
                if code==200:
                    state=current(False);op=None
                    if self.command=='POST':
                        data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                        old=receipt(data['intent']);old.update(principal_id=actor,operation_id=data['operation_id'],request=data)
                        from workspace_control.worklist_control_contract import request_digest
                        old['request_digest']=request_digest(data)
                        old['effect'].update(instance_id='forge-1',workset_id=workset,workset_revision=data['expected_revision']+2)
                        if old['effect']['hold']:old['effect']['hold']['operation_id']=data['operation_id']
                        owner.applied[workset]=old
                    old=owner.applied.get(workset)
                    if old:state=deepcopy(old['effect'])
                    if '/commands/' in self.path:
                        key=self.path.rsplit('/',1)[1]
                        if old and key==old['operation_id']:op={'state':'APPLIED','execution_known':True,'operation_id':key,'original_receipt':old}
                        else:code=404
                    state['workset_id']=workset
                    body=readback(state,op);body['principal_id']=actor
                    body['worklist']['scope'].update(principal_id=actor,workset_id=workset);seal(body['worklist'])
                    if self.command=='POST':
                        body['operation']={'state':'APPLIED','execution_known':True,'operation_id':old['operation_id'],'original_receipt':old}
                        body={'contract_version':'forge-worklist-control-readback/v1','original_receipt':old,'recorded':True,'current_readback':body}
                    if owner.corrupt:body['private-extra']='never exposed'
                encoded=json.dumps(body).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(encoded)));self.end_headers();self.wfile.write(encoded)
            do_GET=answer;do_POST=answer
        self.forge=ThreadingHTTPServer(('127.0.0.1',0),Peer);self.thread=Thread(target=self.forge.serve_forever,daemon=True);self.thread.start()
        self.addCleanup(self.stop,self.forge,self.thread)
        self.endpoint=f'http://127.0.0.1:{self.forge.server_port}'
        self.client_tokens={};self.bindings={}
        for token,(actor,workset) in self.tokens.items():
            path=self.root/(actor+'.forge');path.write_text(token);path.chmod(0o600)
            client=self.root/(actor+'.client')
            self.bindings[actor]=self.ws.provision_worklist_control(actor,self.endpoint,'forge-1',[workset],str(path),str(client))
            self.client_tokens[actor]=client.read_text().strip()
        self.http=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.ws));self.http_thread=Thread(target=self.http.serve_forever,daemon=True);self.http_thread.start();self.addCleanup(self.stop,self.http,self.http_thread)
    @staticmethod
    def stop(server,thread):server.shutdown();thread.join(2);server.server_close()
    def call(self,path,method='GET',body=None,actor='actor-a',**headers):
        connection=http.client.HTTPConnection('127.0.0.1',self.http.server_port,timeout=5)
        auth={'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,
              'X-Workspace-Worklist-Control-Grant':self.client_tokens[actor]}
        auth.update(headers)
        if body is not None:auth['Content-Type']='application/json'
        connection.request(method,path,body=None if body is None else json.dumps(body),headers=auth)
        response=connection.getresponse();result=response.status,json.loads(response.read());connection.close();return result
    def testTwoActorsCommandsReadsNoReadGrantUpgradeAndRevocation(self):
        self.assertEqual(self.call('/v1/workset-controls')[0],200)
        self.assertEqual(self.call('/v1/workset-controls/workset-b')[0],403)
        self.assertEqual(self.call('/v1/workset-controls/workset-b',actor='actor-b')[0],200)
        self.assertEqual(self.call('/v1/workset-controls/workset-a',**{'X-Workspace-Instance':'wrong'})[0],409)
        self.assertEqual(self.call('/v1/workset-controls/workset-a',**{'X-Workspace-Worklist-Control-Grant':secrets.token_urlsafe(32)})[0],403)
        code,result=self.call('/v1/workset-controls/workset-a/commands','POST',request());self.assertEqual(code,200);self.assertTrue(result['current_readback']['current']['held'])
        self.assertEqual(self.call('/v1/workset-controls/workset-a/commands/operation-a')[0],200)
        self.assertEqual(self.call('/v1/workset-controls/workset-a/commands/unknown')[0],404)
        self.assertEqual(self.call('/v1/workset-controls/workset-a/arm','POST',{})[0],405)
        count=len(self.calls);body=request();body['actor_id']='actor-a'
        self.assertEqual(self.call('/v1/workset-controls/workset-a/commands','POST',body)[0],400);self.assertEqual(len(self.calls),count)
        self.ws.revoke_worklist_control(self.bindings['actor-a']['binding_id'])
        self.assertEqual(self.call('/v1/workset-controls/workset-a')[0],403)
    def testSourceErrorsIntegrityAndOwnContract(self):
        for code,expected in [(401,401),(403,403),(404,404),(409,409),(503,503),(400,400),(302,503)]:
            self.error=code;status,body=self.call('/v1/workset-controls/workset-a');self.assertEqual(status,expected);self.assertNotIn('private',json.dumps(body))
        self.error=None;self.corrupt=True;self.assertEqual(self.call('/v1/workset-controls/workset-a')[0],503)
        self.corrupt=False
        self.assertEqual(self.call('/v1/workset-controls/openapi.json')[0],200)
        document=worklist_control_openapi_contract();self.assertIn('post',document['paths']['/v1/workset-controls/{workset_id}/commands'])
        self.assertEqual(self.call('/v1/workset-controls/workset-a?foreign')[0],400)
    def testOwnerProvisionCliAndConfigurationDoNotExposeTokens(self):
        self.ws.revoke_worklist_control(self.bindings['actor-a']['binding_id'])
        token_path=self.root/'actor-a.forge';client=self.root/'cli.client'
        out=io.StringIO()
        with redirect_stdout(out):main(['--root',str(self.root),'worklist-control-bind-issue','--actor','actor-a','--forge-endpoint',self.endpoint,'--forge-instance-id','forge-1','--workset-id','workset-a','--forge-token-file',str(token_path),'--client-token-file',str(client)])
        self.assertNotIn(token_path.read_text(),out.getvalue());self.assertNotIn(client.read_text().strip(),out.getvalue())
        parsed=json.loads(out.getvalue());out=io.StringIO()
        with redirect_stdout(out):main(['--root',str(self.root),'worklist-control-bind-revoke','--binding-id',parsed['binding_id']])
        self.assertIn('REVOKED',out.getvalue())
        peer=self.ws.worklist_controls
        with self.assertRaises(ValueError):peer.provision('bad/id',self.endpoint,'forge-1',['workset-a'],str(token_path),str(client))
        with self.assertRaises(ValueError):peer.provision('actor-a',self.endpoint,'forge-1',['workset-a'],'relative',str(client))
        token_path.write_text('wrong');
        with self.assertRaises(ValueError):peer.provision('actor-a',self.endpoint,'forge-1',['workset-a'],str(token_path),str(client))
        with self.assertRaises(WorklistError):peer._path({'workset_ids':[]},'foreign')
        with self.assertRaises(WorklistError):peer.readback(peer.access(self.client_tokens['actor-b']),'workset-b','../path')

if __name__=='__main__':unittest.main()
