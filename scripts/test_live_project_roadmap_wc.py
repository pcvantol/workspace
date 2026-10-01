"""Exercise authority failures independently of the fixed PRM-W fixtures."""

import unittest
from unittest.mock import patch

from validate_live_project_roadmap_wc import classify, load, validate


class RoadmapConsumerTests(unittest.TestCase):
    def test_contract_and_examples(self):
        validate()

    def test_candidate_never_becomes_approved_by_sort(self):
        case = next(x for x in load("LIVE_PROJECT_ROADMAP_WC_EXAMPLES_V1.json")["examples"]
                    if x["id"] == "candidate")
        self.assertEqual(classify(dict(case, action="SORT", owner_receipt=True)),
                         "CANDIDATE_NOT_APPROVED")

    def test_mission_needs_owner_activation_receipt(self):
        case = next(x for x in load("LIVE_PROJECT_ROADMAP_WC_EXAMPLES_V1.json")["examples"]
                    if x["id"] == "mission-verified")
        self.assertEqual(classify(dict(case, owner_receipt=False)), "ACTIVATION_UNVERIFIED")
        self.assertEqual(classify(dict(case, mission_id=None)), "ACTIVATION_UNVERIFIED")
        self.assertEqual(classify(dict(case, activation_receipt={"owner": "forge", "kind": "RELEASE", "ref": "r1"})),
                         "ACTIVATION_UNVERIFIED")
        other = dict(case["activation_receipt"], mission_id="other-mission")
        self.assertEqual(classify(dict(case, activation_receipt=other)), "ACTIVATION_UNVERIFIED")
        other = dict(case["activation_receipt"], approved_subject_ref="other-subject")
        self.assertEqual(classify(dict(case, activation_receipt=other)), "ACTIVATION_UNVERIFIED")
        self.assertEqual(classify(dict(case, consistent=False)), "PARTIAL_STALE_READ_ONLY")

    def test_command_does_not_promote_unqualified_or_stale_source(self):
        case = next(x for x in load("LIVE_PROJECT_ROADMAP_WC_EXAMPLES_V1.json")["examples"]
                    if x["id"] == "release-readback-not-activation")
        for change, expected in [({"capability": "UNQUALIFIED"}, "UNSUPPORTED"),
                                 ({"capability": "STALE"}, "STALE_BLOCKED"),
                                 ({"consistent": False}, "PARTIAL_BLOCKED"),
                                 ({"fresh": False}, "STALE_BLOCKED"),
                                 ({"kind": "EXPECTED"}, "WRONG_SUBJECT_KIND")]:
            with self.subTest(change=change):
                self.assertEqual(classify(dict(case, **change)), expected)

    def test_owner_drift_rejected(self):
        contract = load("LIVE_PROJECT_ROADMAP_WC_CONTRACT_V1.json")
        examples = load("LIVE_PROJECT_ROADMAP_WC_EXAMPLES_V1.json")
        contract["producer_owners"]["activation"] = "workspace"
        with patch("validate_live_project_roadmap_wc.load", side_effect=[contract, examples]):
            with self.assertRaises(AssertionError):
                validate()


if __name__ == "__main__":
    unittest.main()
