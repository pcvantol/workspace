"""Negative drift cases for the PB-W0 owner and target boundary."""

from copy import deepcopy
import unittest

from validate_project_bootstrap_w0 import _load, validate_journey_boundaries


class PBW0BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.contract = _load("PROJECT_BOOTSTRAP_W0_CONTRACT_V1.json")

    def test_current_journey_boundaries(self):
        validate_journey_boundaries(self.contract)

    def test_genesis_cannot_submit_managed_effect(self):
        changed = deepcopy(self.contract)
        changed["journeys"][0]["capabilities_by_phase"]["submit"] = ["EP_MANAGED_CREATE"]
        with self.assertRaisesRegex(ValueError, "journey submit operation"):
            validate_journey_boundaries(changed)

    def test_adoption_cannot_masquerade_as_empty_target(self):
        changed = deepcopy(self.contract)
        changed["journeys"][1]["target_class"] = "LOCAL_MISSING_EMPTY_OR_UNBORN"
        with self.assertRaisesRegex(ValueError, "source/target/remote boundary"):
            validate_journey_boundaries(changed)


if __name__ == "__main__":
    unittest.main()
