"""Finite own consumer tests. Source-derived unit packets are not installed proof."""
from contextlib import nullcontext
from copy import deepcopy
from datetime import datetime,timezone
import json,os,secrets,tempfile,threading,unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from workspace_control.service import Service,initialize
from workspace_control.http import ThreadingHTTPServer,handler_for
from workspace_control.worklist_peer import WorklistError
from workspace_control import workset_activity_contract as wire

FIXTURES=Path(__file__).resolve().parents[1]/'macos/WorkspaceClient/Tests/WorkspaceClientTests/Fixtures/Activity'
def packet(name):return json.loads((FIXTURES/(name+'.json')).read_text())

class ActivityPeerTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.root.chmod(0o700);initialize(self.root)
        self.service=Service(self.root);self.addCleanup(self.service.close);self.peer=self.service.activities
        meta=packet('capability');self.cap={k:v for k,v in meta.items() if k not in {'consumer_contract','binding_id','actor_id','workspace_project_id','producer_source','producer_version','installation_id'}}
        self.page=packet('page');self.detail=packet('detail');self.calls=[];self.fail=None;self.cap_calls=0
        self.receipt={'permissions':['READ'],'state':'ACTIVE','principal_id':meta['actor_id'],'instance_id':self.cap['scope']['instance_id'],'project_id':self.cap['scope']['project_id'],'repository_id':self.cap['scope']['repository_id'],'installation_id':meta['installation_id'],'worksets':self.cap['worksets'],'expires_at':self.cap['expires_at']}
        self.actor=meta['actor_id'];self.project=meta['workspace_project_id'];self.workset=self.cap['worksets'][0]['workset_id']
        self.receipt_file=self.root/'receipt';self.receipt_file.write_text(json.dumps(self.receipt));self.receipt_file.chmod(0o600)
        self.producer=self.root/'producer';self.producer.write_text(secrets.token_urlsafe(48));self.producer.chmod(0o600)
        self.client=self.root/'client'
        self.mock=patch('workspace_control.workset_activity_peer.request',side_effect=self.response);self.mock.start();self.addCleanup(self.mock.stop)
        self.created=self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.client))
        self.token=self.client.read_text().strip();self.binding=self.peer.access(self.token)
    def response(self,binding,method,path,body=None,**options):
        self.calls.append((method,path,body));self.assertEqual(method,'GET');self.assertIsNone(body)
        if self.fail:raise WorklistError(self.fail)
        if path==wire.BASE:self.cap_calls+=1;return deepcopy(self.cap)
        if '/events/' in path:return deepcopy(self.detail)
        return deepcopy(self.page)
    def testFiniteSeparateNamespaceOriginalCursorAndClosedSource(self):
        with self.peer.gate(self.binding,(self.actor,self.project)) as cap:
            self.assertNotIn('token',self.peer.metadata(self.binding,cap))
            self.assertEqual(self.peer.read(self.binding,self.workset),self.page)
            self.assertEqual(self.peer.read(self.binding,self.workset,cursor='originalOpaque.signed'),self.page)
            identity=self.detail['event']['event_id'];self.assertEqual(self.peer.read(self.binding,self.workset,event=identity),self.detail)
        self.assertTrue(any(path.endswith('/pages/originalOpaque.signed') for _,path,_ in self.calls))
        for peer in [self.service.worklists,self.service.worklist_controls,self.service.workset_releases,self.service.advisory]:
            with self.assertRaises(WorklistError):peer.access(self.token)
        for foreign in [('foreign',self.project),(self.actor,'foreign')]:
            with self.assertRaises(WorklistError):
                with self.peer.gate(self.binding,foreign):pass
        for cursor in ['', '../foreign', 'a'*32769]:
            with self.assertRaises(WorklistError):self.peer.read(self.binding,self.workset,cursor=cursor)
        with self.assertRaises(WorklistError):self.peer.read(self.binding,'foreign')
        with self.assertRaises(WorklistError):self.peer.read(self.binding,self.workset,event='not-an-event')
        self.peer.revoke(self.created['binding_id'])
        with self.assertRaises(WorklistError):self.peer.access(self.token)
        with self.assertRaises(WorklistError):
            with self.peer.gate(self.binding,(self.actor,self.project)):pass
    def testProvisionAndCurrentScopesRejectBeforeOwnBinding(self):
        for field,value in [('permissions',['READ','REORDER']),('state','REVOKED'),('principal_id','foreign')]:
            changed=deepcopy(self.receipt);changed[field]=value;self.receipt_file.write_text(json.dumps(changed))
            with self.assertRaises(WorklistError):self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.root/'other'))
        self.receipt_file.write_text(json.dumps(self.receipt))
        with self.assertRaises(ValueError):self.peer.provision('bad/actor',self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.root/'other'))
        with self.assertRaises(ValueError):self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345','relative',str(self.producer),str(self.root/'other'))
        self.page['current']['installation_id']='foreign'
        with self.assertRaises(WorklistError):self.peer.provision(self.actor,self.project,'http://127.0.0.1:12345',str(self.receipt_file),str(self.producer),str(self.root/'other'))
        self.assertFalse((self.root/'other').exists())
    def testCapabilityCurrentDigestTimeAndSourceChecks(self):
        for field,value in [('supported',False),('expires_at','2001-01-01T00:00:00Z'),('worksets',[])]:
            cap=deepcopy(self.cap);cap[field]=value
            with self.assertRaises(WorklistError):wire.capability(cap,self.binding)
        cap=deepcopy(self.cap);cap['scope']['repository_id']='foreign'
        with self.assertRaises(WorklistError):wire.capability(cap,self.binding)
        self.assertFalse(wire.future('not a date'));self.assertFalse(wire.future(None));self.assertFalse(wire.future('2026-01-01'))
        for field,value in [('workset_id','foreign'),('cursor','../x'),('has_more',True)]:
            page=deepcopy(self.page);page[field]=value
            if field=='has_more':page['events']=[]
            with self.assertRaises(WorklistError):wire.read(page,'page',self.binding,self.workset)
        for field in ['snapshot_revision','membership_revision','installation_id','instance_id']:
            page=deepcopy(self.page);page['current'][field]='sha256:'+'f'*64 if 'revision' in field else 'foreign'
            with self.assertRaises(WorklistError):wire.read(page,'page',self.binding,self.workset)
        page=deepcopy(self.page);page['events'].append(page['events'][0])
        with self.assertRaises(WorklistError):wire.read(page,'page',self.binding,self.workset)
        event=deepcopy(self.detail['event']);event['source_reference']['url']=wire.BASE+'/foreign/events/'+event['event_id']
        with self.assertRaises(WorklistError):wire.event(event,self.workset)
        event=deepcopy(self.detail['event']);event['occurred_at']='not a date'
        with self.assertRaises(WorklistError):wire.event(event,self.workset)
        event['occurred_at']=None;event['time_status']='UNKNOWN';wire.event(event,self.workset)
        with self.assertRaises(WorklistError):wire.read(self.detail,'detail',self.binding,self.workset,'f'*64)
    def testOwnHttpPreAndPostAuthorityAndFailures(self):
        catalogue={'source':'LOCAL','observed_at':datetime.now(timezone.utc).isoformat(),'projects':[{'id':self.project,'name':'Own consumer unit context'}]}
        (self.root/'projects.json').write_text(json.dumps(catalogue));(self.root/'projects.json').chmod(0o600)
        draft=self.service.issue_conversation_grant(self.actor,self.project)
        server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service));thread=threading.Thread(target=server.serve_forever);thread.start()
        self.addCleanup(thread.join);self.addCleanup(server.server_close);self.addCleanup(server.shutdown)
        headers={'Authorization':'Bearer '+self.service.token,'X-Workspace-Instance':self.service.instance_id,'X-Workspace-Draft-Grant':draft,'X-Workspace-Activity-Grant':self.token}
        def get(path='/v1/workset-activity',method='GET',extra=None):
            h={**headers,**(extra or {})}
            try:
                with urlopen(Request('http://127.0.0.1:'+str(server.server_port)+path,headers=h,method=method),timeout=3) as response:return response.status,json.loads(response.read())
            except HTTPError as e:
                with e:return e.code,json.loads(e.read())
        self.assertEqual(get()[0],200);self.assertEqual(get('/v1/workset-activity/'+self.workset+'/pages')[1],self.page)
        self.assertEqual(get('/v1/workset-activity/'+self.workset+'/events/'+self.detail['event']['event_id'])[1],self.detail)
        for path in ['/v1/workset-activity?foreign=1','/v1/workset-activity/../foreign','/v1/workset-activity/foreign/pages?x=1']:
            self.assertIn(get(path)[0],[400,404])
        self.assertEqual(get(extra={'X-Workspace-Activity-Grant':'wrong'})[0],403)
        self.assertEqual(get(extra={'Authorization':'Bearer wrong'})[0],401)
        self.assertEqual(get(method='POST')[0],405)
        for state,expected in [('RESYNC_REQUIRED',409),('UNSUPPORTED',404),('EVENT_UNAVAILABLE',404),('INVALID_REQUEST',400),('ACTIVITY_REQUEST_INVALID',400),('ACTIVITY_SCOPE_DENIED',403),('ACTIVITY_ROUTE_MISSING',404),('DENIED',403),('HISTORY_PARTIAL_CAPACITY',503),('UNAVAILABLE',503)]:
            self.fail=state;self.assertEqual(get()[0],expected)
        self.fail=None
        original=self.response;counter=0
        def lose_after_read(*args,**kwargs):
            nonlocal counter
            result=original(*args,**kwargs)
            counter+=1
            if counter==2:self.fail='DENIED'
            return result
        with patch('workspace_control.workset_activity_peer.request',side_effect=lose_after_read):
            code,value=get('/v1/workset-activity/'+self.workset+'/pages');self.assertEqual(code,403);self.assertNotIn('events',value)
        self.fail=None;self.service.revoke_conversation_grants(self.actor,self.project)
        self.assertEqual(get()[0],403)
