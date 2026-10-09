"""Real own auth/storage/HTTP with explicitly external synthetic producer transport."""
from copy import deepcopy
import unittest
from tests import test_advisory_peer as shared
from tests.test_mission_contract import capability, record, catalog
from workspace_control import mission_contract as w


class MissionPeerTests(unittest.TestCase):
    fixture_wire=w
    fixture_capability=staticmethod(capability)
    fixture_record=staticmethod(record)
    fixture_prefix='/v1/mission-concepts'
    fixture_concept=True
    setUp=shared.AdvisoryPeerTests.setUp
    call=shared.AdvisoryPeerTests.call

    def fixture_catalog(self, conversation):
        value=catalog();items=[]
        for turn in self.turns.values():
            if turn['request']['conversation_id'] != conversation:continue
            item=deepcopy(value['items'][0]);item['conversation_id']=conversation
            item['conversation_revision']=self.revision;item['source_turn_id']=turn['request']['turn_id']
            item['context_revision']=turn['request']['context_revision'];item['definition']=turn['outcome']['output']['definition']
            item['definition_digest']=w.digest(item['definition']);item['title']=item['definition']['title'];item['summary']=item['definition']['expected_result']
            items=[item]
        value['items']=items;value['snapshot_revision']=w.digest(items)
        return value

    def fixture_resolve(self, actor, body):
        scope={'instance_id':'forge-one','project_id':'project-one','repository_id':'repo-one'}
        principal='forge-one:'+actor
        binding={'principal_reference':principal,'scope':scope,
            'workspace_conversation_id':body['workspace_conversation_id'],
            'workspace_draft_id':body['workspace_draft_id'],
            'conversation_id':getattr(self,'producer_conversations',self.conversations)[actor],
            'binding_key':w.digest([principal,scope,body['workspace_conversation_id'],body['workspace_draft_id']])}
        return dict(contract_version=w.CONTRACT,operation_id=body['operation_id'],binding=binding,additional_model_calls=0,grant_issued=False,budget_reset=False)

    def testResolverAuthorizesBothOwnReferencesBeforeForwardAndRetainsExactProducerBinding(self):
        c=self.conversations['alice'];path=self.fixture_prefix+'/resolve'
        body=dict(contract_version=w.CONTRACT,operation_id='resolve-original',workspace_conversation_id=c,workspace_draft_id=c)
        status,value=self.call(path,'POST',body);self.assertEqual(status,200,value)
        self.assertEqual(value['binding']['conversation_id'],c)
        self.assertFalse(value['budget_reset']);self.assertFalse(value['grant_issued'])
        self.assertEqual(self.call(path,'POST',body)[1],value)
        self.assertFalse(self.turns)
        before=sum(method=='POST' for method,_ in self.requests)
        for changed in [dict(body,workspace_conversation_id=self.conversations['bob']),dict(body,workspace_draft_id=self.conversations['bob']),dict(body,workspace_draft_id='not-a-workspace-id'),dict(body,principal_id='forged')]:
            self.assertIn(self.call(path,'POST',changed)[0],(400,403))
        self.assertEqual(sum(method=='POST' for method,_ in self.requests),before)
        self.assertEqual(self.call(path,'POST',body,actor='bob')[0],403)
        self.ws.conversations.revoke_grants('alice','ws-project')
        self.assertEqual(self.call(path,'POST',body)[0],403)
        self.assertEqual(sum(method=='POST' for method,_ in self.requests),before)

    def testResolverDraftRevocationDuringBodyReadForwardsNoResolution(self):
        import socket,http.client,json
        c=self.conversations['alice'];body=dict(contract_version=w.CONTRACT,operation_id='resolve-revoked',workspace_conversation_id=c,workspace_draft_id=c)
        payload=json.dumps(body).encode();self.body_authorized.clear()
        headers={'Host':'127.0.0.1:'+str(self.http.server_port),'Authorization':'Bearer '+self.ws.token,'X-Workspace-Instance':self.ws.instance_id,'X-Workspace-Draft-Grant':self.drafts['alice'],'X-Workspace-Advisory-Grant':self.client['alice'],'Content-Type':'application/json','Content-Length':str(len(payload))}
        with socket.create_connection(self.http.server_address,timeout=5) as sock:
            sock.sendall(('POST '+self.fixture_prefix+'/resolve HTTP/1.1\r\n'+''.join(k+': '+v+'\r\n' for k,v in headers.items())+'\r\n').encode())
            self.assertTrue(self.body_authorized.wait(3))
            self.ws.revoke_conversation_grants('alice','ws-project');sock.sendall(payload)
            response=http.client.HTTPResponse(sock);response.begin();self.assertEqual(response.status,403);response.read();response.close()
        self.assertTrue(all(method=='GET' for method,_ in self.requests))
        self.assertFalse(self.turns)

    def testProducerIDsRemainSeparateFromOwnDraftsAndLegacyAdviceAccess(self):
        import json
        self.producer_conversations={**self.conversations,'alice':'producer-slot-a'}
        proof=json.loads(self.proof['alice'].read_text());proof['conversation_ids']=['producer-slot-a']
        self.proof['alice'].write_text(json.dumps(proof))
        original=self.ws.mission_concepts.access(self.client['alice']);self.ws.revoke_mission(original['id'])
        private=self.root/'separate-mission-client'
        self.ws.provision_mission('alice','ws-project',self.endpoint,str(self.proof['alice']),str(self.root/'alice.forge'),str(private))
        token=private.read_text().strip();headers={'X-Workspace-Advisory-Grant':token}
        status,metadata=self.call(self.fixture_prefix+'/access',headers=headers)
        self.assertEqual(status,200,metadata);self.assertEqual(metadata['conversation_ids'],['producer-slot-a'])
        self.assertEqual(self.call('/v1/advisory/access',headers=headers)[0],403)
        c=self.conversations['alice'];body=dict(contract_version=w.CONTRACT,operation_id='separate-pair',workspace_conversation_id=c,workspace_draft_id=c)
        status,resolved=self.call(self.fixture_prefix+'/resolve','POST',body,headers=headers)
        self.assertEqual(status,200,resolved);self.assertEqual(resolved['binding']['conversation_id'],'producer-slot-a')
        self.assertEqual(resolved['binding']['workspace_conversation_id'],c)
        before=sum(method=='POST' for method,_ in self.requests)
        foreign=dict(body,workspace_draft_id=self.conversations['bob'])
        self.assertEqual(self.call(self.fixture_prefix+'/resolve','POST',foreign,headers=headers)[0],403)
        self.assertEqual(sum(method=='POST' for method,_ in self.requests),before)
        self.assertEqual(self.call(self.fixture_prefix+'/producer-slot-b?cursor=0&limit=4',headers=headers)[0],403)
        self.assertTrue((self.root/'mission-bindings.json').exists())
        self.assertFalse((self.root/'advisory-bindings.json').exists())
        self.assertFalse(self.turns)

    def testLocalOwnerMissionBindingIssueAndRevokeRemainBoundedAndPrintNoSecrets(self):
        import json,io
        from contextlib import redirect_stdout
        from workspace_control.cli import main
        existing=self.ws.mission_concepts.access(self.client['alice']);self.ws.revoke_mission(existing['id'])
        private=self.root/'cli-mission-client'
        args=['--root',str(self.root),'mission-bind-issue','--actor','alice','--project','ws-project','--forge-endpoint',self.endpoint,'--forge-grant-receipt-file',str(self.proof['alice']),'--forge-token-file',str(self.root/'alice.forge'),'--client-token-file',str(private)]
        output=io.StringIO()
        with redirect_stdout(output):self.assertEqual(main(args),0)
        issued=json.loads(output.getvalue());self.assertNotIn(self.owner_tokens['alice'],output.getvalue())
        self.assertNotIn(private.read_text().strip(),output.getvalue())
        with redirect_stdout(io.StringIO()):self.assertEqual(main(['--root',str(self.root),'mission-bind-revoke','--binding-id',issued['binding_id']]),0)
        self.assertEqual(self.call(self.fixture_prefix+'/access',headers={'X-Workspace-Advisory-Grant':private.read_text().strip()})[0],403)
        with self.assertRaises(ValueError):self.ws.provision_mission('alice','foreign',self.endpoint,str(self.proof['alice']),str(self.root/'alice.forge'),str(self.root/'refused'))
        self.assertFalse(self.turns)

    def testActualOwnScopeRoutesAndNoReadGeneration(self):
        c=self.conversations['alice'];base=self.fixture_prefix+'/'+c
        self.assertEqual(self.call(self.fixture_prefix+'/access')[1]['actor_id'],'alice')
        self.assertFalse(self.call(self.fixture_prefix+'/capability')[1]['approval_supported'])
        self.assertEqual(self.call(self.fixture_prefix+'/catalog')[1]['items'],[])
        self.assertTrue(all(method=='GET' for method,_ in self.requests))
        r=record()['request'];r['conversation_id']=c
        status,value=self.call(base+'/turns','POST',r);self.assertEqual(status,200,value)
        self.assertEqual(self.call(base+'/turns/turn-one')[0],200)
        self.assertEqual(self.call(base+'?cursor=0&limit=4')[0],200)
        self.assertEqual(self.call(base+'/context')[0],200)
        status,value=self.call(self.fixture_prefix+'/catalog');self.assertEqual(status,200,value)
        self.assertEqual(value['items'][0]['definition']['title'],'Invoice portal')
        self.assertFalse(value['items'][0]['approval_supported']);self.assertIsNone(value['items'][0]['mission_id'])
        self.assertEqual(sum(method=='POST' for method,_ in self.requests),1)
        self.assertEqual(self.call(base,actor='bob')[0],403)
        self.assertEqual(self.call(base,headers={'X-Workspace-Advisory-Grant':self.client['bob']})[0],403)
        for suffix in ['/catalog?limit=5','/catalog?cursor=-1','/catalog?cursor=0&cursor=1','/catalog?snapshot_revision=bad','/capability?source_id=one','/%2e%2e']:
            self.assertEqual(self.call(self.fixture_prefix+suffix)[0],400,suffix)
        self.assertEqual(self.call(self.fixture_prefix+'/catalog?snapshot_revision=sha256:'+('0'*64))[0],503)
        cancel=dict(contract_version=w.CONTRACT,expected_revision=1,request_digest=w.digest(r))
        self.assertFalse(self.call(base+'/turns/turn-one/cancel','POST',cancel)[1]['provider_stopped'])

    def testOriginalContentsAndCurrentAuthorityRemainRequired(self):
        c=self.conversations['alice'];base=self.fixture_prefix+'/'+c
        r=record()['request'];r['conversation_id']=c
        self.assertEqual(self.call(base+'/turns','POST',r)[0],200)
        self.bad=True;self.assertEqual(self.call(base+'/turns/turn-one')[0],503);self.bad=False
        original=self.turns['turn-one']['outcome']['output']['definition'];original['title']='changed'
        self.assertEqual(self.call(self.fixture_prefix+'/catalog')[0],503)
        self.error=403;self.assertEqual(self.call(self.fixture_prefix+'/catalog')[0],403)
        self.error=409;self.assertEqual(self.call(self.fixture_prefix+'/capability')[0],409)


if __name__=='__main__':unittest.main()
