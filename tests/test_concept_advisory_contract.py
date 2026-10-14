"""Exact owner synthetic wire examples. No installed/provider/authority claim."""
from copy import deepcopy
import json
from pathlib import Path
import unittest
from workspace_control.concept_advisory_contract import response, request
from workspace_control.concept_advisory_mapping import peer_digest
from workspace_control.worklist_peer import WorklistError

class ConceptAdviceContractTests(unittest.TestCase):
    def setUp(self):
        self.example=json.loads(Path(__file__).with_name('r53-synthetic-conversation-e581.json').read_text())
        self.rows=self.example['conversation']; self.value=deepcopy(self.rows[0]['response'])
        self.binding={key:self.value[key] for key in ('instance_id','principal_id','audience','dossier_id','conversation_id')}
        self.binding.update(provider_id='concept-fixture',concept_id='concept-one',transfer_policy_digest=self.rows[0]['request']['transfer_policy_digest'])
    def validate(self,value=None):
        return response(value or self.value,'TurnResponse',self.binding,expected=self.rows[0]['request'])
    def bad(self,mutate):
        v=deepcopy(self.value);mutate(v)
        with self.assertRaises(WorklistError):self.validate(v)
    def test_exact_producer_examples_and_read_envelope(self):
        self.assertEqual(self.validate(),self.value)
        v=deepcopy(self.value);del v['recorded'];v['read_only']=True
        self.assertEqual(self.validate(v),v)
        first=self.value['original_turn']
        second=self.rows[1]['response']
        response(second,'TurnResponse',self.binding,expected=self.rows[1]['request'],prior=[first])
        history={k:v for k,v in self.value.items() if k not in ('recorded','original_turn')}
        history.update(turns=[first,second['original_turn']],revision=2,read_only=True)
        self.assertEqual(response(history,'History',self.binding),history)
        for change in ('revision','operation_id','expected_revision'):
            v=deepcopy(history)
            if change=='revision':v['revision']=1
            elif change=='operation_id':v['turns'][1]['request'][change]=v['turns'][0]['request'][change]
            else:v['turns'][1]['request'][change]=0
            with self.assertRaises(WorklistError):response(v,'History',self.binding)
    def test_closed_envelope_never_skips_scope_or_payload_validation(self):
        for mutate in [lambda v:v.update(extra=True),lambda v:v.update(audience='other'),lambda v:v.update(read_only=True),lambda v:v.pop('recorded'),lambda v:v.pop('instance_id'),lambda v:v.update(original_turn={})]:
            self.bad(mutate)
    def test_original_request_and_context_and_result_binding(self):
        for key,value in [('request_digest','sha256:'+'0'*64),('revision',2),('principal_id','other'),('integrity','bad')]:
            self.bad(lambda v,k=key,x=value:v['original_turn'].update({k:x}))
        self.bad(lambda v:v['original_turn']['context'].update(evidence_references=['turn:foreign']))
        self.bad(lambda v:v['original_turn']['context']['evidence_references'].append(v['original_turn']['context']['evidence_references'][0]))
        self.bad(lambda v:v['original_turn']['outcome'].update(result_digest='sha256:'+'0'*64))
        self.bad(lambda v:v['original_turn']['outcome']['output'].update(applied=True))
        self.bad(lambda v:v['original_turn']['request']['briefing']['fields'].update(users='tampered'))
        with self.assertRaises(WorklistError):request(self.rows[0]['request'],dict(self.binding,concept_id='foreign'))
        with self.assertRaises(WorklistError):request(self.rows[0]['request'],dict(self.binding,transfer_policy_digest='sha256:'+'0'*64))
    def test_typed_changes_and_protected_text(self):
        for mutate in [lambda o:o.update(language='de'),lambda o:o.update(answer='<secret>'),lambda o:o['changes'][0].update(before='other'),lambda o:o['changes'][0].update(references=['turn:foreign']),lambda o:o['changes'][0].update(references=[o['changes'][0]['references'][0]]*2),lambda o:o['changes'].append(deepcopy(o['changes'][0]))]:
            v=deepcopy(self.value);o=v['original_turn']['outcome']['output'];mutate(o)
            v['original_turn']['outcome']['result_digest']=peer_digest(o)
            with self.assertRaises(WorklistError):self.validate(v)
    def test_pending_failed_uncertain_never_expose_complete_output(self):
        for state in ('PENDING','FAILED','UNCERTAIN'):
            v=deepcopy(self.value);v['original_turn'].update(status=state,outcome=None)
            self.assertEqual(self.validate(v),v)
            v['original_turn']['outcome']=deepcopy(self.value['original_turn']['outcome'])
            with self.assertRaises(WorklistError):self.validate(v)
        self.bad(lambda v:v['original_turn'].update(outcome=None))
        self.bad(lambda v:v['original_turn']['outcome'].update(execution='MAY_HAVE_HAPPENED'))
        self.bad(lambda v:v['original_turn']['outcome']['usage'].update(input_tokens=999999))
        v=deepcopy(self.value);v['original_turn'].update(status='UNCERTAIN')
        v['original_turn']['outcome'].update(output=None,result_digest=None)
        self.assertEqual(self.validate(v),v)
        v['original_turn']['outcome']['result_digest']='sha256:'+'0'*64
        with self.assertRaises(WorklistError):self.validate(v)
