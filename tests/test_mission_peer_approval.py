"""Consumer composition with real source packets; no approval effects simulated.

This isolates package/original-turn correlation and preflight refusal. Actual
canonical effect and installed proofs are separate mandatory integration gates.
"""
from copy import deepcopy
import unittest
from unittest.mock import patch
from tests import test_mission_approval_contract as source_examples
from workspace_control.mission_peer import MissionConceptTransport
from workspace_control.worklist_peer import WorklistError


class OwnRecords:
    def __init__(self,scope,conversation):self.scope=scope;self.conversation=conversation
    def get(self,scope,conversation):
        if scope!=self.scope or conversation!=self.conversation:raise PermissionError()
        return {'id':conversation}


class MissionPackagePeerTests(unittest.TestCase):
    def setUp(self):
        source=source_examples.MissionApprovalContractTests();source.setUp()
        self.source=source;self.package=deepcopy(source.prepared)
        self.binding=dict(source.binding,workspace_project_id='own-project')
        self.peer=MissionConceptTransport.__new__(MissionConceptTransport)
        self.peer.conversations=OwnRecords((self.binding['actor_id'],'own-project'),source.conversation)
        self.paths=[]
        def read(binding,path):
            self.paths.append(path)
            return self.package if '/package' in path else source.read('operation-current.json')
        self.peer._read=read
        p=source.package;s=p['source']
        self.original={'request_digest':s['request_digest'],'request':{'context_revision':s['context_revision']},
            'session_id':s['session_id'],'invocation_id':s['invocation_id'],
            'outcome':{'result_digest':s['result_digest'],'output':{'definition':p['definition']}}}
        self.peer.turn=lambda binding,conversation,turn_id:{'original_turn':self.original}

    def testPackageRequiresExactOriginalGenerationAndCurrentFrozenMeaning(self):
        self.assertEqual(self.peer.package(self.binding,self.source.conversation,2),self.package)
        original=deepcopy(self.original)
        for key in ['request_digest','session_id','invocation_id']:
            self.original[key]='foreign'
            with self.assertRaises(WorklistError):self.peer.package(self.binding,self.source.conversation,2)
            self.original=deepcopy(original)
        self.original['outcome']['output']['definition']['title']='unseen'
        with self.assertRaises(WorklistError):self.peer.package(self.binding,self.source.conversation,2)
        self.original=original
        self.package=self.source.read('prepared-incomplete.json')
        self.assertIsNone(self.peer.package(self.binding,self.source.conversation)['package'])
        before=len(self.paths)
        for revision in [True,0,9]:
            with self.assertRaises(WorklistError):self.peer.package(self.binding,self.source.conversation,revision)
        self.assertEqual(len(self.paths),before)

    def testChangedPackageRefusesApprovalBeforeAnyExternalWriteAndOperationIsScoped(self):
        body=dict(contract_version=self.package['contract_version'],operation_id='explicit-own-confirmation',
            revision=2,package_digest='sha256:'+'0'*64,confirm=True)
        with patch('workspace_control.mission_peer.control_request') as external:
            with self.assertRaises(WorklistError) as raised:
                self.peer.approve(self.binding,self.source.conversation,body,authority=None)
            self.assertEqual(raised.exception.state,'CONCEPT_OR_CONTEXT_CHANGED');external.assert_not_called()
        value=self.source.read('operation-current.json')
        observed=self.peer.operation(self.binding,self.source.conversation,value['operation_id'])
        self.assertEqual(observed,value)
        before=len(self.paths)
        with self.assertRaises(WorklistError):self.peer.operation(self.binding,self.source.conversation,'../foreign')
        self.assertEqual(len(self.paths),before)
        with self.assertRaises(WorklistError):self.peer.package(self.binding,'foreign',2)
