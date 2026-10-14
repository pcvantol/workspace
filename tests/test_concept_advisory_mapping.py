"""Actual published input limits; no producer response, model or installed proof."""
import json
import unittest
from copy import deepcopy
from workspace_control.concept_briefing import initial,source
from workspace_control.concept_baseline_mapping import digest
from workspace_control.concept_advisory_mapping import prepare,briefing,peer_digest,AdviceInputTooLong,canonical

class ConceptAdvisoryMappingTests(unittest.TestCase):
    def setUp(self):
        self.concept={'id':'a'*32,'actor_id':'alice','context_id':'own','revision':1,'title':'Een idee 🌱','notes':'Originele 日本語 beschrijving','state':'CONCEPT_NOT_CONFIGURED'}
        self.snapshot=source(self.concept,initial(self.concept))
        self.kw={'instance':'forge-own','dossier':'private-dossier','conversation':'own-conversation','operation':'b'*32,'turn':'c'*32,'expected_revision':0,'role':'BUSINESS','language':'nl','message':'Voor wie is dit? 🌱','transfer_digest':'d'*64}
    def test_exact_ascii_digest_preserves_original_own_utf8_source(self):
        original=deepcopy(self.snapshot);value=prepare(self.snapshot,**self.kw);request=value['request']
        self.assertEqual(request['briefing']['fields']['purpose'],self.concept['notes'])
        self.assertIsNone(request['briefing']['fields']['users']);self.assertIsNone(request['briefing']['fields']['open_questions'])
        self.assertEqual(request['briefing_digest'],peer_digest(request['briefing']))
        self.assertNotEqual(peer_digest(request['briefing']),digest(request['briefing']))
        self.assertEqual(json.loads(canonical(request)),request)
        self.assertEqual(value['request_digest'],peer_digest(request));self.assertEqual(self.snapshot,original)
        self.snapshot['concept']['notes']='Later local edit'
        self.assertEqual(value['own_source'],original)
        self.assertNotIn('actor_id',canonical(request).decode());self.assertNotIn('context_id',canonical(request).decode())
    def test_roles_languages_and_original_ids_are_explicit(self):
        for role,peer in [('BUSINESS','BUSINESS'),('ARCHITECT','ARCHITECTURE')]:
            for language in ['en','nl','de','fr','es']:
                value=prepare(self.snapshot,**dict(self.kw,role=role,language=language))
                self.assertEqual(value['request']['advisor_kind'],peer);self.assertEqual(value['request']['operation_id'],'b'*32)
        for updates in [{'expected_revision':True},{'expected_revision':-1},{'language':'pt'},{'role':'UX'},{'instance':'../x'},{'transfer_digest':'bad'}]:
            with self.assertRaises(ValueError):prepare(self.snapshot,**dict(self.kw,**updates))
    def test_no_silent_truncation_and_complete_request_byte_admission(self):
        with self.assertRaises(AdviceInputTooLong):prepare(self.snapshot,**dict(self.kw,message='x'*4001))
        self.assertEqual(prepare(self.snapshot,**dict(self.kw,message='x'*4000))['request']['message'],'x'*4000)
        for message in ['', 'bad\x00']:
            with self.assertRaises(ValueError):prepare(self.snapshot,**dict(self.kw,message=message))
        long=source(dict(self.concept,notes='n'*2001),initial(dict(self.concept,notes='n'*2001)))
        with self.assertRaises(AdviceInputTooLong):prepare(long,**self.kw)
        fields=initial(self.concept);fields['users']='🌱'*2000;fields['constraints']='🌱'*2000
        with self.assertRaises(AdviceInputTooLong):prepare(source(self.concept,fields),**self.kw)
    def test_closed_source_digest_and_question_text_mapping(self):
        with self.assertRaises(ValueError):briefing(dict(self.snapshot,source_digest='0'*64))
        with self.assertRaises(ValueError):briefing({})
        fields=initial(self.concept);fields['open_questions']=['Welke regio?','Welke termijn?']
        self.assertEqual(briefing(source(self.concept,fields))['fields']['open_questions'],'Welke regio?\nWelke termijn?')
