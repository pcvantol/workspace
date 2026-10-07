"""Pinned projection shape, canonical digest and scoped reference regressions."""

from copy import deepcopy
import hashlib
import json
import unittest

from workspace_control.worklist_contract import validate_projection
from workspace_control.worklist_peer import WorklistError


DIGEST = "sha256:" + "a" * 64
BINDING = {"forge_instance_id": "forge-1", "actor_id": "actor-a", "workset_ids": ["workset-a"]}
PINNED_SNAPSHOT_FIELDS = ("contract_version", "instance_id", "installation_id", "scope",
    "membership_revision", "selector_revision", "workset_revision", "activation_support",
    "completeness", "items", "continuation")


def seal(value):
    # Independent test encoding of the exact L3-published fixed field list.
    payload = {key: value[key] for key in PINNED_SNAPSHOT_FIELDS}
    value["snapshot_revision"] = "sha256:" + hashlib.sha256(json.dumps(payload, sort_keys=True,
        ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
    return value


def projection(*, allocated=False, complete=True, empty=False):
    item = {"candidate_id": "candidate-a", "subject_revision": DIGEST, "committed_order": 0,
            "title": "Résumé / safe subject", "mission_id": "mission-a" if allocated else None,
            "mission_state_revision": 7 if allocated else None, "approved": True, "released": True,
            "eligibility": "UNKNOWN", "blocking_reasons": ["ACTIVATION_NOT_YET_QUALIFIED"],
            "active": False, "execution_state": "AWAITING_APPROVAL" if allocated else "PENDING_INTAKE",
            "engineering_result": "PROVEN" if allocated else "UNKNOWN", "review_state": "NONE",
            "final_acceptance": "WAITING" if allocated else "UNKNOWN", "completed": False,
            "effect_mode": "READ_ONLY_ASSESSMENT", "dependencies": [],
            "detail_reference": {"kind": "MISSION_REVIEW", "mission_id": "mission-a"} if allocated else None,
            "allocation_binding": {"kind": "CANONICAL_CANDIDATE_INTAKE", "candidate_id": "candidate-a",
                "subject_revision": DIGEST, "mission_id": "mission-a", "installation_id": "installation-a",
                "envelope_digest": DIGEST} if allocated else None,
            "evidence_references": [{"kind": "MISSION_COMPLETION", "subject_id": "mission-a", "digest": DIGEST},
                {"kind": "FINAL_BUSINESS_ACCEPTANCE", "subject_id": "business-decision-a", "digest": DIGEST}] if allocated else []}
    return seal({"contract_version": "forge-workspace-worklist/v1", "instance_id": "forge-1",
        "installation_id": "installation-a", "scope": {"kind": "EXPLICIT_WORKSET", "principal_id": "actor-a",
            "workset_id": "workset-a", "project_id": None}, "membership_revision": DIGEST,
        "selector_revision": DIGEST, "workset_revision": 1, "observed_at": "2026-10-07T12:00:00Z",
        "freshness": "CURRENT_READBACK", "completeness": "COMPLETE_WITHIN_SCOPE" if complete else "PARTIAL",
        "activation_support": "NOT_YET_QUALIFIED", "items": [] if empty else [item], "read_only": True,
        "continuation": {"state": "IDLE" if empty else "UNKNOWN", "candidate_id": None if empty else "candidate-a",
            "mission_id": None if empty else item["mission_id"], "committed_order": None if empty else 0,
            "reason_codes": ["NO_REMAINING_APPROVED_WORK"] if empty else ["ACTIVATION_NOT_YET_QUALIFIED"]}})


class WorklistContractTests(unittest.TestCase):
    def assert_rejected(self, document):
        with self.assertRaises(WorklistError): validate_projection(document, BINDING, "workset-a")

    def test_canonical_unicode_snapshot_and_allocation_proof_are_read_only(self):
        for allocated in (False, True):
            document = projection(allocated=allocated)
            original = deepcopy(document)
            self.assertEqual(validate_projection(document, BINDING, "workset-a"), original)
            self.assertEqual(document, original)
        idle = projection(empty=True)
        self.assertEqual(validate_projection(idle, BINDING, "workset-a")["continuation"]["state"], "IDLE")

    def test_snapshot_digest_binds_every_declared_authority_and_selector_field(self):
        valid = projection()
        for key, value in [("membership_revision", "sha256:" + "b" * 64),
                           ("selector_revision", "sha256:" + "c" * 64), ("workset_revision", 2),
                           ("installation_id", "installation-b"), ("activation_support", "QUALIFIED_SERIAL_APPROVED_WORKLIST"),
                           ("completeness", "PARTIAL")]:
            altered = deepcopy(valid)
            altered[key] = value
            self.assert_rejected(altered)
        changed_observation = deepcopy(valid)
        changed_observation["observed_at"] = "2026-10-07T12:01:00+00:00"
        self.assertEqual(validate_projection(changed_observation, BINDING, "workset-a"), changed_observation)

    def test_foreign_scope_claimed_project_or_extra_fields_fail_closed(self):
        for field, value in [("principal_id", "actor-b"), ("workset_id", "workset-b"),
                             ("project_id", "unproven"), ("kind", "PROJECT")]:
            changed = projection()
            changed["scope"][field] = value
            self.assert_rejected(seal(changed))
        for key, value in [("instance_id", "foreign"), ("read_only", 1), ("workset_revision", True),
                           ("membership_revision", "r1"), ("snapshot_revision", "broken"),
                           ("observed_at", "2026-10-07T12:00:00"), ("observed_at", "invalid"),
                           ("observed_at", None), ("freshness", "STALE"), ("completeness", "PAGINATED"), ("completeness", {}),
                           ("activation_support", "IMPLICIT"), ("items", None), ("items", [{}] * 65)]:
            changed = projection()
            changed[key] = value
            self.assert_rejected(changed)
        changed = projection()
        changed["extra"] = "unsupported"
        self.assert_rejected(changed)

    def test_members_positions_and_dependency_edges_must_match_the_exact_snapshot(self):
        duplicate = projection()
        duplicate["items"].append(deepcopy(duplicate["items"][0]))
        self.assert_rejected(seal(duplicate))
        second = deepcopy(duplicate["items"][0])
        second["candidate_id"] = "candidate-b"
        duplicate["items"][1] = second
        self.assert_rejected(seal(duplicate))
        changed = projection()
        changed["items"][0]["committed_order"] = 1
        changed["continuation"]["committed_order"] = 1
        self.assert_rejected(seal(changed))
        changed["completeness"] = "PARTIAL"
        changed["items"][0]["dependencies"] = ["missing-candidate"]
        self.assertEqual(validate_projection(seal(changed), BINDING, "workset-a")["completeness"], "PARTIAL")
        changed["completeness"] = "COMPLETE_WITHIN_SCOPE"
        self.assert_rejected(seal(changed))
        changed = projection()
        changed["items"][0]["dependencies"] = ["candidate-a"]
        self.assert_rejected(seal(changed))

    def test_typed_allocation_detail_and_evidence_cannot_borrow_another_subject(self):
        for field, value in [("candidate_id", "foreign"), ("subject_revision", "sha256:" + "b" * 64),
                             ("mission_id", "foreign"), ("installation_id", "foreign"),
                             ("envelope_digest", "unverified"), ("kind", "RELEASE")]:
            changed = projection(allocated=True)
            changed["items"][0]["allocation_binding"][field] = value
            self.assert_rejected(seal(changed))
        for field, value in [("mission_id", "foreign"), ("kind", "URL")]:
            changed = projection(allocated=True)
            changed["items"][0]["detail_reference"][field] = value
            self.assert_rejected(seal(changed))
        for field, value in [("subject_id", "foreign"), ("kind", "EXTERNAL_URL"), ("digest", "file:///secret")]:
            changed = projection(allocated=True)
            changed["items"][0]["evidence_references"][0][field] = value
            self.assert_rejected(seal(changed))
        changed = projection(allocated=True)
        changed["items"][0]["evidence_references"] *= 2
        self.assert_rejected(seal(changed))
        changed["items"][0]["evidence_references"] *= 8
        self.assert_rejected(seal(changed))
        changed = projection()
        changed["items"][0]["mission_state_revision"] = 1
        self.assert_rejected(seal(changed))

    def test_real_partial_missing_state_keeps_only_unverified_typed_mission_reference(self):
        doc = projection(allocated=True, complete=False)
        item = doc["items"][0]
        item.update(execution_state="UNAVAILABLE", mission_state_revision=None, allocation_binding=None,
                    detail_reference=None, evidence_references=[], engineering_result="UNKNOWN", final_acceptance="UNKNOWN")
        self.assertEqual(validate_projection(seal(doc), BINDING, "workset-a")["items"][0]["mission_id"], "mission-a")
        doc["completeness"] = "COMPLETE_WITHIN_SCOPE"
        self.assert_rejected(seal(doc))
        doc["completeness"] = "PARTIAL"
        item["execution_state"] = "COMPLETED"
        self.assert_rejected(seal(doc))

    def test_next_and_idle_are_producer_facts_not_client_count_inference(self):
        for field, value in [("candidate_id", "foreign"), ("mission_id", "foreign"),
                             ("committed_order", 2), ("committed_order", True), ("state", "IDLE"),
                             ("reason_codes", ["BAD" + "X" * 64])]:
            changed = projection()
            changed["continuation"][field] = value
            self.assert_rejected(seal(changed))
        changed = projection()
        changed["continuation"]["candidate_id"] = None
        self.assert_rejected(seal(changed))
        changed["continuation"]["committed_order"] = None
        self.assertEqual(validate_projection(seal(changed), BINDING, "workset-a")["continuation"]["state"], "UNKNOWN")
        changed = projection(empty=True, complete=False)
        self.assert_rejected(changed)

    def test_bounded_codes_text_booleans_and_enums_reject_malformed_data(self):
        for field, value in [("candidate_id", "../foreign"), ("title", "bad\nspoof"), ("title", "x" * 161),
                             ("committed_order", True), ("approved", 1), ("released", None),
                             ("eligibility", "START"), ("eligibility", {}), ("review_state", []), ("engineering_result", "COMPLETE"),
                             ("review_state", "APPROVED"), ("final_acceptance", "COMPLETE"),
                             ("effect_mode", "FULL_CONTROL"), ("execution_state", "/private/path"),
                             ("blocking_reasons", ["DUPLICATE", "DUPLICATE"]),
                             ("dependencies", ["x", "x"]), ("dependencies", ["../outside"])]:
            changed = projection()
            changed["items"][0][field] = value
            self.assert_rejected(seal(changed))


if __name__ == "__main__": unittest.main()
