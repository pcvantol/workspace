"""Real own/peer HTTP with synthetic producer double, NOT installed Forge proof."""
from copy import deepcopy
import http.server
import json
from pathlib import Path
import socket
import sqlite3
import threading
import unittest
from workspace_control.concept_advisory_mapping import CONTRACT,peer_digest
from workspace_control.http import ThreadingHTTPServer,handler_for
from workspace_control.service import Service
import test_project_concepts as original

class ConceptChatHTTPTests(unittest.TestCase):
    request=original.ProjectConceptTests.request
    fields=original.ProjectConceptTests.fields
    def setUp(self):
        original.ProjectConceptTests.setUp(self)
        _,self.concept=self.request(method='POST',body=self.fields());self.identity=self.concept['id']
        self.prefix='/v1/concept-chats/'+self.identity
        self.peer=self.service.concept_chats;self.turns=[];self.posts=0;self.lose=False;self.denied=False;self.reads=0;self.original_error=404;self.drop_before_record=False;self.post_rejection=None;self.received_posts=0
        self.template=json.loads(Path(__file__).with_name('r53-synthetic-conversation-e581.json').read_text())['conversation'][0]['response']['original_turn']
        self.binding={'id':'binding-one','actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':'synthetic-instance','principal_id':'alice','audience':'synthetic-workspace','dossier_id':'dossier-alice','conversation_id':'conversation-alice','producer_source':'a'*40,'transfer_policy_digest':self.template['request']['transfer_policy_digest'],'endpoint':'http://127.0.0.1:1','forge_token':'T'*64,'expires_at':'2099-01-01T00:00:00+00:00','permissions':['ADVISE','READ'],'maximum_turns':8,'maximum_tokens':384000,'maximum_seconds':960,'provider_id':'concept-fixture','dossier_ids':['dossier-alice'],'conversation_ids':['conversation-alice']}
        owner=self
        class ProducerDouble(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def reply(self,code,value):
                raw=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
            def allowed(self):
                if owner.denied or self.headers.get('Authorization')!='Bearer '+'T'*64 or self.headers.get('X-Forge-Concept-Audience')!='synthetic-workspace':
                    self.reply(403,{'contract_version':CONTRACT,'error':{'code':'CONCEPT_SCOPE_DENIED'}});return False
                return True
            def do_GET(self):
                owner.reads+=1
                if not self.allowed():return
                if self.path.endswith('/capability'):return self.reply(200,owner.cap())
                base=owner.envelope()
                if '/history?' in self.path:return self.reply(200,base|{'turns':owner.turns,'revision':len(owner.turns),'read_only':True})
                op=self.path.split('/intents/')[-1].split('?')[0]
                for turn in owner.turns:
                    if turn['request']['operation_id']==op:return self.reply(200,base|{'original_turn':turn,'read_only':True})
                self.reply(owner.original_error,{'contract_version':CONTRACT,'error':{'code':'CONCEPT_TURN_NOT_FOUND'}})
            def do_POST(self):
                if not self.allowed():return
                r=json.loads(self.rfile.read(int(self.headers['Content-Length'])));owner.received_posts+=1
                if owner.post_rejection is not None:
                    code,error=owner.post_rejection;self.reply(code,{'contract_version':CONTRACT,'error':{'code':error}});return
                if owner.drop_before_record:
                    owner.drop_before_record=False;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
                owner.posts+=1
                turn=owner.make_turn(r);owner.turns.append(turn)
                if owner.lose:
                    owner.lose=False;self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
                self.reply(200,owner.envelope()|{'original_turn':turn,'recorded':True})
        self.producer=http.server.ThreadingHTTPServer(('127.0.0.1',0),ProducerDouble)
        self.pt=threading.Thread(target=self.producer.serve_forever);self.pt.start()
        self.binding['endpoint']='http://127.0.0.1:'+str(self.producer.server_port)
        self.peer._write_bindings([self.binding])
    def tearDown(self):
        self.producer.shutdown();self.producer.server_close();self.pt.join();original.ProjectConceptTests.tearDown(self)
    def envelope(self):return {'contract_version':CONTRACT,**{k:self.binding[k] for k in ('instance_id','principal_id','audience','dossier_id','conversation_id')}}
    def cap(self):
        provider=self.template['provider']
        return {'contract_version':CONTRACT,**{k:self.binding[k] for k in ('instance_id','principal_id','audience','dossier_ids','conversation_ids','permissions','maximum_turns','maximum_tokens','maximum_seconds')},'supported_languages':['en','nl','de','fr','es'],'briefing_fields':['name','purpose','users','non_goals','constraints','open_questions'],'provider':{'provider_id':'concept-fixture','model':'SESSION_CONFIGURED_NOT_REPORTED','profile':None,'policy_digest':provider['policy_digest'],'input_token_bound':40000,'context_token_bound':48000,'output_token_bound':8000,'timeout_seconds':2,'data_transfer':['explicit_briefing','user_message','accepted_prior_turns'],'receiver':'INSTANCE_CONFIGURED_EXTERNAL_SESSION','tools':False,'transfer_policy_digest':self.binding['transfer_policy_digest']},'transfer_authorized':True,'generation_on_read':False,'approval':False,'apply':False,'retention':'PRIVATE_NO_AUTOMATIC_DELETE'}
    def make_turn(self,r):
        t=deepcopy(self.template);t.update(request=r,request_digest=peer_digest(r),revision=r['expected_revision']+1)
        t['context']['evidence_references']=['briefing:'+r['briefing_digest'],'turn:'+r['turn_id']]
        out=t['outcome']['output'];out.update(request_digest=t['request_digest'],briefing_digest=r['briefing_digest'],advisor_kind=r['advisor_kind'],language=r['language'])
        out['changes'][0].update(before=r['briefing']['fields']['users'],references=['briefing:'+r['briefing_digest']])
        t['outcome']['result_digest']=peer_digest(out);return t
    def command(self,**kw):return dict({'operation_id':'b'*32,'turn_id':'c'*32,'expected_concept_revision':1,'role':'BUSINESS','language':'nl','message':'Voor wie is dit?'},**kw)
    def send(self,**kw):return self.request(self.prefix+'/turns','POST',self.command(**kw))
    def test_actual_http_original_recovery_adoption_and_separate_service_reopen(self):
        self.assertEqual(self.request(self.prefix+'/access')[0],200)
        self.assertEqual(self.request(self.prefix+'/briefing')[0],200)
        self.assertEqual(self.posts,0)
        self.lose=True;self.assertEqual(self.send()[0],503);self.assertEqual(self.posts,1)
        code,value=self.send();self.assertEqual(code,200);self.assertEqual(self.posts,1)
        self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32),(200,value))
        with Service(self.root) as reopened:
            self.assertEqual(reopened.concept_chats.read(self.grant,self.identity,'b'*32),value)
        proposal=value['proposal'];self.assertTrue(proposal['adoptable'])
        command={'operation_id':'d'*32,'expected_revision':1,'result_reference':proposal['result_reference'],'displayed_change_digest':proposal['displayed_change_digest']}
        code,accepted=self.request(self.prefix+'/adopt','POST',command);self.assertEqual(code,200)
        self.assertEqual(accepted['concept']['revision'],2);self.assertEqual(accepted['fields']['users'],'Lokale vrijwilligers')
        self.assertEqual(self.request(self.prefix+'/adopt','POST',command),(200,accepted));self.assertEqual(self.posts,1)
        with Service(self.root) as restarted:
            intent=restarted.concept_baselines.intents.freeze(('alice','own-context'),self.identity,{'operation_id':'e'*32,'expected_revision':2,'description':None},{'id':'baseline','actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':'synthetic-instance','principal_id':'alice','audience':'dossier-read','dossier_id':'dossier-alice','producer_source':'a'*40})
            self.assertIn('Lokale vrijwilligers',json.dumps(intent,ensure_ascii=False))
    def test_denial_readonly_expiry_stale_and_frozen_original(self):
        self.assertEqual(self.request(self.prefix+'/access',grant=self.other)[0],404)
        self.denied=True;self.assertEqual(self.send()[0],403);self.assertEqual(self.posts,0);self.denied=False
        self.binding['permissions']=['READ'];self.peer._write_bindings([self.binding]);self.assertFalse(self.request(self.prefix+'/access')[1]['can_advise']);self.assertEqual(self.send()[0],403)
        self.binding['permissions']=['ADVISE','READ'];self.peer._write_bindings([self.binding])
        self.assertEqual(self.send(expected_concept_revision=2)[0],409)
        self.assertEqual(self.send()[0],200)
        self.assertEqual(self.send(message='changed')[0],409)
        self.binding['expires_at']='2020-01-01T00:00:00+00:00';self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.prefix+'/history')[0],403)
        self.assertEqual(self.posts,1)
    def test_unresolved_original_blocks_new_operation_and_no_effect_on_reads(self):
        self.lose=True;self.assertEqual(self.send()[0],503)
        self.turns[0].update(status='UNCERTAIN',outcome=None)
        self.assertEqual(self.send(operation_id='d'*32,turn_id='e'*32)[0],409)
        self.assertEqual(self.request(self.prefix+'/history')[0],200);self.assertEqual(self.posts,1)
        self.service.conversations.revoke_grants('alice','own-context');self.assertEqual(self.request(self.prefix+'/history')[0],403)
    def test_owner_receipt_pairing_and_missing_binding_marker_fail_closed(self):
        self.peer.revoke(self.binding['id'])
        token=self.root/'advice-token';token.write_text('T'*64);token.chmod(0o600)
        receipt={k:self.binding[k] for k in ('instance_id','principal_id','audience','dossier_ids','conversation_ids','permissions','maximum_turns','maximum_tokens','maximum_seconds','provider_id','transfer_policy_digest','expires_at')};receipt.update(state='ACTIVE',grant_id='concept-'+'a'*32)
        path=self.root/'advice-receipt';path.write_text(json.dumps(receipt));path.chmod(0o600)
        result=self.peer.provision('alice','own-context',self.identity,self.binding['endpoint'],'dossier-alice','conversation-alice','a'*40,str(path),str(token));self.assertEqual(result['concept_id'],self.identity)
        with self.assertRaises(ValueError):self.peer.provision('alice','own-context',self.identity,self.binding['endpoint'],'dossier-alice','conversation-alice','a'*40,'relative',str(token))
        (self.root/'concept-chat-bindings.json').unlink();self.assertEqual(self.request(self.prefix+'/access')[0],503)
    def test_owner_cli_returns_safe_receipt_and_actual_revocation(self):
        import io
        from contextlib import redirect_stdout
        from workspace_control.cli import main
        self.peer.revoke(self.binding['id'])
        token=self.root/'cli-advice-token';token.write_text('T'*64);token.chmod(0o600)
        receipt={k:self.binding[k] for k in ('instance_id','principal_id','audience','dossier_ids','conversation_ids','permissions','maximum_turns','maximum_tokens','maximum_seconds','provider_id','transfer_policy_digest','expires_at')};receipt.update(state='ACTIVE',grant_id='concept-'+'a'*32)
        path=self.root/'cli-advice-receipt';path.write_text(json.dumps(receipt));path.chmod(0o600)
        out=io.StringIO()
        with redirect_stdout(out):
            status=main(['--root',str(self.root),'concept-chat-bind-issue','--actor','alice','--context','own-context','--concept-id',self.identity,'--forge-endpoint',self.binding['endpoint'],'--dossier-id','dossier-alice','--conversation-id','conversation-alice','--producer-source','a'*40,'--forge-grant-receipt-file',str(path),'--forge-token-file',str(token)])
        self.assertEqual(status,0);value=json.loads(out.getvalue());self.assertEqual(set(value),{'binding_id','concept_id','producer_source'});self.assertEqual(value['concept_id'],self.identity)
        self.assertEqual(self.request(self.prefix+'/access')[0],200)
        out=io.StringIO()
        with redirect_stdout(out):status=main(['--root',str(self.root),'concept-chat-bind-revoke','--binding-id',value['binding_id']])
        self.assertEqual(status,0);self.assertEqual(json.loads(out.getvalue())['binding_id'],value['binding_id']);self.assertEqual(self.request(self.prefix+'/access')[0],403);self.assertEqual(self.posts,0)
    def test_closed_routes_and_bad_commands(self):
        for action in ('access','briefing','history'):self.assertEqual(self.request(self.prefix+'/'+action,'POST',{})[0],405)
        self.assertEqual(self.request(self.prefix+'/turns')[0],405)
        self.assertEqual(self.request(self.prefix+'/missing')[0],400)
        self.assertEqual(self.request(self.prefix+'/history','PATCH',{})[0],405)
        for body in ({},[],self.command(role='UX'),dict(self.command(),endpoint='http://other')):
            self.assertEqual(self.request(self.prefix+'/turns','POST',body)[0],400)
        self.assertEqual(self.request(self.prefix+'/operations/'+'f'*32)[0],404)

    def test_503_notfound_code_is_not_healthy_absence_and_never_posts(self):
        self.original_error=503
        self.assertEqual(self.send()[0],503);self.assertEqual(self.posts,0)
        self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32)[0],503)
        self.assertEqual(self.posts,0)
    def test_wrong_provider_identity_never_becomes_an_adoptable_result(self):
        self.assertEqual(self.send()[0],200)
        self.turns[0]['provider']['provider_id']='foreign-provider'
        code,value=self.request(self.prefix+'/operations/'+'b'*32)
        self.assertEqual(code,403);self.assertNotIn('turn',value);self.assertNotIn('proposal',value)
    def test_request_lost_before_producer_record_original_discoverable_after_restart(self):
        self.drop_before_record=True
        self.assertEqual(self.send()[0],503);self.assertEqual(self.posts,0)
        with Service(self.root) as restarted:
            history=restarted.concept_chats.history(self.grant,self.identity)
            self.assertEqual(history['history']['turns'],[])
            original=history['local_operations'][0]
            self.assertEqual(original['state'],'PRODUCER_NOT_OBSERVED');self.assertEqual(original['command'],self.command())
            result=restarted.concept_chats.send(self.grant,self.identity,original['command'])
            self.assertEqual(result['operation_id'],'b'*32)
        self.assertEqual(self.posts,1)

    def test_pre_capture_rejection_is_distinct_from_retained_server_original(self):
        code,error=self.send(message='<not accepted by the pinned contract>')
        self.assertEqual(code,400);self.assertEqual(self.posts,0);self.assertEqual(self.received_posts,0)
        code,error=self.request(self.prefix+'/operations/'+'b'*32)
        self.assertEqual((code,error),(404,{'error':'CHAT_NOT_FOUND'}))
        self.assertEqual(self.request(self.prefix+'/history')[1]['local_operations'],[])
        self.assertEqual(self.send(operation_id='d'*32,turn_id='e'*32)[0],200);self.assertEqual(self.posts,1)
    def test_producer_rejection_after_capture_is_never_pre_capture_absence(self):
        for code,error,expected in [(400,'CONCEPT_REQUEST_INVALID',503),(409,'CONVERSATION_STALE',409)]:
            self.post_rejection=(code,error)
            status,_=self.send();self.assertEqual(status,expected)
            status,body=self.request(self.prefix+'/operations/'+'b'*32)
            self.assertEqual((status,body),(404,{'error':'CONCEPT_TURN_NOT_FOUND'}))
            history=self.request(self.prefix+'/history')[1]
            self.assertEqual(history['local_operations'][0]['state'],'PRODUCER_NOT_OBSERVED')
            self.assertEqual(history['local_operations'][0]['command'],self.command())
            self.assertEqual(self.posts,0)
