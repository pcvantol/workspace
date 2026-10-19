"""Real own/loopback HTTP and SQLite, explicit producer double, not installed PASS."""
from copy import deepcopy
from datetime import datetime,timezone,timedelta
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import hashlib,json,socket,threading,unittest
from pathlib import Path
from unittest.mock import patch
import test_project_concepts as own
from workspace_control import genesis_wire as wire
from workspace_control.genesis_binding import PRODUCER_SOURCE
from workspace_control.service import Service
from workspace_control.concept_baseline_mapping import digest

class GenesisHTTPTests(unittest.TestCase):
    request=own.ProjectConceptTests.request
    fields=own.ProjectConceptTests.fields
    def setUp(self):
        own.ProjectConceptTests.setUp(self)
        _,self.concept=self.request(method='POST',body=self.fields());self.identity=self.concept['id'];self.peer=self.service.genesis;self.path='/v1/concept-genesis/'+self.identity;self.sourceop='c'*32
        self.original=json.loads((Path(__file__).parent/'fixtures/genesis/original-plan.json').read_text());self.subject=self.original['source_subject'];self.source={'result':{'result_digest':self.original['documents']['bundle_digest'],'artifacts':[{k:f[k] for k in ('path','mode','sha256','content')} for f in self.original['documents']['files']]}}
        self.content={'subject':self.subject,'decision_revision':0,'history':[],'state':'DECISION_NEEDED'};self.calls=[];self.plans={};self.decisions={};self.drop=False;self.drop_before=False;self.corrupt=False;self.denied=False;self.eligible=True;self.peer503=False
        test=self
        class Producer(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):self.respond()
            def do_POST(self):self.respond()
            def respond(self):
                body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0')))) if self.command=='POST' else None
                test.calls.append((self.command,self.path,body,dict(self.headers)))
                if test.drop_before and self.command=='POST':self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
                status,value=test.transport(self.command,self.path,body,self.headers)
                if test.drop and self.command=='POST':test.drop=False;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
                raw=json.dumps(value,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
        self.forge=ThreadingHTTPServer(('127.0.0.1',0),Producer);self.forge_thread=threading.Thread(target=self.forge.serve_forever);self.forge_thread.start()
        endpoint='http://127.0.0.1:'+str(self.forge.server_port);expiry=(datetime.now(timezone.utc)+timedelta(minutes=60)).isoformat();p=self.original
        self.sourcebinding={'id':'original-source','actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':p['instance_id'],'principal_id':self.subject['proposal_principal_id'],'dossier_id':p['dossier_id'],'audience':p['audience'],'producer_source':PRODUCER_SOURCE,'endpoint':endpoint,'forge_token':'S'*64,'expires_at':expiry,'permissions':['PREPARE','READ'],'maximum_records':8};self.service.concept_baselines._write_bindings([self.sourcebinding])
        self.binding={k:self.sourcebinding[k] for k in ('actor_id','context_id','concept_id','instance_id','dossier_id','audience','producer_source','endpoint','expires_at')}
        self.binding.update(id='genesis-plan-binding',source_binding_id='original-source',source_principal_id=self.sourcebinding['principal_id'],principal_id=p['principal_id'],grant_id='genesis-plan-grant',human_binding={'operator_id':'human','operator_binding_version':1,'installation_id':'installation'},forge_token='P'*64,permissions=['PREPARE','READ'],source_plan_ids=[self.subject['plan_id']],exact_plans=[],kind='PLAN',targets=[{'id':'local','label':'Nieuw lokaal project','target':{k:p['target'][k] for k in ('ep_instance_id','placement_ref','target_ref')},'expires_at':expiry,'blocking_open_points':[]}])
        self.peer._write_bindings([self.binding]);self.install_source()
    def install_source(self):
        self.source_patch=patch.object(self.peer,'_source',side_effect=lambda *args:(self.concept,{'mapping':{'source':{'revision':1,'title':'Saved idea'}}},deepcopy(self.source),deepcopy(self.subject)));self.source_patch.start();self.addCleanup(self.source_patch.stop)
        self.content_patch=patch.object(self.peer.content,'read_proposal',side_effect=lambda *args:{'decision':deepcopy(self.content)});self.content_patch.start();self.addCleanup(self.content_patch.stop)
    def tearDown(self):
        self.forge.shutdown();self.forge.server_close();self.forge_thread.join();own.ProjectConceptTests.tearDown(self)
    def transport(self,method,path,body,headers):
        def error(status,code):return status,{'contract_version':wire.CONTRACT,'error':{'code':code}}
        if self.denied:return error(403,'GENESIS_SCOPE_DENIED')
        if self.peer503:return error(503,'GENESIS_STORAGE_UNAVAILABLE')
        self.assertEqual(headers['X-Forge-Bootstrap-Audience'],self.binding['audience']);self.assertNotIn('X-Forge-Content-Audience',headers)
        b=self.decider if headers['Authorization']=='Bearer '+'D'*64 else self.binding
        if path.endswith('/capability'):return 200,{'contract_version':wire.CONTRACT,**{k:b[k] for k in ('instance_id','principal_id','audience','source_plan_ids','permissions')},'dossier_ids':[b['dossier_id']],'profile_id':wire.PROFILE,'purpose':wire.PURPOSE,'target_write':False,'ep_admission':False,'execution_authorized':False}
        if method=='POST' and path.endswith('/plans'):
            self.assertEqual(self.peer.intents.get(('alice','own-context'),self.identity,body['operation_id'])['request'],body)
            p=deepcopy(self.original);p.update(plan_id='bootstrap-plan-'+body['operation_id'],plan_revision=body['expected_plan_revision']+1,previous_plan_id=body['previous_plan_id'],operation_id=body['operation_id'],request_digest=wire.peer_digest(body),expires_at=body['expires_at'],content_revision=body['expected_content_revision'],blocking_open_points=body['blocking_open_points']);p['target'].update(body['target']);p['plan_digest']=wire.peer_digest({k:v for k,v in p.items() if k!='plan_digest'});self.plans[body['operation_id']]=p
            return 200,self.view(b,p)
        if method=='POST' and path.endswith('/decisions'):
            self.assertEqual(self.peer.intents.get(('alice','own-context'),self.identity,body['operation_id'])['request'],body)
            p=next(v for v in self.plans.values() if v['plan_id']==body['plan_id']);history=self.history(p);d={'decision_id':'bootstrap-decision-'+body['operation_id'],'decision_revision':len(history)+1,'principal_id':b['principal_id'],'audience':b['audience'],'grant_id':b['grant_id'],'human_binding':b['human_binding'],'occurred_at':datetime.now(timezone.utc).isoformat(),**body,'request_digest':wire.peer_digest(body)};d['decision_digest']=wire.peer_digest(d);self.decisions[body['operation_id']]=d;return 200,self.view(b,p,d)
        leaf=path.split('/')[-2];ref=path.split('/')[-1].split('?')[0]
        if leaf in ('decision-intents','decisions'):
            d=self.decisions.get(ref) if leaf=='decision-intents' else next((d for d in self.decisions.values() if d['decision_id']==ref),None)
            if d is None:return error(404,'GENESIS_NOT_FOUND')
            return 200,self.view(b,next(p for p in self.plans.values() if p['plan_id']==d['plan_id']),d)
        p=self.plans.get(ref) if leaf=='intents' else next((p for p in self.plans.values() if p['plan_id']==ref),None)
        return (200,self.view(b,p)) if p else error(404,'GENESIS_NOT_FOUND')
    def history(self,p):return [d for d in self.decisions.values() if d['plan_id']==p['plan_id']]
    def view(self,b,p,original=None):
        history=self.history(p);reasons=[] if self.eligible else ['CURRENT_CONTENT_AUTHORITY_REQUIRED']
        return {'summary':'Synthetic loopback plan, no execution','contract_version':wire.CONTRACT,**{k:b[k] for k in ('instance_id','principal_id','audience','dossier_id')},'plan':deepcopy(p),'effect_decision_revision':len(history),'effect_history':deepcopy(history),'original_decision':deepcopy(original),'effect_decision_eligible':not reasons,'inapplicability_reasons':reasons,'effect_decision_currently_applicable':bool(history) and history[-1]['decision']=='APPROVE_EFFECT' and not reasons,'state':'EP_ADMISSION_REQUIRED','execution_authorized':self.corrupt,'target_write':'NOT_PERFORMED','ep_credential':'NOT_ISSUED'}
    def access(self):
        status,value=self.request(self.path+'/access/'+self.sourceop);self.assertEqual(status,200,value);return value
    def command(self,op='b'*32):
        access=self.access();return {'operation_id':op,'source_operation_id':self.sourceop,'expected_concept_revision':1,'selection_digest':access['selection_digest'],'target_id':'local'}
    def prepare(self,op='b'*32):
        command=self.command(op);status,value=self.request(self.path+'/plans','POST',command);self.assertEqual(status,200,value);return value
    def add_decider(self,value):
        p=value['result']['plan'];self.decider=deepcopy(self.binding);self.decider.update(id='finite-effect',kind='DECISION',principal_id='human',grant_id='effect-grant',forge_token='D'*64,permissions=['DECIDE_EFFECT','READ'],exact_plans=[{'plan_id':p['plan_id'],'plan_digest':p['plan_digest']}],targets=[]);self.peer._write_bindings([self.binding,self.decider])
    def decision_command(self,op='d'*32):
        status,value=self.request(self.path+'/decision-access/'+'b'*32);self.assertEqual(status,200,value)
        return {'operation_id':op,'source_operation_id':self.sourceop,'expected_concept_revision':1,'selection_digest':value['selection_digest'],'plan_operation_id':'b'*32,'decision':'APPROVE_EFFECT','reason':'Synthetic explicit effect decision, not Peter approval'}
    def posts(self):return [c for c in self.calls if c[0]=='POST']
    def test_real_own_HTTP_original_plan_reopen_no_execution(self):
        result=self.prepare();self.assertFalse(result['result']['execution_authorized']);self.assertEqual(len(self.posts()),1)
        self.assertEqual(self.request(self.path+'/operations/'+'b'*32)[1]['result']['plan'],result['result']['plan']);self.assertEqual(len(self.posts()),1)
        self.assertEqual(len(self.peer.intents.list(('alice','own-context'),self.identity)),1)
    def test_lost_committed_plan_reply_recovers_same_without_second_POST(self):
        command=self.command();self.drop=True;self.assertEqual(self.request(self.path+'/plans','POST',command)[0],503);self.assertEqual(len(self.plans),1)
        status,value=self.request(self.path+'/plans','POST',command);self.assertEqual(status,200,value);self.assertEqual(len(self.posts()),1)
    def test_uncertain_precommit_loss_never_automatically_rePOSTs(self):
        command=self.command();self.drop_before=True;self.assertEqual(self.request(self.path+'/plans','POST',command)[0],503);self.drop_before=False
        self.assertEqual(self.request(self.path+'/plans','POST',command)[0],409);self.assertEqual(len(self.posts()),1);self.assertEqual(self.plans,{})
    def test_separate_finite_effect_decision_and_lost_reply_restore(self):
        original=self.prepare();self.add_decider(original);command=self.decision_command();self.drop=True;self.assertEqual(self.request(self.path+'/decisions','POST',command)[0],503)
        code,value=self.request(self.path+'/decisions','POST',command);self.assertEqual(code,200,value);self.assertEqual(len(self.decisions),1);self.assertEqual(len(self.posts()),2);self.assertEqual(value['result']['plan'],original['result']['plan']);self.assertFalse(value['result']['execution_authorized'])
    def test_missing_effect_rights_not_content_or_plan_authority(self):
        self.prepare();command=self.decision_command();self.assertEqual(self.request(self.path+'/decisions','POST',command)[0],403);self.assertEqual(len(self.posts()),1)
    def test_missing_content_authority_blocks_positive_not_history(self):
        result=self.prepare();self.add_decider(result);self.eligible=False;command=self.decision_command();self.assertEqual(self.request(self.path+'/decisions','POST',command)[0],409);self.assertEqual(len(self.posts()),1)
    def test_changed_selection_or_target_or_concept_cannot_reuse_positive(self):
        command=self.command();self.assertEqual(self.request(self.path+'/plans','POST',command|{'target_id':'foreign'})[0],409)
        self.binding['targets'][0]['target']['target_ref']='changed';self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.path+'/plans','POST',command)[0],409);self.assertEqual(self.posts(),[])
    def test_foreign_actor_revocation_and_expiry_deny_without_POST(self):
        command=self.command();self.assertEqual(self.request(self.path+'/plans','POST',command,grant=self.other)[0],404)
        self.denied=True;self.assertEqual(self.request(self.path+'/plans','POST',command)[0],403);self.assertEqual(self.posts(),[])
        self.denied=False;self.binding['expires_at']='2000-01-01T00:00:00+00:00';self.binding['targets'][0]['expires_at']=self.binding['expires_at'];self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.path+'/plans','POST',command)[0],403)
    def test_true_non_authority_response_detector_red_green(self):
        original=self.prepare();self.corrupt=True;self.assertEqual(self.request(self.path+'/operations/'+'b'*32)[0],503);self.corrupt=False;status,value=self.request(self.path+'/operations/'+'b'*32);self.assertEqual(status,200,value);self.assertEqual(value['result']['plan'],original['result']['plan'])
    def test_peer503_not_healthy_empty_and_no_apply_route(self):
        self.peer503=True;self.assertEqual(self.request(self.path+'/access/'+self.sourceop)[0],503);self.assertEqual(self.request(self.path+'/apply','POST',{})[0],400);self.assertEqual(self.posts(),[])

if __name__=='__main__':unittest.main()
