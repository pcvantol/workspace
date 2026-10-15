"""Workspace-owned references; EP remains the identity and read authority.

Gateway results are normalized consumer projections, not an accepted EP wire
contract. The default gateway is unavailable until the owning JOIN is bound.
"""
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import re
from typing import Protocol, ContextManager


class LinkConflict(ValueError):
    """Identity, topology or original intent differs from the confirmed source."""


class LinkExpired(PermissionError):
    """Existing paired viewer or producer read window has expired."""


class ProducerUnavailable(ConnectionError):
    """No owning qualified producer binding is available."""


def identifier(value):
    if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", value) is None:
        raise ValueError("invalid link identity")
    return value


def valid_revision(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None


def timestamp(value):
    if not isinstance(value, str):
        raise ValueError("invalid link timestamp")
    try:
        result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise ValueError("invalid link timestamp") from None
    if result.tzinfo is None:
        raise ValueError("unqualified link timestamp")
    return result


@dataclass(frozen=True)
class LinkScope:
    actor_id: str
    peer_id: str
    project_ids: frozenset[str]
    expires_at: str
    epoch: str

    def require(self, project_id=None, *, now=None):
        identifier(self.actor_id); identifier(self.peer_id); identifier(self.epoch)
        if not isinstance(self.project_ids, frozenset) or len(self.project_ids) > 100:
            raise ValueError("invalid link scope")
        for project in self.project_ids:
            identifier(project)
        if timestamp(self.expires_at) <= (now or datetime.now(timezone.utc)):
            raise LinkExpired("link access expired")
        if project_id is not None and project_id not in self.project_ids:
            raise PermissionError("project outside viewer scope")


def validate_topology(raw, scope, project_id):
    scope.require(project_id)
    fields = {"peer_id", "project_id", "name", "authority_repository_id", "revision", "observed_at", "repositories"}
    if not isinstance(raw, dict) or set(raw) != fields:
        raise ValueError("invalid normalized topology")
    if raw['peer_id'] != scope.peer_id or raw['project_id'] != project_id:
        raise LinkConflict("wrong owning peer or project")
    identifier(raw['authority_repository_id'])
    if (not isinstance(raw['name'], str) or not raw['name'].strip() or len(raw['name']) > 128
            or any(ord(x) < 32 for x in raw['name'])):
        raise ValueError("invalid project name")
    if not valid_revision(raw['revision']):
        raise ValueError("invalid topology revision")
    timestamp(raw['observed_at'])
    repositories = raw['repositories']
    if not isinstance(repositories, list) or not 1 <= len(repositories) <= 100:
        raise ValueError("invalid repository topology")
    ids = set(); authority = []
    for item in repositories:
        if not isinstance(item, dict) or set(item) != {'id', 'name', 'role', 'available_attachments'}:
            raise ValueError("invalid repository item")
        identity = identifier(item['id'])
        if identity in ids:
            raise LinkConflict("duplicate logical repository")
        ids.add(identity)
        if (not isinstance(item['name'], str) or not item['name'].strip() or len(item['name']) > 128
                or any(ord(x) < 32 for x in item['name'])):
            raise ValueError("invalid repository name")
        if item['role'] not in ['authority', 'child'] or item['available_attachments'] is not None and (type(item['available_attachments']) is not int or not 0 <= item['available_attachments'] <= 100):
            raise ValueError("invalid repository availability")
        if item['role'] == 'authority':
            authority.append(identity)
    if authority != [raw['authority_repository_id']]:
        raise LinkConflict("canonical authority mismatch")
    # Detach the validated payload from a gateway's mutable response buffers.
    return json.loads(json.dumps(raw, ensure_ascii=False))


class ProjectReadGateway(Protocol):
    """Composite boundary: existing own actor pairing AND qualified EP read scope.

    scope() must resolve current Workspace identity, an explicit owning binding
    and its narrower producer scope. Neither an EP credential nor the own read
    bearer alone authorizes a viewer. This interface issues no credentials.
    """
    def scope(self, viewer_token: str) -> LinkScope: ...
    def authorization(self, viewer_token: str, expected: LinkScope) -> ContextManager[None]:
        """Fence existing pairing revoke/scope change through local commit.

        An accepted adapter must serialize owning revocation with this guard,
        validate the explicit narrower producer scope at entry, and retain the
        current scope until exit. A snapshot or a pre/post read is not a fence.
        This grants no new authority and never issues credentials.
        """
        ...
    def discover(self, scope: LinkScope) -> list[dict]: ...
    def topology(self, scope: LinkScope, project_id: str) -> dict: ...


class UnboundProjectGateway:
    def scope(self, viewer_token):
        raise ProducerUnavailable("EP producer JOIN is not qualified")


class ProjectLinkStore:
    """Minimal references/intent receipts in the existing private Workspace DB."""
    def __init__(self, conversations):
        self.conversations = conversations

    def _connect(self):
        connection = self.conversations._connect(create=True)
        connection.execute('''CREATE TABLE IF NOT EXISTS project_links (
            actor_id TEXT NOT NULL, project_id TEXT NOT NULL, peer_id TEXT NOT NULL,
            authority_id TEXT NOT NULL, topology_revision TEXT NOT NULL,
            PRIMARY KEY(actor_id, project_id))''')
        connection.execute('''CREATE TABLE IF NOT EXISTS project_link_operations (
            actor_id TEXT NOT NULL, operation_id TEXT NOT NULL, request_digest TEXT NOT NULL,
            project_id TEXT NOT NULL, PRIMARY KEY(actor_id, operation_id))''')
        connection.commit()
        return connection

    def record(self, scope, topology, operation_id, *, authorize):
        scope.require(topology['project_id']); identifier(operation_id)
        project = topology['project_id']
        request = [project, topology['peer_id'], topology['authority_repository_id'], topology['revision']]
        digest = hashlib.sha256(json.dumps(request, separators=(',', ':')).encode()).hexdigest()
        with self.conversations.lock:
            connection = self._connect()
            try:
                with connection:
                    connection.execute('BEGIN IMMEDIATE')
                    authorize()  # Current scope after local database/lock wait.
                    scope.require(project)
                    prior = connection.execute('SELECT * FROM project_link_operations WHERE actor_id=? AND operation_id=?',
                                               (scope.actor_id, operation_id)).fetchone()
                    if prior is not None and prior['request_digest'] != digest:
                        raise LinkConflict("original link intent changed")
                    existing = connection.execute('SELECT * FROM project_links WHERE actor_id=? AND project_id=?',
                                                  (scope.actor_id, project)).fetchone()
                    if existing is not None and (existing['peer_id'], existing['authority_id']) != (scope.peer_id, topology['authority_repository_id']):
                        raise LinkConflict("existing reference binding differs")
                    if prior is None:
                        count = connection.execute('SELECT count(*) FROM project_link_operations WHERE actor_id=?', (scope.actor_id,)).fetchone()[0]
                        if count >= 4096:
                            raise ValueError("link intent limit reached")
                        connection.execute('INSERT INTO project_link_operations VALUES (?,?,?,?)', (scope.actor_id, operation_id, digest, project))
                    connection.execute('INSERT INTO project_links VALUES (?,?,?,?,?) ON CONFLICT(actor_id,project_id) DO NOTHING',
                                       (scope.actor_id, project, scope.peer_id, topology['authority_repository_id'], topology['revision']))
                    authorize()  # Failed current authority rolls back all inserts.
                    scope.require(project)
            finally:
                connection.close()
        return {'project_id': project, 'operation_id': operation_id, 'state': 'REFERENCE_SAVED', 'engineering_readiness': 'NOT_ASSESSED'}

    def identities(self, scope):
        scope.require()
        with self.conversations.lock:
            connection = self._connect()
            try:
                rows = connection.execute('SELECT project_id,peer_id,authority_id FROM project_links WHERE actor_id=? ORDER BY project_id', (scope.actor_id,)).fetchall()
            finally:
                connection.close()
        return [dict(row) for row in rows if row['project_id'] in scope.project_ids and row['peer_id'] == scope.peer_id]


class ProjectLinks:
    def __init__(self, conversations, gateway=None):
        self.store = ProjectLinkStore(conversations)
        self.gateway = gateway or UnboundProjectGateway()

    def _scope(self, token, expected=None):
        scope = self.gateway.scope(token)
        if not isinstance(scope, LinkScope):
            raise ValueError("invalid owning scope projection")
        scope.require()
        if expected is not None and scope != expected:
            raise PermissionError("viewer or peer scope changed")
        return scope

    def access(self, token):
        scope = self._scope(token)
        return {"actor_id":scope.actor_id,"peer_id":scope.peer_id,"project_ids":sorted(scope.project_ids),
                "expires_at":scope.expires_at,"epoch":scope.epoch}

    def discover(self, token, *, expected=None):
        scope = self._scope(token, expected)
        projects = self.gateway.discover(scope)
        if not isinstance(projects, list) or len(projects) > 100:
            raise ValueError("invalid bounded discovery")
        identities = []
        for project in projects:
            if not isinstance(project, dict) or set(project) != {'id', 'name'}:
                raise ValueError('invalid discovery row')
            identity = identifier(project['id']); scope.require(identity); identities.append(identity)
            name = project['name']
            if not isinstance(name, str) or not name.strip() or len(name) > 128 or any(ord(x) < 32 for x in name):
                raise ValueError('invalid discovery name')
        if len(set(identities)) != len(identities):
            raise ValueError("duplicate discovery identity")
        self._scope(token, scope)
        return {'projects': json.loads(json.dumps(projects)), 'state': 'AVAILABLE' if projects else 'EMPTY'}

    def inspect(self, token, project, *, expected=None):
        identifier(project); scope = self._scope(token, expected); scope.require(project)
        topology = validate_topology(self.gateway.topology(scope, project), scope, project)
        self._scope(token, scope)
        return topology

    def link(self, token, project, expected_revision, operation_id, *, authority_id, expected=None):
        scope = self._scope(token, expected); scope.require(project)
        topology = validate_topology(self.gateway.topology(scope, project), scope, project)
        if not valid_revision(expected_revision) or topology['revision'] != expected_revision or topology['authority_repository_id'] != authority_id:
            raise LinkConflict("topology changed; inspect again")
        self._scope(token, scope)
        # No implicit snapshot-only fallback: an unqualified gateway cannot save.
        authorization = getattr(self.gateway, "authorization", None)
        if not callable(authorization):
            raise ProducerUnavailable("owning authorization fence is unqualified")
        with authorization(token, scope):
            self._scope(token, scope)
            result = self.store.record(scope, topology, operation_id,
                                       authorize=lambda: self._scope(token, scope))
        self._scope(token, scope)
        return result

    def open(self, token, project, *, expected=None):
        scope = self._scope(token, expected); scope.require(project)
        linked = next((row for row in self.store.identities(scope) if row['project_id'] == project), None)
        if linked is None:
            raise FileNotFoundError("project reference not found")
        topology = validate_topology(self.gateway.topology(scope, project), scope, project)
        if linked['authority_id'] != topology['authority_repository_id']:
            raise LinkConflict("linked authority changed")
        self._scope(token, scope)
        return {'topology': topology, 'state': 'VERIFIED_REFERENCE', 'engineering_readiness': 'NOT_ASSESSED'}
