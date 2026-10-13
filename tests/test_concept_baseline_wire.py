"""Recorded published R50 bytes wrapped as source-only R52 contract packets.

This is not installed R52 or consumer qualification evidence.
"""
import json,unittest
from copy import deepcopy
from pathlib import Path
from workspace_control.concept_baseline_wire import result,capability,peer_digest

class ConceptBaselineWireTests(unittest.TestCase):
    def setUp(self):
        folder=Path(__file__).parent/'fixtures/concept-baseline-source'
        source=json.loads((folder/'authority-input.json').read_text());bundle=json.loads((folder/'authority-bundle.json').read_text())
        self.binding={'instance_id':'synthetic-instance','principal_id':'alice','audience':'synthetic-workspace','dossier_id':'alice-dossier'}
        self.request={'contract_version':'forge-project-proposal-http/v1','instance_id':self.binding['instance_id'],'dossier_id':self.binding['dossier_id'],'operation_id':'a'*32,'proposal_kind':'pb-render/1.0','input':source}
        artifacts=[{'path':path,'mode':420,'sha256':v['sha256'],'content':v['utf8']} for path,v in sorted(bundle['files'].items())]
        output={'state':'PROPOSED_NOT_APPROVED','original_contract_version':'pb-render/1.0','input_digest':peer_digest(source),'summary':'Synthetic source-only proposal','artifacts':artifacts,'result_digest':peer_digest(artifacts),'observations':'SUPPLIED_UNVERIFIED','repository_quality':'NOT_ASSESSED'}
        identity='proposal-'+peer_digest([self.binding[k] for k in ('instance_id','principal_id','audience','dossier_id')]+[self.request['operation_id']])[:32]
        self.packet={'contract_version':'forge-project-proposal-http/v1',**self.binding,'operation_id':self.request['operation_id'],'plan_id':identity,'proposal_kind':'pb-render/1.0','request_digest':peer_digest(self.request),'record_digest':'','result':output,'read_only_result':True,'approval':'NOT_PERFORMED','registration':'NOT_PERFORMED'};self.rehash(self.packet)
    def rehash(self,packet):
        packet['result']['result_digest']=peer_digest(packet['result']['artifacts'])
        original={k:packet[k] for k in ('plan_id','instance_id','principal_id','audience','dossier_id','operation_id','proposal_kind','request_digest')};original.update(input=self.request['input'],result=packet['result']);packet['record_digest']=peer_digest(original)
    def test_actual_published_documents_and_original_input_binding(self):
        value=result(self.packet,self.binding,self.request);self.assertTrue(any('#' in d['content'] for d in value['result']['artifacts']))
        self.assertEqual(value['approval'],'NOT_PERFORMED');self.assertEqual(value['result']['input_digest'],peer_digest(self.request['input']))
    def test_scope_operation_and_semantics_reject(self):
        for key,wrong in [('principal_id','bob'),('audience','other'),('instance_id','foreign'),('dossier_id','other'),('operation_id','b'*32),('approval','APPROVED'),('plan_id','proposal-wrong')]:
            packet=deepcopy(self.packet);packet[key]=wrong
            with self.assertRaises(ValueError):result(packet,self.binding,self.request)
        for key,wrong in [('observations','VERIFIED'),('repository_quality','PASS'),('state','APPROVED')]:
            packet=deepcopy(self.packet);packet['result'][key]=wrong;self.rehash(packet)
            with self.assertRaises(ValueError):result(packet,self.binding,self.request)
    def test_rehashed_content_manifest_and_untrusted_renderer_reject(self):
        import hashlib
        packet=deepcopy(self.packet);packet['result']['artifacts'][0]['content']+='Untrusted alteration';packet['result']['artifacts'][0]['sha256']=hashlib.sha256(packet['result']['artifacts'][0]['content'].encode()).hexdigest();self.rehash(packet)
        with self.assertRaises(ValueError):result(packet,self.binding,self.request)
        packet=deepcopy(self.packet);item=next(d for d in packet['result']['artifacts'] if d['path']=='engineering/bootstrap-manifest.json');manifest=json.loads(item['content']);manifest['renderer_source_digest']='f'*64;manifest['manifest_digest']=peer_digest({k:v for k,v in manifest.items() if k!='manifest_digest'});item['content']=json.dumps(manifest,sort_keys=True,separators=(',',':'))+'\n';item['sha256']=hashlib.sha256(item['content'].encode()).hexdigest();self.rehash(packet)
        with self.assertRaises(ValueError):result(packet,self.binding,self.request)
    def test_inventory_path_modes_size_and_original_request_reject(self):
        for patch in [dict(path='../host'),dict(mode=493),dict(content='x'*131073)]:
            packet=deepcopy(self.packet);packet['result']['artifacts'][0].update(patch);self.rehash(packet)
            with self.assertRaises(ValueError):result(packet,self.binding,self.request)
        packet=deepcopy(self.packet);packet['result']['artifacts'].append(packet['result']['artifacts'][0]);self.rehash(packet)
        with self.assertRaises(ValueError):result(packet,self.binding,self.request)
        request=deepcopy(self.request);request['input']['product']['purpose']='Other input'
        with self.assertRaises(ValueError):result(self.packet,self.binding,request)

    def test_nested_manifest_duplicate_keys_and_rehashed_duplicate_rows_reject(self):
        import hashlib
        for duplicate_key in (True,False):
            packet=deepcopy(self.packet)
            item=next(d for d in packet['result']['artifacts'] if d['path']=='engineering/bootstrap-manifest.json')
            manifest=json.loads(item['content'])
            if duplicate_key:
                content=item['content'].replace('{','{"input_digest":"shadowed",',1)
            else:
                manifest['artifacts'].append(deepcopy(manifest['artifacts'][0]))
                manifest['manifest_digest']=peer_digest({k:v for k,v in manifest.items() if k!='manifest_digest'})
                content=json.dumps(manifest,sort_keys=True,separators=(',',':'))+'\n'
            item['content']=content;item['sha256']=hashlib.sha256(content.encode()).hexdigest();self.rehash(packet)
            with self.assertRaises(ValueError):result(packet,self.binding,self.request)
