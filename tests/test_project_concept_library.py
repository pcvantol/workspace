"""Actual bounded own HTTP lifecycle extension and legacy immutable receipts."""
from tests import test_project_concepts as original
import json
import os
import sqlite3
from contextlib import closing
from unittest.mock import patch
import threading
import unittest
from workspace_control.project_concept_library import ProjectConceptLibrary, MARKER, TABLE, VERSION

class ProjectConceptLibraryTests(unittest.TestCase):
    setUp=original.ProjectConceptTests.setUp
    tearDown=original.ProjectConceptTests.tearDown
    request=original.ProjectConceptTests.request
    fields=original.ProjectConceptTests.fields
    def create(self,**kw):
        code,item=self.request(method='POST',body=self.fields(**kw));self.assertEqual(code,201);return item
    def move(self,item,target='ARCHIVED',operation='b'*32,revision=None,grant=None):
        return self.request('/v2/project-concepts/'+item['id']+'/lifecycle','POST',{'operation_id':operation,'expected_revision':item['revision'] if revision is None else revision,'lifecycle':target},grant=grant)
    def detail(self,item,grant=None):return self.request('/v2/project-concepts/'+item['id'],grant=grant)
    def receipts(self):
        with closing(sqlite3.connect(self.root/'conversations.sqlite3')) as db:
            return db.execute('SELECT actor_id,context_id,operation_id,request_digest,response FROM project_concept_operations_v1 ORDER BY operation_id').fetchall()
    def test_legacy_reads_never_migrate_archive_restore_preserve_and_replay_original(self):
        self.assertEqual(self.request('/v2/project-concepts')[1]['concepts'],[]);self.assertFalse((self.root/'conversations.sqlite3').exists())
        before=self.create();receipts=self.receipts();raw=(self.root/'conversations.sqlite3').read_bytes()
        code,inventory=self.request('/v2/project-concepts');self.assertEqual(code,200);self.assertEqual(inventory['library_version'],VERSION)
        self.assertEqual(inventory['concepts'][0]['lifecycle'],'ACTIVE');self.assertNotIn('notes',inventory['concepts'][0])
        self.assertFalse((self.root/MARKER).exists());self.assertEqual((self.root/'conversations.sqlite3').read_bytes(),raw)
        code,archived=self.move(before);self.assertEqual(code,200);self.assertEqual(archived['revision'],2);self.assertEqual(archived['lifecycle'],'ARCHIVED')
        for key in ['id','title','notes','actor_id','context_id','created_at','state']:self.assertEqual(archived[key],before[key])
        self.assertEqual(self.receipts()[0],receipts[0]);self.assertEqual(self.move(before),(200,archived))
        # Legacy successful response/digest is immutable even after archiving.
        self.assertEqual(self.request(method='POST',body=self.fields()),(201,before))
        self.assertEqual(self.request('/v1/project-concepts/'+before['id'],'PATCH',self.fields(expected_revision=2,operation_id='c'*32))[0],409)
        self.assertEqual(self.detail(before)[1],archived)
        code,restored=self.move(archived,'ACTIVE','d'*32);self.assertEqual(code,200);self.assertEqual(restored['revision'],3)
        self.assertEqual(self.move(before),(200,archived));self.assertEqual(self.detail(before)[1]['lifecycle'],'ACTIVE')
        self.assertEqual(self.detail(before)[1]['revision'],3);self.assertEqual(self.receipts()[0],receipts[0])
        code,edited=self.request('/v1/project-concepts/'+before['id'],'PATCH',self.fields(expected_revision=3,operation_id='e'*32,title='New text'))
        self.assertEqual(code,200);self.assertEqual(edited['revision'],4);self.assertEqual(self.detail(before)[1]['lifecycle'],'ACTIVE')
    def test_stale_intent_identity_actor_context_and_closed_capability(self):
        item=self.create();archived=self.move(item)[1]
        self.assertEqual(self.move(item,operation='c'*32)[0],409)
        self.assertEqual(self.move(archived,'ACTIVE','d'*32,revision=1)[0],409)
        self.assertEqual(self.move(archived,'ACTIVE','b'*32)[0],409) # original op cannot change meaning
        self.assertEqual(self.move(archived,'ACTIVE','c'*32,grant=self.other)[0],404)
        self.assertEqual(self.detail(item,grant=self.other)[0],404)
        # Archived identities must not leak via legacy save's archive guard.
        self.assertEqual(self.request('/v1/project-concepts/'+item['id'],'PATCH',self.fields(expected_revision=2,operation_id='d'*32),grant=self.other)[0],404)
        grant=self.service.conversations.issue_grant('alice','different-context')
        self.assertEqual(self.move(archived,'ACTIVE','d'*32,grant=grant)[0],404)
        for fields in [{},{'operation_id':'c'*32,'expected_revision':True,'lifecycle':'ACTIVE'}, {'operation_id':'bad','expected_revision':2,'lifecycle':'ACTIVE'}, {'operation_id':'c'*32,'expected_revision':2,'lifecycle':'DELETED'}, {'operation_id':'c'*32,'expected_revision':2,'lifecycle':'ACTIVE','notes':'hidden save'}]:
            self.assertEqual(self.request('/v2/project-concepts/'+item['id']+'/lifecycle','POST',fields)[0],400)
        for path,method in [('/v2/project-concepts?lifecycle=ACTIVE','GET'),('/v2/project-concepts','POST'),('/v2/project-concepts/'+item['id'],'PATCH'),('/v2/project-concepts/'+item['id']+'/lifecycle','GET'),('/v1/project-concepts/'+item['id']+'/lifecycle','POST')]:
            self.assertIn(self.request(path,method,self.fields() if method!='GET' else None)[0],[400,405])
        self.service.conversations.revoke_grants('alice','own-context')
        self.assertEqual(self.detail(item)[0],403);self.assertEqual(self.move(archived,'ACTIVE','d'*32)[0],403)
    def test_storage_schema_loss_and_corruption_are_unavailable_never_empty(self):
        item=self.create();self.move(item);db=self.root/'conversations.sqlite3';saved=db.read_bytes();db.unlink()
        self.assertEqual(self.request('/v2/project-concepts')[0],503);self.assertFalse(db.exists())
        db.write_bytes(saved);db.chmod(0o600)
        marker=self.root/MARKER;original_marker=marker.read_bytes();marker.write_text('{invalid')
        self.assertEqual(self.request('/v2/project-concepts')[0],503);self.assertEqual(self.detail(item)[0],503)
        marker.write_bytes(original_marker);marker.chmod(0o600)
        with closing(sqlite3.connect(db)) as conn,conn:conn.execute('DROP TABLE '+TABLE)
        after=db.read_bytes();self.assertEqual(self.request('/v2/project-concepts')[0],503);self.assertEqual(db.read_bytes(),after)
        self.assertEqual(self.move(item,'ACTIVE','c'*32,revision=2)[0],503)
        db.write_bytes(saved);db.chmod(0o600)
        with closing(sqlite3.connect(db)) as conn,conn:conn.execute('ALTER TABLE '+TABLE+' ADD COLUMN unknown TEXT')
        self.assertEqual(self.request('/v2/project-concepts')[0],503)
    def test_archive_keeps_total_and_receipt_quotas(self):
        item=self.create();archived=self.move(item)[1]
        with closing(sqlite3.connect(self.root/'conversations.sqlite3')) as db,db:
            db.executemany('INSERT INTO project_concepts_v1 VALUES (?,?,?,?,?,?,?,?)',[(f'{i:032x}','alice','own-context','Same title','Own notes',1,item['created_at'],item['updated_at']) for i in range(499)])
        self.assertEqual(len(self.request('/v2/project-concepts')[1]['concepts']),500)
        self.assertEqual(self.request(method='POST',body=self.fields(operation_id='c'*32))[0],400)
        with closing(sqlite3.connect(self.root/'conversations.sqlite3')) as db,db:
            db.executemany('INSERT INTO project_concept_operations_v1 VALUES (?,?,?,?,?)',[('alice','own-context',str(i),'digest','{}') for i in range(4094)])
        self.assertEqual(self.move(archived,'ACTIVE','d'*32)[0],400)
        self.assertEqual(self.move(item),(200,archived)) # original replay survives exhausted quota
    def test_publication_fence_revoke_waits_and_next_read_denied(self):
        item=self.create();handler=self.server.RequestHandlerClass;reply=handler._reply;entered=threading.Event();finish=threading.Event();revoked=threading.Event();result=[]
        def held(instance,code,value,*args,**kw):
            if instance.path.endswith('/lifecycle') and code==200:entered.set();self.assertTrue(finish.wait(3))
            return reply(instance,code,value,*args,**kw)
        with patch.object(handler,'_reply',held):
            request=threading.Thread(target=lambda:result.append(self.move(item)));request.start();self.assertTrue(entered.wait(3))
            revoker=threading.Thread(target=lambda:(self.service.conversations.revoke_grants('alice','own-context'),revoked.set()));revoker.start()
            self.assertFalse(revoked.wait(.1));finish.set();request.join(3);revoker.join(3)
        self.assertTrue(revoked.is_set());self.assertEqual(result[0][0],200);self.assertEqual(self.detail(item)[0],403)


class LibraryAllocationRegressionTests(unittest.TestCase):
    setUp=ProjectConceptLibraryTests.setUp
    tearDown=ProjectConceptLibraryTests.tearDown
    request=ProjectConceptLibraryTests.request
    fields=ProjectConceptLibraryTests.fields
    create=ProjectConceptLibraryTests.create
    move=ProjectConceptLibraryTests.move
    detail=ProjectConceptLibraryTests.detail
    receipts=ProjectConceptLibraryTests.receipts
    def test_retained_library_marker_blocks_missing_database_before_every_open(self):
        item=self.create();self.move(item)
        db=self.root/'conversations.sqlite3';original_db=db.read_bytes();old=self.root/'project-concepts-schema-v1.json';original_old=old.read_bytes()
        db.unlink();old.unlink()
        for path,method,body in [('/v2/project-concepts','GET',None),('/v2/project-concepts/'+item['id'],'GET',None),('/v2/project-concepts/'+item['id']+'/lifecycle','POST',{'operation_id':'c'*32,'expected_revision':2,'lifecycle':'ACTIVE'}),('/v1/project-concepts','GET',None),('/v1/project-concepts','POST',self.fields(operation_id='c'*32))]:
            self.assertEqual(self.request(path,method,body)[0],503);self.assertFalse(db.exists());self.assertFalse(old.exists())
        (self.root/MARKER).write_text('{bad')
        self.assertEqual(self.request('/v2/project-concepts')[0],503);self.assertFalse(db.exists())
        db.write_bytes(original_db);db.chmod(0o600);old.write_bytes(original_old);old.chmod(0o600)
    def test_missing_overlay_and_marker_preserved_receipts_never_reactivate(self):
        item=self.create();self.move(item);db=self.root/'conversations.sqlite3';marker=self.root/MARKER;original=db.read_bytes();original_marker=marker.read_bytes();receipts=self.receipts()
        for drop in [False,True]:
            marker.unlink()
            if drop:
                with closing(sqlite3.connect(db)) as conn,conn:conn.execute('DROP TABLE '+TABLE)
            before=db.read_bytes()
            self.assertEqual(self.request('/v2/project-concepts')[0],503)
            self.assertEqual(self.request('/v1/project-concepts/'+item['id'],'PATCH',self.fields(expected_revision=2,operation_id='c'*32))[0],503)
            self.assertEqual(self.move(item,'ACTIVE','c'*32,revision=2)[0],503)
            self.assertEqual(db.read_bytes(),before);self.assertFalse(marker.exists());self.assertEqual(self.receipts(),receipts)
            db.write_bytes(original);db.chmod(0o600);marker.write_bytes(original_marker);marker.chmod(0o600)
        self.assertEqual(self.detail(item)[1]['lifecycle'],'ARCHIVED')
    def test_nullable_wrong_type_invalid_orphaned_overlay_fail_without_normalizing(self):
        item=self.create();self.move(item);db=self.root/'conversations.sqlite3';original=db.read_bytes()
        for definition,identity,life in [('concept_id TEXT PRIMARY KEY,lifecycle TEXT',item['id'],None),('concept_id TEXT PRIMARY KEY,lifecycle INTEGER NOT NULL',item['id'],1),('concept_id TEXT PRIMARY KEY,lifecycle TEXT NOT NULL',None,'ACTIVE'),('concept_id TEXT PRIMARY KEY,lifecycle TEXT NOT NULL',item['id'],'DELETED')]:
            with closing(sqlite3.connect(db)) as conn,conn:
                conn.execute('DROP TABLE '+TABLE);conn.execute('CREATE TABLE '+TABLE+' ('+definition+')');conn.execute('INSERT INTO '+TABLE+' VALUES (?,?)',(identity,life))
            before=db.read_bytes();self.assertEqual(self.request('/v2/project-concepts')[0],503);self.assertEqual(self.move(item,'ACTIVE','c'*32,revision=2)[0],503);self.assertEqual(db.read_bytes(),before)
            db.write_bytes(original);db.chmod(0o600)

if __name__=='__main__':unittest.main()
