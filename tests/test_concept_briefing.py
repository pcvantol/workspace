import unittest
from copy import deepcopy
from workspace_control.concept_briefing import initial, source, changes, validate

class ConceptBriefingTests(unittest.TestCase):
    def setUp(self):
        self.concept={'id':'a'*32,'actor_id':'alice','context_id':'own','revision':1,'title':'Idee 🌱','notes':'Originele 日本語 tekst','state':'CONCEPT_NOT_CONFIGURED'}
        self.before=initial(self.concept)
    def test_source_keeps_complete_notes_and_unknowns(self):
        self.assertEqual(self.before['purpose'],self.concept['notes'])
        self.assertEqual(self.before['users'],'')
        first=source(self.concept,self.before)
        self.concept['revision']=2
        self.assertNotEqual(first['source_digest'],source(self.concept,self.before)['source_digest'])
        self.concept['notes']='🌱'*10000
        value=source(self.concept,initial(self.concept))
        self.assertEqual(value['concept']['notes'],self.concept['notes'])
        self.assertEqual(value['fields']['purpose'],'')
    def test_exact_changes_do_not_mutate_or_invent(self):
        old=deepcopy(self.before)
        result=changes(self.before,[{'field':'users','before':'','after':'Vrijwilligers','reason':'De gebruiker noemt vrijwilligers.'},{'field':'open_questions','before':[],'after':['Welke regio?'],'reason':'Nog onbekend.'}])
        self.assertEqual(result['users'],'Vrijwilligers');self.assertEqual(result['constraints'],'')
        self.assertEqual(self.before,old)
        for proposal in [[],[{}],[{'field':'users','before':'wrong','after':'x','reason':'r'}],[{'field':'users','before':'','after':'','reason':'r'}],[{'field':'repo','before':'','after':'x','reason':'r'}]]:
            with self.assertRaises(ValueError):changes(self.before,proposal)
        change={'field':'users','before':'','after':'x','reason':'r'}
        with self.assertRaises(ValueError):changes(self.before,[change,change])
    def test_closed_bounded_text_and_question_schema(self):
        for bad in [None,{},dict(self.before,extra=True),dict(self.before,name=''),dict(self.before,purpose='x'*4097),dict(self.before,users='bad\x00'),dict(self.before,open_questions='q'),dict(self.before,open_questions=['q']*33),dict(self.before,open_questions=['q','q']),dict(self.before,open_questions=['']),dict(self.before,open_questions=['x'*1025])]:
            with self.assertRaises(ValueError):validate(bad)
        self.assertEqual(validate(self.before),self.before)
