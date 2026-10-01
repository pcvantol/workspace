"""Negative checks that the POL-WC classifier fails closed on authority gaps."""

import unittest
from unittest.mock import patch

from validate_policy_automation_wc import classify, load, validate


class PolicyConsumerBoundaryTests(unittest.TestCase):
    def test_contract_and_examples(self):
        validate()

    def test_proposal_never_activates_and_missing_receipt_waits(self):
        case = next(item for item in load("POLICY_AUTOMATION_WC_EXAMPLES_V1.json")["examples"]
                    if item["id"] == "proposal-draft")
        self.assertEqual(classify(case), "PROPOSAL_SUBMITTED_NOT_ACTIVE")
        case = dict(case, action="ACTIVATE", owner_receipt=False)
        self.assertEqual(classify(case), "PENDING_OWNER_READBACK")

    def test_stale_and_self_authorizing_mutations_fail_closed(self):
        case = next(item for item in load("POLICY_AUTOMATION_WC_EXAMPLES_V1.json")["examples"]
                    if item["id"] == "proposal-draft")
        for change, outcome in [({"fresh": False}, "STALE_BLOCKED"),
                                ({"self_approval": True}, "DENIED"),
                                ({"reset_grant_or_budget": True}, "DENIED"),
                                ({"operation_id": False}, "OPERATION_ID_REQUIRED"),
                                ({"capability": "UNQUALIFIED"}, "UNSUPPORTED"),
                                ({"capability": "STALE"}, "STALE_BLOCKED")]:
            with self.subTest(change=change):
                self.assertEqual(classify(dict(case, **change)), outcome)

    def test_offline_recovery_keeps_identity_without_claiming_readback(self):
        case = next(item for item in load("POLICY_AUTOMATION_WC_EXAMPLES_V1.json")["examples"]
                    if item["id"] == "lost-ack")
        self.assertEqual(classify(dict(case, capability="OFFLINE")), "OFFLINE_UNCERTAIN_KEEP_OPERATION")

    def test_owner_drift_is_rejected(self):
        contract = load("POLICY_AUTOMATION_WC_CONTRACT_V1.json")
        fixtures = load("POLICY_AUTOMATION_WC_EXAMPLES_V1.json")
        contract["projections"]["EffectivePolicy"]["owner"] = "workspace"
        with patch("validate_policy_automation_wc.load", side_effect=[contract, fixtures]):
            with self.assertRaises(AssertionError):
                validate()


if __name__ == "__main__":
    unittest.main()
