"""Offline PB-W0 contract and negative-example guard; no product runtime."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
JOURNEYS = {"NEW_GENESIS", "ADOPT_GENESIS", "NEW_MANAGED", "ADOPT_MANAGED", "PROMOTE_GENESIS"}
PHASES = {"prepare", "submit", "readback", "enter"}
JOURNEY_BOUNDARIES = {
    "NEW_GENESIS": ("NONE", "GENESIS", "LOCAL_MISSING_EMPTY_OR_UNBORN", "FORBIDDEN", "PROVISIONAL", "EP_GENESIS_CREATE"),
    "ADOPT_GENESIS": ("LOCAL_EXISTING", "GENESIS", "LOCAL_EXISTING_REVIEWED", "FORBIDDEN", "PROVISIONAL", "EP_GENESIS_ADOPT"),
    "NEW_MANAGED": ("NONE", "MANAGED", "REMOTE_ABSENT_VERIFIED", "EXPLICIT_APPROVAL_REQUIRED", "PROVISIONAL", "EP_MANAGED_CREATE"),
    "ADOPT_MANAGED": ("REMOTE_EXISTING", "MANAGED", "REMOTE_EXISTING_REVIEWED", "EXPLICIT_APPROVAL_REQUIRED", "PROVISIONAL", "EP_MANAGED_ADOPT"),
    "PROMOTE_GENESIS": ("GENESIS", "MANAGED", "EXISTING_GENESIS_AND_EXPLICIT_REMOTE_DESTINATION",
                        "HISTORY_PUBLICATION_APPROVAL_REQUIRED", "EXISTING_COMMITTED", "EP_PROMOTE_MANAGED"),
}


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate contract key: {key}")
        result[key] = value
    return result


def _load(name):
    return json.loads((DOCS / name).read_text(), object_pairs_hook=_unique)


def _require(condition, message):
    if not condition:
        raise ValueError(message)


def submit_state(example):
    if not example["fresh"]:
        return "STALE"
    if example["owner_capability"] in {"UNSUPPORTED", "UNAVAILABLE", "DENIED"}:
        return example["owner_capability"]
    if example["owner_capability"] != "QUALIFIED_AUTHORIZED":
        return "BLOCKED"
    if not all(example[key] for key in ("frozen_plan", "decisions", "stable_operation")):
        return "BLOCKED"
    if example["journey"] in {"NEW_MANAGED", "ADOPT_MANAGED", "PROMOTE_GENESIS"} and not example.get("remote_approval", False):
        return "BLOCKED"
    if example["journey"] == "PROMOTE_GENESIS" and not example.get("history_review", False):
        return "BLOCKED"
    return "AVAILABLE"


def validate_journey_boundaries(contract):
    owners = contract["capability_families"]
    journeys = contract["journeys"]
    by_id = {journey["id"]: journey for journey in journeys}
    _require(len(journeys) == len(by_id) == 5 and set(by_id) == JOURNEYS,
             "PB-W0 must define exactly five distinct journeys")
    for name, journey in by_id.items():
        phases = journey["capabilities_by_phase"]
        _require(set(phases) == PHASES and all(phases[phase] for phase in PHASES),
                 f"PB-W0 missing capability phase: {name}")
        _require(all(capability in owners for group in phases.values() for capability in group),
                 f"PB-W0 unknown capability: {name}")
        source_mode, target_mode, target_class, remote_effect, identity, submit = JOURNEY_BOUNDARIES[name]
        _require((journey["source_mode"], journey["target_mode"], journey["target_class"],
                  journey["remote_effect"], journey["identity_before_readback"]) ==
                 (source_mode, target_mode, target_class, remote_effect, identity),
                 f"PB-W0 source/target/remote boundary drift: {name}")
        _require(phases["submit"] == [submit] and owners[submit] == "engineering-platform" and
                 journey["effect_owner"] == "engineering-platform",
                 f"PB-W0 journey submit operation escaped owner boundary: {name}")
        _require(phases["readback"] == ["EP_OPERATION_READBACK"] and
                 phases["enter"] == ["FORGE_PROJECT_READINESS"] and
                 "FORGE_ARTIFACT_PLAN" in phases["prepare"] and
                 ("EP_HOST_TARGET_INVENTORY" if target_mode == "GENESIS" else "EP_PROVIDER_SCOPE") in phases["prepare"],
                 f"PB-W0 prepare/readback/readiness boundary drift: {name}")


def validate():
    contract = _load("PROJECT_BOOTSTRAP_W0_CONTRACT_V1.json")
    examples = _load("PROJECT_BOOTSTRAP_W0_EXAMPLES_V1.json")
    dag = _load("PROJECT_BOOTSTRAP_V1_DAG.json")
    _require(contract["schema_version"] == examples["schema_version"] == 1, "PB-W0 schema mismatch")
    _require(contract["contract"] == examples["contract"], "PB-W0 fixture mismatch")
    _require(contract["authority"] == "CONTRACT_ONLY" and
             contract["producer_bindings"] == "UNQUALIFIED", "PB-W0 cannot claim runtime authority")
    identity = contract["identity"]
    _require(identity["canonical_source"] == "EP_COMMITTED_REPOSITORY_DECLARATION" and
             identity["reservation"] == "PROVISIONAL_UNTIL_OWNER_READBACK" and
             identity["display_name_is_identity"] is False and
             identity["promotion_preserves_project_and_repository_ids"] is True,
             "PB-W0 identity authority drift")
    owners = contract["capability_families"]
    _require(owners and set(owners.values()) == {"forge", "engineering-platform"} and
             all(name.startswith("FORGE_") == (owner == "forge") for name, owner in owners.items()),
             "PB-W0 capability owner drift")
    validate_journey_boundaries(contract)
    by_id = {journey["id"]: journey for journey in contract["journeys"]}
    submission = contract["submission"]
    _require(submission["mode_fallback"] == "FORBIDDEN" and
             submission["workspace_executes_effects"] is False and
             submission["draft_is_authorization"] is False and
             submission["lost_acknowledgement"] == "READ_BACK_SAME_OPERATION" and
             {"EXACT_SCOPE", "FRESH_CAPABILITY_SNAPSHOT", "QUALIFIED_OWNER_OPERATION",
              "FROZEN_PLAN_DIGEST", "APPLICABLE_DECISION_RECEIPTS", "STABLE_OPERATION_ID"}
             <= set(submission["requires"]), "PB-W0 submission authority drift")
    shape = {"id", "journey", "owner_capability", "fresh", "frozen_plan", "decisions", "stable_operation", "expected"}
    optional = {"remote_approval", "history_review"}
    _require(all(shape <= set(example) <= shape | optional for example in examples["submit_examples"]) and
             len({example["id"] for example in examples["submit_examples"]}) == len(examples["submit_examples"]),
             "PB-W0 example shape drift")
    _require({example["journey"] for example in examples["submit_examples"] if example["expected"] == "AVAILABLE"}
             == JOURNEYS, "PB-W0 examples must cover five ready journeys")
    _require({example["expected"] for example in examples["submit_examples"]}
             >= {"AVAILABLE", "UNSUPPORTED", "UNAVAILABLE", "DENIED", "STALE", "BLOCKED"},
             "PB-W0 negative examples missing")
    _require({example["id"] for example in examples["submit_examples"]} >=
             {"managed-requires-remote-approval", "promotion-requires-history-review"},
             "PB-W0 remote/history negatives missing")
    for example in examples["submit_examples"]:
        _require(example["owner_capability"] in
                 {"QUALIFIED_AUTHORIZED", "UNSUPPORTED", "UNAVAILABLE", "DENIED"} and
                 all(type(example[key]) is bool for key in
                     ("fresh", "frozen_plan", "decisions", "stable_operation")) and
                 all(type(example[key]) is bool for key in optional if key in example),
                 f"PB-W0 invalid example input: {example['id']}")
        _require(example["journey"] in by_id and submit_state(example) == example["expected"] and
                 example["expected"] in contract["projection_states"],
                 f"PB-W0 unsafe projection example: {example['id']}")
    _require({(entry["owner_readback"], entry["expected"]) for entry in examples["identity_examples"]} ==
             {("NONE", "PROVISIONAL"), ("EP_COMMITTED_REPOSITORY_DECLARATION", "COMMITTED"),
              ("EP_PROMOTION_READBACK_SAME_IDS", "COMMITTED_SAME_IDS")},
             "PB-W0 provisional/committed identity examples missing")
    nodes = {node["id"]: node for node in dag["nodes"]}
    _require(nodes["PB-W0"]["depends_on"] == [] and "PB-W0" in nodes["PB-W1"]["depends_on"],
             "PB-W0 dependency edge drift")
    print("PB-W0 five-journey intent, owner boundary and negative projection contract passed.")


if __name__ == "__main__":
    validate()
