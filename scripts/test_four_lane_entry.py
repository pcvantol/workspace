"""Offline lane-entry tests; no Workspace product or installed proof."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    return json.loads((ROOT / 'docs' / name).read_text(encoding='utf-8'))


class FourLaneEntryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.http = load('WORKSPACE_HTTP_API_V1_DAG.json')
        cls.package = load('WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json')

    def test_single_product_lane_and_same_assignment(self):
        for graph in (self.http, self.package):
            entry = graph['lane_allocation']
            self.assertEqual(graph['owner'], 'workspace')
            self.assertEqual(entry['lane'], 'LANE_4')
            self.assertEqual(entry['register'], 'https://github.com/pcvantol/forge/issues/208')
            self.assertEqual(entry['assignment_id'], 'L4-WORKSPACE-SERVER-READONLY-V1-20261001')
            self.assertFalse(entry['selection_is_implementation_evidence'])
            self.assertFalse(entry['current_installer_release_dependency'])
            self.assertTrue(entry['existing_dependency_and_external_evidence_gates_unchanged'])
            self.assertTrue((ROOT / entry['owning_scope']).is_file())
            self.assertFalse(graph['executable'])

    def test_current_native_priority_preserves_historical_delivery(self):
        assignment = 'L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002'
        for graph in (self.http, self.package):
            active = graph['active_product_priority']
            self.assertEqual(active['assignment_id'], assignment)
            self.assertEqual(active['register'], 'https://github.com/pcvantol/forge/issues/208')
            self.assertFalse(active['first_installer_release_dependency'])
            self.assertFalse(active.get('client_requires_python_or_local_server',
                                        active.get('native_client_requires_python_or_local_server')))
            self.assertEqual(graph['status'], 'PLANNED')
            self.assertFalse(graph['first_slice_checkpoint']['full_parent_qualified'])
        remote = self.http['active_product_priority']
        self.assertEqual(remote['two_mac_host_trust_authorization_gate'],
                         'INSTALLED_SERVER_REMOTE_HTTPS_HTTP_TRANSPORT_PASS_NATIVE_APP_NOT_RUN')
        self.assertEqual(remote['https_server_listener_gate'], 'PROTECTED_DELIVERED_WORKSPACE_PR_119')
        self.assertTrue(any('packaged Workspace.app remote readback' in item
                            for item in remote['two_mac_missing']))
        self.assertEqual(remote['forge_read_gate'],
                         'LOCAL_INSTALLED_TWO_SERVER_HTTP_PROTECTED_DELIVERED_WORKSPACE_PR_121')
        self.assertEqual(remote['native_forge_visible_gate'],
                         'LOCAL_PACKAGED_FINDER_READBACK_PROTECTED_DELIVERED_PR_122_MAIN_CFFBA50')
        self.assertTrue(any('double-clicked in Finder' in item
                            for item in remote['native_forge_visible_evidence']))
        self.assertEqual(remote['forge_read_remote_https_native_app_gate'], 'NOT_RUN')
        self.assertEqual(self.package['active_product_priority']['native_client_signed_keychain_trust_gate'], 'NOT_RUN')

    def test_http_dependencies_preserved(self):
        self.assertEqual({n['id']: n['depends_on'] for n in self.http['nodes']}, {
            'WH-CONTRACT': [], 'WH-SERVICES': ['WH-CONTRACT'],
            'WH-HTTP': ['WH-SERVICES'], 'WH-CLI': ['WH-SERVICES'],
            'WH-PEERS': ['WH-HTTP'], 'WH-Q': ['WH-CLI','WH-PEERS']})
        self.assertEqual(self.http['lane_allocation']['selected_node_subsets'],
                         ['WH-CONTRACT','WH-SERVICES','WH-HTTP','WH-CLI'])
        self.assertEqual(self.http['external_requirements']['WH-SERVICES'],
                         ['WORKSPACE_SERVER_IDENTITY_STATE_SUBSET'])
        self.assertEqual(self.http['external_requirements']['WH-PEERS'],
                         ['FORGE_HTTP_OPERATIONS_USED_QUALIFIED','EP_HTTP_OPERATIONS_USED_QUALIFIED'])
        self.assertFalse(self.http['execution_authority'])

    def test_peer_authority_not_moved_into_workspace(self):
        contract = self.http['shared_contract']
        for field in ['workspace_to_forge','workspace_to_ep','workspace_client_to_server']:
            self.assertEqual(contract[field], 'HTTP_ONLY')
        for field in ['peer_cli_fallback','peer_file_inbox_fallback',
                      'peer_direct_database_access','peer_python_import_execution',
                      'cli_is_business_authority','workspace_replaced_by_console']:
            self.assertFalse(contract[field])

    def test_package_dependencies_and_public_gate_preserved(self):
        self.assertEqual({n['id']:n['depends_on'] for n in self.package['nodes']}, {
            'WPK-IDENTITY':[], 'WPK-PACKAGE':['WPK-IDENTITY'],
            'WPK-PUBLISH':['WPK-PACKAGE'], 'WPK-READBACK':['WPK-PUBLISH'],
            'WPK-CONSUMER':['WPK-READBACK']})
        self.assertEqual(self.package['lane_allocation']['selected_node_subsets'],
                         ['WPK-IDENTITY','WPK-PACKAGE'])
        self.assertEqual(self.package['canonical_installable_channel'],'PyPI')
        self.assertEqual(self.package['canonical_installable_channel_scope'],
                         'PYTHON_SERVER_AND_LEGACY_PYTHON_ENTRYPOINT_ONLY')
        self.assertIn('MACOS_APP', self.package['native_client_channel'])
        self.assertEqual(self.package['evidence_gates']['WPK-PACKAGE'],
                         ['OWNED_ROLE_ENTRYPOINT_AND_ASSET_SUBSET'])
        self.assertEqual(self.package['evidence_gates']['WPK-PUBLISH'],
                         ['QUALIFIED_INSTALLABLE_ROLE_SUBSET','CONFIGURED_PYPI_PUBLISHER'])
        self.assertFalse(self.package['authorizes_execution'])
        self.assertFalse(self.package['invariants']['publication_implies_live_installation'])
        self.assertFalse(self.package['invariants']['pypi_fallback_to_github'])

    def test_unselected_parent_gates_not_silently_completed(self):
        self.assertTrue(self.http['lane_allocation']['peer_and_full_parent_qualification_remain_open'])
        self.assertTrue(self.package['lane_allocation']['public_publish_readback_consumer_gates_remain_open'])
        self.assertEqual(self.package['lane_allocation']['first_slice_delivery'],
                         'LOCAL_NONEDITABLE_INSTALLED_WHEEL_NOT_PUBLIC_RELEASE')
        for graph in (self.http,self.package):
            ids = [n['id'] for n in graph['nodes']]
            self.assertEqual(len(ids),len(set(ids)))
            for selected in graph['lane_allocation']['selected_node_subsets']:
                self.assertIn(selected,ids)

    def test_entry_navigation_and_evidence_limits(self):
        bootstrap = (ROOT/'BOOTSTRAP.md').read_text(encoding='utf-8')
        backlog = (ROOT/'BACKLOG.md').read_text(encoding='utf-8')
        scope = (ROOT/'docs/WORKSPACE_LANE_4_START_V1.md').read_text(encoding='utf-8')
        self.assertIn('WORKSPACE_LANE_4_START_V1.md',bootstrap)
        self.assertIn('WORKSPACE_LANE_4_START_V1.md',backlog)
        self.assertIn('WORK_SESSION_STARTED = FALSE',scope)
        self.assertIn('FIRST_INSTALLER_RELEASE_DEPENDENCY = FALSE',scope)
        self.assertIn('VERTICAL_SLICE_DELIVERY_V1',scope)


if __name__ == '__main__':
    unittest.main()
