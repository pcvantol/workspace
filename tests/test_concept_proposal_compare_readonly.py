"""Own HTTP read seam for comparison. Source-only peer double, not qualification.

The real qualified R52/native first vertical is separately recorded for plan105.
"""
import unittest
from unittest.mock import patch
import test_concept_baseline_http as fixture
from workspace_control.worklist_peer import WorklistError


class ProposalCompareReadOnlyTests(unittest.TestCase):
    def setUp(self):
        self.fixture=fixture.BaselineHTTPTests('test_actual_own_http_original_intent_readfirst_and_scope')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.addCleanup(self.fixture.tearDown)
        f=self.fixture
        self.operations=['b'*32,'c'*32]
        self.assertEqual(f.request(f.prefix+'/prepare','POST',f.command())[0],200)
        command=f.fields(title='Newer saved source',notes='Second original purpose',expected_revision=1,operation_id='e'*32)
        self.assertEqual(f.request('/v1/project-concepts/'+f.identity,'PATCH',command)[0],200)
        self.assertEqual(f.request(f.prefix+'/prepare','POST',f.command(operation_id=self.operations[1],expected_revision=2))[0],200)
        self.originals=[f.peer.intents.get(('alice','own-context'),f.identity,op) for op in self.operations]

    def test_two_original_GETs_preserve_exact_sources_and_never_prepare(self):
        f=self.fixture
        self.assertEqual(f.request(f.prefix+'/operations')[0],200)
        before_posts=len(f.posts)
        first=f.request(f.prefix+'/operations/'+self.operations[0])
        second=f.request(f.prefix+'/operations/'+self.operations[1])
        self.assertEqual((first[0],second[0]),(200,200))
        self.assertEqual(first[1]['source_revision'],1)
        self.assertEqual(second[1]['source_revision'],2)
        self.assertNotEqual(first[1]['source_product']['name'],second[1]['source_product']['name'])
        self.assertEqual(first[1]['current_revision'],2)
        self.assertEqual(len(f.posts),before_posts)
        self.assertEqual([f.peer.intents.get(('alice','own-context'),f.identity,op) for op in self.operations],self.originals)

    def test_one_denied_or_missing_original_never_substitutes_or_recreates(self):
        f=self.fixture
        original=f.transport
        def denied(binding,method,path,body=None,**kwargs):
            if method=='GET' and self.operations[1] in path:raise WorklistError('DENIED')
            return original(binding,method,path,body,**kwargs)
        with patch('workspace_control.concept_baseline_peer.request',side_effect=denied):
            self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[0])[0],200)
            self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[1])[0],403)
        del f.created[self.operations[1]]
        self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[1])[0],404)
        self.assertEqual(len(f.posts),2)
        self.assertEqual([f.peer.intents.get(('alice','own-context'),f.identity,op) for op in self.operations],self.originals)

    def test_current_actor_grant_and_peer_binding_remain_independent(self):
        f=self.fixture
        self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[0],grant=f.other)[0],404)
        f.service.conversations.revoke_grants('alice','own-context')
        self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[0])[0],403)
        f.grant=f.service.conversations.issue_grant('alice','own-context')
        self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[0])[0],200)
        f.peer.revoke(f.binding['id'])
        self.assertEqual(f.request(f.prefix+'/operations/'+self.operations[1])[0],403)
        self.assertEqual(len(f.posts),2)
