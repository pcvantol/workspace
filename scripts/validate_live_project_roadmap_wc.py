"""Validate the offline PRM-W consumer contract and authority fixtures."""

import json
from pathlib import Path


DOCS = Path(__file__).resolve().parents[1] / "docs"


def load(name):
    return json.loads((DOCS / name).read_text(encoding="utf-8"))


def classify(case):
    if not case["actor"]:
        return "DENIED"
    if case["scope"] != "EXACT":
        return "ASK_SCOPE"
    capability = case["capability"]
    if capability == "DENIED":
        return "DENIED"
    if capability in ("UNQUALIFIED", "UNSUPPORTED"):
        return "UNSUPPORTED"
    passive = case["action"] in ("VIEW", "REFRESH", "SORT", "OPEN")
    if capability == "OFFLINE":
        return "UNAVAILABLE" if passive else "OFFLINE_BLOCKED"
    if not case["consistent"]:
        return "PARTIAL_STALE_READ_ONLY" if passive else "PARTIAL_BLOCKED"
    if capability == "STALE" or not case["fresh"]:
        return "STALE_READ_ONLY" if passive else "STALE_BLOCKED"
    if passive:
        kind = case["kind"]
        if kind == "CAPABILITY":
            return "CAPABILITY_NO_MISSION"
        if kind == "APPROVED_SUBJECT":
            return "APPROVED_NOT_ACTIVE"
        if kind == "CANDIDATE":
            return "CANDIDATE_NOT_APPROVED"
        if kind == "EXPECTED":
            return "EXPECTED_ADVISORY"
        if kind == "HISTORY":
            return "HISTORY_READ_ONLY"
        mission_id = case.get("mission_id")
        receipt = case.get("activation_receipt")
        activated = (case["owner_receipt"] and isinstance(mission_id, str) and bool(mission_id)
                     and isinstance(case.get("approved_subject_ref"), str) and bool(case["approved_subject_ref"])
                     and isinstance(receipt, dict) and receipt.get("owner") == "forge"
                     and receipt.get("kind") == "ACTIVATION"
                     and isinstance(receipt.get("ref"), str) and bool(receipt["ref"])
                     and receipt.get("mission_id") == mission_id
                     and receipt.get("approved_subject_ref") == case["approved_subject_ref"])
        return "ACTUAL_MISSION" if activated else "ACTIVATION_UNVERIFIED"
    if case["action"] == "RELEASE" and case["kind"] != "APPROVED_SUBJECT":
        return "WRONG_SUBJECT_KIND"
    if not case["expected_revision"]:
        return "REVISION_REQUIRED"
    if not case["operation_id"]:
        return "OPERATION_ID_REQUIRED"
    if not case["owner_receipt"]:
        return "PENDING_OWNER_READBACK"
    return "RELEASE_RECEIPT_NOT_ACTIVATION" if case["action"] == "RELEASE" else "PROPOSAL_NOT_COMMITTED"


def validate():
    contract = load("LIVE_PROJECT_ROADMAP_WC_CONTRACT_V1.json")
    fixtures = load("LIVE_PROJECT_ROADMAP_WC_EXAMPLES_V1.json")
    assert contract["schema_version"] == fixtures["schema_version"] == 1
    assert contract["contract"] == fixtures["contract"] == "WORKSPACE_LIVE_PROJECT_ROADMAP_WC_V1"
    assert contract["owner"] == "workspace" and contract["authority"] == "CONTRACT_ONLY"
    assert contract["producer_bindings"] == "UNQUALIFIED"
    assert contract["evidence_status"] == "OFFLINE_FIXTURES_ONLY"
    assert fixtures["purpose"] == "OFFLINE_CONSUMER_FIXTURES_NOT_RUNTIME_PROOF"
    assert contract["producer_owners"] == {"roadmap": "forge", "eligibility": "forge",
                                           "activation": "forge", "execution": "engineering-platform"}
    assert contract["request"]["expected_revision_for_command"] is True
    assert contract["request"]["operation_id_for_command"] is True
    assert contract["request"]["owner_http_only"] is True
    assert contract["consumer_boundary"]["producer_transport"] == "QUALIFIED_AUTHENTICATED_HTTP_ONLY"
    for key, value in contract["consumer_boundary"].items():
        if key != "producer_transport":
            assert value is False, key
    required = {"ProjectSnapshot": {"project_id", "snapshot_id", "source_revision", "partial", "pagination_cursor", "availability"},
                "RoadmapItem": {"kind", "typed_id", "project_id", "source_revision", "owner", "provenance_refs", "availability"},
                "Approval": {"subject_id", "subject_revision", "decision_owner", "decision_ref", "availability"},
                "Release": {"subject_id", "subject_revision", "release_receipt", "availability"},
                "Eligibility": {"subject_id", "subject_revision", "blockers", "owner_receipt", "availability"},
                "Activation": {"mission_id", "approved_subject_ref", "activation_receipt", "availability"},
                "Execution": {"mission_id", "action_id", "admission_receipt", "availability"}}
    assert set(contract["projection"]) == set(required)
    for name, fields in required.items():
        assert fields.issubset(contract["projection"][name]), name
    assert set(contract["item_kinds"]) == {"CAPABILITY", "APPROVED_SUBJECT", "CANDIDATE", "EXPECTED", "MISSION", "HISTORY"}
    assert set(contract["passive_actions"]) == {"VIEW", "REFRESH", "SORT", "OPEN"}
    assert set(contract["command_actions"]) == {"PROPOSE_PRIORITY", "RELEASE"}
    seen = set()
    for case in fixtures["examples"]:
        assert case["id"] not in seen
        seen.add(case["id"])
        assert case["kind"] in contract["item_kinds"]
        assert case["action"] in contract["passive_actions"] + contract["command_actions"]
        assert case["capability"] in contract["availability"]
        assert case["scope"] in {"EXACT", "AMBIGUOUS"}
        assert classify(case) == case["expected"], case["id"]
    assert len(seen) >= 25
    print(f"PRM-W offline consumer contract passed: {len(seen)} fixtures; producer/UI unqualified.")


if __name__ == "__main__":
    validate()
