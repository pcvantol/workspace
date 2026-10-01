"""Focused negative contract drift tests."""

import copy
import unittest

from validate_role_aware_conversations_wc import load, outcome, validate


class ConsumerContractTests(unittest.TestCase):
    def setUp(self):
        self.contract = load("ROLE_AWARE_CONVERSATIONS_WC_CONTRACT_V1.json")
        self.fixtures = load("ROLE_AWARE_CONVERSATIONS_WC_EXAMPLES_V1.json")

    def test_contract(self):
        validate(self.contract, self.fixtures)

    def test_mode_cannot_become_role(self):
        contract = copy.deepcopy(self.contract)
        contract["request"]["client_advice_mode_is_role"] = True
        with self.assertRaisesRegex(ValueError, "scope/role"):
            validate(contract, self.fixtures)

    def test_decision_owner_receipt_and_revision_cannot_disappear(self):
        contract = copy.deepcopy(self.contract)
        contract["projections"]["DecisionProjection"]["required"].remove("owner_receipt")
        with self.assertRaisesRegex(ValueError, "DecisionProjection"):
            validate(contract, self.fixtures)
        exact = next(item for item in self.fixtures["examples"] if item["id"] == "decision-exact")
        self.assertEqual("STALE", outcome({**exact, "exact_revision": False}))
        self.assertEqual("PENDING_OWNER_READBACK", outcome({**exact, "owner_receipt": False}))

    def test_navigation_never_invokes_provider(self):
        contract = copy.deepcopy(self.contract)
        contract["interaction_boundary"]["passive_actions_invoke_provider"] = True
        with self.assertRaisesRegex(ValueError, "authority/replay"):
            validate(contract, self.fixtures)
        history = next(item for item in self.fixtures["examples"] if item["id"] == "history")
        self.assertEqual("DENIED", outcome({**history, "capability": "DENIED"}))
        self.assertEqual("UNSUPPORTED", outcome({**history, "capability": "UNQUALIFIED"}))
        self.assertEqual("OFFLINE_UNAVAILABLE", outcome({**history, "online": False}))

    def test_lost_response_never_replays(self):
        recover = next(item for item in self.fixtures["examples"] if item["id"] == "lost-response")
        self.assertEqual("READ_BACK_SAME_OPERATION", outcome(recover))
        self.assertEqual("UNCERTAIN_NO_REPLAY", outcome({**recover, "operation_id": False}))
        contract = copy.deepcopy(self.contract)
        contract["interaction_boundary"]["lost_response"] = "RESUBMIT"
        with self.assertRaisesRegex(ValueError, "authority/replay"):
            validate(contract, self.fixtures)


if __name__ == "__main__":
    unittest.main()
