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
            'conversation_id':self.conversations[actor],
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
