"""Actual own HTTP/private storage; no EP, Forge, provider or project creation."""
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from workspace_control.service import Service,initialize
from workspace_control.http import ThreadingHTTPServer,handler_for
from workspace_control.conversations import ConversationConflict
from workspace_control.project_concepts import ConceptStorageUnavailable

class ProjectConceptTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);os.chmod(self.root,0o700)
        initialize(self.root);self.service=Service(self.root)
        # Normal owner issuer, same finite existing actor/context pairing table.
        self.grant=self.service.conversations.issue_grant('alice','own-context')
        self.other=self.service.conversations.issue_grant('bob','own-context')
        self.server=ThreadingHTTPServer(('127.0.0.1',0),handler_for(self.service))
        self.thread=threading.Thread(target=self.server.serve_forever);self.thread.start()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.service.close();self.tmp.cleanup()
    def request(self,path='/v1/project-concepts',method='GET',body=None,grant=None,token=None,extra=None):
        headers={'Authorization':'Bearer '+(token or self.service.token),'X-Workspace-Instance':self.service.instance_id,'X-Workspace-Draft-Grant':grant or self.grant}
        headers.update(extra or {})
        data=None
        if body is not None:data=json.dumps(body).encode();headers['Content-Type']='application/json'
        r=Request('http://127.0.0.1:'+str(self.server.server_port)+path,method=method,headers=headers,data=data)
        try:
            with urlopen(r,timeout=3) as response:return response.status,json.loads(response.read())
        except HTTPError as e:
            with e:return e.code,json.loads(e.read())
    def fields(self,**updates):return {'title':'Een nieuw idee 🌱','notes':'Vrij beschrijven\n日本語 Deutsch français español','expected_revision':0,'operation_id':'a'*32,**updates}
    def test_real_http_create_replay_edit_restart_and_original_receipts(self):
        self.assertEqual(self.request()[1]['concepts'],[]);self.assertFalse((self.root/'conversations.sqlite3').exists())
        body=self.fields();code,item=self.request(method='POST',body=body);self.assertEqual(code,201)
        self.assertEqual(item['state'],'CONCEPT_NOT_CONFIGURED');identity=item['id']
        self.assertEqual(self.request(method='POST',body=body),(201,item))
        self.assertEqual(self.request(method='POST',body=self.fields(title='Changed'))[0],409)
        path='/v1/project-concepts/'+identity
        changed=self.fields(expected_revision=1,operation_id='b'*32,title='Verder uitgewerkt',notes='Bewaar echte inhoud')
        code,updated=self.request(path,'PATCH',changed);self.assertEqual(code,200);self.assertEqual(updated['revision'],2)
        self.assertEqual(self.request(path,'PATCH',changed),(200,updated))
        self.assertEqual(self.request(path,'PATCH',self.fields(expected_revision=1,operation_id='c'*32))[0],409)
        with Service(self.root) as restarted:
            with restarted.project_concepts.authorized(self.grant) as scope:
                self.assertEqual(restarted.project_concepts.get(scope,identity),updated)
                self.assertEqual(restarted.project_concepts.save(scope,body),item) # Original receipt, not new mutation.
        self.assertEqual(self.request()[1]['concepts'][0],updated)
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            self.assertEqual(db.execute('SELECT count(*) FROM project_concepts_v1').fetchone()[0],1)
            self.assertEqual(db.execute('SELECT count(*) FROM conversations').fetchone()[0],0)
    def test_scoped_actor_revocation_and_closed_ingress(self):
        _,item=self.request(method='POST',body=self.fields());path='/v1/project-concepts/'+item['id']
        self.assertEqual(self.request(grant=self.other)[1]['concepts'],[])
        self.assertEqual(self.request(path,grant=self.other)[0],404)
        self.assertEqual(self.request(path,'PATCH',self.fields(expected_revision=1,operation_id='d'*32),grant=self.other)[0],404)
        self.assertEqual(self.request(token='wrong')[0],401)
        for p in ['/v1/project-concepts?all=true','/v1/project-concepts/../all','/v1/project-concepts/%61','/v1/project-concepts/unknown']:
            self.assertEqual(self.request(p)[0],400)
        for body in [None,{},self.fields(extra=True),self.fields(title=''),self.fields(title='x'*121),self.fields(notes='x'*10001),self.fields(notes='bad\x00'),self.fields(operation_id='bad'),self.fields(expected_revision=True),self.fields(expected_revision=1)]:
            self.assertEqual(self.request(method='POST',body=body)[0],400)
        self.assertEqual(self.request(path,'POST',self.fields())[0],405)
        self.assertEqual(self.request(method='PATCH',body=self.fields())[0],405)
        self.assertEqual(self.request('/v1/project-concepts/'+'0'*32)[0],404)
        self.service.conversations.revoke_grants('alice','own-context')
        self.assertEqual(self.request(path)[0],403)
        self.assertEqual(self.request(method='POST',body=self.fields(operation_id='e'*32))[0],403)
    def test_storage_loss_never_becomes_successful_empty_or_replacement(self):
        _,item=self.request(method='POST',body=self.fields())
        db=self.root/'conversations.sqlite3';saved=db.read_bytes();db.unlink()
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.request(method='POST',body=self.fields(operation_id='e'*32))[0],503)
        self.assertFalse(db.exists())
        db.write_bytes(saved);db.chmod(0o600)
        self.assertEqual(self.request('/v1/project-concepts/'+item['id'])[0],200)
        db.chmod(0o644);self.assertEqual(self.request()[0],503)
        db.chmod(0o600)
        with sqlite3.connect(db) as connection:connection.execute('ALTER TABLE project_concepts_v1 ADD COLUMN unauthorized TEXT')
        self.assertEqual(self.request()[0],503)
        self.assertEqual(self.request(method='POST',body=self.fields(operation_id='e'*32))[0],503)
    def test_existing_conversations_preserved_and_limits_fenced(self):
        base=self.service.conversations
        chat=base.create(('alice','own-context'),{'title':'Existing chat','focus':'','mode':'UX','draft':'Untouched','request_id':'f'*32})
        self.request(method='POST',body=self.fields())
        self.assertEqual(base.get(('alice','own-context'),chat['id'])['draft'],'Untouched')
        with sqlite3.connect(self.root/'conversations.sqlite3') as db:
            db.executemany('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',[('alice','own-context',str(i),'digest','{}') for i in range(4095)])
        self.assertEqual(self.request(method='POST',body=self.fields(operation_id='e'*32))[0],400)
        with self.service.project_concepts.authorized(self.other) as scope:
            with self.assertRaises(FileNotFoundError):self.service.project_concepts.get(scope,'invalid')
        self.assertEqual(self.request(grant='x'*43)[0],403)
        with self.assertRaises(PermissionError):
            with self.service.project_concepts.authorized('wrong'):pass

if __name__=='__main__':unittest.main()
