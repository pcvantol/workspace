"""Actual loopback HTTP framing/header/error tests; no owning Forge qualification."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
import threading
import unittest
from workspace_control.advisory_http import request
from workspace_control.proposal_content_wire import error
from workspace_control.worklist_peer import WorklistError

class ContentHTTPTransportTests(unittest.TestCase):
    def setUp(self):
        self.seen=[];self.status=200;self.raw=b'{"value":true}';self.kind='application/json';test=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args):pass
            def do_GET(self):self.do_POST()
            def do_POST(self):
                body=self.rfile.read(int(self.headers.get('Content-Length','0')));test.seen.append((self.path,dict(self.headers),body));self.send_response(test.status);self.send_header('Content-Type',test.kind);self.send_header('Content-Length',str(len(test.raw)));self.end_headers();self.wfile.write(test.raw)
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.thread=threading.Thread(target=self.server.serve_forever);self.thread.start()
        self.binding={'endpoint':'http://127.0.0.1:'+str(self.server.server_port),'forge_token':'T'*64}
    def tearDown(self):self.server.shutdown();self.server.server_close();self.thread.join()
    def call(self,**kw):return request(self.binding,'POST','/v1/project-proposal-decisions/decisions',{'reason':'🌱 café'},content_audience='workspace',error_validator=error,**kw)
    def test_actual_separate_content_audience_and_UTF8_payload(self):
        self.assertEqual(self.call(),{'value':True});_,headers,body=self.seen[0]
        self.assertEqual(headers['X-Forge-Content-Audience'],'workspace');self.assertNotIn('X-Forge-Proposal-Audience',headers);self.assertNotIn('X-Forge-Concept-Audience',headers);self.assertIn('🌱'.encode(),body)
        self.assertEqual(headers['Authorization'],'Bearer '+'T'*64)
        for kw in [{'proposal_audience':'other'},{'concept_audience':'other'}]:
            with self.assertRaises(WorklistError):self.call(**kw)
        self.assertEqual(len(self.seen),1)
    def test_actual_denied_unknown_notfound_error_status_and_closed_payload(self):
        for status in [401,403]:
            self.status=status;self.raw=b'not-json'
            with self.assertRaises(WorklistError) as raised:self.call()
            self.assertEqual(raised.exception.state,'DENIED')
        self.raw=b'{"contract_version":"forge-project-proposal-content-decision/v1","error":{"code":"CONTENT_NOT_FOUND"}}'
        for status in [404,503]:
            self.status=status
            with self.assertRaises(WorklistError) as raised:self.call()
            self.assertEqual(raised.exception.state,'CONTENT_NOT_FOUND');self.assertEqual(raised.exception.http_status,status)
        self.status=200
        for raw,kind in [(b'{"duplicate":1,"duplicate":2}','application/json'),(b'{}','text/html'),(b'{','application/json'),(b' '*200,'application/json')]:
            self.raw=raw;self.kind=kind
            with self.assertRaises(WorklistError) as raised:self.call(maximum_bytes=100)
            self.assertEqual(raised.exception.state,'INVALID_RESPONSE')
    def test_guarded_actual_connection_denial_prevents_any_request_bytes(self):
        @contextmanager
        def denied():
            raise WorklistError('DENIED')
            yield
        with self.assertRaises(WorklistError) as raised:self.call(send_guard=denied)
        self.assertEqual(raised.exception.state,'DENIED');self.assertEqual(self.seen,[])
