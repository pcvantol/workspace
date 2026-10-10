"""Own consumer authorization tests; synthetic peer responses are not installed evidence."""
from contextlib import nullcontext
from copy import deepcopy
from pathlib import Path
import secrets
import tempfile
import unittest
from unittest.mock import patch
from tests.test_workset_release_contract import cap, selected
from workspace_control.service import initialize, Service
from workspace_control.worklist_peer import WorklistError


class ReleasePeerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name); self.root.chmod(0o700); initialize(self.root)
        self.service = Service(self.root); self.addCleanup(self.service.close)
        self.peer = self.service.workset_releases
        self.cap = cap(); self.calls = []
        self.mock = patch('workspace_control.workset_release_peer.request', side_effect=self.request)
        self.mock.start(); self.addCleanup(self.mock.stop)
        producer = self.root / 'producer'; producer.write_text(secrets.token_urlsafe(32)); producer.chmod(0o600)
        client = self.root / 'client'
        self.created = self.peer.provision('actor', 'own-project', 'http://127.0.0.1:12345', str(producer), str(client))
        self.token = client.read_text().strip(); self.binding = self.peer.access(self.token)

    def request(self, binding, method, path, body=None, **options):
        with options.get('gate') or nullcontext():
            self.calls.append((method, path, body))
            if path.endswith('/capability'): return deepcopy(self.cap)
            raise WorklistError('UNAVAILABLE')

    def testSeparateNamespaceExactScopeAndRevocation(self):
        self.assertEqual(self.peer.capability(self.binding), self.cap)
        metadata = self.peer.metadata(self.binding, ('actor', 'own-project'))
        self.assertNotIn('token', str(metadata)); self.assertNotIn(self.token, str(self.created))
        for scope in [('foreign', 'own-project'), ('actor', 'foreign')]:
            with self.assertRaises(WorklistError): self.peer.bound(self.binding, scope)
        for transport in [self.service.worklists, self.service.worklist_controls, self.service.advisory]:
            with self.assertRaises(WorklistError): transport.access(self.token)
        self.peer.revoke(self.created['binding_id'])
        with self.assertRaises(WorklistError): self.peer.capability(self.binding)
        with self.assertRaises(WorklistError): self.peer.access(self.token)

    def testFreshProducerPermissionStopsMutationBeforePost(self):
        self.cap.update(release_supported=False, disarm_supported=False, permissions=['READ'])
        body = {'contract_version': self.cap['contract_version'], 'operation_id': 'one-operation',
                'intent': 'release', 'selection': selected(self.cap), 'package_digest': 'sha256:'+'b'*64,
                'confirm': True, 'expected_revision': None}
        with self.assertRaises(WorklistError): self.peer.submit(self.binding, body, authority=nullcontext())
        self.assertFalse(any(method == 'POST' for method, _, _ in self.calls))
        self.cap['subjects'][0]['subject_revision'] = 'sha256:'+'c'*64
        with self.assertRaises(WorklistError): self.peer.capability(self.binding)

    def testMalformedPrivateBindingFailsClosed(self):
        for mutate in [lambda v: v.update(admin=True), lambda v: v.update(client_digest='invalid'),
                       lambda v: v.update(endpoint='file:///tmp'), lambda v: v.update(subjects=[]),
                       lambda v: v.update(subjects=[{}]), lambda v: v.update(actor_id='../actor')]:
            bad = deepcopy(self.binding); mutate(bad)
            self.assertFalse(self.peer._valid_record(bad))
        with self.assertRaises(ValueError): self.peer.provision('actor','project','http://127.0.0.1:12345','relative','relative')
        with self.assertRaises(WorklistError): self.peer.operation(self.binding, '../foreign')


if __name__ == '__main__': unittest.main()

class ReleaseHTTPTests(ReleasePeerTests):
    def setUp(self):
        super().setUp()
        import json
        from datetime import datetime, timezone
        from threading import Thread
        from workspace_control.http import ThreadingHTTPServer, handler_for
        p=self.root/'projects.json'
        p.write_text(json.dumps({'source':'LOCAL','observed_at':datetime.now(timezone.utc).isoformat(),'projects':[{'id':'own-project','name':'Synthetic release project'}]}));p.chmod(0o600)
        self.draft=self.service.issue_conversation_grant('actor','own-project')
        self.http=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service))
        self.thread=Thread(target=self.http.serve_forever,daemon=True);self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.http.shutdown();self.thread.join(3);self.http.server_close()

    def call(self,path,method='GET',body=None,headers=None):
        import http.client,json
        conn=http.client.HTTPConnection('127.0.0.1',self.http.server_port,timeout=5)
        own={'Authorization':'Bearer '+self.service.token,'X-Workspace-Instance':self.service.instance_id,
             'X-Workspace-Draft-Grant':self.draft,'X-Workspace-Workset-Release-Grant':self.token,
             'Content-Type':'application/json'}
        own.update(headers or {})
        conn.request(method,path,body=None if body is None else json.dumps(body),headers=own)
        result=conn.getresponse();status,value=result.status,json.loads(result.read());conn.close();return status,value

    def testClosedRoutesCannotBorrowReadChatOrHoldGrants(self):
        self.assertEqual(self.call('/v1/workset-releases/access')[0],200)
        self.assertEqual(self.call('/v1/workset-releases/capability')[0],200)
        for header,value,expected in [('X-Workspace-Workset-Release-Grant',secrets.token_urlsafe(32),403),
                                      ('X-Workspace-Draft-Grant',secrets.token_urlsafe(32),403),
                                      ('X-Workspace-Instance','foreign',409),('Authorization','Bearer wrong',401)]:
            self.assertEqual(self.call('/v1/workset-releases/access',headers={header:value})[0],expected)
        for path in ['/v1/workset-releases/start','/v1/workset-releases/operations/../foreign','/v1/workset-releases/capability?foreign']:
            self.assertEqual(self.call(path)[0],400)
        self.assertEqual(self.call('/v1/workset-releases/commands')[0],400)
        self.assertFalse(any(method=='POST' for method,_,_ in self.calls))

    def testDelayedDraftAndBindingRevocationHideProtectedResponse(self):
        from workspace_control import workset_release_http
        original=workset_release_http._read
        def revoked(transport,binding,scope,path):
            value=original(transport,binding,scope,path)
            self.service.revoke_conversation_grants('actor','own-project')
            return value
        with patch.object(workset_release_http,'_read',revoked):
            status,body=self.call('/v1/workset-releases/access')
            self.assertEqual(status,403);self.assertNotIn('subjects',body)
        self.draft=self.service.issue_conversation_grant('actor','own-project')
        def removed(transport,binding,scope,path):
            value=original(transport,binding,scope,path);transport.revoke(binding['id']);return value
        with patch.object(workset_release_http,'_read',removed):
            status,body=self.call('/v1/workset-releases/access')
            self.assertEqual(status,403);self.assertNotIn('subjects',body)

    def testMalformedBodyAndRevocationBeforePostNeverForwardMutation(self):
        self.assertEqual(self.call('/v1/workset-releases/prepare','POST',{}, {'Content-Type':'text/plain'})[0],400)
        self.assertEqual(self.call('/v1/workset-releases/prepare','POST',{'admin':True})[0],400)
        from workspace_control import workset_release_http
        original=workset_release_http._body
        def revoked(handler):
            value=original(handler);self.service.revoke_conversation_grants('actor','own-project');return value
        with patch.object(workset_release_http,'_body',revoked):
            status,body=self.call('/v1/workset-releases/prepare','POST',selected(self.cap))
            self.assertEqual(status,403);self.assertNotIn('package',body)
        self.assertFalse(any(method=='POST' for method,_,_ in self.calls))

    def testCLIUsesSameSeparateScopeAndNeverPrintsCredential(self):
        import io,json
        from contextlib import redirect_stdout,redirect_stderr
        from workspace_control.cli import main
        draft=self.root/'draft.private';draft.write_text(self.draft);draft.chmod(0o600)
        arguments=['--root',str(self.root),'workset-release-capability','--release-token-file',str(self.root/'client'),'--draft-grant-file',str(draft)]
        out=io.StringIO()
        with redirect_stdout(out):self.assertEqual(main(arguments),0)
        value=json.loads(out.getvalue());self.assertEqual(value['principal_id'],'actor')
        self.assertNotIn(self.token,out.getvalue());self.assertNotIn(self.draft,out.getvalue())
        arguments[2]='workset-release-access';out=io.StringIO()
        with redirect_stdout(out):self.assertEqual(main(arguments),0)
        self.assertEqual(json.loads(out.getvalue())['workspace_project_id'],'own-project')
        arguments[2]='workset-release-prepare';body=self.root/'request.private';body.write_text(json.dumps({'admin':True}));body.chmod(0o600)
        with redirect_stdout(io.StringIO()),redirect_stderr(io.StringIO()):
            self.assertEqual(main(arguments+['--request-file',str(body)]),2)
        self.assertFalse(any(method=='POST' for method,_,_ in self.calls))
