"""Source-only consumer contracts; fixtures are never installed/GUI evidence."""
import copy
import json
from pathlib import Path
import unittest
from workspace_control import execution_progress_wire as w


def sample(schema):
    if 'enum' in schema:return schema['enum'][0]
    if 'const' in schema:return schema['const']
    for union in ('oneOf','anyOf'):
        if union in schema:return sample(schema[union][0])
    kind=schema.get('type')
    if isinstance(kind,list):kind=kind[0]
    if kind=='object':return {k:sample(schema['properties'][k]) for k in schema.get('required',[])}
    if kind=='array':return [sample(schema.get('items',{})) for _ in range(schema.get('minItems',0))]
    if kind=='integer':return schema.get('minimum',0)
    if kind=='boolean':return False
    if kind=='null':return None
    if schema.get('format')=='date-time':return '2026-10-15T00:00:00Z'
    return 'identifier'


def fixture(run=None):
    s=w.SCHEMA['oneOf'][0];v=sample(s)
    selection={'project_id':'alpha','authority_repository_id':'alpha','repository_ids':['alpha'],'mission_ids':['mission'],'producer_ids':['forge']}
    b={'instance_id':'ep-instance','selection':selection,'producer_id':'forge'}
    v.update(instance_id=b['instance_id'],producer_version='2.3.122',snapshot_id='a'*64,selected_mission_id='mission',selected_run_id=run,selection=selection,completeness='EXACT_RUN' if run else 'COMPLETE_WITHIN_KNOWN_SCOPED_SUBMISSIONS',business_mutations=0)
    r=sample(s['properties']['records']['items']);r.update(submission_id='sub',project_id='alpha',repository_id='alpha',producer_id='forge',mission_id='mission',mission_revision='1',engineering_action_id='ea',correlation_id='correlation',run_id=run,description=None,description_status='NOT_RECORDED')
    r['result']['forge_mission_acceptance']='NOT_OWNED_BY_EP';r['result']['qualification']={'required_validation_state':'UNAVAILABLE','run_qualification':'UNAVAILABLE'}
    v['records']=[r]
    return v,b


class ExecutionProgressWireTests(unittest.TestCase):
    def reject(self,v,b,code='INVALID_RESPONSE',run=None,expected=None):
        with self.assertRaises(w.ProgressError) as c:w.validate(v,b,'mission',run,expected)
        self.assertEqual(c.exception.code,code)

    def test_actual_schema_digest_and_closed_surface(self):
        self.assertEqual(w.SCHEMA_SHA256,'ac4ccc1c43c02742dc6ad15e642fadc6456844f8a1a3e7425275f67d247b7d89')
        v,b=fixture();self.assertIs(w.validate(v,b,'mission'),v)
        v['prompt']='private';self.reject(v,b)

    def test_all_scope_dimensions_are_exact(self):
        for field in ('instance_id','selected_mission_id','selected_run_id'):
            v,b=fixture();v[field]='foreign';self.reject(v,b,'DENIED')
        for field in ('project_id','authority_repository_id','repository_ids','mission_ids','producer_ids'):
            v,b=fixture();v=copy.deepcopy(v);v['selection'][field]=['foreign'] if isinstance(v['selection'][field],list) else 'foreign';self.reject(v,b,'DENIED')
        for field in ('project_id','repository_id','producer_id','mission_id'):
            v,b=fixture();v['records'][0][field]='foreign';self.reject(v,b,'DENIED')

    def test_snapshot_is_opaque_exact_and_never_ordered(self):
        v,b=fixture('run');w.validate(v,b,'mission','run','a'*64)
        self.reject(v,b,'SNAPSHOT_CONFLICT','run','b'*64)
        for value in ('1','A'*64,'../x',None):
            with self.assertRaises(w.ProgressError):w.snapshot(value)
        self.assertEqual(w.snapshot('0'*64),'0'*64)

    def test_technical_complete_is_never_mission_acceptance(self):
        v,b=fixture();v['records'][0]['result']['technical_outcome']='COMPLETE';w.validate(v,b,'mission')
        v['records'][0]['result']['forge_mission_acceptance']='ACCEPTED';self.reject(v,b)
        v,b=fixture();v['business_mutations']=False;self.reject(v,b)
        v['business_mutations']=1;self.reject(v,b)

    def test_retries_and_repeated_original_history_preserved(self):
        v,b=fixture('run');r=v['records'][0];r['progress']['history']=[{'phase':'EXECUTE_AGENT','recorded_at':'2026-10-15T00:00:00Z','responsible_role':'IMPLEMENTATION_AGENT','wait_reason':'NOT_RECORDED'}]*2
        self.assertEqual(len(w.validate(v,b,'mission','run')['records'][0]['progress']['history']),2)
        v['records'].append(copy.deepcopy(r));self.reject(v,b,run='run')
        v,b=fixture();v['records'].append(copy.deepcopy(v['records'][0]));self.reject(v,b)
        v,b=fixture();v['records'][0]['run_id']='same';other=copy.deepcopy(v['records'][0]);other['submission_id']='other';v['records'].append(other);self.reject(v,b)

    def test_run_filter_and_empty_are_different(self):
        v,b=fixture('run');v['records'][0]['run_id']='other';self.reject(v,b,'DENIED','run')
        v,b=fixture();v['records']=[];w.validate(v,b,'mission')
        v['completeness']='EXACT_RUN';self.reject(v,b)
        v,b=fixture('run');v['records']=[];self.reject(v,b,run='run')

    def test_private_description_is_never_published(self):
        for text in ('/Users/person/file','folder\\private','Bearer secret','api_key:secret','password=secret','sk-example','line\nprivate'):
            v,b=fixture();v['records'][0].update(description=text,description_status='AVAILABLE');self.reject(v,b,'UNSAFE_SOURCE')
        v,b=fixture();v['records'][0].update(description='Safe registered description',description_status='AVAILABLE');w.validate(v,b,'mission')
        v['records'][0]['description_status']='WITHHELD_PRIVACY';self.reject(v,b)
        v['records'][0]['description']=None;w.validate(v,b,'mission')

    def test_limits_unknown_phase_and_producer_are_explicit(self):
        v,b=fixture();v['producer_version']='2.3.121';self.reject(v,b,'UNSUPPORTED')
        v,b=fixture();v['records'][0]['progress']['current_phase']='FUTURE';self.reject(v,b)
        v['records'][0]['progress']['current_phase']='UNAVAILABLE';w.validate(v,b,'mission')
        v['records']=v['records']*101;self.reject(v,b)

    def test_qualified_cannot_override_noncomplete_execution(self):
        v,b=fixture();v['records'][0]['result']['qualification']['run_qualification']='QUALIFIED';v['records'][0]['result']['technical_outcome']='FAILED';self.reject(v,b)
        v['records'][0]['result']['technical_outcome']='COMPLETE';w.validate(v,b,'mission')

    def test_non_snapshot_conflicts_cannot_request_snapshot_recovery(self):
        for original,code in [('PROGRESS_SNAPSHOT_CONFLICT','SNAPSHOT_CONFLICT'),('PROGRESS_SOURCE_CONFLICT','SNAPSHOT_CONFLICT'),('PROGRESS_QUALIFICATION_CONFLICT','SOURCE_CORRUPT'),('PROGRESS_PROVENANCE_CONFLICT','SOURCE_CORRUPT'),('PROGRESS_RECORD_LIMIT','UNAVAILABLE'),('PROGRESS_ROOT_UNAVAILABLE','SOURCE_CORRUPT'),('PROGRESS_UNKNOWN','INVALID_RESPONSE')]:
            with self.assertRaises(w.ProgressError) as c:w.error({'error':original},409)
            self.assertEqual(c.exception.code,code)

    def test_errors_and_input_never_collapse_to_empty(self):
        for status,code in ((400,'INVALID_REQUEST'),(401,'DENIED'),(403,'DENIED'),(404,'RUN_NOT_FOUND'),(409,'SNAPSHOT_CONFLICT'),(422,'UNSUPPORTED'),(500,'SOURCE_CORRUPT'),(503,'UNAVAILABLE')):
            with self.assertRaises(w.ProgressError) as c:w.error({'error':'PROGRESS_SNAPSHOT_CONFLICT' if status==409 else 'PROGRESS_SCOPE_MISMATCH'},status)
            self.assertEqual((c.exception.code,c.exception.status),(code,status))
        for value in ({'error':'X','token':'private'},{},None):
            with self.assertRaises(w.ProgressError):w.error(value,401)
        with self.assertRaises(w.ProgressError):w.error({'error':'X'},302)
        for value in ('','a/b','../x',None):
            with self.assertRaises(w.ProgressError):w.identifier(value)
        self.assertEqual(w.identifier('mission-1'),'mission-1')
        self.assertIsNotNone(w.date('2026-10-15T00:00:00Z'))
        for value in ('2026-10-15',None,'x'):
            with self.assertRaises(w.ProgressError):w.date(value)


if __name__=='__main__':unittest.main()
