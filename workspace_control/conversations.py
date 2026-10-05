"""Private Workspace conversation navigation and unsent drafts.

No Forge session, provider request, proposal or decision is stored here.
"""

from datetime import datetime, timezone
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import stat
import threading

from .service import _private_json


MODES = frozenset(("BUSINESS", "ARCHITECTURE", "UX"))
ACTOR = re.compile(r"[A-Za-z0-9._:-]{1,128}\Z")


class ConversationConflict(ValueError):
    """An expected draft revision no longer matches the stored revision."""


def _text(value, limit, *, required=False):
    if not isinstance(value, str) or len(value) > limit or (required and not value.strip()):
        raise ValueError("invalid conversation field")
    if any(ord(character) < 32 and character not in "\n\t" for character in value):
        raise ValueError("invalid conversation field")
    return value


def _now():
    return datetime.now(timezone.utc).isoformat()


class ConversationStore:
    OPERATION_RECEIPT_LIMIT = 4096

    def __init__(self, root: Path, root_fd: int):
        self.root = root
        self.root_fd = root_fd
        self.lock = threading.RLock()

    @contextmanager
    def _grant_write_lock(self):
        """Serialize grant read/modify/write across CLI and Server processes."""
        descriptor = os.open("conversation-grants.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        try:
            info = os.fstat(descriptor)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError("invalid conversation grant lock")
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            yield
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def _grants(self):
        try:
            document = _private_json("conversation-grants.json", dir_fd=self.root_fd)
        except FileNotFoundError:
            return []
        grants = document.get("grants") if isinstance(document, dict) else None
        if not isinstance(document, dict) or set(document) != {"grants"} or not isinstance(grants, list) or len(grants) > 100:
            raise ValueError("invalid conversation grants")
        for grant in grants:
            if (not isinstance(grant, dict) or set(grant) != {"digest", "actor_id", "project_id"}
                    or not isinstance(grant["digest"], str)
                    or re.fullmatch(r"[0-9a-f]{64}", grant["digest"]) is None
                    or not isinstance(grant["actor_id"], str)
                    or ACTOR.fullmatch(grant["actor_id"]) is None
                    or not isinstance(grant["project_id"], str)):
                raise ValueError("invalid conversation grants")
        if len({grant["digest"] for grant in grants}) != len(grants):
            raise ValueError("duplicate conversation grant")
        return grants

    def issue_grant(self, actor_id, project_id):
        if not isinstance(actor_id, str) or ACTOR.fullmatch(actor_id) is None:
            raise ValueError("invalid actor")
        if not isinstance(project_id, str) or not 1 <= len(project_id) <= 120:
            raise ValueError("invalid project")
        with self.lock, self._grant_write_lock():
            grants = self._grants()
            if len(grants) >= 100:
                raise ValueError("conversation grant limit reached")
            token = secrets.token_urlsafe(32)
            grants.append({"digest": hashlib.sha256(token.encode()).hexdigest(),
                           "actor_id": actor_id, "project_id": project_id})
            self._write_grants(grants)
            return token

    def _write_grants(self, grants):
        temporary = "conversation-grants-" + secrets.token_hex(8) + ".tmp"
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=self.root_fd)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                json.dump({"grants": grants}, stream, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(temporary, "conversation-grants.json", src_dir_fd=self.root_fd,
                       dst_dir_fd=self.root_fd)
            os.fsync(self.root_fd)
        finally:
            try:
                os.unlink(temporary, dir_fd=self.root_fd)
            except FileNotFoundError:
                pass

    def revoke_grants(self, actor_id, project_id):
        if not isinstance(actor_id, str) or ACTOR.fullmatch(actor_id) is None:
            raise ValueError("invalid actor")
        if not isinstance(project_id, str) or not 1 <= len(project_id) <= 120:
            raise ValueError("invalid project")
        with self.lock, self._grant_write_lock():
            existing = self._grants()
            remaining = [grant for grant in existing if (grant["actor_id"], grant["project_id"]) !=
                         (actor_id, project_id)]
            if len(remaining) != len(existing):
                self._write_grants(remaining)
            return len(existing) - len(remaining)

    def scope(self, token):
        if not isinstance(token, str) or re.fullmatch(r"[A-Za-z0-9_-]{43}", token) is None:
            raise PermissionError("conversation grant denied")
        digest = hashlib.sha256(token.encode()).hexdigest()
        with self.lock:
            for grant in self._grants():
                if secrets.compare_digest(digest, grant["digest"]):
                    return grant["actor_id"], grant["project_id"]
        raise PermissionError("conversation grant denied")

    def _connect(self, *, create=False):
        path = self.root / "conversations.sqlite3"
        if create:
            try:
                descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
            except FileExistsError:
                pass
            else:
                os.close(descriptor)
        info = os.stat(path, follow_symlinks=False)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise ValueError("invalid conversation store")
        connection = sqlite3.connect(path, timeout=5)
        connection.row_factory = sqlite3.Row
        if create:
            connection.execute("""CREATE TABLE IF NOT EXISTS conversations (
                id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, project_id TEXT NOT NULL,
                request_id TEXT NOT NULL, request_digest TEXT NOT NULL,
                title TEXT NOT NULL, focus TEXT NOT NULL, mode TEXT NOT NULL,
                draft TEXT NOT NULL, revision INTEGER NOT NULL,
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)))""")
            connection.execute("""CREATE UNIQUE INDEX IF NOT EXISTS conversation_request
                ON conversations(actor_id, project_id, request_id)""")
        columns = {row[1] for row in connection.execute("PRAGMA table_info(conversations)")}
        if "archived" not in columns:
            connection.execute("ALTER TABLE conversations ADD COLUMN archived INTEGER NOT NULL DEFAULT 0")
        connection.execute("""CREATE TABLE IF NOT EXISTS conversation_operations (
            actor_id TEXT NOT NULL, project_id TEXT NOT NULL, operation_id TEXT NOT NULL,
            conversation_id TEXT NOT NULL, request_digest TEXT NOT NULL,
            action TEXT NOT NULL, completed_revision INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (actor_id, project_id, operation_id))""")
        connection.commit()
        return connection

    @staticmethod
    def _record(row):
        record = {key: value for key, value in dict(row).items()
                  if key not in ("request_id", "request_digest")}
        record["archived"] = bool(record["archived"])
        return record | {"history": [], "history_availability": "UNQUALIFIED_FORGE",
                         "state": "DRAFT_ONLY"}

    def list(self, scope):
        actor, project = scope
        with self.lock:
            try:
                connection = self._connect()
            except FileNotFoundError:
                return {"project_id": project, "actor_id": actor, "conversations": [],
                        "history_availability": "UNQUALIFIED_FORGE"}
            try:
                rows = connection.execute("""SELECT * FROM conversations
                    WHERE actor_id=? AND project_id=? ORDER BY updated_at DESC, id""",
                                          (actor, project)).fetchall()
            finally:
                connection.close()
        return {"project_id": project, "actor_id": actor,
                "conversations": [self._record(row) for row in rows],
                "history_availability": "UNQUALIFIED_FORGE"}

    def get(self, scope, conversation_id):
        if re.fullmatch(r"[0-9a-f]{32}", conversation_id) is None:
            raise FileNotFoundError("conversation not found")
        actor, project = scope
        with self.lock:
            try:
                connection = self._connect()
            except FileNotFoundError:
                raise FileNotFoundError("conversation not found") from None
            try:
                row = connection.execute("SELECT * FROM conversations WHERE id=? AND actor_id=? AND project_id=?",
                                         (conversation_id, actor, project)).fetchone()
            finally:
                connection.close()
        if row is None:
            raise FileNotFoundError("conversation not found")
        return self._record(row)

    def create(self, scope, fields):
        if not isinstance(fields, dict) or set(fields) != {"title", "focus", "mode", "draft", "request_id"}:
            raise ValueError("invalid conversation request")
        request_id = fields["request_id"]
        if not isinstance(request_id, str) or re.fullmatch(r"[0-9a-f]{32}", request_id) is None:
            raise ValueError("invalid conversation request")
        title = _text(fields["title"], 120, required=True)
        focus = _text(fields["focus"], 240)
        draft = _text(fields["draft"], 10000)
        mode = fields["mode"]
        if mode not in MODES:
            raise ValueError("invalid advice mode")
        request_digest = hashlib.sha256(json.dumps(fields, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
        actor, project = scope
        identity = secrets.token_hex(16)
        stamp = _now()
        with self.lock:
            connection = self._connect(create=True)
            replay = None
            try:
                with connection:
                    connection.execute("BEGIN IMMEDIATE")
                    prior = connection.execute("""SELECT * FROM conversations
                        WHERE actor_id=? AND project_id=? AND request_id=?""",
                        (actor, project, request_id)).fetchone()
                    if prior is not None:
                        if prior["request_digest"] != request_digest:
                            raise ConversationConflict("request ID reused for different draft")
                        replay = self._record(prior)
                    else:
                        count = connection.execute("SELECT count(*) FROM conversations WHERE actor_id=? AND project_id=?",
                                                   (actor, project)).fetchone()[0]
                        if count >= 500:
                            raise ValueError("conversation limit reached")
                        connection.execute("""INSERT INTO conversations
                            (id, actor_id, project_id, request_id, request_digest, title, focus,
                             mode, draft, revision, created_at, updated_at, archived)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,0)""",
                            (identity, actor, project, request_id, request_digest,
                             title, focus, mode, draft, 1, stamp, stamp))
            finally:
                connection.close()
            if replay is not None:
                return replay
        return self.get(scope, identity)

    def update(self, scope, conversation_id, fields):
        if (not isinstance(fields, dict) or set(fields) != {"expected_revision", "title", "focus", "mode", "draft"}
                or type(fields["expected_revision"]) is not int or fields["expected_revision"] < 1):
            raise ValueError("invalid conversation request")
        title = _text(fields["title"], 120, required=True)
        focus = _text(fields["focus"], 240)
        draft = _text(fields["draft"], 10000)
        if fields["mode"] not in MODES:
            raise ValueError("invalid advice mode")
        current = self.get(scope, conversation_id)
        if current["revision"] != fields["expected_revision"]:
            raise ConversationConflict("draft revision changed")
        actor, project = scope
        with self.lock:
            connection = self._connect()
            try:
                with connection:
                    cursor = connection.execute("""UPDATE conversations SET title=?, focus=?, mode=?, draft=?,
                        revision=revision+1, updated_at=? WHERE id=? AND actor_id=? AND project_id=? AND revision=?""",
                        (title, focus, fields["mode"], draft, _now(), conversation_id, actor, project,
                         fields["expected_revision"]))
                    if cursor.rowcount != 1:
                        raise ConversationConflict("draft revision changed")
            finally:
                connection.close()
        return self.get(scope, conversation_id)

    def set_archived(self, scope, conversation_id, fields, *, archived):
        """Apply one durable, replay-safe presentation-state command."""
        if (not isinstance(fields, dict) or set(fields) != {"expected_revision", "operation_id"}
                or type(fields["expected_revision"]) is not int or fields["expected_revision"] < 1
                or not isinstance(fields["operation_id"], str)
                or re.fullmatch(r"[0-9a-f]{32}", fields["operation_id"]) is None):
            raise ValueError("invalid conversation operation")
        if re.fullmatch(r"[0-9a-f]{32}", conversation_id) is None:
            raise FileNotFoundError("conversation not found")
        actor, project = scope
        action = "ARCHIVE" if archived else "RESTORE"
        request_digest = hashlib.sha256(json.dumps({
            "action": action, "conversation_id": conversation_id,
            "expected_revision": fields["expected_revision"]
        }, sort_keys=True).encode()).hexdigest()
        with self.lock:
            connection = self._connect()
            result = None
            try:
                with connection:
                    connection.execute("BEGIN IMMEDIATE")
                    prior = connection.execute("""SELECT request_digest FROM conversation_operations
                        WHERE actor_id=? AND project_id=? AND operation_id=?""",
                        (actor, project, fields["operation_id"])).fetchone()
                    if prior is not None:
                        if prior["request_digest"] != request_digest:
                            raise ConversationConflict("operation ID reused for different command")
                        row = connection.execute("""SELECT * FROM conversations
                            WHERE id=? AND actor_id=? AND project_id=?""",
                            (conversation_id, actor, project)).fetchone()
                        if row is None:
                            raise FileNotFoundError("conversation not found")
                        result = self._record(row)
                    else:
                        row = connection.execute("""SELECT * FROM conversations
                            WHERE id=? AND actor_id=? AND project_id=?""",
                            (conversation_id, actor, project)).fetchone()
                        if row is None:
                            raise FileNotFoundError("conversation not found")
                        if row["revision"] != fields["expected_revision"]:
                            raise ConversationConflict("draft revision changed")
                        completed_revision = row["revision"]
                        receipt_count = connection.execute("""SELECT COUNT(*)
                            FROM conversation_operations
                            WHERE actor_id=? AND project_id=?""",
                            (actor, project)).fetchone()[0]
                        if receipt_count >= self.OPERATION_RECEIPT_LIMIT:
                            raise ConversationConflict("operation receipt budget exhausted")
                        if bool(row["archived"]) != archived:
                            completed_revision += 1
                            cursor = connection.execute("""UPDATE conversations
                                SET archived=?, revision=?, updated_at=?
                                WHERE id=? AND actor_id=? AND project_id=? AND revision=?""",
                                (int(archived), completed_revision, _now(), conversation_id,
                                 actor, project, fields["expected_revision"]))
                            if cursor.rowcount != 1:
                                raise ConversationConflict("draft revision changed")
                        connection.execute("""INSERT INTO conversation_operations
                            (actor_id, project_id, operation_id, conversation_id, request_digest,
                             action, completed_revision, created_at)
                            VALUES (?,?,?,?,?,?,?,?)""",
                            (actor, project, fields["operation_id"], conversation_id,
                             request_digest, action, completed_revision, _now()))
                        row = connection.execute("""SELECT * FROM conversations
                            WHERE id=? AND actor_id=? AND project_id=?""",
                            (conversation_id, actor, project)).fetchone()
                        result = self._record(row)
            finally:
                connection.close()
        return result
