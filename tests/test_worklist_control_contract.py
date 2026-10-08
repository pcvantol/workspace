"""Consumer shape/revision/receipt negatives, not installed producer evidence."""
from copy import deepcopy
import unittest
from tests.test_worklist_contract import BINDING, DIGEST, projection, seal
from workspace_control.worklist_control_contract import *


def request(intent='hold'):
    return {'contract_version': REQUEST, 'operation_id':'operation-a', 'intent':intent,
            'instance_id':'forge-1','workset_id':'workset-a','definition_revision':DIGEST,
            'expected_revision':1,'hold_operation_id':None if intent=='hold' else 'original-hold',
            'expected_hold_revision':None if intent=='hold' else 1,'reason_code':'USER_REQUEST'}


def current(held=False, revision=1):
    return {'instance_id':'forge-1','workset_id':'workset-a','definition_revision':DIGEST,
            'workset_revision':revision,'control_revision':1 if held else 0,'held':held,
            'hold':{'operation_id':'operation-a','control_revision':1,'reason_code':'USER_REQUEST','owned_by_principal':True} if held else None,
            'hold_provenance':'RECORDED' if held else 'NONE','admitted_mission_ids':[],
            'boundary':'FUTURE_ADMISSION_ONLY','ongoing_work_cancelled':False,'observed_at':'2026-10-08T00:00:00Z'}


def readback(state=None, operation=None):
    state=state or current(); p=projection();p['workset_revision']=state['workset_revision'];seal(p)
    return {'contract_version':READBACK,'principal_id':'actor-a','read_only':True,'operation':operation,'current':state,'worklist':p}


def receipt(intent='hold'):
    r=request(intent);effect=current(intent=='hold',3)
    return {'contract_version':RECEIPT,'operation_id':r['operation_id'],'principal_id':'actor-a','grant_id':'grant-a',
            'request':r,'request_digest':request_digest(r),'outcome':'APPLIED','effect':effect,
            'only_target_hold_removed':r['hold_operation_id']}


class ControlContractTests(unittest.TestCase):
    def testExactCurrentOwnedForeignAndLegacy(self):
        for held in [False,True]:validate_readback(readback(current(held)),BINDING,'workset-a')
        foreign=current(True);foreign['hold']['owned_by_principal']=False;validate_current(foreign,BINDING,'workset-a')
        legacy=current(True);legacy.update(hold=None,hold_provenance='LEGACY_UNKNOWN');validate_current(legacy,BINDING,'workset-a')
        for key,val in [('instance_id','foreign'),('workset_id','foreign'),('held',1),('control_revision',True),('boundary','CANCEL'),('ongoing_work_cancelled',True),('observed_at','wrong'),('admitted_mission_ids',['same','same']),('hold_provenance','NONE')]:
            bad=current(True);bad[key]=val
            with self.assertRaises(WorklistError):validate_current(bad,BINDING,'workset-a')
        bad=readback();bad['current']['admitted_mission_ids']=['phantom']
        with self.assertRaises(WorklistError):validate_readback(bad,BINDING,'workset-a')

    def testRequestsClosedScalarAndTargetBinding(self):
        for intent in ['hold','unhold']:validate_request(request(intent),BINDING,'workset-a')
        for key,val in [('actor_id','actor-a'),('instance_id','foreign'),('intent','arm'),('expected_revision',True),('reason_code','OWNER_REQUEST'),('operation_id','../path'),('hold_operation_id','wrong'),('expected_hold_revision',1)]:
            bad=request();bad[key]=val
            with self.assertRaises(WorklistError):validate_request(bad,BINDING,'workset-a')
        bad=request('unhold');bad['expected_hold_revision']=None
        with self.assertRaises(WorklistError):validate_request(bad,BINDING,'workset-a')

    def testHistoricalReceiptAndCurrentAfterReplayAreSeparate(self):
        for intent in ['hold','unhold']:
            old=receipt(intent);validate_receipt(old,BINDING,'workset-a',request(intent))
            op={'state':'APPLIED','original_receipt':old,'operation_id':'operation-a','execution_known':True}
            current_state=current(False,5)
            rb=readback(current_state,op)
            result={'contract_version':READBACK,'original_receipt':old,'recorded':False,'current_readback':rb}
            validate_result(result,BINDING,'workset-a',request(intent))
            self.assertFalse(result['current_readback']['current']['held'])
        for key,val in [('principal_id','foreign'),('request_digest',DIGEST),('outcome','PENDING'),('only_target_hold_removed','foreign')]:
            bad=receipt();bad[key]=val
            with self.assertRaises(WorklistError):validate_receipt(bad,BINDING,'workset-a')
        bad=receipt();bad['effect']['workset_revision']=2
        with self.assertRaises(WorklistError):validate_receipt(bad,BINDING,'workset-a')
        bad=receipt();bad['effect']['hold']['owned_by_principal']=False
        with self.assertRaises(WorklistError):validate_receipt(bad,BINDING,'workset-a')

    def testPendingAndMalformedOperationJoins(self):
        pending={'state':'PENDING','original_receipt':None,'operation_id':'operation-a','execution_known':False}
        validate_readback(readback(operation=pending),BINDING,'workset-a','operation-a')
        for key,val in [('state','UNKNOWN'),('execution_known',True),('operation_id','foreign'),('original_receipt',receipt())]:
            bad=deepcopy(pending);bad[key]=val
            with self.assertRaises(WorklistError):validate_readback(readback(operation=bad),BINDING,'workset-a','operation-a')
        with self.assertRaises(WorklistError):validate_readback(readback(operation=pending),BINDING,'workset-a')
        bad=readback();bad['principal_id']='foreign'
        with self.assertRaises(WorklistError):validate_readback(bad,BINDING,'workset-a')
        bad=readback();bad['current']['workset_revision']=2
        with self.assertRaises(WorklistError):validate_readback(bad,BINDING,'workset-a')

if __name__=='__main__':unittest.main()
