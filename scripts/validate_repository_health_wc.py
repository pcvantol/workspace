"""Offline HY-WC contract guard; no peer runtime or cleanup command."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
INTENTS = {
    "EXPLAIN": ("FORGE_OBSERVATION", "READ_ONLY", False),
    "REFRESH": ("FORGE_OBSERVATION", "OBSERVATION_ONLY", False),
    "RECONCILE": ("FORGE_RECONCILIATION_CASE", "CASE_ONLY", True),
    "CLEANUP_INTENT": ("FORGE_CLEANUP_PROPOSAL", "PROPOSAL_ONLY", True),
    "PRESERVE_RESIDUAL": ("FORGE_ENGINEERING_PROPOSAL", "ENGINEERING_PROPOSAL_ONLY", True),
}


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate HY-WC key: {key}")
        result[key] = value
    return result


def _load(name):
    return json.loads((DOCS / name).read_text(), object_pairs_hook=_unique)


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_intents(contract):
    capabilities = contract["capability_families"]
    _require(set(capabilities.values()) == {"forge", "engineering-platform"} and
             all(name.startswith("FORGE_") == (owner == "forge") for name, owner in capabilities.items()),
             "HY-WC capability owner drift")
    intents = contract["intents"]
    by_id = {entry["id"]: entry for entry in intents}
    _require(len(intents) == len(by_id) == len(INTENTS) and set(by_id) == set(INTENTS),
             "HY-WC must define exactly five intents")
    for name, (capability, effect, exact_targets) in INTENTS.items():
        entry = by_id[name]
        _require(entry["owner_capability"] == capability and capabilities[capability] == "forge" and
                 entry["effect"] == effect and entry["requires_exact_targets"] is exact_targets and
                 entry["allocates_mission"] is False and entry["deletes"] is False,
                 f"HY-WC intent escaped read/proposal boundary: {name}")


def request_state(example, contract):
    intents = {entry["id"]: entry for entry in contract["intents"]}
    if not example["actor"]:
        return "DENIED"
    if example["scope"] != "EXACT":
        return "ASK_SCOPE"
    if example["capability"] in {"UNSUPPORTED", "UNAVAILABLE", "DENIED"}:
        return example["capability"]
    if example["capability"] != "QUALIFIED_AUTHORIZED":
        return "BLOCKED"
    entry = intents[example["intent"]]
    if entry["requires_exact_targets"] and (not example["targets"] or
                                               len(example["targets"]) != len(set(example["targets"])) or
                                               any(not target or "*" in target for target in example["targets"])):
        return "BLOCKED"
    if entry["requires_exact_targets"] and not example["revision"]:
        return "STALE"
    if example["intent"] == "CLEANUP_INTENT" and not example.get("frozen_targets", False):
        return "BLOCKED"
    if entry["effect"] == "READ_ONLY":
        return "AVAILABLE_READ"
    if entry["effect"] == "OBSERVATION_ONLY":
        return "AVAILABLE_OBSERVATION"
    return entry["effect"]


def projection_state(example):
    if example["freshness"] == "STALE":
        return "STALE"
    if example["coverage"] != "COMPLETE" or example["freshness"] != "FRESH" or example["unknown_targets"]:
        return "INCOMPLETE"
    return "COMPLETE_FRESH"


def valid_claim(example):
    if example["class"] == "FACT":
        return example["owner_evidence"]
    if example["class"] in {"INFERENCE", "RECOMMENDATION"}:
        return example["owner_evidence"] and example["reason"] and example["uncertainty"]
    if example["class"] == "DECISION":
        return example["owner_evidence"] and example["owner_receipt"]
    return False


def validate():
    contract = _load("REPOSITORY_HEALTH_WC_CONTRACT_V1.json")
    examples = _load("REPOSITORY_HEALTH_WC_EXAMPLES_V1.json")
    _require(contract["schema_version"] == examples["schema_version"] == 1 and
             contract["contract"] == examples["contract"], "HY-WC contract/fixture identity drift")
    _require(contract["authority"] == "CONTRACT_ONLY" and contract["producer_bindings"] == "UNQUALIFIED",
             "HY-WC cannot claim runtime authority")
    request = contract["request"]
    _require(request["same_envelope_for_chat_and_view"] is True and
             request["actor"] == "AUTHENTICATED_SESSION_REFERENCE" and
             request["scope"] == ["project_id", "repository_id"] and
             request["scope_resolution"] == "EXPLICIT_OR_UNAMBIGUOUS_AUTHENTICATED_SELECTION" and
             request["ambiguous_scope"] == "ASK_BEFORE_ANY_PROTECTED_ACTION" and
             request["repository_text_is_instruction"] is False and
             request["client_role_is_grant"] is False and
             request["operation_identity"] == "STABLE_FOR_CASE_OR_PROPOSAL_READBACK",
             "HY-WC actor/scope request boundary drift")
    validate_intents(contract)
    projection = contract["projection"]
    _require({"project_id", "repository_id", "observed_revision", "observed_at", "inventory_coverage",
              "freshness", "claims", "cases", "retained_targets"} <= set(projection["required"]) and
             set(projection["inventory_coverage"]) == {"COMPLETE", "PARTIAL", "UNKNOWN", "OFFLINE"} and
             set(projection["freshness"]) == {"FRESH", "STALE", "UNKNOWN"} and
             set(projection["claim_classes"]) == {"FACT", "INFERENCE", "RECOMMENDATION", "DECISION"} and
             all(projection[key] is False for key in
                 ("unknown_is_zero", "case_closed_means_project_clean", "superseded_is_deleted",
                  "untrusted_repository_content_authorizes_action")) and
             all(projection[key] is True for key in
                 ("fact_requires_owner_evidence", "inference_requires_reason_uncertainty",
                  "decision_requires_owner_receipt")), "HY-WC evidence/coverage boundary drift")
    cleanup = contract["cleanup_boundary"]
    _require(cleanup["proposal_requires_frozen_exact_target_set"] is True and
             cleanup["confirmation_requires_expected_revision"] is True and
             cleanup["cancel_emits_execution_command"] is False and
             cleanup["lost_acknowledgement"] == "READ_BACK_SAME_OPERATION" and
             cleanup["execution_owner"] == "engineering-platform" and
             cleanup["execution_capability_in_this_contract"] is False and
             cleanup["mixed_outcome_is_all_success"] is False,
             "HY-WC cleanup authority drift")
    request_examples = examples["request_examples"]
    _require({entry["intent"] for entry in request_examples if entry["expected"] in
              {"AVAILABLE_READ", "AVAILABLE_OBSERVATION", "CASE_ONLY", "PROPOSAL_ONLY",
               "ENGINEERING_PROPOSAL_ONLY"}} == set(INTENTS), "HY-WC positive intent examples missing")
    _require({entry["expected"] for entry in request_examples} >=
             {"ASK_SCOPE", "DENIED", "UNSUPPORTED", "BLOCKED", "STALE"},
             "HY-WC negative request examples missing")
    for entry in request_examples:
        _require(type(entry["actor"]) is bool and type(entry["revision"]) is bool and
                 all(isinstance(target, str) for target in entry["targets"]) and
                 ("frozen_targets" not in entry or type(entry["frozen_targets"]) is bool),
                 f"HY-WC invalid request fixture: {entry['id']}")
        _require(entry["intent"] in INTENTS and request_state(entry, contract) == entry["expected"],
                 f"HY-WC unsafe request example: {entry['id']}")
    _require({entry["id"] for entry in request_examples} >=
             {"unfrozen-cleanup-set", "empty-cleanup-set", "stale-targets"},
             "HY-WC exact cleanup target negatives missing")
    for entry in examples["projection_examples"]:
        _require(entry["coverage"] in projection["inventory_coverage"] and
                 entry["freshness"] in projection["freshness"] and
                 projection_state(entry) == entry["expected"],
                 f"HY-WC unsafe projection example: {entry['id']}")
    _require({entry["expected"] for entry in examples["projection_examples"]} >=
             {"COMPLETE_FRESH", "INCOMPLETE", "STALE"}, "HY-WC negative projection examples missing")
    claim_examples = examples["claim_examples"]
    _require({entry["class"] for entry in claim_examples if entry["expected"]} ==
             set(projection["claim_classes"]) and
             {entry["class"] for entry in claim_examples if not entry["expected"]} >=
             {"FACT", "INFERENCE", "DECISION"}, "HY-WC claim classification cases missing")
    for entry in claim_examples:
        _require(all(type(entry[key]) is bool for key in
                     ("owner_evidence", "reason", "uncertainty", "owner_receipt", "expected")) and
                 valid_claim(entry) is entry["expected"],
                 f"HY-WC unsafe claim example: {entry['id']}")
    print("HY-WC scoped request, evidence classification and negative projection contract passed.")


if __name__ == "__main__":
    validate()
