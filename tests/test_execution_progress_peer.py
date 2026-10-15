"""Actual own pairing/storage/HTTP fences; upstream doubles are source tests only."""
from copy import deepcopy
from datetime import datetime,timedelta,timezone
import hashlib
import json
import os
import threading
import unittest
from unittest.mock import patch
from urllib.request import Request,urlopen
from urllib.error import HTTPError
import test_workset_activity_peer as activity
from test_execution_progress_wire import fixture
from workspace_control import execution_progress_wire as w
from workspace_control.project_links import LinkScope
from workspace_control.http import ThreadingHTTPServer,handler_for

class ExecutionPeerTests(unittest.TestCase):
    response=activity.ActivityPeerTests.response
    def setUp(self):
        activity.ActivityPeerTests.setUp(self)
        self.activity_peer=self.peer;self.activity_binding=self.binding;self.activity_token=self.token
        self.grant=self.service.conversations.issue_grant(self.actor,self.project)
        self.foreign=self.service.conversations.issue_grant('foreign',self.project)
        self.peer=self.service.execution_progress
        self.page['current']['items'][0]['mission_id']='mission';self.resnapshot()
        self.payload,b=fixture()
        now=datetime.now(timezone.utc);expiry=(now+timedelta(hours=1)).isoformat()
        self.progress_receipt={'grant_id':'grant','instance_id':b['instance_id'],'consumer_id':'workspace','workspace_instance_id':self.service.instance_id,'audience':'workspace','selections':[b['selection']],'fields':['history','identity','progress','result'],'issued_at':now.isoformat(),'expires_at':expiry,'status':'ACTIVE'}
        self.receipt_file=self.root/'progress-receipt';self.receipt_file.write_text(json.dumps(self.progress_receipt));self.receipt_file.chmod(0o600)
        self.progress_token=self.root/'progress-token';self.progress_token.write_text('x'*43);self.progress_token.chmod(0o600)
        scope=LinkScope(self.actor,b['instance_id'],frozenset(['alpha']),expiry,'existing-link')
        self.service.project_links.store.record(scope,{'project_id':'alpha','peer_id':b['instance_id'],'authority_repository_id':'alpha','revision':'a'*64},'original-link',authorize=lambda:None)
        self.config={'actor_id':self.actor,'context_id':self.project,'activity_binding_id':self.activity_binding['id'],'workset_id':self.workset,'endpoint':'http://127.0.0.1:12346','producer_source':w.CANDIDATE_SOURCE,'producer_id':'forge','selection':b['selection'],'receipt_file':str(self.receipt_file),'token_file':str(self.progress_token)}
        self.config_file=self.root/'progress-config';self.config_file.write_text(json.dumps(self.config));self.config_file.chmod(0o600)
        self.reads=[];self.progress_failure=None
        self.ep=patch('workspace_control.execution_progress_peer.read',side_effect=self.progress_read);self.ep.start();self.addCleanup(self.ep.stop)
        self.created=self.peer.provision(str(self.config_file));self.binding=self.peer._bindings()[0];self.reads=[]
    def resnapshot(self):
        from workspace_control.worklist_contract import SNAPSHOT_FIELDS
        current=self.page['current'];fields=SNAPSHOT_FIELDS+(('order_revision','order_digest','original_order','effective_order','order_blocking_reasons') if current['contract_version'].endswith('/v2') else ())
        current['snapshot_revision']='sha256:'+hashlib.sha256(json.dumps({k:current[k] for k in fields},sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
    def progress_read(self,binding,mission,run=None,expected=None,guard=None,**kwargs):
        if guard is not None:
            with guard():pass
        self.reads.append((mission,run,expected))
        if self.progress_failure:raise w.ProgressError(self.progress_failure,409 if self.progress_failure=='SNAPSHOT_CONFLICT' else 503)
        value=deepcopy(self.payload)
        if run is not None:value.update(selected_run_id=run,completeness='EXACT_RUN');value['records'][0]['run_id']=run
        return w.validate(value,binding,mission,run,expected)
    def fetch(self,**kw):return self.peer.fetch(self.grant,self.activity_token,self.workset,'mission',**kw)
    def test_exact_pairing_source_and_readonly_publication(self):
        value,pub=self.fetch();self.assertEqual(value['packet'],self.payload);self.assertEqual(value['forge_instance_id'],self.activity_binding['forge_instance_id']);self.assertNotIn('token',value)
        self.assertEqual(self.reads,[('mission',None,None)])
        self.assertEqual(pub.cap(self.binding)['snapshot_id'],'a'*64)
        with pub.dispatch_guard(self.grant,self.workset,self.binding):pass
        self.assertEqual(self.reads[-1],('mission',None,'a'*64))
        self.assertEqual(self.peer._bindings(),[self.binding]);self.assertEqual(len(self.service.project_links.store.identities(LinkScope(self.actor,'ep-instance',frozenset(['alpha']),self.binding['expires_at'],'ref'))),1)
    def test_cross_actor_context_binding_and_mission_fail_before_ep(self):
        for draft,token,workset,mission,binding in [(self.foreign,self.activity_token,self.workset,'mission',None),(self.grant,'wrong',self.workset,'mission',None),(self.grant,self.activity_token,'foreign','mission',None),(self.grant,self.activity_token,self.workset,'foreign',None),(self.grant,self.activity_token,self.workset,'mission','foreign')]:
            with self.assertRaises((w.ProgressError,PermissionError,ValueError)):self.peer.fetch(draft,token,workset,mission,binding_id=binding)
        self.assertEqual(self.reads,[])
    def test_actual_mission_removal_and_local_revoke_fence_publication(self):
        _,pub=self.fetch();before=len(self.reads)
        for row in self.page['current']['items']:row['mission_id']=None
        self.resnapshot()
        with self.assertRaises(w.ProgressError) as c:pub.cap(self.binding)
        self.assertEqual(c.exception.code,'DENIED');self.assertEqual(len(self.reads),before)
        self.peer.revoke(self.binding['id'])
        with self.assertRaises(w.ProgressError):
            with pub.dispatch_guard(self.grant,self.workset,self.binding):pass
        self.assertEqual(self.peer._bindings(),[])
    def test_expiry_own_revoke_and_missing_project_are_not_empty(self):
        self.binding['expires_at']='2001-01-01T01:00:00Z';self.binding['receipt']['issued_at']='2001-01-01T00:00:00Z';self.binding['receipt']['expires_at']=self.binding['expires_at'];self.peer._write_bindings([self.binding])
        with self.assertRaises(w.ProgressError) as c:self.fetch()
        self.assertEqual(c.exception.code,'DENIED')
        self.assertEqual(self.reads,[])
    def test_replay_binding_and_private_source_loss_are_closed(self):
        with self.assertRaises(w.ProgressError):self.peer.provision(str(self.config_file))
        (self.root/'execution-progress-bindings.json').unlink()
        with self.assertRaises(w.ProgressError) as c:self.fetch()
        self.assertEqual(c.exception.code,'SOURCE_CORRUPT');self.assertFalse((self.root/'execution-progress-bindings.json').exists())
    def test_receipt_scope_and_version_do_not_silently_widen(self):
        for key,value in [('producer_source','a'*40),('producer_id','foreign'),('workspace_instance_id','foreign'),('token','short')]:
            b=deepcopy(self.binding);b[key]=value;self.assertFalse(self.peer._valid_record(b),key)
        b=deepcopy(self.binding);b['receipt']['fields'].append('EXECUTE');self.assertFalse(self.peer._valid_record(b))
        b=deepcopy(self.binding);b['selection']['mission_ids'].append('mission');self.assertFalse(self.peer._valid_record(b))
    def test_snapshot_conflict_is_original_and_no_mutation(self):
        _,pub=self.fetch();self.progress_failure='SNAPSHOT_CONFLICT'
        with self.assertRaises(w.ProgressError) as c:pub.cap(self.binding)
        self.assertEqual((c.exception.code,c.exception.status),('SNAPSHOT_CONFLICT',409));self.assertEqual(self.peer._bindings(),[self.binding])
    def test_real_own_http_read_and_closed_scope_methods(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service));thread=threading.Thread(target=server.serve_forever);thread.start()
        def request(suffix,method='GET',extra=None):
            headers={'Authorization':'Bearer '+self.service.token,'X-Workspace-Instance':self.service.instance_id,'X-Workspace-Draft-Grant':self.grant,'X-Workspace-Activity-Grant':self.activity_token};headers.update(extra or {})
            req=Request('http://127.0.0.1:'+str(server.server_port)+'/v1/execution-progress/'+self.workset+suffix,headers=headers,method=method)
            try:
                with urlopen(req,timeout=4) as response:return response.status,json.loads(response.read()),response.headers.get('Cache-Control')
            except HTTPError as e:
                with e:return e.code,json.loads(e.read()),e.headers.get('Cache-Control')
        try:
            code,value,cache=request('/overview?mission_id=mission');self.assertEqual(code,200);self.assertEqual(cache,'no-store');self.assertEqual(value['binding_id'],self.binding['id'])
            self.assertEqual(request('/runs/run?mission_id=mission&expected_snapshot='+'a'*64,extra={'X-Workspace-Execution-Binding':self.binding['id']})[0],200)
            for suffix in ['/overview','/overview?mission_id=mission&mission_id=mission','/overview?mission_id=mission&all=true','/runs/run?mission_id=mission','/wrong?mission_id=mission']:self.assertEqual(request(suffix)[0],400,suffix)
            self.assertEqual(request('/overview?mission_id=mission','POST')[0],405)
            self.assertEqual(request('/overview?mission_id=mission',extra={'X-Workspace-Draft-Grant':self.foreign})[0],403)
            self.progress_failure='SNAPSHOT_CONFLICT';self.assertEqual(request('/overview?mission_id=mission')[0],409)
            self.progress_failure=None
            for code in ['UNAVAILABLE','SOURCE_CORRUPT']:
                with patch.object(self.peer,'fetch',side_effect=w.ProgressError(code,409)):
                    self.assertEqual(request('/overview?mission_id=mission')[:2],(409,{'error':'EXECUTION_PROGRESS_'+code}))
            # Own private storage corruption is never blamed on the request.
            target=self.root/'execution-progress-bindings.json';original=target.read_bytes()
            for raw in [b'{"bindings":',b'\xff',b'[]',b'{"bindings":[]}']:
                target.write_bytes(raw)
                expected='UNBOUND' if raw==b'{"bindings":[]}' else 'SOURCE_CORRUPT'
                self.assertEqual(request('/overview?mission_id=mission')[:2],(503,{'error':'EXECUTION_PROGRESS_'+expected}))
                self.assertEqual(target.read_bytes(),raw)
            target.write_bytes(original);target.chmod(0o644)
            self.assertEqual(request('/overview?mission_id=mission')[:2],(503,{'error':'EXECUTION_PROGRESS_SOURCE_CORRUPT'}))
            target.chmod(0o600);self.assertEqual(request('/overview?mission_id=mission')[0],200)
        finally:server.shutdown();server.server_close();thread.join()
