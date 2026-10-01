"""Offline GP-WC consumer contract guard; never claims a live owner binding."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "docs"


def load(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def outcome(item):
    """Evaluate a consumer action; only an owner receipt can confirm a decision."""
    if not item["actor"] or item["capability"] == "DENIED":
        return "DENIED"
    if item["scope"] != "EXACT":
        return "ASK_SCOPE"
    if item["capability"] != "QUALIFIED_AUTHORIZED":
        return "UNSUPPORTED" if item["capability"] != "OFFLINE" else "OFFLINE_UNAVAILABLE"
    if not item["online"]:
        return "OFFLINE_UNAVAILABLE"
    action = item["action"]
    if action == "VIEW":
        return "OWNER_PROJECTION"
    if action == "RECOVER":
        return "READ_BACK_SAME_OPERATION" if item["operation_id"] else "UNCERTAIN_NO_REPLAY"
    if item["target_class"] != item["label_class"]:
        return "TARGET_CLASS_CONFLICT"
    if action == "DECIDE" and item["requirement_owner"] == "EXTERNAL":
        return "EXTERNAL_OWNER_ONLY"
    if action == "REQUEST_EXTERNAL" and (item["requirement_owner"] != "EXTERNAL" or
                                         item["mode"] != "REQUEST_AND_WAIT"):
        return "UNSUPPORTED"
    if action not in {"DECIDE", "REQUEST_EXTERNAL"}:
        raise ValueError(f"unknown GP-WC action: {action}")
    if not item["revision"]:
        return "STALE"
    if not item["operation_id"]:
        return "BLOCKED_NO_OPERATION_ID"
    if action == "DECIDE":
        return "OWNER_DECISION_CONFIRMED" if item["owner_receipt"] else "PENDING_OWNER_READBACK"
    return ("REQUEST_ACKNOWLEDGED_NOT_APPROVED_OR_DEPLOYED" if item["owner_receipt"]
            else "REQUEST_PENDING_OWNER_READBACK")


def validate(contract=None, fixtures=None):
    contract = contract if contract is not None else load("GOVERNED_PROGRESSION_WC_CONTRACT_V1.json")
    fixtures = fixtures if fixtures is not None else load("GOVERNED_PROGRESSION_WC_EXAMPLES_V1.json")
    require(contract["schema_version"] == fixtures["schema_version"] == 1 and
            contract["contract"] == fixtures["contract"] == "WORKSPACE_GOVERNED_PROGRESSION_WC_V1",
            "GP-WC identity drift")
    require(contract["owner"] == "workspace" and contract["authority"] == "CONTRACT_ONLY" and
            contract["producer_bindings"] == "UNQUALIFIED" and
            fixtures["purpose"] == "OFFLINE_CONSUMER_FIXTURES_NOT_RUNTIME_PROOF", "GP-WC authority drift")
    request = contract["request"]
    require(request["actor"] == "AUTHENTICATED_PRINCIPAL_REFERENCE" and
            request["scope"] == ["project_id", "subject_id", "requirement_id"] and
            request["expected_revision_required_for_command"] is True and
            request["operation_id_required_for_command"] is True and
            request["ui_role_is_grant"] is False and
            request["target_label_is_classification"] is False, "GP-WC scope drift")
    expected = {
        "EffectiveCadence": ("forge", {"project_id", "mission_id", "definition_revision", "assignment_revision", "effective_profile", "supported_range", "mandatory_minimum", "override_allowed", "source_refs", "availability"}),
        "ReviewRequirement": ("forge", {"requirement_id", "project_id", "subject_id", "subject_revision", "decision_owner", "required_role", "blocking_scope", "evidence_refs", "status", "availability"}),
        "DeliveryTarget": ("declared_external_owner", {"target_id", "project_id", "environment_class", "classification_evidence", "artifact_id", "artifact_digest", "source_revision", "trigger_owner", "approval_owner", "delivery_owner", "availability"}),
        "ExternalGate": ("declared_external_owner", {"gate_id", "requirement_id", "target_id", "artifact_digest", "authority_binding", "owner_status", "owner_receipt", "observed_at", "availability"}),
    }
    require(set(contract["projections"]) == set(expected), "GP-WC projection family drift")
    for name, (owner, required) in expected.items():
        projection = contract["projections"][name]
        fields = projection["required"]
        require(projection["owner"] == owner and required <= set(fields) and len(fields) == len(set(fields)),
                f"GP-WC {name} evidence drift")
    boundary = contract["review_boundary"]
    require(boundary["local_decision_owner"] == "forge" and
            boundary["external_approval_owner"] == "declared_external_owner" and
            boundary["owner_receipt_required_for_success"] is True and
            boundary["fence_scope"] == "OWNER_DECLARED_SUBJECT_OR_MISSION" and
            boundary["lost_acknowledgement"] == "READ_BACK_SAME_OPERATION" and
            all(boundary[key] is False for key in (
                "external_gate_has_workspace_approve_control", "request_is_approval", "request_is_deployed",
                "ui_click_is_owner_decision", "stale_subject_can_decide",
                "local_rejection_cancels_running_external_work", "offline_command_allowed")),
            "GP-WC gate/decision authority drift")
    require(contract["external_modes"] == ["OBSERVE_ONLY", "REQUEST_AND_WAIT"] and
            set(contract["availability"]) == {"QUALIFIED_AUTHORIZED", "UNQUALIFIED", "UNSUPPORTED", "DENIED", "OFFLINE"},
            "GP-WC capability drift")
    examples = fixtures["examples"]
    required_examples = {"view-local-requirement", "view-external-gate", "local-decision-pending", "local-decision-receipt", "external-no-duplicate-approve", "request-observe-only", "request-pending", "request-acknowledged-not-deployed", "prod-renamed-acc", "stale-local-decision", "ambiguous-requirement", "denied-view", "unqualified-request", "offline-decision", "lost-acknowledgement", "lost-acknowledgement-no-id"}
    require(len(examples) == len({item["id"] for item in examples}) and
            {item["id"] for item in examples} >= required_examples, "GP-WC critical fixture drift")
    for item in examples:
        require(item["scope"] in {"EXACT", "AMBIGUOUS"} and
                item["capability"] in contract["availability"] and
                item["mode"] in contract["external_modes"] and
                item["requirement_owner"] in {"FORGE", "EXTERNAL"} and
                item["target_class"] in {"TST", "ACC", "PROD", "CUSTOM"} and
                item["label_class"] in {"TST", "ACC", "PROD", "CUSTOM"} and
                outcome(item) == item["expected"], f"GP-WC fixture {item['id']} drift")


if __name__ == "__main__":
    validate()
    print("GP-WC offline gate consumer contract passed; producer/runtime unqualified.")
