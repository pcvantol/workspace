"""Actual own HTTP and durable intents; explicit source-only R55 protocol doubles.
Installed qualified producers and GUI proof are separate, never inferred here.
"""
import json,hashlib,time,sqlite3,threading
from unittest.mock import patch
import unittest
import test_project_concepts as own
from workspace_control import concept_adoption_wire as wire
from workspace_control.worklist_peer import WorklistError

class AdoptionHTTPTests(unittest.TestCase):
 tearDown=own.ProjectConceptTests.tearDown
 request=own.ProjectConceptTests.request
 fields=own.ProjectConceptTests.fields
 def setUp(self):
  own.ProjectConceptTests.setUp(self)
  _,self.concept=self.request(method='POST',body=self.fields())
  self.identity=self.concept['id'];self.source='e'*32;self.peer=self.service.concept_adoptions
  self.prefix='/v1/concept-adoptions/'+self.identity+'/'+self.source
  self.binding={'id':self.source,'actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':'producer-instance','dossier_id':'private-dossier','audience':'workspace-server','producer_source':wire.FORGE,'principal_id':'peer-alice','pairing_id':'selected','identity':{'status':'PROVISIONAL_REFERENCE','project_id':'explicit-product','repository_id':'explicit-core','authority_repository_id':'explicit-core','owner_reference':'explicit-owner'},'source_options':['docs/RICHTING.md'],'endpoint':'http://127.0.0.1:9999','forge_token':'T'*64,'expires_at':'2099-01-01T00:00:00Z','permissions':['PREPARE','READ'],'maximum_records':8,'label':'Setup label only'}
  self.peer._write_bindings([self.binding]);self.created={};self.posts=[];self.lose=False;self.bad_status=None
  patched=patch('workspace_control.concept_adoption_peer.request',side_effect=self.transport);patched.start();self.addCleanup(patched.stop)
 def cap(self):
  b=self.binding
  return {**{k:b[k] for k in ('instance_id','principal_id','audience','pairing_id')},'contract_version':wire.CONTRACT,'permissions':b['permissions'],'dossier_ids':[b['dossier_id']],'proposal_kind':wire.KIND,'producer_revision':wire.EP,'current_peer_access':'CHECKED_BY_ORIGINAL_GET_AT_PREPARE_AND_READ','limits':dict(request_bytes=262144,result_bytes=1048576,global_records=64,per_dossier=8),'apply':False,'inspection_post':False}
 def transport(self,b,method,path,body=None,**kw):
  if path.endswith('/capability'):return self.cap()
  with kw['send_guard']():
   if method=='GET':
    if self.bad_status:raise WorklistError('INSPECTION_ADOPTION_NOT_FOUND',http_status=self.bad_status)
    op=path.split('/')[-1].split('?')[0]
    if op not in self.created:raise WorklistError('INSPECTION_ADOPTION_NOT_FOUND',http_status=404)
    return self.created[op]
   self.posts.append(body);op=body['operation_id']
   v={**{k:b[k] for k in ('instance_id','principal_id','audience','dossier_id','pairing_id')},'contract_version':wire.CONTRACT,'operation_id':op,'plan_id':'inspection-proposal-'+hashlib.sha256(wire.canonical([b[k] for k in ('instance_id','principal_id','audience','dossier_id')]+[op])+b'\n').hexdigest()[:32],'request_digest':wire.peer_digest(body),'state':'PREPARING','result':None,'proposal_kind':wire.KIND,'original_intent':True,'approval':'NOT_PERFORMED','registration':'NOT_PERFORMED'}
   self.created[op]=v
   if self.lose:raise WorklistError('UNAVAILABLE')
   return v
 def command(self,**kw):return dict(operation_id='b'*32,expected_revision=1,requested_artifacts=['docs/product/VISION.md'],mappings=[dict(artifact_path='docs/product/VISION.md',source_path='docs/RICHTING.md',choice='LINK_EXISTING')],**kw)
 def test_real_own_http_original_one_effect_replay_current_scope_and_history(self):
  self.assertEqual(self.request('/v1/concept-adoptions/'+self.identity+'/sources')[1]['sources'][0]['label'],'Setup label only')
  self.assertTrue(self.request(self.prefix+'/access')[1]['can_prepare'])
  self.assertEqual(self.request(self.prefix+'/operations')[1],{'operations':[]})
  code,v=self.request(self.prefix+'/prepare','POST',self.command());self.assertEqual(code,200)
  self.assertEqual(v['proposal']['state'],'PREPARING');self.assertIsNone(v['document'])
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command()),(200,v));self.assertEqual(len(self.posts),1)
  self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32),(200,v))
  self.assertEqual(self.request(self.prefix+'/operations')[1],{'operations':[dict(operation_id='b'*32,source_revision=1)]})
  self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32,grant=self.other)[0],404)
  self.service.conversations.revoke_grants('alice','own-context');self.assertEqual(self.request(self.prefix+'/access')[0],403)
 def test_lost_committed_reply_reads_original_after_server_object_restart_no_post(self):
  self.lose=True;self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],503);self.assertEqual(len(self.posts),1)
  self.lose=False
  from workspace_control.service import Service
  with Service(self.root) as restarted:
   with patch('workspace_control.concept_adoption_peer.request',side_effect=self.transport):
    original=restarted.concept_adoptions.read(self.grant,self.identity,self.source,'b'*32)
    self.assertEqual(original['proposal'],self.created['b'*32])
  self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32)[0],200);self.assertEqual(len(self.posts),1)
 def test_definitive_revision_rejection_is_own_typed_absence_not_producer404(self):
  self.request('/v1/project-concepts/'+self.identity,'PATCH',self.fields(operation_id='c'*32,expected_revision=1))
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command()),(409,{'error':'ADOPTION_SOURCE_REJECTED_BEFORE_CAPTURE'}))
  self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32),(404,{'error':'ADOPTION_NOT_FOUND'}));self.assertEqual(self.posts,[])
  self.assertEqual(self.request(self.prefix+'/operations')[1],{'operations':[]})
 def test_unavailable_notfound_error_is_not_public_absence_and_never_posts(self):
  self.bad_status=503
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],503);self.assertEqual(self.posts,[])
  self.bad_status=None
  # Dispatch was not claimed by any non-404 response.
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],200);self.assertEqual(len(self.posts),1)
 def test_readonly_expiry_storage_capacity_and_archive_preserve_permissions(self):
  self.binding['permissions']=['READ'];self.peer._write_bindings([self.binding]);self.assertFalse(self.request(self.prefix+'/access')[1]['can_prepare']);self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],403)
  self.binding['permissions']=['PREPARE','READ'];self.peer._write_bindings([self.binding])
  with patch.object(self.peer.intents,'freeze',side_effect=sqlite3.OperationalError('source-only full store')):self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],503)
  self.binding['expires_at']='2000-01-01T00:00:00Z';self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.prefix+'/access')[0],403)
  self.binding['expires_at']='2099-01-01T00:00:00Z';self.peer._write_bindings([self.binding])
  from workspace_control.project_concept_library import ProjectConceptLibrary
  ProjectConceptLibrary(self.service.project_concepts).move(('alice','own-context'),self.identity,dict(operation_id='d'*32,expected_revision=1,lifecycle='ARCHIVED'))
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],403);self.assertEqual(self.posts,[])
 def test_closed_routes_body_missing_original_and_invalid_mapping(self):
  for suffix in ['/access/','/operations/../foreign','/operations/'+'z'*32]:self.assertEqual(self.request(self.prefix+suffix)[0],400)
  self.assertEqual(self.request(self.prefix+'/prepare')[0],405)
  self.assertEqual(self.request(self.prefix+'/prepare','PATCH',{})[0],405)
  self.assertEqual(self.request(self.prefix+'/operations','POST',{})[0],405)
  for body in [{},dict(self.command(),mappings=[dict(artifact_path='docs/product/VISION.md',source_path='private/foreign',choice='LINK_EXISTING')]),dict(self.command(),actor='foreign')]:self.assertEqual(self.request(self.prefix+'/prepare','POST',body)[0],400)
  self.assertEqual(self.request(self.prefix+'/operations/'+'f'*32)[0],404)
 def test_owner_private_pairing_receipt_and_missing_initialized_allocation(self):
  self.peer.revoke(self.source)
  token=self.root/'r55-token';token.write_text('T'*64+'\n');token.chmod(0o600)
  receipt=self.root/'r55-receipt';receipt.write_text(json.dumps({**{k:self.binding[k] for k in ('instance_id','principal_id','audience','pairing_id','expires_at','permissions','maximum_records')},'state':'ACTIVE','dossier_ids':[self.binding['dossier_id']]}));receipt.chmod(0o600)
  config=self.root/'owner-config';config.write_text(json.dumps({**{k:self.binding[k] for k in ('actor_id','context_id','concept_id','endpoint','dossier_id','label','identity','source_options')},'receipt_file':str(receipt),'token_file':str(token)}));config.chmod(0o600)
  issued=self.peer.provision(str(config));self.assertEqual(issued['state'],'OWNER_LINKED_SETUP_METADATA')
  self.peer.revoke(issued['binding_id'])
  (self.root/'concept-adoption-bindings.json').unlink();self.assertEqual(self.request('/v1/concept-adoptions/'+self.identity+'/sources')[0],503);self.assertFalse((self.root/'concept-adoption-bindings.json').exists())

 def test_late_archived_source_stays403_with_proven_pre_capture_receipt_then_restore(self):
  from workspace_control.project_concept_library import ProjectConceptLibrary
  library=ProjectConceptLibrary(self.service.project_concepts)
  library.move(('alice','own-context'),self.identity,dict(operation_id='c'*32,expected_revision=1,lifecycle='ARCHIVED'))
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command()),(403,{'error':'DENIED','reason':'ADOPTION_SOURCE_ARCHIVED_BEFORE_CAPTURE'}))
  self.assertEqual(self.posts,[]);self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32),(404,{'error':'ADOPTION_NOT_FOUND'}))
  restored=library.move(('alice','own-context'),self.identity,dict(operation_id='d'*32,expected_revision=2,lifecycle='ACTIVE'))
  new=self.command();new['operation_id']='e'*32;new['expected_revision']=restored['revision']
  self.assertEqual(self.request(self.prefix+'/prepare','POST',new)[0],200);self.assertEqual(len(self.posts),1)
  self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32)[0],404)
  library.move(('alice','own-context'),self.identity,dict(operation_id='f'*32,expected_revision=3,lifecycle='ARCHIVED'))
  self.assertEqual(self.request(self.prefix+'/prepare','POST',new),(403,{'error':'DENIED'}))
  self.assertEqual(self.request(self.prefix+'/operations/'+'e'*32)[0],200);self.assertEqual(len(self.posts),1)

 def test_future_revision_never_produces_retireable_receipt_after_archive(self):
  from workspace_control.project_concept_library import ProjectConceptLibrary
  future=self.command();future['expected_revision']=3
  self.assertEqual(self.request(self.prefix+'/prepare','POST',future),(409,{'error':'ADOPTION_CONFLICT'}))
  ProjectConceptLibrary(self.service.project_concepts).move(('alice','own-context'),self.identity,dict(operation_id='c'*32,expected_revision=1,lifecycle='ARCHIVED'))
  self.assertEqual(self.request(self.prefix+'/prepare','POST',future),(403,{'error':'DENIED'}))
  self.assertEqual(self.posts,[])

 def test_real_own_capacity_distinct_from_storage_or_mislabelled_producer_failure(self):
  self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],200)
  second=self.command();second['operation_id']='c'*32
  with patch('workspace_control.concept_adoption_intents.LIMIT',1):
   self.assertEqual(self.request(self.prefix+'/prepare','POST',second),(409,{'error':'ADOPTION_CAPACITY'}))
  self.assertEqual(len(self.posts),1);self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32)[0],200)
  with patch.object(self.peer,'cap',side_effect=WorklistError('INSPECTION_ADOPTION_CAPACITY_EXHAUSTED',http_status=503)):
   self.assertEqual(self.request(self.prefix+'/access')[0],503)
  with patch.object(self.peer,'cap',side_effect=WorklistError('INSPECTION_ADOPTION_IDEMPOTENCY_CONFLICT',http_status=503)):
   self.assertEqual(self.request(self.prefix+'/access')[0],503)
  with patch.object(self.peer,'cap',side_effect=WorklistError('INSPECTION_ADOPTION_CAPACITY_EXHAUSTED',http_status=409)):
   self.assertEqual(self.request(self.prefix+'/access')[0],409)
