"""Instance and catalogue services shared by the own CLI and HTTP ingress."""

import base64
import json
import os
from pathlib import Path
import re
import secrets
import stat
import threading
from datetime import datetime, timezone
from contextlib import contextmanager

from . import __version__


def _private_root(root):
    path = Path(root)
    if not path.is_absolute():
        raise ValueError("data root must be an existing absolute directory")
    info = os.stat(path, follow_symlinks=False)
    if not stat.S_ISDIR(info.st_mode):
        raise ValueError("data root must be an existing absolute directory")
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("data root must be owned by this user and mode 0700")
    return path, info


def _open_private_root(root):
    path, inspected = _private_root(root)
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("data root must be owned by this user and mode 0700")
        if (info.st_dev, info.st_ino) != (inspected.st_dev, inspected.st_ino):
            raise ValueError("data root changed during open")
    except Exception:
        os.close(descriptor)
        raise
    return path, descriptor


def _regular_private(path, *, dir_fd=None):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)
    with os.fdopen(descriptor, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("instance files must be private regular files")
        if info.st_size > 1_000_000:
            raise ValueError("instance file too large")
        content = stream.read(1_000_001)
        if len(content) > 1_000_000:
            raise ValueError("instance file too large")
        return content.decode("utf-8")


def _unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _private_json(path, *, dir_fd=None):
    try:
        return json.loads(_regular_private(path, dir_fd=dir_fd), object_pairs_hook=_unique_json_object)
    except RecursionError as exc:
        raise ValueError("invalid private JSON nesting") from exc


def _validated_catalogue_items(raw):
    required = {"source", "observed_at", "projects"}
    if not isinstance(raw, dict) or not required <= raw.keys() or raw.keys() - required - {"partial"}:
        raise ValueError("invalid catalogue schema")
    if raw["source"] not in ("LOCAL", "DEMO"):
        raise ValueError("invalid catalogue source")
    items = raw["projects"]
    if not isinstance(items, list) or len(items) > 100:
        raise ValueError("invalid project catalogue")
    if not isinstance(raw.get("partial", False), bool):
        raise ValueError("invalid partial flag")
    _validate_project_items(items)
    return items


def _alternate_observed_datetime(normalized):
    week = re.fullmatch(r"[0-9]{4}-W[0-9]{2}-[1-7]T[0-9]{2}:[0-9]{2}"
                        r"(?::[0-9]{2}(?:\.[0-9]{1,6})?)?[+-][0-9]{2}:?[0-9]{2}", normalized)
    compact = re.fullmatch(r"[0-9]{8}T(?:[0-9]{4}(?:[0-9]{2}(?:\.[0-9]{1,6})?)?"
                           r"|[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,6})?)?)"
                           r"[+-][0-9]{2}:?[0-9]{2}", normalized)
    if week or compact:
        time_part = normalized.split("T", 1)[1].split("+", 1)[0].split("-", 1)[0]
        date_pattern = "%G-W%V-%uT" if week else "%Y%m%dT"
        extended = ":" in time_part
        date_pattern += "%H:%M" if extended else "%H%M"
        if extended and time_part.count(":") == 2 or not extended and len(time_part.split(".")[0]) == 6:
            date_pattern += ":%S" if extended else "%S"
        if "." in time_part:
            date_pattern += ".%f"
        try:
            return datetime.strptime(normalized, date_pattern + "%z")
        except ValueError:
            raise ValueError("invalid observed_at") from None
    if re.match(r"^[0-9]{4}-W|^[0-9]{7,8}T", normalized):
        raise ValueError("invalid observed_at")
    return None


def _observed_datetime(stamp):
    normalized = stamp.replace("Z", "+00:00")
    if re.search(r"[+-][0-9]{2}$", normalized):
        normalized += ":00"
    alternate = _alternate_observed_datetime(normalized)
    if alternate is not None:
        return alternate
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        raise ValueError("invalid observed_at") from None


def _validate_project_items(items):
    project_ids = set()
    for item in items:
        if not isinstance(item, dict) or set(item) != {"id", "name"}:
            raise ValueError("invalid project item")
        if any(not isinstance(item[k], str) or not 1 <= len(item[k]) <= 120 for k in ("id", "name")):
            raise ValueError("invalid project item")
        if item["id"] in project_ids:
            raise ValueError("duplicate project id")
        project_ids.add(item["id"])


def _validated_token(token_file):
    if re.fullmatch(r"[A-Za-z0-9_-]{43}\n", token_file) is None:
        raise ValueError("invalid instance token")
    token = token_file[:-1]
    decoded = base64.urlsafe_b64decode(token + "=")
    if len(decoded) != 32 or base64.urlsafe_b64encode(decoded).rstrip(b"=").decode("ascii") != token:
        raise ValueError("invalid instance token")
    return token


def _validated_identity(identity):
    legacy_fields = {"instance_id", "created_at"}
    fields = set(identity) if isinstance(identity, dict) else set()
    if fields not in (legacy_fields, legacy_fields | {"init_protocol"}):
        raise ValueError("invalid instance identity")
    marker_required = "init_protocol" in fields
    if marker_required and identity["init_protocol"] != "COMMIT_MARKER_V1":
        raise ValueError("invalid instance identity")
    instance_id = identity["instance_id"]
    if not isinstance(instance_id, str) or re.fullmatch(r"[0-9a-f]{32}", instance_id) is None:
        raise ValueError("invalid instance identity")
    created = identity["created_at"]
    if not isinstance(created, str):
        raise ValueError("invalid instance creation time")
    try:
        timestamp = datetime.fromisoformat(created.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("invalid instance creation time") from exc
    if timestamp.tzinfo is None or timestamp.utcoffset() is None:
        raise ValueError("invalid instance creation time")
    return instance_id, marker_required


def _validate_initialization_marker(root_fd, instance_id, marker_required):
    try:
        marker_info = os.stat("initialized", dir_fd=root_fd, follow_symlinks=False)
    except FileNotFoundError:
        if marker_required:
            raise ValueError("instance initialization incomplete")
        return  # Legacy roots were initialized before the completion marker.
    if not marker_required:
        raise ValueError("invalid legacy instance marker")
    if not stat.S_ISREG(marker_info.st_mode) or stat.S_IMODE(marker_info.st_mode) != 0o600:
        raise ValueError("instance initialization incomplete")
    if _regular_private("initialized", dir_fd=root_fd) != instance_id + "\n":
        raise ValueError("instance initialization incomplete")


def _load_instance(root_fd):
    identity = _private_json("instance.json", dir_fd=root_fd)
    token = _validated_token(_regular_private("token", dir_fd=root_fd))
    instance_id, marker_required = _validated_identity(identity)
    _validate_initialization_marker(root_fd, instance_id, marker_required)
    return identity, token


def inspect(root):
    """Classify private initialization state without exposing or changing it."""
    _, root_fd = _open_private_root(root)
    try:
        present = {}
        for label, name in (("identity", "instance.json"), ("token", "token"),
                            ("marker", "initialized")):
            try:
                os.stat(name, dir_fd=root_fd, follow_symlinks=False)
            except FileNotFoundError:
                present[label] = False
            else:
                present[label] = True
        if not any(present.values()):
            return {"state": "UNINITIALIZED", "files": present}
        try:
            identity, _ = _load_instance(root_fd)
        except (OSError, ValueError, UnicodeError):
            return {"state": "INCOMPLETE", "files": present}
        validated = {"identity": True, "token": True,
                     "marker": "init_protocol" in identity}
        return {"state": "READY", "files": validated, "instance_id": identity["instance_id"]}
    finally:
        os.close(root_fd)


def initialize(root):
    """Create the single immutable local identity and secret in an explicit root."""
    _, root_fd = _open_private_root(root)
    marker_fd = None
    try:
        for name in ("instance.json", "token", "initialized"):
            try:
                os.stat(name, dir_fd=root_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            raise ValueError("instance already initialized or partially initialized")
        instance_id = secrets.token_hex(16)
        marker_fd = os.open("initialized", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                            0o000, dir_fd=root_fd)
        marker = (instance_id + "\n").encode("ascii")
        if os.write(marker_fd, marker) != len(marker):
            raise OSError("incomplete initialization marker")
        os.fsync(marker_fd)
        os.fsync(root_fd)
        created = datetime.now(timezone.utc).isoformat()
        values = (("instance.json", json.dumps({"instance_id": instance_id, "created_at": created,
                                                  "init_protocol": "COMMIT_MARKER_V1"}) + "\n"),
                  ("token", secrets.token_urlsafe(32) + "\n"))
        for name, content in values:
            fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=root_fd)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
        os.fsync(root_fd)
        os.fchmod(marker_fd, 0o600)
        return instance_id
    finally:
        for descriptor in (marker_fd, root_fd):
            if descriptor is not None:
                try:
                    os.close(descriptor)
                except OSError:
                    pass  # No fallible step after the marker's final publication.


class Service:
    def __init__(self, root):
        self._root_lock = threading.Lock()
        self.root, self._root_fd = _open_private_root(root)
        try:
            self._load_instance()
            from .conversations import ConversationStore
            from .review_peer import ReviewTransport
            from .worklist_peer import WorklistReadTransport
            from .worklist_control_peer import WorklistControlTransport
            from .advisory_peer import AdvisoryTransport
            from .candidate_peer import CandidateTransport
            from .mission_peer import MissionConceptTransport
            self.conversations = ConversationStore(self.root, self._root_fd)
            self.reviews = ReviewTransport(self.root, self._root_fd)
            self.worklists = WorklistReadTransport(self.root, self._root_fd)
            self.worklist_controls = WorklistControlTransport(self.root, self._root_fd)
            self.advisory = AdvisoryTransport(self.root, self._root_fd, self.conversations)
            self.mission_concepts = MissionConceptTransport(self.root, self._root_fd, self.conversations)
            self.candidates = CandidateTransport(self.root, self._root_fd, self.conversations)
        except Exception:
            self.close()
            raise

    def _load_instance(self):
        self.identity, self.token = _load_instance(self._root_fd)

    def close(self):
        with self._root_lock:
            if self._root_fd is not None:
                os.close(self._root_fd)
                self._root_fd = None

    def __enter__(self):
        return self

    def __exit__(self, _exc_type, _exc_value, _traceback):
        self.close()

    def __del__(self):
        if getattr(self, "_root_fd", None) is not None:
            self.close()

    @property
    def instance_id(self):
        return self.identity["instance_id"]

    def status(self):
        try:
            project_source = self.projects()["state"]
        except (ValueError, OSError, UnicodeError):
            project_source = "SOURCE_UNAVAILABLE"
        return {"instance_id": self.instance_id, "version": __version__,
                "state": "READY", "project_source": project_source}

    def projects(self):
        with self._root_lock:
            if self._root_fd is None:
                raise ValueError("instance is closed")
            try:
                raw = _private_json("projects.json", dir_fd=self._root_fd)
            except FileNotFoundError:
                return {"state": "UNCONFIGURED", "projects": [], "source": None,
                        "partial": False, "stale": False}
        items = _validated_catalogue_items(raw)
        stamp = raw.get("observed_at")
        if not isinstance(stamp, str):
            raise ValueError("missing observed_at")
        observed = _observed_datetime(stamp)
        if observed.tzinfo is None:
            raise ValueError("observed_at requires timezone")
        age = (datetime.now(timezone.utc) - observed).total_seconds()
        if age < -60:
            raise ValueError("observed_at is in the future")
        partial = raw.get("partial", False)
        stale = age > 300
        state = "STALE" if stale else ("PARTIAL" if partial else
                                          ("EMPTY" if not items else "AVAILABLE"))
        return {"state": state, "projects": items, "source": raw["source"],
                "observed_at": stamp, "partial": partial, "stale": stale}

    def conversation_scope(self, grant_token):
        """Bind an explicit draft grant to a currently listed own project."""
        scope = self.conversations.scope(grant_token)
        catalogue = self.projects()
        if catalogue["state"] not in ("AVAILABLE", "PARTIAL"):
            raise ValueError("project source unavailable for conversations")
        if scope[1] not in {project["id"] for project in catalogue["projects"]}:
            raise PermissionError("conversation project denied")
        return scope

    def issue_conversation_grant(self, actor_id, project_id):
        catalogue = self.projects()
        if catalogue["state"] not in ("AVAILABLE", "PARTIAL") or project_id not in {
                project["id"] for project in catalogue["projects"]}:
            raise ValueError("current project required for conversation grant")
        return self.conversations.issue_grant(actor_id, project_id)

    def revoke_conversation_grants(self, actor_id, project_id):
        return self.conversations.revoke_grants(actor_id, project_id)

    @contextmanager
    def advisory_forward_scope(self, token, expected_scope):
        with self.conversations.forward_grant(token, expected_scope):
            if self.conversation_scope(token)!=expected_scope:raise PermissionError('advisory scope changed')
            yield

    def provision_review(self, actor_id, endpoint, forge_instance_id,
                         forge_token_file, client_token_file):
        """Owner-held pairing of one authenticated actor to a scoped Forge grant."""
        return self.reviews.provision(actor_id, endpoint, forge_instance_id,
                                      forge_token_file, client_token_file)

    def revoke_review(self, binding_id):
        return self.reviews.revoke(binding_id)

    def provision_worklist(self, actor_id, endpoint, forge_instance_id,
                           forge_token_file, client_token_file):
        """Owner-provisioned read capability, separate from status/review grants."""
        return self.worklists.provision(actor_id, endpoint, forge_instance_id,
                                       forge_token_file, client_token_file)

    def revoke_worklist(self, binding_id):
        return self.worklists.revoke(binding_id)

    def provision_worklist_control(self, actor_id, endpoint, forge_instance_id, workset_ids,
                                   forge_token_file, client_token_file):
        return self.worklist_controls.provision(actor_id, endpoint, forge_instance_id, workset_ids,
                                               forge_token_file, client_token_file)

    def revoke_worklist_control(self, binding_id):
        return self.worklist_controls.revoke(binding_id)

    def provision_advisory(self, actor, project, endpoint, receipt_file, token_file, client_file):
        catalogue=self.projects()
        if catalogue["state"] not in ("AVAILABLE", "PARTIAL") or project not in {p["id"] for p in catalogue["projects"]}:
            raise ValueError("current Workspace project required")
        return self.advisory.provision(actor, project, endpoint, receipt_file, token_file, client_file)

    def provision_candidate(self, actor, project, endpoint, receipt_file, token_file, client_file):
        catalogue=self.projects()
        if catalogue["state"] not in ("AVAILABLE", "PARTIAL") or project not in {p["id"] for p in catalogue["projects"]}:
            raise ValueError("current Workspace project required")
        return self.candidates.provision(actor, project, endpoint, receipt_file, token_file, client_file)

    def revoke_candidate(self, binding_id):
        return self.candidates.revoke(binding_id)

    def revoke_advisory(self, binding_id):
        return self.advisory.revoke(binding_id)

    def forge_status(self):
        """Read a scoped Forge observation without borrowing peer authority."""
        from .forge_peer import projection

        with self._root_lock:
            if self._root_fd is None:
                raise ValueError("instance is closed")
            descriptor = os.dup(self._root_fd)
        try:
            return projection(descriptor)
        finally:
            os.close(descriptor)

    def configure_forge_read(self, endpoint, instance_id, repository_id, token_file,
                             *, expected_instance_id=None, expected_repository_id=None,
                             expected_revision=None):
        """Local administration only; no peer business read through the CLI."""
        from .forge_peer import configure

        with self._root_lock:
            if self._root_fd is None:
                raise ValueError("instance is closed")
            descriptor = os.dup(self._root_fd)
        try:
            return configure(descriptor, endpoint, instance_id, repository_id, token_file,
                             expected_instance_id=expected_instance_id,
                             expected_repository_id=expected_repository_id,
                             expected_revision=expected_revision)
        finally:
            os.close(descriptor)
