import unittest
import socket
import threading
from contextlib import contextmanager
from types import SimpleNamespace
from unittest.mock import patch
import test_concept_baseline_intents as original
from workspace_control.concept_baseline_dispatch import install_guarded_send
from workspace_control.worklist_peer import WorklistError

class BaselineDispatchTests(unittest.TestCase):
    setUp=original.ConceptBaselineIntentTests.setUp
    tearDown=original.ConceptBaselineIntentTests.tearDown
    freeze=original.ConceptBaselineIntentTests.freeze
    def paired(self):
        binding=dict(self.binding,endpoint='http://127.0.0.1:8765',forge_token='T'*64,expires_at='2099-01-01T00:00:00+00:00',permissions=['PREPARE','READ'],maximum_records=8)
        self.service.concept_baselines._write_bindings([binding]);return binding

    def test_late_revocation_after_intent_read_prevents_post_bytes(self):
        peer=self.service.concept_baselines;binding=self.paired();intent=self.freeze()
        sent=[]
        def transport(binding,method,path,body=None,**kwargs):
            if method=='GET':
                self.service.conversations.revoke_grants('alice','context')
                raise WorklistError('PROPOSAL_NOT_FOUND')
            with kwargs['send_guard']():sent.append(body)
        with patch('workspace_control.concept_baseline_peer.request',side_effect=transport), patch('workspace_control.concept_baseline_peer.wire.result',return_value={}):
            with self.assertRaises(WorklistError) as denied:peer.fetch(binding,intent,prepare=True,draft=self.token,identity=self.source['id'])
            self.assertEqual(denied.exception.state,'DENIED')
        self.assertEqual(sent,[])
        self.assertEqual(intent,self.journal.get(self.scope,self.source['id'],self.command['operation_id']))

    def test_real_http_replay_after_own_revocation_is_denied_not_unavailable(self):
        import http.server,json
        peer=self.service.concept_baselines;binding=self.paired();calls=[];owner=self.service
        class ProducerDouble(http.server.BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(handler):
                calls.append('GET');owner.conversations.revoke_grants('alice','context')
                body=json.dumps({'contract_version':'forge-project-proposal-http/v1','error':{'code':'PROPOSAL_NOT_FOUND'}}).encode()
                handler.send_response(404);handler.send_header('Content-Type','application/json');handler.send_header('Content-Length',str(len(body)));handler.end_headers();handler.wfile.write(body)
            def do_POST(handler):calls.append('POST');handler.send_error(500)
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),ProducerDouble)
        binding['endpoint']='http://127.0.0.1:'+str(server.server_port);peer._write_bindings([binding]);intent=self.freeze()
        runner=threading.Thread(target=server.serve_forever);runner.start()
        try:
            with self.assertRaises(WorklistError) as denied:peer.fetch(binding,intent,prepare=True,draft=self.token,identity=self.source['id'])
            self.assertEqual(denied.exception.state,'DENIED');self.assertEqual(calls,['GET'])
            self.assertEqual(intent,self.journal.get(self.scope,self.source['id'],self.command['operation_id']))
        finally:server.shutdown();runner.join(2);server.server_close()

    def test_old_pairing_cannot_publish_under_replacement(self):
        peer=self.service.concept_baselines;old=self.paired()
        replacement=dict(old,id='new-binding',dossier_id='another-dossier');peer._write_bindings([replacement])
        with self.assertRaises(WorklistError):peer.snapshot(self.token,self.source['id'],old)
        with self.assertRaises(WorklistError):
            with peer.dispatch_guard(self.token,self.source['id'],old):self.fail('old pairing authorized')

    def test_initialized_pairing_loss_never_recreates_empty_store(self):
        peer=self.service.concept_baselines;self.paired()
        (self.root/'concept-baseline-bindings.json').unlink()
        with self.assertRaises(WorklistError):peer._bindings()
        self.assertTrue((self.root/'concept-baseline-bindings-initialized.json').exists())

class NonblockingDispatchTests(unittest.TestCase):
    def test_request_chunks_recheck_authority_and_response_wait_not_guarded(self):
        left,right=socket.socketpair();connection=SimpleNamespace(sock=left);calls=[];received=[]
        def drain():
            while True:
                part=right.recv(100000)
                if not part:break
                received.append(part)
        reader=threading.Thread(target=drain);reader.start()
        @contextmanager
        def guard():
            calls.append('check')
            if len(calls)>1:raise WorklistError('DENIED')
            yield
        try:
            install_guarded_send(connection,guard,1)
            with self.assertRaises(WorklistError):connection.send(b'x'*70000)
            left.shutdown(socket.SHUT_WR);reader.join(2)
            data=b''.join(received)
            self.assertGreater(len(data),0);self.assertLessEqual(len(data),65536)
            self.assertEqual(data,b'x'*len(data))
            self.assertEqual(calls,['check','check']);self.assertIsNone(left.gettimeout())
        finally:left.close();reader.join(2);right.close()
