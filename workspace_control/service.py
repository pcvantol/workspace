"""Instance and catalogue services shared by the own CLI and HTTP ingress."""

import json
import os
from pathlib import Path
import re
import secrets
import stat
from datetime import datetime, timezone

from . import __version__


def _private_root(root):
    path = Path(root)
    if not path.is_absolute() or not path.is_dir() or path.is_symlink():
        raise ValueError("data root must be an existing absolute directory")
    if path.stat().st_uid != os.getuid() or path.stat().st_mode & 0o077:
        raise ValueError("data root must be owned by this user and mode 0700")
    return path


def _regular_private(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("instance files must be private regular files")
    if info.st_size > 1_000_000:
        raise ValueError("instance file too large")
    return path.read_text(encoding="utf-8")


def _unique_json_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def initialize(root):
    """Create the single immutable local identity and secret in an explicit root."""
    path = _private_root(root)
    identity = path / "instance.json"
    token = path / "token"
    if identity.exists() or token.exists() or identity.is_symlink() or token.is_symlink():
        raise ValueError("instance already initialized or partially initialized")
    instance_id = secrets.token_hex(16)
    created = datetime.now(timezone.utc).isoformat()
    values = ((identity, json.dumps({"instance_id": instance_id, "created_at": created}) + "\n"),
              (token, secrets.token_urlsafe(32) + "\n"))
    created_paths = []
    try:
        for target, content in values:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            created_paths.append(target)
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
    except Exception:
        for target in created_paths:
            target.unlink(missing_ok=True)
        raise
    return instance_id


class Service:
    def __init__(self, root):
        self.root = _private_root(root)
        self.identity = json.loads(_regular_private(self.root / "instance.json"),
                                   object_pairs_hook=_unique_json_object)
        self.token = _regular_private(self.root / "token").strip()
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
        if len(self.token) < 32:
            raise ValueError("invalid instance token")

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
        catalogue = self.root / "projects.json"
        if not catalogue.exists() and not catalogue.is_symlink():
            return {"state": "UNCONFIGURED", "projects": [], "source": None,
                    "partial": False, "stale": False}
        raw = json.loads(_regular_private(catalogue), object_pairs_hook=_unique_json_object)
        if not isinstance(raw, dict) or raw.get("source") not in ("LOCAL", "DEMO"):
            raise ValueError("invalid catalogue source")
        items = raw.get("projects")
        if not isinstance(items, list) or len(items) > 100:
            raise ValueError("invalid project catalogue")
        if not isinstance(raw.get("partial", False), bool):
            raise ValueError("invalid partial flag")
        project_ids = set()
        for item in items:
            if not isinstance(item, dict) or set(item) != {"id", "name"}:
                raise ValueError("invalid project item")
            if any(not isinstance(item[k], str) or not 1 <= len(item[k]) <= 120 for k in ("id", "name")):
                raise ValueError("invalid project item")
            if item["id"] in project_ids:
                raise ValueError("duplicate project id")
            project_ids.add(item["id"])
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
