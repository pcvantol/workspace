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

from . import __version__


def _private_root(root):
    path = Path(root)
    if not path.is_absolute() or not path.is_dir() or path.is_symlink():
        raise ValueError("data root must be an existing absolute directory")
    if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise ValueError("data root must be owned by this user and mode 0700")
    return path


def _open_private_root(root):
    path = _private_root(root)
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("data root must be owned by this user and mode 0700")
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


def initialize(root):
    """Create the single immutable local identity and secret in an explicit root."""
    _, root_fd = _open_private_root(root)
    try:
        for name in ("instance.json", "token"):
            try:
                os.stat(name, dir_fd=root_fd, follow_symlinks=False)
            except FileNotFoundError:
                continue
            raise ValueError("instance already initialized or partially initialized")
        instance_id = secrets.token_hex(16)
        created = datetime.now(timezone.utc).isoformat()
        values = (("instance.json", json.dumps({"instance_id": instance_id, "created_at": created}) + "\n"),
                  ("token", secrets.token_urlsafe(32) + "\n"))
        created_names = []
        try:
            for name, content in values:
                fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=root_fd)
                created_names.append(name)
                with os.fdopen(fd, "w", encoding="utf-8") as stream:
                    stream.write(content)
                    stream.flush()
                    os.fsync(stream.fileno())
        except Exception:
            for name in created_names:
                try:
                    os.unlink(name, dir_fd=root_fd)
                except FileNotFoundError:
                    pass
            raise
        return instance_id
    finally:
        os.close(root_fd)


class Service:
    def __init__(self, root):
        self._root_lock = threading.Lock()
        self.root, self._root_fd = _open_private_root(root)
        try:
            self._load_instance()
        except Exception:
            self.close()
            raise

    def _load_instance(self):
        self.identity = _private_json("instance.json", dir_fd=self._root_fd)
        self.token = _validated_token(_regular_private("token", dir_fd=self._root_fd))
        if not isinstance(self.identity, dict) or set(self.identity) != {"instance_id", "created_at"}:
            raise ValueError("invalid instance identity")
        instance_id = self.identity["instance_id"]
        if not isinstance(instance_id, str) or re.fullmatch(r"[0-9a-f]{32}", instance_id) is None:
            raise ValueError("invalid instance identity")
        created = self.identity["created_at"]
        if not isinstance(created, str):
            raise ValueError("invalid instance creation time")
        try:
            timestamp = datetime.fromisoformat(created.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("invalid instance creation time") from exc
        if timestamp.tzinfo is None or timestamp.utcoffset() is None:
            raise ValueError("invalid instance creation time")

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
        observed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
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
