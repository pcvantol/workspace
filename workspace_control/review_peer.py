"""Actor-bound Workspace transport for Forge's scoped Mission review V1."""

from datetime import datetime, timezone
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import ssl
import stat

from .forge_peer import _endpoint
from .service import _private_json, _regular_private


_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}\Z")
_DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")
_TOKEN = re.compile(r"[A-Za-z0-9_-]{43}\Z")
_OUTCOMES = frozenset(("approve", "reject", "amend", "defer"))
_INBOX = "forge-workspace-review-inbox/v1"
_DECISION = "forge-workspace-review-decision/v1"
_OPERATION = "forge-workspace-review-operation/v1"
_MAX_RESPONSE = 256_000


class ReviewError(ValueError):
    def __init__(self, state):
        self.state = state
        super().__init__(state)


def _id(value):
    return isinstance(value, str) and _ID.fullmatch(value) is not None


def _digest(value):
    return isinstance(value, str) and _DIGEST.fullmatch(value) is not None


def _text(value, limit, *, nullable=False):
    return ((nullable and value is None) or
            (isinstance(value, str) and len(value) <= limit and
             all(ord(character) >= 32 for character in value)))


def _time(value):
    if not isinstance(value, str):
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def _shape(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise ReviewError("INVALID_RESPONSE")


def _request(binding, method, path, body=None):
    scheme, host, port = _endpoint(binding["endpoint"])
    connection = (http.client.HTTPSConnection(host, port, timeout=5, context=ssl.create_default_context())
                  if scheme == "https" else http.client.HTTPConnection(host, port, timeout=5))
    try:
        payload = (None if body is None else
                   json.dumps(body, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
        headers = {"Authorization": "Bearer " + binding["forge_token"],
                   "Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        connection.request(method, path, body=payload, headers=headers)
        response = connection.getresponse()
        if response.status in (401, 403, 404, 409, 503):
            raise ReviewError({401: "UNAUTHORIZED", 403: "DENIED", 404: "NOT_FOUND",
                               409: "CONFLICT", 503: "UNAVAILABLE"}[response.status])
        if (response.status not in (200, 201) or
                response.getheader("Content-Type", "").split(";", 1)[0].lower() != "application/json"):
            raise ReviewError("INVALID_RESPONSE")
        length = response.getheader("Content-Length")
        if length is not None and (not length.isdecimal() or int(length) > _MAX_RESPONSE):
            raise ReviewError("INVALID_RESPONSE")
        raw = response.read(_MAX_RESPONSE + 1)
        if len(raw) > _MAX_RESPONSE:
            raise ReviewError("INVALID_RESPONSE")
        return response.status, json.loads(raw, object_pairs_hook=_unique_pairs)
    except ReviewError:
        raise
    except (ssl.SSLCertVerificationError, ssl.CertificateError):
        raise ReviewError("TLS_UNTRUSTED") from None
    except (OSError, TimeoutError, http.client.HTTPException):
        raise ReviewError("UNAVAILABLE") from None
    except (ValueError, UnicodeError, RecursionError):
        raise ReviewError("INVALID_RESPONSE") from None
    finally:
        connection.close()


def _unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _item(value, binding, mission_id=None):
    _shape(value, ("contract_version", "instance_id", "mission_id", "authority", "title",
                   "lifecycle_state", "mission_state_revision", "review_kind", "decision",
                   "requirement", "action_result", "allowed_outcomes", "observed_at", "freshness"))
    if (value["contract_version"] != _INBOX or value["instance_id"] != binding["forge_instance_id"]
            or not _id(value["mission_id"]) or value["mission_id"] not in binding["mission_ids"]
            or mission_id is not None and value["mission_id"] != mission_id
            or not _text(value["title"], 160, nullable=True)
            or not _text(value["lifecycle_state"], 64) or not value["lifecycle_state"]
            or type(value["mission_state_revision"]) is not int or value["mission_state_revision"] < 1
            or value["review_kind"] not in ("PROGRESSION", "FINAL_ACCEPTANCE", "EXTERNAL_GATE", "NONE")
            or not _time(value["observed_at"]) or value["freshness"] != "CURRENT_FORGE_RUNTIME_READBACK"):
        raise ReviewError("INVALID_RESPONSE")
    authority = value["authority"]
    _shape(authority, ("principal_id", "role", "role_actor", "capability", "expires_at"))
    if (authority["principal_id"] != binding["actor_id"] or
            authority["role"] != "platform_architect" or
            authority["role_actor"] != "primary_operator" or
            authority["capability"] != "ARCHITECTURE_APPROVAL" or
            not _time(authority["expires_at"])):
        raise ReviewError("INVALID_RESPONSE")
    requirement = value["requirement"]
    if requirement is not None:
        _shape(requirement, ("requirement_id", "subject_digest", "subject_revision",
                             "mission_state_revision", "completed_action_id", "evidence_digest",
                             "policy_revision", "policy_digest", "required_role", "required_role_actor",
                             "required_capability", "reason", "blocking_scope",
                             "blocking_scope_redacted", "status"))
        if (not _id(requirement["requirement_id"]) or not _digest(requirement["subject_digest"])
                or not _text(requirement["subject_revision"], 128, nullable=True)
                or type(requirement["mission_state_revision"]) is not int
                or requirement["mission_state_revision"] < 1
                or requirement["mission_state_revision"] > value["mission_state_revision"]
                or requirement["completed_action_id"] is not None and not _id(requirement["completed_action_id"])
                or requirement["evidence_digest"] is not None and not _digest(requirement["evidence_digest"])
                or not _text(requirement["policy_revision"], 128, nullable=True)
                or requirement["policy_digest"] is not None and not _digest(requirement["policy_digest"])
                or not _text(requirement["required_role"], 64)
                or not _text(requirement["required_role_actor"], 128, nullable=True)
                or not _text(requirement["required_capability"], 64)
                or not _text(requirement["reason"], 512, nullable=True)
                or not isinstance(requirement["blocking_scope"], list)
                or len(requirement["blocking_scope"]) > 64
                or any(not _text(part, 256) for part in requirement["blocking_scope"])
                or type(requirement["blocking_scope_redacted"]) is not bool
                or not _text(requirement["status"], 64, nullable=True)):
            raise ReviewError("INVALID_RESPONSE")
    decision = value["decision"]
    if decision is not None:
        _shape(decision, ("decision_id", "outcome", "decision_digest"))
        if (decision["decision_id"] is not None and not _id(decision["decision_id"]) or
                not isinstance(decision["outcome"], str) or
                decision["outcome"] not in _OUTCOMES or not _digest(decision["decision_digest"])):
            raise ReviewError("INVALID_RESPONSE")
    action = value["action_result"]
    if action is not None:
        _shape(action, ("action_id", "status", "outcome", "evidence_reference"))
        if (not _id(action["action_id"]) or not _text(action["status"], 32, nullable=True)
                or not _text(action["outcome"], 32, nullable=True)):
            raise ReviewError("INVALID_RESPONSE")
        reference = action["evidence_reference"]
        if reference is not None:
            _shape(reference, ("kind", "digest", "receipt_id"))
            if (reference["kind"] != "FORGE_EXECUTION_EVIDENCE" or
                    not _digest(reference["digest"]) or
                    reference["receipt_id"] is not None and not _id(reference["receipt_id"])):
                raise ReviewError("INVALID_RESPONSE")
    outcomes = value["allowed_outcomes"]
    if (not isinstance(outcomes, list) or len(outcomes) > 4 or
            any(not isinstance(outcome, str) or outcome not in _OUTCOMES for outcome in outcomes)
            or len(set(outcomes)) != len(outcomes)):
        raise ReviewError("INVALID_RESPONSE")
    if outcomes and (value["review_kind"] != "PROGRESSION" or requirement is None or
                     decision is not None or value["lifecycle_state"] != "AWAITING_APPROVAL" or
                     requirement["evidence_digest"] is None or not requirement["policy_revision"] or
                     requirement["required_role"] != authority["role"] or
                     requirement["required_role_actor"] != authority["role_actor"] or
                     requirement["required_capability"] != authority["capability"]):
        raise ReviewError("INVALID_RESPONSE")
    if value["review_kind"] in ("NONE", "EXTERNAL_GATE") and (requirement is not None or outcomes):
        raise ReviewError("INVALID_RESPONSE")
    if value["review_kind"] == "FINAL_ACCEPTANCE" and outcomes:
        raise ReviewError("INVALID_RESPONSE")
    return value


def _inbox(value, binding):
    _shape(value, ("contract_version", "instance_id", "scope", "items", "read_only"))
    if (value["contract_version"] != _INBOX or value["instance_id"] != binding["forge_instance_id"]
            or value["read_only"] is not True):
        raise ReviewError("INVALID_RESPONSE")
    scope = value["scope"]
    _shape(scope, ("kind", "principal_id", "mission_ids", "complete_within_scope"))
    if (scope["kind"] != "EXPLICIT_MISSION_SET" or scope["principal_id"] != binding["actor_id"]
            or scope["complete_within_scope"] is not True
            or not isinstance(scope["mission_ids"], list)
            or not 1 <= len(scope["mission_ids"]) <= 32
            or any(not _id(mission) for mission in scope["mission_ids"])
            or len(set(scope["mission_ids"])) != len(scope["mission_ids"])
            or set(scope["mission_ids"]) != set(binding["mission_ids"])
            or len(scope["mission_ids"]) != len(binding["mission_ids"])):
        raise ReviewError("INVALID_RESPONSE")
    items = value["items"]
    if (not isinstance(items, list) or len(items) != len(binding["mission_ids"]) or
            len(items) > 32):
        raise ReviewError("INVALID_RESPONSE")
    for item in items:
        _item(item, binding)
    if {item["mission_id"] for item in items} != set(binding["mission_ids"]):
        raise ReviewError("INVALID_RESPONSE")
    return value


def _decision_request(value, operation_id=None):
    fields = ("contract_version", "operation_id", "requirement_id", "subject_digest",
              "mission_state_revision", "evidence_digest", "policy_revision", "decision", "reason")
    if not isinstance(value, dict) or set(value) != set(fields):
        raise ReviewError("INVALID_REQUEST")
    if (value["contract_version"] != _DECISION or not _id(value["operation_id"])
            or operation_id is not None and value["operation_id"] != operation_id
            or not _id(value["requirement_id"]) or not _digest(value["subject_digest"])
            or type(value["mission_state_revision"]) is not int or value["mission_state_revision"] < 1
            or not _digest(value["evidence_digest"])
            or not _text(value["policy_revision"], 128) or not value["policy_revision"]
            or not isinstance(value["decision"], str) or value["decision"] not in _OUTCOMES
            or not _text(value["reason"], 512)
            or not value["reason"]):
        raise ReviewError("INVALID_REQUEST")
    return value


def _request_digest(mission_id, request):
    encoded = json.dumps(request | {"mission_id": mission_id}, sort_keys=True,
                         ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def _operation_response(value, binding, mission_id, request, *, submitted):
    fields = (("contract_version", "operation", "current", "runtime_status", "recorded")
              if submitted else ("contract_version", "operation", "current", "read_only"))
    _shape(value, fields)
    if value["contract_version"] != _OPERATION:
        raise ReviewError("INVALID_RESPONSE")
    if submitted:
        if type(value["recorded"]) is not bool or not _text(value["runtime_status"], 64, nullable=True):
            raise ReviewError("INVALID_RESPONSE")
    elif value["read_only"] is not True:
        raise ReviewError("INVALID_RESPONSE")
    operation = value["operation"]
    _shape(operation, ("operation_id", "mission_id", "requirement_id", "subject_digest",
                       "decision", "decision_digest", "request_digest", "recorded_at"))
    if (operation["operation_id"] != request["operation_id"] or
            operation["mission_id"] != mission_id or
            operation["requirement_id"] != request["requirement_id"] or
            operation["subject_digest"] != request["subject_digest"] or
            operation["decision"] != request["decision"] or
            not _digest(operation["decision_digest"]) or
            operation["request_digest"] != _request_digest(mission_id, request) or
            not _time(operation["recorded_at"])):
        raise ReviewError("INVALID_RESPONSE")
    current = _item(value["current"], binding, mission_id)
    if current["mission_state_revision"] < request["mission_state_revision"]:
        raise ReviewError("INVALID_RESPONSE")
    return value


class ReviewTransport:
    def __init__(self, root, root_fd):
        self.root = Path(root)
        self.root_fd = root_fd

    def _bindings(self):
        try:
            document = _private_json("review-bindings.json", dir_fd=self.root_fd)
        except FileNotFoundError:
            return []
        if (not isinstance(document, dict) or set(document) != {"bindings"} or
                not isinstance(document["bindings"], list) or len(document["bindings"]) > 100):
            raise ReviewError("INVALID_CONFIGURATION")
        for binding in document["bindings"]:
            if (not isinstance(binding, dict) or
                    set(binding) != {"id", "client_digest", "actor_id", "forge_instance_id",
                                     "endpoint", "forge_token", "mission_ids"} or
                    not _id(binding["id"]) or not isinstance(binding["client_digest"], str)
                    or not _digest("sha256:" + binding["client_digest"])
                    or not _id(binding["actor_id"]) or not _id(binding["forge_instance_id"])
                    or not isinstance(binding["forge_token"], str)
                    or re.fullmatch(r"[A-Za-z0-9_-]{32,256}", binding["forge_token"]) is None
                    or not isinstance(binding["mission_ids"], list)
                    or not 1 <= len(binding["mission_ids"]) <= 32
                    or any(not _id(mission) for mission in binding["mission_ids"])
                    or len(set(binding["mission_ids"])) != len(binding["mission_ids"])):
                raise ReviewError("INVALID_CONFIGURATION")
            try:
                _endpoint(binding["endpoint"])
            except ValueError:
                raise ReviewError("INVALID_CONFIGURATION") from None
        if (len({binding["id"] for binding in document["bindings"]}) != len(document["bindings"])
                or len({binding["client_digest"] for binding in document["bindings"]})
                != len(document["bindings"])
                or len({(binding["actor_id"], binding["forge_instance_id"])
                        for binding in document["bindings"]}) != len(document["bindings"])):
            raise ReviewError("INVALID_CONFIGURATION")
        return document["bindings"]

    def access(self, client_token):
        if not isinstance(client_token, str) or _TOKEN.fullmatch(client_token) is None:
            raise ReviewError("DENIED")
        digest = hashlib.sha256(client_token.encode("ascii")).hexdigest()
        for binding in self._bindings():
            if secrets.compare_digest(binding["client_digest"], digest):
                return binding
        raise ReviewError("DENIED")

    def _write_bindings(self, bindings):
        temporary = ".review-bindings-" + secrets.token_hex(8)
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump({"bindings": bindings}, stream, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, "review-bindings.json", src_dir_fd=self.root_fd,
                       dst_dir_fd=self.root_fd)
            os.fsync(self.root_fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.root_fd)
            except FileNotFoundError:
                pass

    def _locked(self):
        descriptor = os.open(".review-bindings.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            os.close(descriptor)
            raise ReviewError("INVALID_CONFIGURATION")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        return descriptor

    def provision(self, actor_id, endpoint, forge_instance_id, forge_token_file, client_token_file):
        if not _id(actor_id) or not _id(forge_instance_id):
            raise ValueError("invalid review actor or Forge instance")
        _endpoint(endpoint)
        if (not isinstance(forge_token_file, str) or not os.path.isabs(forge_token_file)
                or not isinstance(client_token_file, str) or not os.path.isabs(client_token_file)):
            raise ValueError("review token paths must be absolute")
        forge_token = _regular_private(forge_token_file).strip()
        if re.fullmatch(r"[A-Za-z0-9_-]{32,256}", forge_token) is None:
            raise ValueError("invalid Forge review token")
        provisional = {"endpoint": endpoint, "forge_token": forge_token,
                       "forge_instance_id": forge_instance_id, "actor_id": actor_id,
                       "mission_ids": []}
        _, response = _request(provisional, "GET", "/v1/reviews")
        scope = response.get("scope") if isinstance(response, dict) else None
        if not isinstance(scope, dict) or not isinstance(scope.get("mission_ids"), list):
            raise ReviewError("INVALID_RESPONSE")
        provisional["mission_ids"] = scope["mission_ids"]
        _inbox(response, provisional)
        parent = Path(client_token_file).parent
        info = os.stat(parent, follow_symlinks=False)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("client token parent must be private")
        token = secrets.token_urlsafe(32)
        binding = {"id": secrets.token_hex(16),
                   "client_digest": hashlib.sha256(token.encode("ascii")).hexdigest(),
                   **provisional}
        lock = self._locked()
        try:
            bindings = self._bindings()
            if len(bindings) >= 100 or any(item["actor_id"] == actor_id and
                                           item["forge_instance_id"] == forge_instance_id
                                           for item in bindings):
                raise ValueError("review actor binding already exists or limit reached")
            descriptor = os.open(client_token_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                 0o600)
            try:
                with os.fdopen(descriptor, "w", encoding="ascii") as stream:
                    stream.write(token + "\n")
                    stream.flush()
                    os.fsync(stream.fileno())
                self._write_bindings(bindings + [binding])
            except Exception:
                os.unlink(client_token_file)
                raise
        finally:
            os.close(lock)
        return {"binding_id": binding["id"], "actor_id": actor_id,
                "forge_instance_id": forge_instance_id, "mission_ids": binding["mission_ids"],
                "client_token_file": client_token_file}

    def revoke(self, binding_id):
        if not _id(binding_id):
            raise ValueError("invalid review binding ID")
        lock = self._locked()
        try:
            bindings = self._bindings()
            remaining = [item for item in bindings if item["id"] != binding_id]
            if len(remaining) == len(bindings):
                raise FileNotFoundError("review binding not found")
            self._write_bindings(remaining)
        finally:
            os.close(lock)
        return {"binding_id": binding_id, "state": "REVOKED"}

    def inbox(self, binding):
        status, value = _request(binding, "GET", "/v1/reviews")
        if status != 200:
            raise ReviewError("INVALID_RESPONSE")
        return _inbox(value, binding)

    def item(self, binding, mission_id):
        if not _id(mission_id) or mission_id not in binding["mission_ids"]:
            raise ReviewError("DENIED")
        status, value = _request(binding, "GET", f"/v1/reviews/missions/{mission_id}")
        if status != 200:
            raise ReviewError("INVALID_RESPONSE")
        return _item(value, binding, mission_id)

    def _connect_intents(self, *, create=False):
        path = self.root / "review-intents.sqlite3"
        if create:
            try:
                descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            except FileExistsError:
                pass
            else:
                os.close(descriptor)
        info = os.stat(path, follow_symlinks=False)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ReviewError("INVALID_CONFIGURATION")
        connection = sqlite3.connect(path, timeout=5)
        if create:
            connection.execute("""CREATE TABLE IF NOT EXISTS intents (
                actor_id TEXT NOT NULL, operation_id TEXT NOT NULL, mission_id TEXT NOT NULL,
                request_json TEXT NOT NULL, request_digest TEXT NOT NULL,
                PRIMARY KEY(actor_id, operation_id))""")
            connection.commit()
        return connection

    def _persist_intent(self, binding, mission_id, request):
        encoded = json.dumps(request, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        digest = _request_digest(mission_id, request)
        connection = self._connect_intents(create=True)
        try:
            with connection:
                connection.execute("BEGIN IMMEDIATE")
                row = connection.execute("""SELECT mission_id, request_digest FROM intents
                    WHERE actor_id=? AND operation_id=?""",
                    (binding["actor_id"], request["operation_id"])).fetchone()
                if row is None:
                    connection.execute("""INSERT INTO intents
                        (actor_id, operation_id, mission_id, request_json, request_digest)
                        VALUES (?,?,?,?,?)""",
                        (binding["actor_id"], request["operation_id"], mission_id, encoded, digest))
                elif row != (mission_id, digest):
                    raise ReviewError("CONFLICT")
        finally:
            connection.close()

    def _intent(self, binding, mission_id, operation_id):
        try:
            connection = self._connect_intents()
        except FileNotFoundError:
            raise ReviewError("NOT_FOUND") from None
        try:
            row = connection.execute("""SELECT mission_id, request_json, request_digest FROM intents
                WHERE actor_id=? AND operation_id=?""", (binding["actor_id"], operation_id)).fetchone()
        finally:
            connection.close()
        if row is None or row[0] != mission_id:
            raise ReviewError("NOT_FOUND")
        try:
            request = json.loads(row[1], object_pairs_hook=_unique_pairs)
            _decision_request(request, operation_id)
        except (ValueError, UnicodeError):
            raise ReviewError("INVALID_CONFIGURATION") from None
        if row[2] != _request_digest(mission_id, request):
            raise ReviewError("INVALID_CONFIGURATION")
        return request

    def submit(self, binding, mission_id, request):
        if not _id(mission_id) or mission_id not in binding["mission_ids"]:
            raise ReviewError("DENIED")
        _decision_request(request)
        self._persist_intent(binding, mission_id, request)
        status, value = _request(binding, "POST", f"/v1/reviews/missions/{mission_id}/decisions", request)
        if status not in (200, 201):
            raise ReviewError("INVALID_RESPONSE")
        _operation_response(value, binding, mission_id, request, submitted=True)
        if value["recorded"] != (status == 201):
            raise ReviewError("INVALID_RESPONSE")
        return status, value

    def readback(self, binding, mission_id, operation_id):
        if not _id(mission_id) or mission_id not in binding["mission_ids"]:
            raise ReviewError("DENIED")
        if not _id(operation_id):
            raise ReviewError("INVALID_REQUEST")
        request = self._intent(binding, mission_id, operation_id)
        status, value = _request(binding, "GET",
                                 f"/v1/reviews/missions/{mission_id}/decisions/{operation_id}")
        if status != 200:
            raise ReviewError("INVALID_RESPONSE")
        return _operation_response(value, binding, mission_id, request, submitted=False)
