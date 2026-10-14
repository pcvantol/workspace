"""Consumer contract fixtures. No qualified installed-producer claim."""
import copy
from datetime import datetime, timedelta, timezone
import http.server
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from workspace_control.service import Service,initialize
from workspace_control.project_link_peer import ProjectLinkPeer,SOURCE,ep_get
from workspace_control.project_links import LinkConflict,ProducerUnavailable

class ProjectLinkPeerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);os.chmod(self.root,0o700)
        initialize(self.root);self.s=Service(self.root);self.peer=self.s.project_link_peer
        self.token=self.s.conversations.issue_grant('alice','ideas')
        self.scope={'grant_id':'read1','instance_id':'ep1','consumer_id':'workspace','workspace_instance_id':self.s.instance_id,'audience':'workspace','project_ids':['atlas'],'fields':['project_identity','repository_identity','attachment_availability'],'issued_at':(datetime.now(timezone.utc)-timedelta(seconds=5)).isoformat(),'expires_at':(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat(),'status':'ACTIVE'}
        self.binding={'id':'pair1','actor_id':'alice','context_id':'ideas','endpoint':'http://127.0.0.1:12345','token':'x'*64,'receipt':self.scope,'project_ids':['atlas'],'producer_source':SOURCE}
        common={'contract_version':'1.0','producer':{'id':'engineering-platform','version':'2.3.120'},'instance_id':'ep1','snapshot_id':'a'*64,'topology_revision':'a'*64,'scope':self.scope,'observed_at':datetime.now(timezone.utc).isoformat()}
        self.row={'project_id':'atlas','authority_repository_id':'core'}
        self.page=common|{'projects':[self.row],'next_cursor':None,'completeness':'COMPLETE_PAGE'}
        self.top=common|{'project':self.row,'repositories':[{'repository_id':'core','role':'authority'},{'repository_id':'child','role':'child'}],'attachments':[{'repository_id':'core','agent_id':'agent1','availability':'AVAILABLE'},{'repository_id':'core','agent_id':'agent2','availability':'UNAVAILABLE'}],'attachment_visibility':'GRANTED','completeness':'COMPLETE'}
        self.receipt=self.root/'receipt.json';self.receipt.write_text(json.dumps(self.scope));self.receipt.chmod(0o600)
        self.secret=self.root/'peer-token';self.secret.write_text('x'*64);self.secret.chmod(0o600)
    def tearDown(self):self.s.close();self.temp.cleanup()
    def install(self):self.peer._write_bindings([copy.deepcopy(self.binding)]);return self.peer.scope(self.token)
    def get(self,b,path):return copy.deepcopy(self.top if '/topology?' in path else self.page)
    def test_real_own_flow_exact_sha_unknown_visibility_and_current_scope(self):
        with patch('workspace_control.project_link_peer.ep_get',side_effect=self.get):
            result=self.peer.provision('alice','ideas',self.binding['endpoint'],SOURCE,str(self.receipt),str(self.secret),['atlas'])
            self.assertEqual(result['state'],'ACTIVE')
            scope=self.peer.scope(self.token);self.assertEqual(self.peer.discover(scope),[{'id':'atlas','name':'atlas'}])
            top=self.s.project_links.inspect(self.token,'atlas');self.assertEqual(top['revision'],'a'*64);self.assertEqual(top['repositories'][0]['available_attachments'],1)
            for op in ['original','original','duplicate']:
                self.s.project_links.link(self.token,'atlas','a'*64,op,authority_id='core')
            self.assertEqual(self.s.project_links.open(self.token,'atlas')['state'],'VERIFIED_REFERENCE')
            self.assertEqual(len(self.s.project_links.store.identities(scope)),1)
            with self.assertRaises(LinkConflict):self.peer.provision('alice','ideas',self.binding['endpoint'],SOURCE,str(self.receipt),str(self.secret),['atlas'])
            self.assertEqual(self.peer.revoke(result['binding_id'])['state'],'REVOKED')
            with self.assertRaises(FileNotFoundError):self.peer.revoke(result['binding_id'])
            with self.assertRaises(ProducerUnavailable):self.peer.scope(self.token)
    def test_pairing_requires_current_own_context_and_narrower_qualified_scope(self):
        for actor,ctx in [('bob','ideas'),('alice','other')]:
            with self.assertRaises(PermissionError):self.peer.provision(actor,ctx,self.binding['endpoint'],SOURCE,str(self.receipt),str(self.secret),['atlas'])
        for key,value in [('producer_source','0'*40),('token','bad\n'),('id','bad/path'),('receipt',{}),('project_ids',['outside']),('project_ids',['atlas','atlas'])]:
            b=copy.deepcopy(self.binding);b[key]=value
            with self.assertRaises((ValueError,PermissionError)):self.peer._validate(b)
        for key,value in [('workspace_instance_id','wrong'),('fields',['project_identity']),('audience','other'),('fields',['project_identity','repository_identity','repository_identity']),('project_ids',['atlas','atlas']),('issued_at',self.scope['expires_at'])]:
            b=copy.deepcopy(self.binding);b['receipt'][key]=value
            with self.assertRaises((ValueError,PermissionError)):self.peer._validate(b)
    def test_missing_corrupt_and_duplicate_binding_stores_fail_closed(self):
        self.assertEqual(self.peer._bindings(),[]);self.install()
        p=self.root/'project-link-bindings.json';p.unlink()
        with self.assertRaises(ValueError):self.peer._bindings()
        for payload in [{}, {'bindings':{}},{'bindings':[self.binding,self.binding]}]:
            p.write_text(json.dumps(payload));p.chmod(0o600)
            with self.assertRaises(ValueError):self.peer._bindings()
    def test_scope_revocation_binding_changes_and_commit_publication_fences(self):
        scope=self.install()
        from dataclasses import replace
        with self.assertRaises(PermissionError):self.peer._for_scope(replace(scope,actor_id='bob'))
        with self.assertRaises(PermissionError):self.peer._for_scope(replace(scope,peer_id='other'))
        with self.assertRaises(PermissionError):
            with self.peer.authorization(self.token,replace(scope,epoch='other')):pass
        with self.assertRaises(PermissionError):
            with patch.object(self.peer,'scope',side_effect=[scope,replace(scope,epoch='changed')]):
                with self.peer.authorization(self.token,scope):pass
        self.s.conversations.revoke_grants('alice','ideas')
        with self.assertRaises(PermissionError):self.peer.scope(self.token)
        self.peer.revoke('pair1')
        with self.assertRaises(PermissionError):self.peer._for_scope(scope)
    def test_schema_exact_scope_version_digest_and_time_never_fallback(self):
        self.install()
        for change in [{'extra':True},{'producer':{'id':'engineering-platform','version':'9.9.9'}},{'instance_id':'other'},{'scope':self.scope|{'consumer_id':'other'}},{'snapshot_id':'b'*64},{'observed_at':(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()}]:
            with patch('workspace_control.project_link_peer.ep_get',return_value=self.page|change):
                with self.assertRaises((ValueError,PermissionError)):self.peer.discover(self.peer.scope(self.token))
    def test_pages_opaque_bounds_consistency_and_never_duplicate(self):
        first=self.page|{'projects':[],'next_cursor':'opaque','completeness':'PARTIAL_PAGE'}
        with patch('workspace_control.project_link_peer.ep_get',side_effect=[first,self.page]) as read:
            rows,revision=self.peer._pages(self.binding);self.assertEqual(rows,[self.row]);self.assertIn('cursor=opaque',read.call_args[0][1])
        cases=[[first,self.page|{'topology_revision':'b'*64,'snapshot_id':'b'*64}], [self.page|{'projects':[self.row,self.row]}], [self.page|{'projects':[{'project_id':'other','authority_repository_id':'core'}]}], [self.page|{'completeness':'PARTIAL_PAGE'}], [self.page|{'next_cursor':''}], [first,first]]
        for values in cases:
            with patch('workspace_control.project_link_peer.ep_get',side_effect=values):
                with self.assertRaises((ValueError,LinkConflict)):self.peer._pages(self.binding)
        values=[self.page|{'projects':[],'next_cursor':str(i),'completeness':'PARTIAL_PAGE'} for i in range(5)]
        with patch('workspace_control.project_link_peer.ep_get',side_effect=values):
            with self.assertRaises(ValueError):self.peer._pages(self.binding)
    def test_topology_scope_authority_duplicates_and_visibility(self):
        scope=self.install()
        for change in [{'project':{'project_id':'atlas','authority_repository_id':'other'}},{'topology_revision':'b'*64,'snapshot_id':'b'*64},{'repositories':[{'repository_id':'core','role':'child'}]},{'repositories':[{'repository_id':'core','role':'authority'}]*2},{'attachments':None},{'attachments':[{'repository_id':'outside','agent_id':'agent','availability':'AVAILABLE'}]},{'attachments':self.top['attachments']*2}]:
            with patch('workspace_control.project_link_peer.ep_get',side_effect=[self.page,self.top|change]):
                with self.assertRaises((ValueError,LinkConflict)):self.peer.topology(scope,'atlas')
        with patch('workspace_control.project_link_peer.ep_get',return_value=self.page|{'projects':[]}):
            with self.assertRaises(PermissionError):self.peer.topology(scope,'atlas')
        self.scope['fields'].remove('attachment_availability');self.binding['receipt']=self.scope
        self.peer._write_bindings([self.binding]);self.top['attachment_visibility']='NOT_GRANTED';self.top['attachments']=None
        with patch('workspace_control.project_link_peer.ep_get',side_effect=self.get):
            self.assertIsNone(self.peer.topology(scope,'atlas')['repositories'][0]['available_attachments'])
    def test_actual_http_transport_exact_headers_status_bounds_and_no_redirect(self):
        case={'status':200,'body':self.page,'type':'application/json','cache':'no-store'};captured=[]
        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):
                captured.append(dict(self.headers));raw=case['body'] if isinstance(case['body'],bytes) else json.dumps(case['body']).encode()
                self.send_response(case['status']);self.send_header('Content-Type',case['type']);self.send_header('Cache-Control',case['cache']);self.end_headers();self.wfile.write(raw)
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever);thread.start()
        b=self.binding|{'endpoint':'http://127.0.0.1:'+str(server.server_port)}
        try:
            self.assertEqual(ep_get(b,'/v1/onboarding/projects?limit=25'),self.page)
            self.assertEqual(captured[0]['EP-Consumer-ID'],'workspace');self.assertEqual(captured[0]['Workspace-Instance-ID'],self.s.instance_id)
            for code,error in [(401,PermissionError),(403,PermissionError),(409,LinkConflict),(422,ProducerUnavailable),(302,ConnectionError),(503,ConnectionError)]:
                case['status']=code
                with self.assertRaises(error):ep_get(b,'/v1/onboarding/projects?limit=25')
            case['status']=200
            for key,value in [('body',b'{"a":1,"a":2}'),('body',b'x'*262145),('type','text/html'),('cache','public')]:
                old=case[key];case[key]=value
                with self.assertRaises(ValueError):ep_get(b,'/v1/onboarding/projects?limit=25')
                case[key]=old
        finally:server.shutdown();server.server_close();thread.join()
        with self.assertRaises(ConnectionError):ep_get(b,'/v1/onboarding/projects?limit=25')

if __name__=='__main__':unittest.main()
