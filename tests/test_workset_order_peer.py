"""Own order namespace and authority fail closed before any producer write."""
from pathlib import Path
from tempfile import TemporaryDirectory
import json
import unittest
from unittest.mock import patch
from workspace_control.service import initialize, Service
from workspace_control.worklist_peer import WorklistError
from workspace_control import workset_order_contract as wire


class OrderBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'own'; self.root.mkdir(mode=0o700)
        initialize(self.root)
        self.service = Service(self.root); self.addCleanup(self.service.close)
        self.peer = self.service.workset_orders

    def test_order_namespace_is_distinct_and_does_not_admit_read_tokens(self):
        self.assertEqual(self.peer.namespace, 'workset-order')
        for peer in [self.peer, self.service.activities, self.service.worklists, self.service.workset_releases]:
            with self.assertRaises(WorklistError): peer.access('x' * 43)

    def test_unknown_local_actor_is_rejected_without_producer_probe(self):
        with patch('workspace_control.workset_order_peer.request') as request:
            with self.assertRaises(WorklistError):
                with self.peer.gate({'actor_id':'a','workspace_project_id':'p'}, ('other','p')): pass
            request.assert_not_called()

    def test_closed_request_and_error_schema(self):
        for value in [{}, {'contract_version':wire.CONTRACT,'confirm':True}, {'error':{'code':False},'contract_version':wire.CONTRACT}]:
            with self.assertRaises(WorklistError): wire.validate(value, 'request' if 'confirm' in value else 'error')
        wire.validate({'contract_version':wire.CONTRACT,'proposed_order':['a','b']}, 'preview_request')

    def test_future_scope_membership_and_grant_boundaries(self):
        from datetime import datetime,timezone,timedelta
        binding={'forge_instance_id':'i','forge_project_id':'p','repository_id':'r','worksets':[{'workset_id':'w','definition_digest':'sha256:'+'a'*64}], 'permissions':['READ','REORDER'], 'expires_at':(datetime.now(timezone.utc)+timedelta(minutes=5)).isoformat(),'maximum_amendments':2}
        cap={'contract_version':wire.CONTRACT,'scope':{'instance_id':'i','project_id':'p','repository_id':'r'},'worksets':binding['worksets'],'permissions':binding['permissions'],'maximum_amendments':2,'consumed_amendments':0,'remaining_amendments':2,'expires_at':binding['expires_at'],'reorder_supported':True,'required_roles':['business_owner','platform_architect'],'read_only':True}
        self.assertEqual(wire.capability(cap,binding),cap)
        for key,value in [('permissions',['READ']),('worksets',[{'workset_id':'other','definition_digest':'sha256:'+'a'*64}]),('remaining_amendments',3),('required_roles',['business_owner']),('expires_at','2000-01-01T00:00:00Z')]:
            bad={**cap,key:value}
            with self.assertRaises(WorklistError):wire.capability(bad,binding)


if __name__ == '__main__': unittest.main()
