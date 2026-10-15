"""Real own HTTP ingress over SYNTHETIC gateway, never installed EP evidence."""
import http.client
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from workspace_control.service import Service, initialize
from workspace_control.http import ThreadingHTTPServer, handler_for
from workspace_control.project_links import ProjectLinks
from test_project_links import FixtureGateway


class ProjectLinkHTTPTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);os.chmod(self.root,0o700)
        initialize(self.root);self.service=Service(self.root);self.gateway=FixtureGateway()
        self.service.project_links=ProjectLinks(self.service.conversations,self.gateway)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service))
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.service.close();self.temp.cleanup()
    def request(self,path,method='GET',body=None,headers=None):
        values={'Authorization':'Bearer '+self.service.token,'X-Workspace-Instance':self.service.instance_id,
                'X-Workspace-Project-Grant':'synthetic-viewer','X-Workspace-Project-Binding':'epoch-1'}
        if headers is not None:values.update(headers)
        if body is not None:
            if not isinstance(body,str):body=json.dumps(body)
            values.setdefault('Content-Type','application/json')
        connection=http.client.HTTPConnection('127.0.0.1',self.server.server_port,timeout=3)
        connection.request(method,path,body=body,headers=values);response=connection.getresponse()
        status=response.status;data=json.loads(response.read());connection.close();return status,data
    def test_actual_own_http_roundtrip_restartable_reference_no_ep_effect(self):
        self.assertEqual(self.request('/v1/project-links/projects')[0],200)
        status,summary=self.request('/v1/project-links/atlas/inspect');self.assertEqual(status,200)
        fields={'expected_revision':summary['revision'],'authority_id':summary['authority_repository_id'],'operation_id':'same-operation'}
        for _ in range(2):self.assertEqual(self.request('/v1/project-links/atlas/link','POST',fields)[0],200)
        status,opened=self.request('/v1/project-links/atlas/open');self.assertEqual(status,200)
        self.assertEqual(opened['engineering_readiness'],'NOT_ASSESSED')
        self.assertEqual(len(self.service.project_links.store.identities(self.gateway.access)),1)
    def test_own_peer_viewer_and_literal_route_guards(self):
        for path in ['/v1/project-links/atlas/scan','/v1/project-links/../open','/v1/project-links/projects?cursor=x','/v1/project-links/a%2fb/open']:
            self.assertEqual(self.request(path)[0],400)
        self.assertEqual(self.request('/v1/project-links/projects',headers={'Authorization':'Bearer invalid'})[0],401)
        self.assertEqual(self.request('/v1/project-links/projects',headers={'X-Workspace-Instance':'wrong'})[0],409)
        for token in ['', 'wrong-viewer', 'x'*4097]:self.assertEqual(self.request('/v1/project-links/projects',headers={'X-Workspace-Project-Grant':token})[0],403)
        self.assertEqual(self.request('/v1/project-links/outside/inspect')[0],403)
        self.assertEqual(self.request('/v1/project-links/atlas/open')[0],404)
        self.assertEqual(self.request('/v1/project-links/atlas/link')[0],405)
        self.assertEqual(self.request('/v1/project-links/projects','POST',{})[0],405)
        self.assertEqual(self.request('/v1/project-links/projects',body='{}')[0],400)
        self.service.project_links=ProjectLinks(self.service.conversations)
        code,body=self.request('/v1/project-links/projects');self.assertEqual(code,503)
        self.assertEqual(body,{'error':'PROJECT_LINK_PRODUCER_UNBOUND'})
    def test_closed_mutation_snapshot_authority_and_late_scope_checks(self):
        base={'expected_revision':'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','authority_id':'core','operation_id':'op'}
        for value in [{},base|{'extra':True},base|{'operation_id':'bad/path'},'not-json','{"expected_revision":1,"expected_revision":2}',base|{'expected_revision':True}]:
            self.assertIn(self.request('/v1/project-links/atlas/link','POST',value)[0],[400,409])
        self.assertEqual(self.request('/v1/project-links/atlas/link','POST',base,{'Content-Type':'text/plain'})[0],400)
        for body in [base|{'authority_id':'child'},base|{'expected_revision':'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}]:self.assertEqual(self.request('/v1/project-links/atlas/link','POST',body)[0],409)
        self.gateway.deny_after_read=True
        self.assertEqual(self.request('/v1/project-links/atlas/link','POST',base)[0],403)
        self.assertFalse((self.root/'conversations.sqlite3').exists())
        self.gateway.deny_after_read=False;self.gateway.reads=0
        self.gateway.value['peer_id']='wrong';self.assertEqual(self.request('/v1/project-links/atlas/inspect')[0],409)
        self.gateway.value['peer_id']='ep-test';self.gateway.value['revision']=False
        self.assertEqual(self.request('/v1/project-links/atlas/inspect')[0],400)
    def test_declared_own_inventory_no_new_issuer_and_current_access_expiry(self):
        from workspace_control.http import operation_inventory
        operations={x['id']:x for x in operation_inventory(self.service.instance_id)['operations'] if x['id'].startswith('project_link.') and x['exposure']=='HTTP_EXPOSED'}
        self.assertEqual(set(operations),{'project_link.access','project_link.projects','project_link.inspect','project_link.link','project_link.open'})
        self.assertTrue(all(x['auth']=='BEARER_PINNED_AND_EXISTING_ACTOR_PAIRING' for x in operations.values()))
        self.assertNotIn('project_link.issue',operations)
        status,access=self.request('/v1/project-links/access');self.assertEqual(status,200)
        self.assertEqual(access['actor_id'],'actor');self.assertEqual(access['workspace_instance_id'],self.service.instance_id)
        from dataclasses import replace
        self.gateway.access=replace(self.gateway.access,expires_at='2020-01-01T00:00:00Z')
        status,body=self.request('/v1/project-links/access');self.assertEqual(status,403)
        self.assertEqual(body['error'],'PROJECT_LINK_ACCESS_EXPIRED')

    def test_original_request_binding_survives_scope_change_and_publication(self):
        from dataclasses import replace
        from unittest.mock import patch
        original=self.service.project_links.discover
        def swap(token,**kw):
            result=original(token,**kw)
            self.gateway.access=replace(self.gateway.access,epoch='replacement',project_ids=frozenset())
            return result
        with patch.object(self.service.project_links,'discover',side_effect=swap):
            status,body=self.request('/v1/project-links/projects')
        self.assertEqual(status,403);self.assertEqual(set(body),{'error'});self.assertNotIn('Atlas',str(body))
        self.gateway.access=replace(self.gateway.access,epoch='epoch-1',project_ids=frozenset(['atlas']))
        for epoch in ['', 'replacement']:
            status,body=self.request('/v1/project-links/atlas/link','POST',{'expected_revision':'a'*64,'authority_id':'core','operation_id':'old-binding'},headers={'X-Workspace-Project-Binding':epoch})
            self.assertEqual(status,403)
        self.assertFalse((self.root/'conversations.sqlite3').exists())
        link=self.service.project_links.link
        def before_commit(*args,**kw):
            self.gateway.access=replace(self.gateway.access,epoch='replacement')
            return link(*args,**kw)
        with patch.object(self.service.project_links,'link',side_effect=before_commit):
            status,body=self.request('/v1/project-links/atlas/link','POST',{'expected_revision':'a'*64,'authority_id':'core','operation_id':'racing-old-binding'})
        self.assertEqual(status,403);self.assertFalse((self.root/'conversations.sqlite3').exists())

    def test_contract_valid_internal_dots_and_128_byte_identifier_route(self):
        from dataclasses import replace
        for identity in ['atlas..prod','x'*121,'x'*128]:
            self.gateway.access=replace(self.gateway.access,project_ids=frozenset([identity]))
            self.gateway.value['project_id']=identity;self.gateway.value['name']=identity
            code,body=self.request('/v1/project-links/'+identity+'/inspect')
            self.assertEqual(code,200);self.assertEqual(body['project_id'],identity)
        for identity in ['..','.hidden','x'*129,'a/b']:
            self.assertEqual(self.request('/v1/project-links/'+identity+'/inspect')[0],400)

    def test_closed_error_projection_without_private_diagnostics(self):
        from unittest.mock import patch
        import sqlite3
        for error in [OSError('secret-path'),sqlite3.Error('secret-path'),TypeError('secret-path'),RecursionError('secret')]:
            with patch.object(self.service.project_links,'discover',side_effect=error):
                code,body=self.request('/v1/project-links/projects');self.assertIn(code,[400,503]);self.assertNotIn('secret',json.dumps(body))

if __name__=='__main__':unittest.main()
