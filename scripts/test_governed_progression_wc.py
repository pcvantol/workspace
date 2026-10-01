"""Negative drift cases for the GP-WC owner and external gate boundary."""

import copy
import unittest

from validate_governed_progression_wc import load, outcome, validate


class GovernedProgressionConsumerTests(unittest.TestCase):
    def setUp(self):
        self.contract = load("GOVERNED_PROGRESSION_WC_CONTRACT_V1.json")
        self.fixtures = load("GOVERNED_PROGRESSION_WC_EXAMPLES_V1.json")
        self.cases = {item["id"]: item for item in self.fixtures["examples"]}

    def test_contract(self):
        validate(self.contract, self.fixtures)

    def test_external_gate_never_has_workspace_approval(self):
        self.assertEqual("EXTERNAL_OWNER_ONLY", outcome(self.cases["external-no-duplicate-approve"]))
        changed = copy.deepcopy(self.contract)
        changed["review_boundary"]["external_gate_has_workspace_approve_control"] = True
        with self.assertRaisesRegex(ValueError, "gate/decision authority"):
            validate(changed, self.fixtures)

    def test_request_is_not_approval_or_deployment(self):
        self.assertEqual("REQUEST_ACKNOWLEDGED_NOT_APPROVED_OR_DEPLOYED",
                         outcome(self.cases["request-acknowledged-not-deployed"]))
        self.assertEqual("UNSUPPORTED", outcome(self.cases["request-observe-only"]))
        changed = copy.deepcopy(self.contract)
        changed["review_boundary"]["request_is_approval"] = True
        with self.assertRaisesRegex(ValueError, "gate/decision authority"):
            validate(changed, self.fixtures)

    def test_revision_target_and_receipt_are_exact(self):
        self.assertEqual("STALE", outcome(self.cases["stale-local-decision"]))
        self.assertEqual("TARGET_CLASS_CONFLICT", outcome(self.cases["prod-renamed-acc"]))
        self.assertEqual("PENDING_OWNER_READBACK", outcome(self.cases["local-decision-pending"]))
        changed = copy.deepcopy(self.contract)
        changed["projections"]["ExternalGate"]["required"].remove("owner_receipt")
        with self.assertRaisesRegex(ValueError, "ExternalGate"):
            validate(changed, self.fixtures)

    def test_scope_capability_offline_and_recovery_fail_closed(self):
        self.assertEqual("ASK_SCOPE", outcome(self.cases["ambiguous-requirement"]))
        self.assertEqual("DENIED", outcome(self.cases["denied-view"]))
        self.assertEqual("UNSUPPORTED", outcome(self.cases["unqualified-request"]))
        self.assertEqual("OFFLINE_UNAVAILABLE", outcome(self.cases["offline-decision"]))
        self.assertEqual("UNCERTAIN_NO_REPLAY", outcome(self.cases["lost-acknowledgement-no-id"]))
        changed = copy.deepcopy(self.contract)
        changed["review_boundary"]["local_rejection_cancels_running_external_work"] = True
        with self.assertRaisesRegex(ValueError, "gate/decision authority"):
            validate(changed, self.fixtures)


if __name__ == "__main__":
    unittest.main()
