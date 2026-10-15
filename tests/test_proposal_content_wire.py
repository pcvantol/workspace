"""Closed synthetic R54 contracts only; not installed producer qualification."""
import unittest,json
from copy import deepcopy
from pathlib import Path
from workspace_control import proposal_content_wire as wire
from workspace_control.concept_baseline_wire import peer_digest
from workspace_control.worklist_peer import WorklistError

class ContentWireTests(unittest.TestCase):
    def setUp(self):
        schema=wire.SCHEMA['$defs'];self.subject={'plan_id':'proposal-synthetic','proposal_principal_id':'source-owner','proposal_kind':'pb-render/1.0','input_digest':'a'*64,'result_digest':'b'*64,'record_digest':'c'*64,'manifest_digest':'d'*64,'baseline':'portable-docs/1.0.0','profile_id':wire.PROFILE,'source_references':[{'reference':'synthetic-brief','owner':'USER_DECLARED','digest':'e'*64}],'concept_revision':None}
        self.binding={'instance_id':'instance','principal_id':'human-alice','audience':'workspace','dossier_id':'dossier','permissions':['DECIDE','READ'],'roles':['ARCHITECTURE','BUSINESS'],'grant_id':'grant','human_binding':{'operator_id':'human-alice','operator_binding_version':1,'installation_id':'install'}}
        self.points=['Which database later?'];self.value={'contract_version':wire.CONTRACT,**{k:self.binding[k] for k in ('instance_id','principal_id','audience','dossier_id')},'plan_id':self.subject['plan_id'],'subject':self.subject,'decision_revision':0,'state':'DECISION_NEEDED','required_roles':wire.ROLES,'open_points':self.points,'history':[],'original_decision':None,'meaning':'CONTENT_BASELINE_ONLY','effects_authorized':False,'execution_readiness':'NOT_ASSESSED','concept_revision_qualification':'NOT_STRUCTURALLY_PROVIDED_BY_R52','original_proposal_state':'PROPOSED_NOT_APPROVED'}
        self.cap={'contract_version':wire.CONTRACT,**{k:self.binding[k] for k in ('instance_id','principal_id','audience','permissions','roles')},'dossier_ids':['dossier'],'profile':schema['Capability']['properties']['profile']['const'],'limits':schema['Capability']['properties']['limits']['const'],'generation':False,'apply':False}
    def append(self,role='BUSINESS',decision='APPROVE_CONTENT'):
        index=len(self.value['history']);request={'contract_version':wire.CONTRACT,'instance_id':'instance','dossier_id':'dossier','operation_id':str(index+1)*32,'plan_id':self.subject['plan_id'],'subject':deepcopy(self.subject),'profile_id':wire.PROFILE,'role':role,'decision':decision,'expected_decision_revision':index,'previous_decision_id':self.value['history'][-1]['decision_id'] if index else None,'reason':'Synthetic human reason','acknowledged_open_points':self.points[:]}
        record={'decision_id':'decision-'+str(index),'request':request,'request_digest':peer_digest(request),'principal_id':'human-alice','audience':'workspace','human_binding':self.binding['human_binding'],'grant_id':'grant','occurred_at':'2026-10-15T13:00:00+00:00','revision':index+1,'integrity':'f'*64};self.value['history'].append(record);self.value['decision_revision']=index+1;return request
    def check(self,expected=None):return wire.response(self.value,self.binding,self.subject,self.points,expected)
    def test_separate_roles_partial_then_content_only_and_original_recovery(self):
        wire.capability(self.cap,self.binding);self.check();self.append();self.check();request=self.append('ARCHITECTURE');self.value['state']='CONTENT_APPROVED';self.check();self.value['original_decision']=self.value['history'][-1];self.check(request);self.assertFalse(self.value['effects_authorized']);self.assertIsNone(self.value['subject']['concept_revision'])
    def test_changes_request_successor_requires_exact_CAS_and_open_points(self):
        self.append(decision='REQUEST_CHANGES');self.value['state']='CHANGES_REQUESTED';self.check();self.append();self.value['state']='DECISION_NEEDED';self.check()
        self.value['history'][-1]['request']['previous_decision_id']='wrong'
        with self.assertRaises(WorklistError):self.check()
    def test_foreign_human_and_optimistic_or_forged_projections_reject(self):
        for key,value in [('principal_id','other'),('state','CONTENT_APPROVED'),('decision_revision',1),('effects_authorized',True),('open_points',[])]:
            original=deepcopy(self.value);self.value[key]=value
            with self.assertRaises(WorklistError):self.check()
            self.value=original
        request=self.append();self.value['original_decision']=self.value['history'][0];self.value['original_decision']['human_binding']={'operator_id':'bob','operator_binding_version':1,'installation_id':'install'}
        with self.assertRaises(WorklistError):self.check(request)
    def test_closed_schema_null_concept_revision_original_points_and_request_limit(self):
        request=self.append();bad=deepcopy(request);bad['subject']['concept_revision']=3
        with self.assertRaises(WorklistError):wire.decision_request(bad)
        self.value['history'][0]['request']['acknowledged_open_points']=[];self.value['history'][0]['request_digest']=peer_digest(self.value['history'][0]['request'])
        with self.assertRaises(WorklistError):self.check()
        self.cap['roles']=[]
        with self.assertRaises(WorklistError):wire.capability(self.cap,self.binding)
        with self.assertRaises(WorklistError):wire.error({'contract_version':wire.CONTRACT,'error':{'code':'CONTENT_DENIED','extra':True}})
        wire.error({'contract_version':wire.CONTRACT,'error':{'code':'CONTENT_DENIED'}})
