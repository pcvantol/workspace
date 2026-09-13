"""Documentary integrity only; not packaging, publishing or installed proof."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PyPIDistributionRoadmapTests(unittest.TestCase):
    def setUp(self):
        self.graph = json.loads((ROOT / "docs/WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json").read_text())

    def test_scope_and_authority(self):
        self.assertEqual(self.graph["owner"], "workspace")
        self.assertEqual(self.graph["authority"], "DOCUMENTARY")
        self.assertEqual(self.graph["version_change"], "NO_BUMP")
        for key in ("executable", "authorizes_execution", "first_canary_prerequisite"):
            self.assertFalse(self.graph[key])

    def test_ordered_dag_and_no_invented_receipts(self):
        seen = set()
        for node in self.graph["nodes"]:
            self.assertNotIn(node["id"], seen)
            self.assertTrue(set(node["depends_on"]) <= seen)
            self.assertEqual(node["status"], "PLANNED")
            self.assertEqual(node["qualification_evidence"], [])
            seen.add(node["id"])
        self.assertEqual(len(seen), 5)
        self.assertTrue(set(self.graph["evidence_gates"]) <= seen)

    def test_distribution_and_role_boundaries(self):
        self.assertEqual(self.graph["canonical_installable_channel"], "PyPI")
        rules = self.graph["invariants"]
        self.assertTrue(rules["names_owned_before_publish"])
        self.assertTrue(rules["server_and_client_mapping_required"])
        for key in ("source_archive_is_installed_proof", "same_version_different_bytes_allowed",
                    "pypi_fallback_to_github", "publication_implies_live_installation",
                    "cleanup_failure_erases_publication", "production_workflow_changed"):
            self.assertFalse(rules[key])

    def test_scenarios_and_parent_are_discoverable(self):
        text = (ROOT / self.graph["roadmap"]).read_text()
        cases = self.graph["required_scenarios"]
        self.assertEqual(cases, [f"WPK-T{i:02d}" for i in range(1, 7)])
        for case in cases:
            self.assertIn(case, text)
        parent = (ROOT / self.graph["architecture"]).read_text()
        self.assertIn(Path(self.graph["roadmap"]).name, parent)
        self.assertIn("WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json", parent)


if __name__ == "__main__":
    unittest.main()
