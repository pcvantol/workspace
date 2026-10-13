import unittest
from copy import deepcopy
from workspace_control.concept_baseline_mapping import map_concept,provisional_references,DescriptionRequired,digest

class ConceptBaselineMappingTests(unittest.TestCase):
    def setUp(self):
        self.concept={'id':'a'*32,'actor_id':'alice','context_id':'own-context','revision':1,'title':'Een idee 🌱','notes':'Originele beschrijving 日本語','state':'CONCEPT_NOT_CONFIGURED'}
        self.references=provisional_references()
    def mapped(self, **kwargs):return map_concept(self.concept,('alice','own-context'),self.references,**kwargs)
    def test_exact_declared_text_and_honest_unknowns(self):
        original=deepcopy(self.concept);value=self.mapped();body=value['input']
        self.assertEqual(body['product']['name'],self.concept['title']);self.assertEqual(body['product']['purpose'],self.concept['notes'])
        self.assertEqual(value['unknown_fields'],['users','non_goals','constraints']);self.assertEqual(len(body['product']['open_questions']),3)
        self.assertEqual(body['identity']['status'],'PROVISIONAL_REFERENCE');self.assertEqual(body['identity']['repository_id'],body['identity']['authority_repository_id'])
        self.assertEqual(body['document_language'],'en');self.assertEqual(self.concept,original);self.assertEqual(value,self.mapped())
        self.assertTrue(all(item['owner']=='USER_DECLARED' for item in body['source_references']))
        self.assertEqual(body['source_references'][0]['digest'],digest(value['source']))
    def test_long_notes_require_explicit_choice_and_preserve_full_source(self):
        self.concept['notes']='n'*4097
        with self.assertRaises(DescriptionRequired):self.mapped()
        value=self.mapped(description='Chosen short purpose');self.assertEqual(value['source']['notes'],'n'*4097);self.assertEqual(value['input']['product']['purpose'],'Chosen short purpose')
        self.concept['notes']='n'*4096;self.assertEqual(self.mapped()['input']['product']['purpose'],'n'*4096)
        with self.assertRaises(ValueError):self.mapped(description='n'*4097)
    def test_scope_revision_content_and_choice_each_bind(self):
        first=self.mapped();self.concept['revision']=2;second=self.mapped();self.assertNotEqual(first['source_digest'],second['source_digest'])
        self.concept['notes']='Changed';self.assertNotEqual(second['source_digest'],self.mapped()['source_digest'])
        selected=self.mapped(description='Explicit other purpose');self.assertNotEqual(selected['input_digest'],self.mapped()['input_digest'])
        with self.assertRaises(PermissionError):map_concept(self.concept,('bob','own-context'),self.references)
        with self.assertRaises(PermissionError):map_concept(self.concept,('alice','other-context'),self.references)
    def test_empty_unknown_invalid_and_random_identity_limits(self):
        self.concept['notes']='';value=self.mapped();self.assertIn('purpose',value['unknown_fields']);self.assertEqual(len(value['input']['product']['open_questions']),4)
        self.assertNotEqual(self.references,provisional_references())
        for key,value in [('revision',True),('revision',0),('id','../path'),('state','READY'),('title',''),('notes','x\x00')]:
            source=deepcopy(self.concept);source[key]=value
            with self.assertRaises(ValueError):map_concept(source,('alice','own-context'),self.references)
        for references in [dict(self.references,unexpected='extra'),dict(self.references,project_id='/tmp/private'),dict(self.references,owner_reference='')]:
            with self.assertRaises(ValueError):map_concept(self.concept,('alice','own-context'),references)
        with self.assertRaises(ValueError):self.mapped(description='')
