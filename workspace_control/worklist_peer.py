"""Separate actor/workset read binding; no Forge writer or general proxy."""

import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat

from .forge_peer import _endpoint
from .review_peer import _id, _unique_pairs
from .service import _private_json, _regular_private


SCOPES_CONTRACT = "forge-workspace-worklist-scopes/v1"
_TOKEN = re.compile(r"[A-Za-z0-9_-]{43}\Z")
_FORGE_TOKEN = re.compile(r"[A-Za-z0-9_-]{32,256}\Z")
_MAX_RESPONSE = 1_000_000
_BINDING_FIELDS = {"id", "client_digest", "actor_id", "forge_instance_id",
                   "endpoint", "forge_token", "workset_ids"}


class WorklistError(ValueError):
    def __init__(self, state):
        self.state = state
        super().__init__(state)


def _shape(value, fields):
    if not isinstance(value, dict) or set(value) != set(fields):
        raise WorklistError("INVALID_RESPONSE")


def _ids(value, maximum):
    return (isinstance(value, list) and 1 <= len(value) <= maximum
            and all(_id(part) for part in value) and len(set(value)) == len(value))


def _get(binding, path):
    """Only internally selected GET routes; no caller-supplied method/body."""
    scheme, host, port = _endpoint(binding["endpoint"])
    connection = (http.client.HTTPSConnection(host, port, timeout=5,
                                              context=ssl.create_default_context())
                  if scheme == "https" else http.client.HTTPConnection(host, port, timeout=5))
    try:
        connection.request("GET", path, headers={"Authorization": "Bearer " + binding["forge_token"],
                                                "Accept": "application/json"})
        response = connection.getresponse()
        errors = {401: "UNAUTHORIZED", 403: "DENIED", 404: "NOT_FOUND",
                  409: "CONFLICT", 503: "UNAVAILABLE"}
        if response.status in errors:
            raise WorklistError(errors[response.status])
        if (response.status != 200 or
                response.getheader("Content-Type", "").split(";", 1)[0].lower() != "application/json"):
            raise WorklistError("INVALID_RESPONSE")
        length = response.getheader("Content-Length")
        if length is not None and (not length.isdecimal() or int(length) > _MAX_RESPONSE):
            raise WorklistError("INVALID_RESPONSE")
        raw = response.read(_MAX_RESPONSE + 1)
        if len(raw) > _MAX_RESPONSE:
            raise WorklistError("INVALID_RESPONSE")
        return json.loads(raw, object_pairs_hook=_unique_pairs)
    except WorklistError:
        raise
    except (ssl.SSLCertVerificationError, ssl.CertificateError):
        raise WorklistError("TLS_UNTRUSTED") from None
    except (OSError, TimeoutError, http.client.HTTPException):
        raise WorklistError("UNAVAILABLE") from None
    except (ValueError, UnicodeError, RecursionError):
        raise WorklistError("INVALID_RESPONSE") from None
    finally:
        connection.close()


def _scopes(value, binding, *, provisioning=False):
    _shape(value, {"contract_version", "instance_id", "principal_id", "workset_ids", "read_only"})
    if (value["contract_version"] != SCOPES_CONTRACT
            or value["instance_id"] != binding["forge_instance_id"]
            or value["principal_id"] != binding["actor_id"]
            or value["read_only"] is not True or not _ids(value["workset_ids"], 16)):
        raise WorklistError("INVALID_RESPONSE")
    if not provisioning and set(value["workset_ids"]) != set(binding["workset_ids"]):
        raise WorklistError("INVALID_RESPONSE")
    return value


def _valid_binding(binding):
    if not isinstance(binding, dict) or set(binding) != _BINDING_FIELDS:
        return False
    if (not all(_id(binding[key]) for key in ("id", "actor_id", "forge_instance_id"))
            or not isinstance(binding["client_digest"], str)
            or re.fullmatch(r"[0-9a-f]{64}", binding["client_digest"]) is None
            or not isinstance(binding["forge_token"], str)
            or _FORGE_TOKEN.fullmatch(binding["forge_token"]) is None
            or not _ids(binding["workset_ids"], 16)):
        return False
    try:
        _endpoint(binding["endpoint"])
    except ValueError:
        return False
    return True


class WorklistReadTransport:
    def __init__(self, root, root_fd, *, namespace="worklist"):
        if namespace not in ("worklist", "worklist-control", "advisory", "candidate", "mission", "workset-release"):
            raise ValueError("unsupported binding namespace")
        self.namespace = namespace
        self.root = Path(root)
        self.root_fd = root_fd

    scope_field = "workset_ids"

    def _valid_record(self, binding):
        return _valid_binding(binding)

    def _bindings(self):
        try:
            document = _private_json(self.namespace + "-bindings.json", dir_fd=self.root_fd)
        except FileNotFoundError:
            return []
        except (ValueError, OSError, UnicodeError):
            raise WorklistError("INVALID_CONFIGURATION") from None
        if (not isinstance(document, dict) or set(document) != {"bindings"}
                or not isinstance(document["bindings"], list) or len(document["bindings"]) > 100
                or not all(self._valid_record(binding) for binding in document["bindings"])):
            raise WorklistError("INVALID_CONFIGURATION")
        bindings = document["bindings"]
        for identity in (lambda item: item["id"], lambda item: item["client_digest"],
                         lambda item: (item["actor_id"], item["forge_instance_id"])):
            if len({identity(item) for item in bindings}) != len(bindings):
                raise WorklistError("INVALID_CONFIGURATION")
        return bindings

    def access(self, client_token):
        if not isinstance(client_token, str) or _TOKEN.fullmatch(client_token) is None:
            raise WorklistError("DENIED")
        digest = hashlib.sha256(client_token.encode("ascii")).hexdigest()
        for binding in self._bindings():
            if secrets.compare_digest(binding["client_digest"], digest):
                return binding
        raise WorklistError("DENIED")

    def _write_bindings(self, bindings):
        name = "." + self.namespace + "-bindings-" + secrets.token_hex(8)
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump({"bindings": bindings}, stream, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.namespace + "-bindings.json", src_dir_fd=self.root_fd,
                       dst_dir_fd=self.root_fd)
            os.fsync(self.root_fd)
        finally:
            try:
                os.unlink(name, dir_fd=self.root_fd)
            except FileNotFoundError:
                pass

    def _locked(self):
        descriptor = os.open("." + self.namespace + "-bindings.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            os.close(descriptor)
            raise WorklistError("INVALID_CONFIGURATION")
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        return descriptor

    def provision(self, actor_id, endpoint, forge_instance_id, forge_token_file, client_token_file):
        if not _id(actor_id) or not _id(forge_instance_id):
            raise ValueError("invalid worklist actor or Forge instance")
        _endpoint(endpoint)
        if not all(isinstance(path, str) and os.path.isabs(path)
                   for path in (forge_token_file, client_token_file)):
            raise ValueError("worklist token paths must be absolute")
        forge_token = _regular_private(forge_token_file).strip()
        if _FORGE_TOKEN.fullmatch(forge_token) is None:
            raise ValueError("invalid Forge worklist token")
        provisional = {"actor_id": actor_id, "endpoint": endpoint,
                       "forge_instance_id": forge_instance_id, "forge_token": forge_token}
        scopes = _scopes(_get(provisional, "/v1/worksets"), provisional, provisioning=True)
        provisional["workset_ids"] = scopes["workset_ids"]
        return self._provision_binding(provisional, client_token_file)

    def _provision_binding(self, provisional, client_token_file):
        actor_id = provisional["actor_id"]
        forge_instance_id = provisional["forge_instance_id"]
        info = os.stat(Path(client_token_file).parent, follow_symlinks=False)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("worklist client token parent must be private")
        token = secrets.token_urlsafe(32)
        binding = {"id": secrets.token_hex(16), "client_digest": hashlib.sha256(token.encode("ascii")).hexdigest(),
                   **provisional}
        lock = self._locked()
        try:
            bindings = self._bindings()
            if len(bindings) >= 100 or any(item["actor_id"] == actor_id and
                                           item["forge_instance_id"] == forge_instance_id for item in bindings):
                raise ValueError("worklist actor binding already exists or limit reached")
            descriptor = os.open(client_token_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
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
                "forge_instance_id": forge_instance_id, self.scope_field: binding[self.scope_field],
                "client_token_file": client_token_file}

    def revoke(self, binding_id):
        if not _id(binding_id):
            raise ValueError("invalid worklist binding ID")
        lock = self._locked()
        try:
            bindings = self._bindings()
            remaining = [item for item in bindings if item["id"] != binding_id]
            if len(remaining) == len(bindings):
                raise FileNotFoundError("worklist binding not found")
            self._write_bindings(remaining)
        finally:
            os.close(lock)
        return {"binding_id": binding_id, "state": "REVOKED"}

    def scopes(self, binding):
        return _scopes(_get(binding, "/v1/worksets"), binding)

    def projection(self, binding, workset_id):
        from .worklist_contract import validate_projection
        if not _id(workset_id) or workset_id not in binding["workset_ids"]:
            raise WorklistError("DENIED")
        return validate_projection(_get(binding, "/v1/worksets/" + workset_id), binding, workset_id)
