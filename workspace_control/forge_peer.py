"""Bounded read-only Forge Server HTTP consumer for Workspace Server."""

from datetime import datetime, timezone
import fcntl
import http.client
import ipaddress
import json
import os
import re
import secrets
import ssl
import stat
from urllib.parse import urlsplit

from .service import _private_json, _regular_private


_MAX_RESPONSE = 1_000_000
_STATES = {"AVAILABLE", "UNAVAILABLE"}
_FRESHNESS = {"CURRENT", "STALE", "UNKNOWN", "UNAVAILABLE"}


class PeerReadError(ValueError):
    def __init__(self, state):
        self.state = state
        super().__init__(state)


def _endpoint(value):
    if not isinstance(value, str) or len(value) > 512 or value.strip() != value:
        raise ValueError("invalid Forge endpoint")
    try:
        parsed = urlsplit(value)
        host, port = parsed.hostname, parsed.port
    except ValueError as exc:
        raise ValueError("invalid Forge endpoint") from exc
    if not _valid_endpoint_parts(parsed, host, port):
        raise ValueError("invalid Forge endpoint")
    _validate_host(parsed.scheme, host)
    return parsed.scheme, host, port or (443 if parsed.scheme == "https" else 80)


def _valid_endpoint_parts(parsed, host, port):
    return (parsed.scheme in {"http", "https"} and bool(host)
            and parsed.username is None and parsed.password is None
            and parsed.path in {"", "/"} and not parsed.query and not parsed.fragment
            and (port is None or 1 <= port <= 65535))


def _validate_host(scheme, host):
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?", host):
            raise ValueError("invalid Forge host") from None
        address = None
    if scheme == "http" and host != "127.0.0.1":
        raise ValueError("remote Forge endpoint requires HTTPS")
    if address is not None and (address.is_unspecified or address.is_multicast):
        raise ValueError("invalid Forge host")


def _valid_binding(config):
    return (isinstance(config, dict)
            and set(config) == {"schema_version", "revision", "endpoint", "instance_id", "repository_id", "token"}
            and type(config["schema_version"]) is int and config["schema_version"] == 1
            and type(config["revision"]) is int and config["revision"] >= 1
            and _valid_binding_identifiers(config)
            and isinstance(config["token"], str)
            and re.fullmatch(r"[A-Za-z0-9_-]{32,256}", config["token"]) is not None)


def _valid_binding_identifiers(config):
    return (isinstance(config["instance_id"], str)
            and re.fullmatch(r"[A-Za-z0-9_-]{8,128}", config["instance_id"]) is not None
            and isinstance(config["repository_id"], str)
            and re.fullmatch(r"[A-Za-z0-9_.:-]{1,128}", config["repository_id"]) is not None)


def _binding(root_fd):
    try:
        config = _private_json("forge-read-binding.json", dir_fd=root_fd)
    except FileNotFoundError:
        raise PeerReadError("UNCONFIGURED") from None
    except (OSError, ValueError, UnicodeError):
        raise PeerReadError("INVALID_CONFIGURATION") from None
    if not _valid_binding(config):
        raise PeerReadError("INVALID_CONFIGURATION")
    try:
        scheme, host, port = _endpoint(config["endpoint"])
    except ValueError:
        raise PeerReadError("INVALID_CONFIGURATION") from None
    return config, config["token"], scheme, host, port


def _publish(temporary, root_fd):
    os.replace(temporary, "forge-read-binding.json", src_dir_fd=root_fd, dst_dir_fd=root_fd)


def _validate_new_binding(endpoint, instance_id, repository_id, token_file):
    _endpoint(endpoint)
    if not _valid_binding_identifiers({"instance_id": instance_id, "repository_id": repository_id}):
        raise ValueError("invalid Forge read binding")
    if not isinstance(token_file, str) or not os.path.isabs(token_file):
        raise ValueError("invalid Forge read binding")
    token = _regular_private(token_file).strip()
    if not re.fullmatch(r"[A-Za-z0-9_-]{32,256}", token):
        raise ValueError("invalid Forge read credential")
    return token


def _next_revision(root_fd, expected_instance_id, expected_repository_id, expected_revision):
    if expected_instance_id is None and expected_repository_id is None and expected_revision is None:
        try:
            os.stat("forge-read-binding.json", dir_fd=root_fd, follow_symlinks=False)
        except FileNotFoundError:
            return 1
        raise ValueError("Forge read binding already exists; guarded replacement required")
    if not (expected_instance_id and expected_repository_id and type(expected_revision) is int):
        raise ValueError("replacement requires expected binding identifiers and revision")
    prior, *_unused = _binding(root_fd)
    if (prior["instance_id"] != expected_instance_id or prior["repository_id"] != expected_repository_id
            or prior["revision"] != expected_revision):
        raise ValueError("current Forge read binding differs from expected")
    return expected_revision + 1


def _write_binding(root_fd, config):
    temporary = ".forge-read-" + secrets.token_hex(12)
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=root_fd)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(json.dumps(config, sort_keys=True).encode("utf-8"))
            stream.flush()
            os.fsync(stream.fileno())
        _publish(temporary, root_fd)
        os.fsync(root_fd)
    finally:
        try:
            os.unlink(temporary, dir_fd=root_fd)
        except FileNotFoundError:
            pass


def configure(root_fd, endpoint, instance_id, repository_id, token_file,
              *, expected_instance_id=None, expected_repository_id=None,
              expected_revision=None):
    """Store a separately issued read token as owner-held Server configuration."""
    token = _validate_new_binding(endpoint, instance_id, repository_id, token_file)
    config = {"schema_version": 1, "revision": 1, "endpoint": endpoint,
              "instance_id": instance_id, "repository_id": repository_id, "token": token}
    lock_fd = os.open(".forge-read-config.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                      0o600, dir_fd=root_fd)
    try:
        info = os.fstat(lock_fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("Forge read configuration lock must be owner-held")
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        config["revision"] = _next_revision(root_fd, expected_instance_id,
                                             expected_repository_id, expected_revision)
        _write_binding(root_fd, config)
    finally:
        os.close(lock_fd)
    return {"instance_id": instance_id, "repository_id": repository_id,
            "revision": config["revision"],
            "endpoint": endpoint}


def _read(scheme, host, port, path, token):
    connection = (http.client.HTTPSConnection(host, port, timeout=3, context=ssl.create_default_context())
                  if scheme == "https" else http.client.HTTPConnection(host, port, timeout=3))
    try:
        connection.request("GET", path, headers={"Authorization": "Bearer " + token,
                                                 "Accept": "application/json"})
        response = connection.getresponse()
        if response.status == 401:
            raise PeerReadError("UNAUTHORIZED")
        if response.status == 403:
            raise PeerReadError("DENIED")
        if response.status == 503:
            raise PeerReadError("UNAVAILABLE")
        if response.status != 200 or response.getheader("Content-Type", "").split(";", 1)[0].lower() != "application/json":
            raise PeerReadError("INVALID_RESPONSE")
        if int(response.getheader("Content-Length", "0")) > _MAX_RESPONSE:
            raise PeerReadError("INVALID_RESPONSE")
        body = response.read(_MAX_RESPONSE + 1)
        if len(body) > _MAX_RESPONSE:
            raise PeerReadError("INVALID_RESPONSE")
        return json.loads(body)
    except PeerReadError:
        raise
    except (ssl.SSLCertVerificationError, ssl.CertificateError):
        raise PeerReadError("TLS_UNTRUSTED") from None
    except (TimeoutError, OSError, http.client.HTTPException):
        raise PeerReadError("UNAVAILABLE") from None
    except (UnicodeError, ValueError):
        raise PeerReadError("INVALID_RESPONSE") from None
    finally:
        connection.close()


def _observed_at(value):
    if value is None:
        return None
    if not isinstance(value, str):
        raise PeerReadError("INVALID_RESPONSE")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise PeerReadError("INVALID_RESPONSE") from None
    if parsed.tzinfo is None:
        raise PeerReadError("INVALID_RESPONSE")
    return value


def _scope(document, config):
    scope = document.get("workspace_read_scope") if isinstance(document, dict) else None
    return (isinstance(scope, dict) and set(scope) == {"contract_version", "instance_id", "repository_id"}
            and scope["contract_version"] == "forge-workspace-status-read/v1"
            and scope["instance_id"] == config["instance_id"]
            and scope["repository_id"] == config["repository_id"])


def _identity_version(identity, config):
    if not _scope(identity, config):
        raise PeerReadError("READ_SCOPE_UNVERIFIED")
    instance = identity.get("instance")
    if not isinstance(instance, dict):
        raise PeerReadError("INVALID_RESPONSE")
    if instance.get("instance_id") != config["instance_id"]:
        raise PeerReadError("WRONG_INSTANCE")
    if (identity.get("api_version") != "1" or identity.get("contract_version") != "1.0"
            or identity.get("read_only") is not True):
        raise PeerReadError("INVALID_RESPONSE")
    version = instance.get("product_version")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise PeerReadError("INVALID_RESPONSE")
    return version


def _validated_status(status, config, version):
    if not _scope(status, config):
        raise PeerReadError("READ_SCOPE_UNVERIFIED")
    if (status.get("api_version") != "1" or status.get("read_only") is not True
            or status.get("availability") not in _STATES
            or status.get("freshness") not in _FRESHNESS
            or not isinstance(status.get("runtime"), dict)):
        raise PeerReadError("INVALID_RESPONSE")
    if status["runtime"].get("instance_id") != config["instance_id"]:
        raise PeerReadError("WRONG_INSTANCE")
    if status["runtime"].get("product_version") != version:
        raise PeerReadError("INVALID_RESPONSE")
    observed = _observed_at(status.get("source_observed_at"))
    if not _consistent_status(status, observed):
        raise PeerReadError("INVALID_RESPONSE")
    return observed


def _consistent_status(status, observed):
    availability, freshness = status["availability"], status["freshness"]
    return (not (availability == "UNAVAILABLE" and freshness != "UNAVAILABLE")
            and not (availability == "AVAILABLE" and freshness == "UNAVAILABLE")
            and not (freshness in {"CURRENT", "STALE"} and observed is None))


def projection(root_fd):
    """Return a non-secret status; producer errors never become a Workspace PASS."""
    base = {"schema_version": 1, "state": "UNCONFIGURED", "instance_id": None,
            "repository_id": None, "product_version": None, "availability": None,
            "freshness": None, "source_observed_at": None, "retrieved_at": None}
    try:
        config, token, scheme, host, port = _binding(root_fd)
        base["instance_id"] = config["instance_id"]
        base["repository_id"] = config["repository_id"]
        identity = _read(scheme, host, port, "/v1/instance", token)
        version = _identity_version(identity, config)
        status = _read(scheme, host, port, "/v1/status", token)
        observed = _validated_status(status, config, version)
        base.update(state="OBSERVED", product_version=version,
                    availability=status["availability"], freshness=status["freshness"],
                    source_observed_at=observed,
                    retrieved_at=datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"))
    except PeerReadError as error:
        base["state"] = error.state
    return base
