"""Negative drift tests for the HY-WC no-delete/no-Mission contract."""

from copy import deepcopy
import unittest

from validate_repository_health_wc import _load, validate_intents


class HealthContractTests(unittest.TestCase):
    def setUp(self):
        self.contract = _load("REPOSITORY_HEALTH_WC_CONTRACT_V1.json")

    def test_current_intents(self):
        validate_intents(self.contract)

    def test_reconciliation_case_cannot_allocate_mission(self):
        changed = deepcopy(self.contract)
        changed["intents"][2]["allocates_mission"] = True
        with self.assertRaisesRegex(ValueError, "intent escaped"):
            validate_intents(changed)

    def test_cleanup_intent_cannot_be_delete_command(self):
        changed = deepcopy(self.contract)
        changed["intents"][3]["effect"] = "DELETE"
        changed["intents"][3]["deletes"] = True
        with self.assertRaisesRegex(ValueError, "intent escaped"):
            validate_intents(changed)

    def test_cleanup_intent_cannot_bind_ep_execution_receipt(self):
        changed = deepcopy(self.contract)
        changed["intents"][3]["owner_capability"] = "EP_CLEANUP_RECEIPT"
        with self.assertRaisesRegex(ValueError, "intent escaped"):
            validate_intents(changed)


if __name__ == "__main__":
    unittest.main()
