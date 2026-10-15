"""Real loopback HTTP contract probes, not qualified EP installed proof."""
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json
import threading
import time
import unittest
from workspace_control.execution_progress_transport import read
from workspace_control.execution_progress_wire import ProgressError
from test_execution_progress_wire import fixture


class ExecutionProgressTransportTests(unittest.TestCase):
    def setUp(self):
        self.payload,self.binding=fixture();self.status=200;self.raw=None;self.delay=0;self.requests=[];self.headers=[('Content-Type','application/json'),('Cache-Control','no-store')];owner=self
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                owner.requests.append((self.command,self.path,dict(self.headers)))
                raw=owner.raw if owner.raw is not None else json.dumps(owner.payload).encode()
                self.send_response(owner.status)
                for k,v in owner.headers:self.send_header(k,v)
                self.send_header('Content-Length',str(len(raw)));self.end_headers()
                time.sleep(owner.delay)
                try:self.wfile.write(raw)
                except (BrokenPipeError,ConnectionResetError):pass
            def log_message(self,*args):pass
        self.server=ThreadingHTTPServer(('127.0.0.1',0),Handler);self.server.daemon_threads=False
        self.thread=threading.Thread(target=self.server.serve_forever);self.thread.start()
        self.binding.update(endpoint='http://127.0.0.1:'+str(self.server.server_port),token='x'*43,consumer_id='workspace',workspace_instance_id='workspace-instance')
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join()
    def test_real_get_exact_headers_original_snapshot_and_no_mutation_method(self):
        counter=[]
        @contextmanager
        def guard():counter.append('enter');yield;counter.append('exit')
        value=read(self.binding,'mission',expected='a'*64,guard=guard)
        self.assertEqual(value,self.payload);self.assertGreaterEqual(counter.count('enter'),2);self.assertEqual(counter.count('enter'),counter.count('exit'))
        method,path,h=self.requests[0];self.assertEqual(method,'GET');self.assertEqual(path,'/v1/execution-progress/projects/alpha?mission_id=mission&expected_snapshot='+'a'*64)
        for k,v in {'Authorization':'Bearer '+'x'*43,'EP-Progress-Contract':'1.0','EP-Instance-ID':'ep-instance','EP-Consumer-ID':'workspace','Workspace-Instance-ID':'workspace-instance','EP-Audience':'workspace'}.items():self.assertEqual(h[k],v)
        self.assertFalse(any(k in h for k in ('EP-Discovery-Contract','EP-Inspection-Contract')))
    def test_detail_uses_same_original_run(self):
        self.payload,_=fixture('run');self.assertEqual(read(self.binding,'mission','run','a'*64)['selected_run_id'],'run');self.assertIn('/runs/run?',self.requests[0][1])
    def test_foreign_mission_refused_before_io(self):
        with self.assertRaises(ProgressError) as c:read(self.binding,'foreign')
        self.assertEqual(c.exception.code,'DENIED');self.assertEqual(self.requests,[])
    def test_auth_errors_deny_without_parsing_or_fallback(self):
        for status in (401,403):
            self.status=status;self.raw=b'non-json private text'
            with self.assertRaises(ProgressError) as c:read(self.binding,'mission')
            self.assertEqual((c.exception.code,c.exception.status),('DENIED',status))
        self.assertEqual(len(self.requests),2)
    def test_closed_error_statuses_are_distinct(self):
        self.payload={'error':'PROGRESS_SOURCE_UNAVAILABLE'}
        for status,code in ((400,'INVALID_REQUEST'),(404,'RUN_NOT_FOUND'),(409,'SNAPSHOT_CONFLICT'),(422,'UNSUPPORTED'),(500,'SOURCE_CORRUPT'),(503,'UNAVAILABLE'),(302,'INVALID_RESPONSE')):
            self.status=status;self.payload={'error':'PROGRESS_SNAPSHOT_CONFLICT' if status==409 else 'PROGRESS_SOURCE_UNAVAILABLE'}
            with self.assertRaises(ProgressError) as c:read(self.binding,'mission')
            self.assertEqual(c.exception.code,code)
    def test_content_and_duplicate_headers_rejected(self):
        for headers in ([('Content-Type','text/html'),('Cache-Control','no-store')],[('Content-Type','application/json'),('Cache-Control','max-age=5')],[('Content-Type','application/json'),('Content-Type','application/json'),('Cache-Control','no-store')]):
            self.headers=headers
            with self.assertRaises(ProgressError) as c:read(self.binding,'mission')
            self.assertEqual(c.exception.code,'INVALID_RESPONSE')
    def test_size_duplicate_json_malformed_and_schema_fail_closed(self):
        for raw in (b'x'*524289,b'{"purpose":"x","purpose":"y"}',b'not json',b'{}'):
            self.raw=raw
            with self.assertRaises(ProgressError) as c:read(self.binding,'mission')
            self.assertEqual(c.exception.code,'INVALID_RESPONSE')
    def test_bounded_deadline_and_unavailable_socket(self):
        self.delay=.12
        with self.assertRaises(ProgressError) as c:read(self.binding,'mission',timeout=.03)
        self.assertEqual(c.exception.code,'UNAVAILABLE')
        self.binding['endpoint']='http://127.0.0.1:1'
        with self.assertRaises(ProgressError) as c:read(self.binding,'mission')
        self.assertEqual(c.exception.code,'UNAVAILABLE')
    def test_current_guard_rejects_before_connect(self):
        @contextmanager
        def denied():raise PermissionError('revoked');yield
        with self.assertRaises(ProgressError) as c:read(self.binding,'mission',guard=denied)
        self.assertEqual((c.exception.code,c.exception.status),('DENIED',403))
        self.assertEqual(self.requests,[])


if __name__=='__main__':unittest.main()
