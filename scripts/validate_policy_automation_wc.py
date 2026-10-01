"""Validate the offline POL-WC consumer boundary and deterministic fixtures."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


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
    if capability == "STALE":
        return "STALE_READ_ONLY" if case["action"] in ("READ", "READ_PARTIAL") else "STALE_BLOCKED"
    if capability == "OFFLINE" and case["action"] == "RECOVER":
        return "OFFLINE_UNCERTAIN_KEEP_OPERATION" if case["operation_id"] else "UNCERTAIN_NO_REPLAY"
    if case["action"] in ("READ", "READ_PARTIAL"):
        if capability == "OFFLINE":
            return "UNAVAILABLE"
        if not case["fresh"]:
            return "STALE_READ_ONLY"
        return "PARTIALLY_ACTIVE" if case["action"] == "READ_PARTIAL" else "CURRENT"
    if case["action"] == "RECOVER":
        return "READ_BACK_SAME_OPERATION" if case["operation_id"] else "UNCERTAIN_NO_REPLAY"
    if capability == "OFFLINE":
        return "OFFLINE_DRAFT_ONLY"
    if not case["fresh"]:
        return "STALE_BLOCKED"
    if case["self_approval"] or case["reset_grant_or_budget"]:
        return "DENIED"
    if not case["operation_id"]:
        return "OPERATION_ID_REQUIRED"
    if not case["expected_revision"]:
        return "REVISION_REQUIRED"
    if not case["owner_receipt"]:
        return "PENDING_OWNER_READBACK"
    return "PROPOSAL_SUBMITTED_NOT_ACTIVE" if case["action"] == "PROPOSE" else "OWNER_RECEIPT_READBACK"


def validate():
    contract = load("POLICY_AUTOMATION_WC_CONTRACT_V1.json")
    fixtures = load("POLICY_AUTOMATION_WC_EXAMPLES_V1.json")
    assert contract["schema_version"] == fixtures["schema_version"] == 1
    assert contract["contract"] == fixtures["contract"] == "WORKSPACE_POLICY_AUTOMATION_WC_V1"
    assert contract["owner"] == "workspace"
    assert contract["authority"] == "CONTRACT_ONLY"
    assert contract["producer_bindings"] == "UNQUALIFIED"
    assert fixtures["purpose"] == "OFFLINE_CONSUMER_FIXTURES_NOT_RUNTIME_PROOF"
    assert contract["request"]["expected_revision_required_for_command"] is True
    assert contract["request"]["operation_id_required_for_command"] is True
    assert contract["request"]["ui_role_is_grant"] is False
    assert contract["request"]["workspace_writes_owner_policy"] is False
    boundary = contract["consumer_boundary"]
    for key in ("read_only_cached_projection_can_authorize", "draft_is_active",
                "impact_preview_is_decision", "ui_role_is_owner_grant", "proposal_approves_itself",
                "policy_change_resets_existing_grant_or_budget", "in_flight_snapshot_rewritten",
                "cross_owner_activation_is_atomic", "missing_owner_receipt_is_success", "offline_command_allowed"):
        assert boundary[key] is False, key
    assert boundary["lost_acknowledgement"] == "READ_BACK_SAME_OPERATION_WHEN_OWNER_AVAILABLE_ELSE_KEEP_OPERATION_UNCERTAIN"
    assert boundary["owner_transport"] == "QUALIFIED_AUTHENTICATED_HTTP_ONLY"
    assert set(contract["projections"]) == {"PolicyDefinition", "PolicyAssignment", "EffectivePolicy",
                                             "RunPolicySnapshot", "PolicyProposal", "PolicyDecision", "PolicyActivation"}
    expected_owners = {"PolicyDefinition": "declared_policy_owner",
                       "PolicyAssignment": "declared_policy_owner",
                       "EffectivePolicy": "declared_policy_owner",
                       "RunPolicySnapshot": "execution_or_planning_owner",
                       "PolicyProposal": "declared_policy_owner",
                       "PolicyDecision": "declared_decision_owner",
                       "PolicyActivation": "declared_policy_owner"}
    for name, projection in contract["projections"].items():
        assert projection["owner"] == expected_owners[name], name
        assert "availability" in projection["required"]
        if name in {"RunPolicySnapshot", "PolicyDecision", "PolicyActivation"}:
            assert "owner_receipt" in projection["required"]
    seen = set()
    for case in fixtures["examples"]:
        assert case["id"] not in seen
        seen.add(case["id"])
        assert case["action"] in {"READ", "READ_PARTIAL", "PROPOSE", "DECIDE", "ACTIVATE", "RECOVER"}
        assert case["capability"] in contract["availability"]
        assert case["scope"] in {"EXACT", "AMBIGUOUS"}
        assert classify(case) == case["expected"], case["id"]
    assert len(seen) >= 15
    print(f"POL-WC offline consumer contract passed: {len(seen)} fixtures; producers/UI unqualified.")


if __name__ == "__main__":
    validate()
