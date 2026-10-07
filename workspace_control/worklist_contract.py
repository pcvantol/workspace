"""Validate the pinned Forge worklist read projection without owning its decisions."""

from datetime import datetime, timezone
import hashlib
import json
import re

from .review_peer import _digest, _id, _text
from .worklist_peer import WorklistError, _shape


CONTRACT = "forge-workspace-worklist/v1"
SNAPSHOT_FIELDS = ("contract_version", "instance_id", "installation_id", "scope",
                   "membership_revision", "selector_revision", "workset_revision",
                   "activation_support", "completeness", "items", "continuation")
PROJECTION_FIELDS = set(SNAPSHOT_FIELDS) | {"snapshot_revision", "observed_at", "freshness", "read_only"}
ITEM_FIELDS = {"candidate_id", "subject_revision", "committed_order", "title", "mission_id",
               "mission_state_revision", "approved", "released", "eligibility", "blocking_reasons",
               "active", "execution_state", "engineering_result", "review_state", "final_acceptance",
               "completed", "effect_mode", "dependencies", "detail_reference", "allocation_binding",
               "evidence_references"}
_CODE = re.compile(r"[A-Z][A-Z0-9_]{0,63}\Z")
_EFFECTS = {"READ_ONLY_ASSESSMENT", "DOCUMENTATION_ONLY", "ARCHITECTURE_DESIGN_ONLY",
            "BOUNDED_REPOSITORY_CHANGE", "UNKNOWN"}


def snapshot_digest(value):
    selected = {key: value[key] for key in SNAPSHOT_FIELDS}
    return "sha256:" + hashlib.sha256(json.dumps(selected, sort_keys=True, ensure_ascii=False,
                                               separators=(",", ":")).encode("utf-8")).hexdigest()


def _require(condition):
    if not condition:
        raise WorklistError("INCONSISTENT_SNAPSHOT")


def _integer(value, minimum=0, maximum=2**63 - 1):
    return type(value) is int and minimum <= value <= maximum


def _enum(value, allowed):
    return isinstance(value, str) and value in allowed


def _codes(value):
    return (isinstance(value, list) and len(value) <= 64
            and all(isinstance(code, str) and _CODE.fullmatch(code) for code in value)
            and len(set(value)) == len(value))


def _timestamp(value):
    if not isinstance(value, str) or len(value) > 64:
        return False
    try:
        stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return stamp.tzinfo is not None and stamp.utcoffset() == timezone.utc.utcoffset(stamp)


def _allocation(item, installation):
    if item["mission_id"] is None:
        _require(item["mission_state_revision"] is None and item["allocation_binding"] is None
                 and item["detail_reference"] is None)
        return
    _require(_id(item["mission_id"]))
    binding = item["allocation_binding"]
    if binding is None:
        _require(item["execution_state"] == "UNAVAILABLE" and item["mission_state_revision"] is None
                 and item["detail_reference"] is None and item["evidence_references"] == [])
        return
    _require(_integer(item["mission_state_revision"]))
    _shape(binding, {"kind", "candidate_id", "subject_revision", "mission_id", "installation_id", "envelope_digest"})
    _require(binding["kind"] == "CANONICAL_CANDIDATE_INTAKE"
             and binding["candidate_id"] == item["candidate_id"]
             and binding["subject_revision"] == item["subject_revision"]
             and binding["mission_id"] == item["mission_id"]
             and binding["installation_id"] == installation and _digest(binding["envelope_digest"]))
    if item["detail_reference"] is not None:
        detail = item["detail_reference"]
        _shape(detail, {"kind", "mission_id"})
        _require(detail["kind"] == "MISSION_REVIEW" and detail["mission_id"] == item["mission_id"])


def _evidence(item):
    values = item["evidence_references"]
    _require(isinstance(values, list) and len(values) <= 16)
    identities = []
    for reference in values:
        _shape(reference, {"kind", "subject_id", "digest"})
        _require(_enum(reference["kind"], {"MISSION_COMPLETION", "FINAL_BUSINESS_ACCEPTANCE"})
                 and _id(reference["subject_id"]) and _digest(reference["digest"]))
        _require(item["mission_id"] is not None)
        if reference["kind"] == "MISSION_COMPLETION":
            _require(reference["subject_id"] == item["mission_id"])
        identities.append((reference["kind"], reference["subject_id"], reference["digest"]))
    _require(len(set(identities)) == len(identities))


def _item(item, installation):
    _shape(item, ITEM_FIELDS)
    _require(_id(item["candidate_id"]) and _digest(item["subject_revision"])
             and _integer(item["committed_order"], maximum=63) and _text(item["title"], 160))
    _require(all(type(item[key]) is bool for key in ("approved", "released", "active", "completed")))
    _require(_enum(item["eligibility"], {"ELIGIBLE", "BLOCKED", "UNKNOWN"})
             and _enum(item["engineering_result"], {"PROVEN", "UNPROVEN", "UNKNOWN"})
             and _enum(item["review_state"], {"WAITING", "ACCEPTED", "NONE", "UNKNOWN"})
             and _enum(item["final_acceptance"], {"WAITING", "ACCEPTED", "NOT_REQUIRED", "UNKNOWN"})
             and _enum(item["effect_mode"], _EFFECTS))
    _require(isinstance(item["execution_state"], str) and _CODE.fullmatch(item["execution_state"])
             and _codes(item["blocking_reasons"]))
    dependencies = item["dependencies"]
    _require(isinstance(dependencies, list) and len(dependencies) <= 64
             and all(_id(value) for value in dependencies) and len(set(dependencies)) == len(dependencies))
    _allocation(item, installation)
    _evidence(item)


def _continuation(value, items, complete):
    _shape(value, {"state", "candidate_id", "mission_id", "committed_order", "reason_codes"})
    _require(_enum(value["state"], {"READY", "BLOCKED", "IDLE", "UNKNOWN"}) and _codes(value["reason_codes"]))
    if value["candidate_id"] is None:
        _require(value["mission_id"] is None and value["committed_order"] is None)
        _require(value["state"] in {"IDLE", "UNKNOWN"})
        if value["state"] == "IDLE":
            _require(complete)
        return
    _require(_id(value["candidate_id"]))
    matched = next((item for item in items if item["candidate_id"] == value["candidate_id"]), None)
    _require(matched is not None)
    _require(value["state"] != "IDLE" and value["mission_id"] == matched["mission_id"]
             and type(value["committed_order"]) is int
             and value["committed_order"] == matched["committed_order"])


def validate_projection(value, binding, workset_id):
    _shape(value, PROJECTION_FIELDS)
    _require(value["contract_version"] == CONTRACT and value["instance_id"] == binding["forge_instance_id"]
             and _id(value["installation_id"]) and value["read_only"] is True)
    scope = value["scope"]
    _shape(scope, {"kind", "principal_id", "workset_id", "project_id"})
    _require(scope["kind"] == "EXPLICIT_WORKSET" and scope["principal_id"] == binding["actor_id"]
             and scope["workset_id"] == workset_id and scope["project_id"] is None)
    _require(all(_digest(value[key]) for key in ("membership_revision", "selector_revision", "snapshot_revision"))
             and _integer(value["workset_revision"], 1) and _timestamp(value["observed_at"]))
    _require(value["freshness"] == "CURRENT_READBACK"
             and _enum(value["completeness"], {"COMPLETE_WITHIN_SCOPE", "PARTIAL"})
             and _enum(value["activation_support"], {"NOT_YET_QUALIFIED", "QUALIFIED_SERIAL_APPROVED_WORKLIST"}))
    items = value["items"]
    _require(isinstance(items, list) and len(items) <= 64)
    for item in items:
        _item(item, value["installation_id"])
    by_id = {item["candidate_id"]: item for item in items}
    positions = {item["committed_order"] for item in items}
    _require(len(by_id) == len(items) and len(positions) == len(items))
    complete = value["completeness"] == "COMPLETE_WITHIN_SCOPE"
    if complete:
        _require(positions == set(range(len(items)))
                 and all(item["execution_state"] != "UNAVAILABLE" for item in items))
    for item in items:
        for dependency in item["dependencies"]:
            if dependency in by_id:
                _require(by_id[dependency]["committed_order"] < item["committed_order"])
            else:
                _require(not complete)
    _continuation(value["continuation"], items, complete)
    _require(value["snapshot_revision"] == snapshot_digest(value))
    return value
