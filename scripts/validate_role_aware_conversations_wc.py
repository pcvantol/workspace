"""Offline RC-WC consumer-contract drift guard; no peer or runtime qualification."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"


def load(name):
    return json.loads((DOCS / name).read_text(encoding="utf-8"))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def outcome(example):
    """Evaluate the consumer-visible result without treating a UI state as a grant."""
    action = example["action"]
    if not example["actor"]:
        return "DENIED"
    if example["scope"] != "EXACT":
        return "ASK_SCOPE"
    if example["capability"] == "DENIED":
        return "DENIED"
    if example["capability"] in {"UNQUALIFIED", "UNSUPPORTED"}:
        return "UNSUPPORTED"
    if not example["online"] or example["capability"] == "OFFLINE":
        return "OFFLINE_DRAFT_ONLY" if action in {"SEND", "DECIDE"} else "OFFLINE_UNAVAILABLE"
    if action in {"LOAD", "FILTER", "POLL", "CHANGE_MODE", "OPEN_MODAL"}:
        return "READ_ONLY"
    if action in {"RECONNECT", "RECOVER"}:
        return "READ_BACK_SAME_OPERATION" if example["operation_id"] else "UNCERTAIN_NO_REPLAY"
    if not example["operation_id"]:
        return "BLOCKED_NO_OPERATION_ID"
    if action == "SEND":
        return "SUBMIT_ONE_BOUNDED_TURN"
    if action == "DECIDE":
        if not example["exact_revision"]:
            return "STALE"
        return "OWNER_DECISION_READBACK" if example["owner_receipt"] else "PENDING_OWNER_READBACK"
    raise ValueError(f"unknown action: {action}")


def validate(contract=None, fixtures=None):
    contract = contract or load("ROLE_AWARE_CONVERSATIONS_WC_CONTRACT_V1.json")
    fixtures = fixtures or load("ROLE_AWARE_CONVERSATIONS_WC_EXAMPLES_V1.json")
    require(contract["schema_version"] == fixtures["schema_version"] == 1 and
            contract["contract"] == fixtures["contract"] == "WORKSPACE_ROLE_AWARE_CONVERSATIONS_WC_V1",
            "RC-WC identity drift")
    require(contract["owner"] == "workspace" and contract["authority"] == "CONTRACT_ONLY" and
            contract["producer_bindings"] == "UNQUALIFIED" and
            fixtures["purpose"] == "OFFLINE_CONSUMER_FIXTURES_NOT_RUNTIME_PROOF",
            "RC-WC claimed runtime or peer qualification")
    request = contract["request"]
    require(request["actor"] == "AUTHENTICATED_PRINCIPAL_REFERENCE" and
            request["scope"] == ["project_id", "principal_id"] and
            request["scope_resolution"] == "EXPLICIT_OR_UNAMBIGUOUS_AUTHENTICATED_SELECTION" and
            request["client_advice_mode_is_role"] is False and
            request["untrusted_context_is_instruction"] is False and
            request["operation_identity"] == "STABLE_UNTIL_OWNER_READBACK", "RC-WC scope/role drift")
    require(contract["advisor_modes"] == ["BUSINESS", "ARCHITECTURE", "UX"] and
            set(contract["capability_states"]) == {"QUALIFIED_AUTHORIZED", "UNSUPPORTED", "UNQUALIFIED", "DENIED", "OFFLINE"} and
            set(contract["presentation_states"]) == {"READY", "PARTIAL", "STALE", "OFFLINE", "PENDING", "UNCERTAIN", "UNSUPPORTED", "DENIED"},
            "RC-WC mode/capability/presentation drift")
    expected = {
        "ConversationSummary": ("workspace", {"conversation_id", "project_id", "title", "last_activity_at", "last_advice_mode", "archive_state", "source_revision", "availability"}),
        "ConversationDetail": ("workspace", {"conversation_id", "project_id", "turn_refs", "context_ref", "session_refs", "source_revision", "availability"}),
        "ContextManifest": ("forge", {"context_id", "project_id", "included_sources", "excluded_sources", "source_revisions", "access_scope", "freshness", "availability"}),
        "SessionProjection": ("forge", {"session_id", "conversation_id", "operation_id", "advice_mode", "status", "result_ref", "source_revision", "availability"}),
        "ProposalProjection": ("forge", {"proposal_id", "project_id", "owner", "revision", "digest", "affected_scope", "status", "availability"}),
        "ArtifactRevision": ("forge", {"artifact_id", "proposal_id", "revision", "digest", "source_refs", "availability"}),
        "DecisionProjection": ("forge", {"decision_id", "proposal_id", "proposal_revision", "artifact_revision", "owner", "owner_receipt", "status", "availability"}),
    }
    require(set(contract["projections"]) == set(expected), "RC-WC projection family drift")
    for name, (owner, fields) in expected.items():
        projection = contract["projections"][name]
        require(projection["owner"] == owner and fields <= set(projection["required"]) and
                len(projection["required"]) == len(set(projection["required"])), f"RC-WC {name} evidence drift")
    boundary = contract["interaction_boundary"]
    require(set(boundary["passive_actions"]) == {"LOAD", "FILTER", "POLL", "RECONNECT", "CHANGE_MODE", "OPEN_MODAL"} and
            boundary["passive_actions_invoke_provider"] is False and
            all(boundary[key] is True for key in ("send_requires_explicit_submit", "send_requires_qualified_authorized_capability", "decision_requires_exact_revision_and_owner_receipt")) and
            boundary["lost_response"] == "READ_BACK_SAME_OPERATION" and
            all(boundary[key] is False for key in ("offline_auto_submit", "conversation_state_is_decision_authority", "advice_completion_is_approval", "workspace_direct_engineering_execution")),
            "RC-WC authority/replay drift")
    examples = fixtures["examples"]
    require(len(examples) == len({item["id"] for item in examples}), "RC-WC duplicate fixture")
    require({item["id"] for item in examples} >= {"history", "mode-switch", "reconnect", "send-explicit", "send-unqualified", "send-offline", "ambiguous-project", "cross-principal", "denied-history", "unqualified-history", "denied-recovery", "offline-history-without-cache", "decision-exact", "decision-stale", "decision-no-receipt", "lost-response", "lost-response-no-id"}, "RC-WC missing critical example")
    for item in examples:
        require(item["scope"] in {"EXACT", "AMBIGUOUS"} and
                item["capability"] in contract["capability_states"] and
                outcome(item) == item["expected"], f"RC-WC fixture {item['id']} drift")


if __name__ == "__main__":
    validate()
    print("RC-WC offline consumer contract passed; peer/runtime unqualified.")
