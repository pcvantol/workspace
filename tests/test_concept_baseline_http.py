"""Real own HTTP authority/storage tests with explicit source-only peer doubles.
These are not installed producer qualification and never render documents.
"""
import json,os,sqlite3,unittest
from pathlib import Path
from unittest.mock import patch
import test_project_concepts as original
from workspace_control.worklist_peer import WorklistError
from workspace_control.concept_baseline_intents import TABLE

class BaselineHTTPTests(unittest.TestCase):
    tearDown=original.ProjectConceptTests.tearDown
    request=original.ProjectConceptTests.request
    fields=original.ProjectConceptTests.fields
    def setUp(self):
        original.ProjectConceptTests.setUp(self)
        _,self.concept=self.request(method='POST',body=self.fields())
        self.peer=self.service.concept_baselines;self.identity=self.concept['id'];self.prefix='/v1/concept-baselines/'+self.identity
        self.binding={'id':'paired-own','actor_id':'alice','context_id':'own-context','concept_id':self.identity,'instance_id':'forge-source-only','principal_id':'limited-alice','dossier_id':'dossier-alice','audience':'workspace-server','producer_source':'a'*40,'endpoint':'http://127.0.0.1:8765','forge_token':'T'*64,'expires_at':'2099-01-01T00:00:00+00:00','permissions':['PREPARE','READ'],'maximum_records':8}
        self.peer._write_bindings([self.binding]);self.created={};self.posts=[]
        self.mock=patch('workspace_control.concept_baseline_peer.request',side_effect=self.transport);self.mock.start();self.addCleanup(self.mock.stop)
        self.validator=patch('workspace_control.concept_baseline_peer.wire.result',side_effect=lambda value,*args:value);self.validator.start();self.addCleanup(self.validator.stop)
    def cap(self):
        return {'contract_version':'forge-project-proposal-http/v1','capability_id':'PROJECT_PROPOSAL_PREPARE_READ_V1','support':'SUPPORTED_PROPOSAL_ONLY',**{k:self.binding[k] for k in ('instance_id','principal_id','audience')},'dossier_ids':['dossier-alice'],'permissions':['PREPARE','READ'],'proposal_kinds':['pb-render/1.0'],'limits':{'request_bytes':262144,'result_bytes':1048576,'artifacts':64,'records_per_dossier':8,'global_records':64,'store_bytes':16777216},'operations':['GET /v1/onboarding/capability','POST /v1/onboarding/plans','GET /v1/onboarding/plans/{plan_id}?dossier_id={dossier_id}','GET /v1/onboarding/intents/{operation_id}?dossier_id={dossier_id}'],'decisions':False,'apply':False,'project_registration':False}
    def transport(self,binding,method,path,body=None,**kwargs):
        if path.endswith('/capability'):return self.cap()
        with kwargs['send_guard']():
            if method=='GET':
                operation=path.split('/')[-1].split('?')[0]
                if operation not in self.created:raise WorklistError('PROPOSAL_NOT_FOUND')
                return self.created[operation]
            self.posts.append(body);self.created[body['operation_id']]={'source_only_test_double':True,'operation_id':body['operation_id']};return self.created[body['operation_id']]
    def command(self,**kwargs):return {'operation_id':'b'*32,'expected_revision':1,'description':None,**kwargs}
    def test_actual_own_http_original_intent_readfirst_and_scope(self):
        self.assertEqual(self.request(self.prefix+'/access')[0],200)
        self.assertEqual(self.request(self.prefix+'/operations')[1]['operations'],[])
        code,value=self.request(self.prefix+'/prepare','POST',self.command());self.assertEqual(code,200)
        self.assertEqual(value['source_revision'],1);self.assertEqual(value['source_product']['name'],self.concept['title'])
        self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command()),(200,value));self.assertEqual(len(self.posts),1)
        self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32),(200,value))
        self.assertEqual(self.request(self.prefix+'/operations')[1]['operations'],[{'operation_id':'b'*32,'source_revision':1}])
        self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command(description='Changed'))[0],409)
        self.assertEqual(self.request(self.prefix+'/operations/'+'b'*32,grant=self.other)[0],404)
        self.service.conversations.revoke_grants('alice','own-context')
        self.assertEqual(self.request(self.prefix+'/operations')[0],403)
    def test_closed_paths_methods_bad_body_and_missing_original(self):
        for path in [self.prefix+'?all=true',self.prefix+'/access/',self.prefix+'/operations/../all',self.prefix+'/operations/'+'z'*32]:self.assertEqual(self.request(path)[0],400)
        for action in ['access','operations']:self.assertEqual(self.request(self.prefix+'/'+action,'POST',{})[0],405)
        self.assertEqual(self.request(self.prefix+'/prepare')[0],405)
        self.assertEqual(self.request(self.prefix+'/prepare','PATCH',{})[0],405)
        for body in [{},dict(self.command(),actor_id='bob'),dict(self.command(),description='x'*4097)]:self.assertEqual(self.request(self.prefix+'/prepare','POST',body)[0],400)
        self.assertEqual(self.request(self.prefix+'/operations/'+'f'*32)[0],404)
    def test_readonly_expiry_storage_failure_and_pairing_revocation(self):
        cap=self.cap();cap['permissions']=['READ'];cap['operations'].remove('POST /v1/onboarding/plans')
        self.binding['permissions']=['READ'];self.peer._write_bindings([self.binding])
        with patch.object(self,'cap',return_value=cap):
            self.assertFalse(self.request(self.prefix+'/access')[1]['can_prepare']);self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command())[0],403)
        self.binding['permissions']=['PREPARE','READ'];self.peer._write_bindings([self.binding])
        with patch.object(self.peer.intents,'freeze',side_effect=sqlite3.OperationalError('synthetic disk-full')):
            self.assertEqual(self.request(self.prefix+'/prepare','POST',self.command()),(503,{'error':'BASELINE_STORAGE_UNAVAILABLE'}))
        self.binding['expires_at']='2000-01-01T00:00:00+00:00';self.peer._write_bindings([self.binding]);self.assertEqual(self.request(self.prefix+'/access')[0],403)
        self.binding['expires_at']='2099-01-01T00:00:00+00:00';self.peer._write_bindings([self.binding]);self.peer.revoke(self.binding['id']);self.assertEqual(self.request(self.prefix+'/access')[0],403)
    def test_owner_pairing_receipt_real_str_token_and_loss(self):
        self.peer.revoke(self.binding['id']);token=self.root/'peer-token';token.write_text('T'*64+'\n');token.chmod(0o600)
        receipt=self.root/'receipt';receipt.write_text(json.dumps({**{k:self.binding[k] for k in ('instance_id','principal_id','audience','expires_at','permissions','maximum_records')},'state':'ACTIVE','dossier_ids':['dossier-alice'],'kinds':['pb-render/1.0']}));receipt.chmod(0o600)
        value=self.peer.provision('alice','own-context',self.identity,self.binding['endpoint'],'dossier-alice','a'*40,str(receipt),str(token));self.assertEqual(value['concept_id'],self.identity)
        with self.assertRaises(ValueError):self.peer.provision('alice','own-context',self.identity,self.binding['endpoint'],'dossier-alice','a'*40,str(receipt),str(token))
        (self.root/'concept-baseline-bindings.json').unlink();self.assertEqual(self.request(self.prefix+'/access')[0],503)
        self.assertFalse((self.root/'concept-baseline-bindings.json').exists())
