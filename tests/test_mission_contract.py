"""Synthetic consumer contract tests, not installed chat-first qualification."""
from copy import deepcopy
import unittest
from tests.test_advisory_contract import capability as base_capability, record as base_record, B
from workspace_control import mission_contract as w
from workspace_control.worklist_peer import WorklistError


def content():
    return dict(components=[],possible_subresults=[],dependency_reasons={},work_kind='INVESTIGATE',title='Invoice portal', objective='View own invoices', business_value='Customers find their invoices', expected_result='Read-only invoice portal', scope=['Own invoices'], exclusions=['Payments'], acceptance_criteria=['A customer sees only their own invoices.'], architecture_choices=['Authenticated read-only access'], risks=['Access isolation requires review'], dependencies=[], questions=[], change_summary='Payments excluded from this revision.')


def capability():
    value = base_capability(); value['contract_version'] = w.CONTRACT
    value['context']['concept_dependency_references'] = []
    value['context']['concept_dependency_catalog'] = []
    value['context']['concept_repository_source']={'repository_id':'repo-one','github_repository':'synthetic-owner/synthetic-repository'}
    value['context']['concept_dependency_graph']={}
    value['context']['concept_work_profiles'] = {}
    value['context']['concept_configuration_revision'] = None
    value['context_revision'] = w.digest(value['context'])
    value.update(workspace_reference_resolution_supported=False,supported_operations=['REFINE', 'READ', 'CANCEL_REQUEST'], approval_supported=False, readiness_qualified=False, generated_content_origin='VALIDATED_MODEL_PROPOSAL',maximum_missions=0,supported_work_kinds=[])
    return value


def record():
    value = base_record(); value['request']['contract_version'] = w.CONTRACT
    value['context'] = capability()['context']; value['request']['context_revision'] = w.digest(value['context'])
    value['request_digest'] = w.digest(value['request'])
    output = dict(contract_version=w.CONTRACT, request_digest=value['request_digest'], definition=content())
    value['outcome']['output'] = output; value['outcome']['result_digest'] = w.digest(output)
    return value


def catalog():
    r = record(); d = content()
    item = dict(object_id='concept-'+'c'*32, conversation_id='a'*32, revision=1, conversation_revision=1, definition_digest=w.digest(d), definition=d, source_turn_id='turn-one', context_revision=r['request']['context_revision'], title=d['title'], summary=d['expected_result'], state='CONCEPT', approval_supported=False, blockers=['TRUSTED_PLANNING_AND_APPROVAL_PACKAGE_REQUIRED'], questions=d['questions'], parent_id=None, group_id=None, labels=[], edges=[], candidate_id=None, mission_id=None,canonical_history=[])
    return dict(contract_version=w.CONTRACT, scope={k:r['request'][k] for k in ('instance_id','project_id','repository_id')}, snapshot_revision=w.digest([item]), items=[item], next_cursor=None, population='AUTHORIZED_ADMITTED_CONCEPTS_ONLY', complete_portfolio=False, read_only=True, additional_model_calls=0)


class MissionContractTests(unittest.TestCase):
    def testScopeAndClosedPreviewCannotClaimNewAuthority(self):
        cap=capability(); self.assertEqual(w.response(cap,'capability',B),cap)
        req=record()['request']; w.request(req,B,'a'*32)
        for field,value in [('readiness_qualified',True),('readiness_qualified',True),('extra','authority'),('context_revision','sha256:'+'0'*64),('conversation_ids',['b'*32])]:
            bad=deepcopy(cap);bad[field]=value
            with self.assertRaises(WorklistError):w.response(bad,'capability',B)
        with self.assertRaises(WorklistError):w.request(req,B,'b'*32)
        bad=deepcopy(req);bad['selected_sources']=[{'source_id':'same','version':'sha256:'+'a'*64}]*2
        with self.assertRaises(WorklistError):w.request(bad,B,'a'*32)
        bad=deepcopy(req);bad['objective']=''
        with self.assertRaises(WorklistError):w.request(bad,B,'a'*32)
        bad=deepcopy(cap);bad['instance_id']='foreign'
        with self.assertRaises(WorklistError):w.response(bad,'capability',B)

    def testSubstantiveQuestionAndDependencyBoundsArePreserved(self):
        d=content();w.definition(d,[])
        d['acceptance_criteria']=[];d['questions']=['Only investigate or also build?'];w.definition(d,[])
        d['questions']=[]
        with self.assertRaises(WorklistError):w.definition(d,[])
        for modify in [lambda d:d.update(title='password=hidden'),lambda d:d.update(scope=['same','same']),lambda d:d.update(dependencies=['foreign']),lambda d:d.update(signer='invented')]:
            d=content();modify(d)
            with self.assertRaises(WorklistError):w.definition(d,[])

    def testOriginalTurnAndCompleteUsageCannotBeInvented(self):
        r=record(); envelope=dict(contract_version=w.CONTRACT,original_turn=r,current_revision=1,read_only=True)
        self.assertEqual(w.response(envelope,'turn',B,'a'*32,r['request']),envelope)
        for change in [lambda d:d['original_turn'].update(request_digest='sha256:'+'0'*64),lambda d:d['original_turn']['outcome'].update(result_digest='sha256:'+'0'*64),lambda d:d['original_turn']['outcome'].update(execution='NOT_STARTED'),lambda d:d['original_turn']['outcome'].update(usage=None,usage_status='NOT_REPORTED'),lambda d:d.update(current_revision=0)]:
            bad=deepcopy(envelope);change(bad)
            with self.assertRaises(WorklistError):w.response(bad,'turn',B,'a'*32)
        with self.assertRaises(WorklistError):w.response(envelope,'turn',B,'a'*32,{**r['request'],'objective':'different intent'})
        bad=deepcopy(r);bad['outcome']=None
        with self.assertRaises(WorklistError):w.turn(bad,B,'a'*32)
        bad['status']='FAILED';w.turn(bad,B,'a'*32)
        h=dict(contract_version=w.CONTRACT,conversation_id='a'*32,scope={k:r['request'][k] for k in ('instance_id','project_id','repository_id')},revision=1,turns=[r],next_cursor=None,consumed_turns=1,maximum_turns=8,retention='PRIVATE_RETAINED_NO_AUTOMATIC_DELETE',read_only=True)
        w.response(h,'history',B,'a'*32);h['turns']*=2
        with self.assertRaises(WorklistError):w.response(h,'history',B,'a'*32)
        h['turns']=[];h['conversation_id']='b'*32
        with self.assertRaises(WorklistError):w.response(h,'history',B,'a'*32)

    def testDependencyReasonValuesAreCheckedAgainstDeclaredAdditionalPropertyType(self):
        from workspace_control.advisory_contract import _check
        schema={'type':'object','maxProperties':8,'additionalProperties':{'type':'string','minLength':20,'maxLength':1000}}
        _check({'candidate-one':'Requires prior authenticated account isolation.'},schema)
        for value in [True,1,None,'short',{'untyped':'map'}]:
            with self.assertRaises(WorklistError):_check({'candidate-one':value},schema)
        with self.assertRaises(WorklistError):_check({str(n):'Requires prior authenticated account isolation.' for n in range(9)},schema)

    def testCatalogSnapshotScopeDigestAndNoFabricatedLinks(self):
        c=catalog();self.assertEqual(w.response(c,'catalog',B),c)
        for modify in [lambda d:d['items'][0].update(title='unrelated'),lambda d:d['items'][0].update(summary='unrelated'),lambda d:d['items'][0].update(definition_digest='sha256:'+'0'*64),lambda d:d['items'][0].update(conversation_id='b'*32),lambda d:d['items'][0].update(mission_id='fabricated'),lambda d:d['items'][0].update(revision=2),lambda d:d.update(next_cursor=3),lambda d:d.update(snapshot_revision='sha256:'+'0'*64)]:
            bad=deepcopy(c);modify(bad)
            with self.assertRaises(WorklistError):w.response(bad,'catalog',B)
        with self.assertRaises(WorklistError):w.response(c,'catalog',B,snapshot='sha256:'+'0'*64)
        invalid=deepcopy(c);invalid['next_cursor']=True
        with self.assertRaises(WorklistError):w.response(invalid,'catalog',B)
        c['next_cursor']=1;w.response(c,'catalog',B,snapshot=c['snapshot_revision'])
        c['items']*=2
        with self.assertRaises(WorklistError):w.response(c,'catalog',B)


if __name__=='__main__':unittest.main()
