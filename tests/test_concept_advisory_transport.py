"""Actual HTTP header/size boundary only; no R53 response or model qualification."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import threading
import unittest
from workspace_control.advisory_http import request
from workspace_control.worklist_peer import WorklistError

class ConceptAdviceTransportTests(unittest.TestCase):
    def test_actual_http_uses_separate_concept_audience_and_preserves_denial(self):
        observed=[];status=[200]
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                observed.append(dict(self.headers));body=b'{"transport_fixture":true}'
                self.send_response(status[0]);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            def log_message(self,*args):pass
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler);thread=threading.Thread(target=server.serve_forever);thread.start()
        binding={'endpoint':'http://127.0.0.1:'+str(server.server_port),'forge_token':'synthetic-transport-only'}
        try:
            self.assertTrue(request(binding,'GET','/v1/concept-advisory/capability',concept_audience='workspace-advice',maximum_bytes=32768)['transport_fixture'])
            self.assertEqual(observed[-1]['X-Forge-Concept-Audience'],'workspace-advice');self.assertNotIn('X-Forge-Proposal-Audience',observed[-1])
            self.assertTrue(request(binding,'GET','/v1/onboarding/capability',proposal_audience='workspace-proposal')['transport_fixture'])
            self.assertEqual(observed[-1]['X-Forge-Proposal-Audience'],'workspace-proposal');self.assertNotIn('X-Forge-Concept-Audience',observed[-1])
            for code in [401,403]:
                status[0]=code
                with self.assertRaises(WorklistError) as error:request(binding,'GET','/v1/concept-advisory/capability',concept_audience='workspace-advice')
                self.assertEqual(error.exception.state,'DENIED')
            count=len(observed)
            for kwargs in [{'concept_audience':'bad\nheader'},{'concept_audience':''},{'concept_audience':'x','proposal_audience':'y'}]:
                with self.assertRaises(WorklistError) as error:request(binding,'GET','/',**kwargs)
                self.assertEqual(error.exception.state,'INVALID_CONFIGURATION')
            self.assertEqual(len(observed),count)
        finally:server.shutdown();server.server_close();thread.join()
