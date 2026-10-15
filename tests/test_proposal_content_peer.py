"""Real own HTTP/private SQLite, explicit synthetic R54 transport only."""
from copy import deepcopy
from datetime import datetime,timezone,timedelta
import json
import threading
import http.client
import io
from contextlib import redirect_stdout
from unittest.mock import patch
import unittest
import test_project_concepts as own
import test_proposal_content_wire as fixtures
from workspace_control.concept_baseline_wire import peer_digest
from workspace_control.worklist_peer import WorklistError
from workspace_control.service import Service

class ContentPeerTests(unittest.TestCase):
    tearDown=own.ProjectConceptTests.tearDown
    request=own.ProjectConceptTests.request
    fields=own.ProjectConceptTests.fields
    def setUp(self):
        own.ProjectConceptTests.setUp(self);_,self.concept=self.request(method='POST',body=self.fields());self.identity=self.concept['id'];self.peer=self.service.proposal_content
        f=fixtures.ContentWireTests();f.setUp();self.fixture=f;self.response=f.value;self.response['principal_id']='human-alice';self.posts=[];self.lost=False;self.deny=False;self.missing_status=404;self.stale_once=False
        expires=(datetime.now(timezone.utc)+timedelta(minutes=20)).isoformat()
        self.source={'id':'source-pair','actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':'instance','principal_id':'source-owner','dossier_id':'dossier','audience':'workspace','producer_source':'a'*40,'endpoint':'http://127.0.0.1:8765','forge_token':'S'*64,'expires_at':expires,'permissions':['PREPARE','READ'],'maximum_records':8}
        self.service.concept_baselines._write_bindings([self.source])
        self.binding={k:self.source[k] for k in ('actor_id','context_id','concept_id','instance_id','audience','dossier_id','producer_source','endpoint','expires_at')}
        self.binding.update(f.binding,id='decision-pair',source_binding_id='source-pair',source_principal_id='source-owner',forge_token='T'*64)
        self.peer._write_bindings([self.binding]);self.prefix='/v1/proposal-content/'+self.identity
        self.source_intent={'mapping':{'source':{'revision':1}}}
        self.source_patch=patch.object(self.peer,'_source',side_effect=lambda *args:(self.concept,self.source_intent,self.fixture.subject,self.fixture.points));self.source_patch.start();self.addCleanup(self.source_patch.stop)
        self.baseline_patch=patch.object(self.service.concept_baselines.intents,'get',return_value=self.source_intent);self.baseline_patch.start();self.addCleanup(self.baseline_patch.stop)
        self.mock=patch('workspace_control.proposal_content_peer.request',side_effect=self.transport);self.mock.start();self.addCleanup(self.mock.stop)
    def transport(self,binding,method,path,body=None,**kwargs):
        self.assertEqual(kwargs['content_audience'],'workspace')
        if self.deny:raise WorklistError('DENIED')
        if kwargs.get('send_guard'):
            with kwargs['send_guard']():pass
        if path.endswith('/capability'):
            return deepcopy(self.fixture.cap)
        if method=='POST':
            self.assertEqual(self.peer.intents.get(('alice','own-context'),self.identity,body['operation_id'])['request'],body)
            if self.stale_once:self.stale_once=False;raise WorklistError('CONTENT_DECISION_STALE',http_status=409)
            if body['expected_decision_revision']!=len(self.response['history']):raise WorklistError('CONTENT_DECISION_STALE',http_status=409)
            record={'decision_id':'decision-'+str(len(self.posts)),'request':deepcopy(body),'request_digest':peer_digest(body),'principal_id':'human-alice','audience':'workspace','human_binding':self.binding['human_binding'],'grant_id':'grant','occurred_at':datetime.now(timezone.utc).isoformat(),'revision':len(self.posts)+1,'integrity':'f'*64}
            self.posts.append(deepcopy(body));self.response['history'].append(record);self.response['decision_revision']=len(self.posts)
            latest={r['request']['role']:r['request']['decision'] for r in self.response['history']}
            self.response['state']='CHANGES_REQUESTED' if 'REQUEST_CHANGES' in latest.values() else 'CONTENT_APPROVED' if all(latest.get(role)=='APPROVE_CONTENT' for role in self.fixture.value['required_roles']) else 'DECISION_NEEDED'
            result=deepcopy(self.response);result['original_decision']=record
            if self.lost:self.lost=False;raise WorklistError('UNAVAILABLE')
            return result
        result=deepcopy(self.response)
        if '/intents/' in path:
            operation=path.split('/intents/')[1].split('?')[0];match=[r for r in result['history'] if r['request']['operation_id']==operation]
            if not match:raise WorklistError('CONTENT_NOT_FOUND',http_status=self.missing_status)
            result['original_decision']=match[0]
        return result
    def selection(self):
        status,value=self.request(self.prefix+'/proposals/'+'c'*32);self.assertEqual(status,200,value);return value
    def command(self,role='BUSINESS',decision='APPROVE_CONTENT',operation='b'*32):
        snapshot=self.selection();return {'operation_id':operation,'source_operation_id':'c'*32,'expected_concept_revision':1,'selection_digest':snapshot['selection_digest'],'role':role,'decision':decision,'reason':'Synthetic role decision, not Peter approval','acknowledged_open_points':self.fixture.points}
    def test_separate_roles_actual_own_http_and_original_effect_once(self):
        first=self.command();code,value=self.request(self.prefix+'/decisions','POST',first);self.assertEqual(code,200,value);self.assertEqual(value['decision']['state'],'DECISION_NEEDED')
        self.assertEqual(self.request(self.prefix+'/decisions','POST',first)[0],200);self.assertEqual(len(self.posts),1)
        second=self.command('ARCHITECTURE',operation='d'*32);code,value=self.request(self.prefix+'/decisions','POST',second);self.assertEqual(code,200,value);self.assertEqual(value['decision']['state'],'CONTENT_APPROVED');self.assertFalse(value['decision']['effects_authorized'])
        self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32)[0],200);self.assertEqual(len(self.posts),2)
    def test_committed_lost_response_reopen_original_without_second_post(self):
        command=self.command();self.lost=True
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],503);self.assertEqual(len(self.posts),1)
        with Service(self.root) as restarted:
            intent=restarted.proposal_content.intents.get(('alice','own-context'),self.identity,'b'*32)
            self.assertEqual(intent['request'],self.posts[0])
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],200);self.assertEqual(len(self.posts),1)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',dict(command,reason='Changed'))[0],409)
    def test_stale_and_role_reject_without_own_or_peer_effect(self):
        old=self.command();self.assertEqual(self.request(self.prefix+'/decisions','POST',dict(old,selection_digest='f'*64))[0],409)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',dict(old,role='OWNER'))[0],403)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',dict(old,extra=True))[0],400)
        self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32,grant=self.other)[0],404)
        self.assertEqual(self.posts,[])
        self.service.project_concepts.save(('alice','own-context'),self.fields(operation_id='e'*32,expected_revision=1),identity=self.identity)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',old)[0],409)
    def test_denied_expired_source_rebind_and_missing_initialized_pairing(self):
        self.deny=True;self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32)[0],403);self.deny=False
        self.binding['expires_at']='2000-01-01T00:00:00+00:00';self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32)[0],403)
        self.binding['expires_at']=self.source['expires_at'];self.peer._write_bindings([self.binding]);self.source['instance_id']='other';self.service.concept_baselines._write_bindings([self.source]);self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32)[0],403)
        self.source['instance_id']='instance';self.service.concept_baselines._write_bindings([self.source]);self.selection()
        (self.root/'proposal-content-bindings.json').unlink();self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32)[0],503)
    def test_owner_explicit_human_pairing_and_wrong_source_receipt(self):
        self.peer.revoke('decision-pair');receipt={k:self.binding[k] for k in ('grant_id','principal_id','instance_id','audience','permissions','roles','human_binding','expires_at')};receipt.update(proposal_principal_id='source-owner',dossier_ids=['dossier'],profile_id='CONTENT_BASELINE_ONLY/1.0',state='ACTIVE')
        path=self.root/'receipt';token=self.root/'content-token';token.write_text('T'*64);token.chmod(0o600)
        def save():path.write_text(json.dumps(receipt));path.chmod(0o600)
        save()
        with self.assertRaises(ValueError):self.peer.provision('alice','own-context',self.identity,'wrong-human',str(path),str(token))
        receipt['proposal_principal_id']='other';save()
        with self.assertRaises(PermissionError):self.peer.provision('alice','own-context',self.identity,'human-alice',str(path),str(token))
        receipt['proposal_principal_id']='source-owner';save();value=self.peer.provision('alice','own-context',self.identity,'human-alice',str(path),str(token));self.assertEqual(value['concept_id'],self.identity)
        self.selection()
    def test_closed_methods_and_no_unsupported_conversion(self):
        for path in [self.prefix+'?all=true',self.prefix+'/proposals/bad',self.prefix+'/operations/'+'z'*32]:self.assertEqual(self.request(path)[0],400)
        self.assertEqual(self.request(self.prefix+'/decisions')[0],405)
        self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32,'POST',{})[0],405)
        self.assertEqual(self.request(self.prefix+'/decisions','PATCH',{})[0],405)
        self.assertEqual(self.request(self.prefix+'/operations/'+'f'*32),(404,{'error':'CONTENT_OWN_INTENT_NOT_FOUND'}))

    def test_notfound503_never_authorizes_post_or_terminal_disposition(self):
        command=self.command();self.missing_status=503
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],503)
        self.assertEqual(self.posts,[]);self.assertEqual(self.peer.intents.rejections(('alice','own-context'),self.identity),set())
        self.assertEqual(len(self.selection()['pending_operations']),1)
        self.missing_status=404
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],200);self.assertEqual(len(self.posts),1)
    def test_definitive_stale409_retains_original_and_allows_fresh_explicit_decision(self):
        command=self.command();self.stale_once=True
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],409)
        original=self.peer.intents.get(('alice','own-context'),self.identity,'b'*32)
        snapshot=self.selection();self.assertEqual(snapshot['pending_operations'],[]);self.assertEqual(snapshot['rejected_operations'],['b'*32])
        with Service(self.root) as restarted:self.assertEqual(restarted.proposal_content.intents.get(('alice','own-context'),self.identity,'b'*32),original)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],409);self.assertEqual(self.posts,[])
        fresh=self.command(operation='e'*32)
        self.assertEqual(self.request(self.prefix+'/decisions','POST',fresh)[0],200);self.assertEqual(len(self.posts),1);self.assertEqual(self.posts[0]['operation_id'],'e'*32)
    def test_original_source_revocation_cannot_complete_inside_send_fence(self):
        started=threading.Event();completed=threading.Event()
        def revoke():
            started.set();self.service.concept_baselines.revoke('source-pair');completed.set()
        with self.peer.dispatch_guard(self.grant,self.identity,self.binding):
            thread=threading.Thread(target=revoke);thread.start();self.assertTrue(started.wait(1));self.assertFalse(completed.wait(.05))
        self.assertTrue(completed.wait(1));thread.join()
        with self.assertRaises(WorklistError):
            with self.peer.dispatch_guard(self.grant,self.identity,self.binding):self.fail('protected bytes after completed source revocation')
        with self.assertRaises(WorklistError):
            with self.peer.decision_guard(self.grant,self.identity,self.binding,1):self.fail('POST after completed source revocation')
        self.assertEqual(self.posts,[])

    def test_late_own_grant_revocation_is_denied_in_both_dispatch_fences(self):
        self.service.conversations.revoke_grants('alice','own-context')
        for guard in [lambda:self.peer.dispatch_guard(self.grant,self.identity,self.binding),lambda:self.peer.decision_guard(self.grant,self.identity,self.binding,1)]:
            with self.assertRaises(WorklistError) as raised:
                with guard():self.fail('send after own revocation')
            self.assertEqual(raised.exception.state,'DENIED')
        self.assertEqual(self.posts,[])

    def test_own_stale_before_any_transport_is_terminal_but_admitted_uncertainty_is_not(self):
        original_freeze=self.peer.intents.freeze
        captured=[]
        def freeze_then_edit(*args):
            intent=original_freeze(*args);captured.append(intent)
            self.service.project_concepts.save(('alice','own-context'),self.fields(operation_id='e'*32,expected_revision=1),identity=self.identity)
            return intent
        command=self.command()
        with patch.object(self.peer.intents,'freeze',side_effect=freeze_then_edit):
            self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],409)
        self.assertEqual(self.posts,[]);self.assertEqual(self.peer.intents.get(('alice','own-context'),self.identity,'b'*32),captured[0])
        self.assertEqual(self.selection()['rejected_operations'],['b'*32]);self.assertEqual(self.selection()['pending_operations'],[])
        fresh=self.command(operation='f'*32);fresh['expected_concept_revision']=2
        self.assertEqual(self.request(self.prefix+'/decisions','POST',fresh)[0],200);self.assertEqual(len(self.posts),1)

    def test_actual_peer_connect_then_own_revoke_returns_denied_before_send(self):
        from workspace_control.advisory_http import request as actual_request
        self.binding['endpoint']='http://127.0.0.1:'+str(self.server.server_port);self.source['endpoint']=self.binding['endpoint'];self.peer._write_bindings([self.binding]);self.service.concept_baselines._write_bindings([self.source])
        original_connect=http.client.HTTPConnection.connect
        def connected_then_revoke(connection):
            original_connect(connection);self.service.conversations.revoke_grants('alice','own-context')
        with patch('http.client.HTTPConnection.connect',connected_then_revoke):
            with self.assertRaises(WorklistError) as raised:actual_request(self.binding,'GET','/v1/project-proposal-decisions/capability',content_audience='workspace',send_guard=lambda:self.peer.dispatch_guard(self.grant,self.identity,self.binding))
        self.assertEqual(raised.exception.state,'DENIED');self.assertEqual(self.posts,[])

    def test_real_owner_CLI_parser_issue_and_revoke_keep_human_mapping_explicit(self):
        from workspace_control.cli import main
        self.peer.revoke('decision-pair')
        receipt={k:self.binding[k] for k in ('grant_id','principal_id','instance_id','audience','permissions','roles','human_binding','expires_at')};receipt.update(proposal_principal_id='source-owner',dossier_ids=['dossier'],profile_id='CONTENT_BASELINE_ONLY/1.0',state='ACTIVE')
        path=self.root/'cli-receipt';path.write_text(json.dumps(receipt));path.chmod(0o600);token=self.root/'cli-token';token.write_text('T'*64);token.chmod(0o600)
        output=io.StringIO()
        with redirect_stdout(output):
            status=main(['--root',str(self.root),'proposal-content-bind-issue','--actor','alice','--context','own-context','--concept-id',self.identity,'--human-principal-id','human-alice','--forge-grant-receipt-file',str(path),'--forge-token-file',str(token)])
        self.assertEqual(status,0);binding=json.loads(output.getvalue());self.assertEqual(binding['concept_id'],self.identity)
        with redirect_stdout(io.StringIO()):self.assertEqual(main(['--root',str(self.root),'proposal-content-bind-revoke','--binding-id',binding['binding_id']]),0)
        self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32)[0],403)

    def test_missing_original_source_is_not_an_absent_own_decision_intent(self):
        command=self.command();self.assertEqual(self.request(self.prefix+'/decisions','POST',command)[0],200)
        with patch.object(self.peer,'_source',side_effect=FileNotFoundError('original source unavailable')):
            self.assertEqual(self.request(self.prefix+'/operations/'+command['operation_id']),(404,{'error':'CONTENT_OWN_NOT_FOUND'}))
        self.assertEqual(self.peer.intents.get(('alice','own-context'),self.identity,command['operation_id'])['command'],command)
        self.assertEqual(len(self.posts),1)

    def test_profile_conflict_status_is_genuine_not_inferred_from_unavailable_code(self):
        for upstream,expected in [(409,409),(503,503)]:
            with patch.object(self.peer,'read_proposal',side_effect=WorklistError('CONTENT_PROFILE_UNSUPPORTED',http_status=upstream)):
                self.assertEqual(self.request(self.prefix+'/proposals/'+'c'*32),(expected,{'error':'CONTENT_PROFILE_UNSUPPORTED'}))
