"""Separate finite release scope is never inferred from chat/read/hold access."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import unittest

from workspace_control import workset_release_contract as wire
from workspace_control.worklist_peer import WorklistError

BINDING = {'forge_instance_id': 'forge-instance', 'forge_project_id': 'forge-project',
           'repository_id': 'repository', 'actor_id': 'actor'}
SUBJECT = {'candidate_id': 'candidate-a', 'subject_revision': 'sha256:' + 'a' * 64}


def cap():
    return {'contract_version': wire.CONTRACT,
            'scope': {'instance_id': 'forge-instance', 'project_id': 'forge-project', 'repository_id': 'repository'},
            'principal_id': 'actor', 'permissions': ['READ', 'RELEASE', 'DISARM'], 'subjects': [deepcopy(SUBJECT)],
            'limits': {'maximum_releases': 2, 'maximum_activations': 2},
            'expires_at': (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
            'release_supported': True, 'disarm_supported': True, 'read_only': True, 'additional_model_calls': 0}


def selected(c):
    return {'contract_version': wire.CONTRACT, 'subjects': [deepcopy(SUBJECT)], 'expires_at': c['expires_at'],
            'maximum_activations': 1, 'progression_mode': 'continuous'}


class WorksetReleaseContractTests(unittest.TestCase):
    def testCurrentFiniteCapabilityAndExactProjectActorScope(self):
        c = cap()
        self.assertEqual(wire.capability(c, BINDING), c)
        for mutate in [lambda v: v.update(principal_id='foreign'),
                       lambda v: v['scope'].update(project_id='foreign'),
                       lambda v: v.update(expires_at='2020-01-01T00:00:00Z'),
                       lambda v: v['limits'].update(maximum_activations=True),
                       lambda v: v.update(subjects=v['subjects'] * 2),
                       lambda v: v.update(permissions=['READ']),
                       lambda v: v.update(permissions=['READ', 'READ']),
                       lambda v: v.update(execution_ready=True)]:
            with self.subTest(mutation=mutate):
                bad = deepcopy(c); mutate(bad)
                with self.assertRaises(WorklistError): wire.capability(bad, BINDING)

    def testSelectionNeverAddsSubjectsOrWidensExistingBounds(self):
        c = cap(); s = selected(c)
        self.assertEqual(wire.selection(s, c), s)
        for mutate in [lambda v: v['subjects'][0].update(candidate_id='unapproved-c'),
                       lambda v: v.update(maximum_activations=3),
                       lambda v: v.update(subjects=v['subjects'] * 2),
                       lambda v: v.update(expires_at=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat())]:
            bad = deepcopy(s); mutate(bad)
            with self.assertRaises(WorklistError): wire.selection(bad, c)

    def testReleaseAndDisarmHaveClosedDifferentConfirmationRequirements(self):
        c = cap()
        request = {'contract_version': wire.CONTRACT, 'operation_id': 'release-operation',
                   'intent': 'release', 'selection': selected(c), 'package_digest': 'sha256:' + 'b' * 64,
                   'confirm': True, 'expected_revision': None}
        self.assertEqual(wire.command(request, BINDING, c), request)
        for mutate in [lambda v: v.update(confirm=False), lambda v: v.update(confirm=1),
                       lambda v: v.update(expected_revision=1), lambda v: v.update(intent='hold'),
                       lambda v: v.update(intent='disarm'), lambda v: v.update(admin=True)]:
            bad = deepcopy(request); mutate(bad)
            with self.assertRaises(WorklistError): wire.command(bad, BINDING, c)
        request.update(intent='disarm', expected_revision=2)
        self.assertEqual(wire.command(request, BINDING, c), request)
        request['expected_revision'] = True
        with self.assertRaises(WorklistError): wire.command(request, BINDING, c)

class WorksetReleasePreparedTests(unittest.TestCase):
    def setUp(self):
        import json
        from pathlib import Path
        self.value = json.loads((Path(__file__).parent/'fixtures/workset-release-source/prepared.json').read_text())
        packet = self.value['package']; s = packet['scope']
        self.binding = {'forge_instance_id': s['instance_id'], 'forge_project_id': s['project_id'],
                        'repository_id': s['repository_id'], 'actor_id': packet['principal_reference'].split(':')[-1]}

    def testProductPacketMatchesExactScopeSelectionDecisionsAndSemanticKey(self):
        packet = self.value['package']; selection = packet['selection']
        self.assertEqual(wire.prepared(self.value, self.binding, selection), self.value)
        for mutate in [lambda v: v.update(package_digest='sha256:'+'0'*64),
                       lambda v: v.update(gaps=[{'code':'PREDECESSOR_NOT_SELECTED','candidate_id':'missing'}]),
                       lambda v: v['package']['definition']['members'][1].update(dependencies=[]),
                       lambda v: v['package']['subjects'][0]['source'].update(project_id='foreign'),
                       lambda v: v['package']['subjects'][0]['candidate_decisions']['business'].update(kind='ARCHITECTURE')]:
            bad = deepcopy(self.value); mutate(bad)
            with self.assertRaises(WorklistError): wire.prepared(bad, self.binding, selection)

    def testActualNativeOperationHasOriginalReceiptAndIndependentlyVerifiedCurrent(self):
        import json
        from pathlib import Path
        value=json.loads((Path(__file__).parent/'fixtures/workset-release-source/operation-released.json').read_text())
        request=value['original_request']
        self.assertEqual(wire.operation(value,self.binding,expected=request),value)
        for mutate in [lambda v: v.update(operation_id='foreign-operation'),
                       lambda v: v['original_receipt'].update(candidate_mission_ids=['different-mission']),
                       lambda v: v['original_request'].update(confirm=False),
                       lambda v: v.update(package_digest='sha256:'+'0'*64),
                       lambda v: v.update(state='PENDING')]:
            bad=deepcopy(value);mutate(bad)
            with self.assertRaises(WorklistError):wire.operation(bad,self.binding,expected=request)

    def testApprovedMissionAndDisplayedDefinitionCannotDiverge(self):
        for target, key, value in [('mission', 'effect_policy', None),
                                   ('mission', 'title', 'Unapproved'),
                                   ('definition', 'expected_result', 'Unapproved result'),
                                   ('definition', 'title', 'Unapproved title'),
                                   ('planning', 'provenance_revision', 'sha256:'+'0'*64)]:
            bad=deepcopy(self.value); packet=bad['package']; subject=packet['subjects'][0]
            subject[target][key]=value
            packet['definition']['members'][0]['mission']=deepcopy(subject['mission'])
            packet['definition']['members'][0]['planning']=deepcopy(subject['planning'])
            with self.assertRaises(WorklistError): wire._subject_proofs(packet,self.binding)

    def testCurrentMissionInstallationAndRevisionJoin(self):
        import json
        from pathlib import Path
        value=json.loads((Path(__file__).parent/'fixtures/workset-release-source/operation-released.json').read_text())
        for mutate in [lambda v:v['original_receipt'].update(applied_revision=999),
                       lambda v:v['frozen_package']['operator_binding'].update(installation_id='foreign')]:
            bad=deepcopy(value);mutate(bad)
            with self.assertRaises(WorklistError):wire.operation(bad,self.binding)
        bad=deepcopy(value);bad['current']['items'][0]['mission_id']='unrelated-mission'
        with self.assertRaises(WorklistError):wire.operation(bad,self.binding)

    def testCanonicalUnicodePlanningAndMissingEvidence(self):
        # Declared wire regression transformation, never installed approval evidence.
        bad=deepcopy(self.value);packet=bad['package'];subject=packet['subjects'][0]
        subject['planning']['human_gates']=['dépôt approuvé 😀']
        packet['definition']['members'][0]['planning']=deepcopy(subject['planning'])
        packet['definition']['members'][0]['progression_policy']['higher_scope_obligations']=subject['planning']['human_gates']
        for role,receipt in subject['candidate_decisions'].items():
            receipt['canonical_decision']['gates']=subject['planning']['human_gates']
            if role=='architecture':receipt['canonical_decision']['evidence']['planning_digest']=wire._canonical(subject['planning'])
            receipt['canonical_decision_digest']=wire.digest(receipt['canonical_decision'])
        wire._subject_proofs(packet,self.binding)
        receipt=subject['candidate_decisions']['architecture']
        receipt['canonical_decision']['evidence'].pop('planning_digest')
        receipt['canonical_decision_digest']=wire.digest(receipt['canonical_decision'])
        with self.assertRaises(WorklistError):wire._subject_proofs(packet,self.binding)

    def testDependencyBindingsMustMatchApprovedPlanning(self):
        bad=deepcopy(self.value);packet=bad['package']
        packet['subjects'][1]['dependency_bindings']=[]
        packet['definition']['members'][1]['dependencies']=[]
        with self.assertRaises(WorklistError):wire._subject_proofs(packet,self.binding)

    def testSelectedPredecessorExactRevisionAndSourceObjectJoin(self):
        for key, invalid in [('subject_revision', 'sha256:'+'0'*64), ('object_id', 'different-object')]:
            bad=deepcopy(self.value)
            bad['package']['subjects'][1]['dependency_bindings'][0][key]=invalid
            bad['package_digest']=wire.digest(bad['package'])
            with self.assertRaises(WorklistError):
                wire.prepared(bad,self.binding,bad['package']['selection'])

    def testRehashedCurrentDependenciesAndOrderMustMatchFrozenMembership(self):
        import json
        from pathlib import Path
        from workspace_control.worklist_contract import snapshot_digest
        value=json.loads((Path(__file__).parent/'fixtures/workset-release-source/operation-released.json').read_text())
        for mutation in ('dependencies', 'order'):
            bad=deepcopy(value)
            if mutation=='dependencies':bad['current']['items'][1]['dependencies']=[]
            else:
                bad['current']['items'][0]['committed_order']=1
                bad['current']['items'][1]['committed_order']=0
                bad['current']['items'][1]['dependencies']=[]
            bad['current']['snapshot_revision']=snapshot_digest(bad['current'])
            with self.assertRaises(WorklistError):wire.operation(bad,self.binding)

    def testRound4BlockedDependencyMatrixAndCoherentlyOmittedOrWrongGaps(self):
        import json
        from pathlib import Path
        matrix=json.loads((Path(__file__).parent/'fixtures/workset-release-unit/dependency-matrix.json').read_text())
        for name,value in matrix.items():
            with self.subTest(valid_packet=name):
                result=wire.prepared(value,self.binding,value['package']['selection'])
                self.assertEqual(result['release_supported'],name=='valid')
            if name=='valid':continue
            for mutation in ('omitted','wrong_candidate','wrong_code'):
                bad=deepcopy(value)
                if mutation=='omitted':
                    bad['package']['gaps']=[];bad['release_supported']=True
                elif mutation=='wrong_candidate':
                    bad['package']['gaps'][0]['candidate_id']=next(s['candidate_id'] for s in value['package']['subjects'] if s['dependency_bindings'])
                else:bad['package']['gaps'][0]['code']='ANOTHER_WORKSET_ARMED'
                bad['gaps']=deepcopy(bad['package']['gaps'])
                bad['package_digest']=wire.digest(bad['package'])
                with self.subTest(invalid_packet=(name,mutation)):
                    with self.assertRaises(WorklistError):
                        wire.prepared(bad,self.binding,bad['package']['selection'])
