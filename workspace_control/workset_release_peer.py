"""Distinct project-bound workset release transport, never a general write proxy."""
from contextlib import contextmanager, nullcontext
import os
import re
from .advisory_http import request
from .forge_peer import _endpoint
from .review_peer import _id
from .service import _regular_private
from .worklist_peer import WorklistReadTransport, WorklistError, _FORGE_TOKEN
from . import workset_release_contract as wire


class WorksetReleaseTransport(WorklistReadTransport):
    scope_field = 'subjects'
    prefix = '/v1/approved-workset-releases'

    def __init__(self, root, root_fd):
        super().__init__(root, root_fd, namespace='workset-release')

    def _valid_record(self, value):
        fields = {'id', 'client_digest', 'actor_id', 'endpoint', 'forge_instance_id', 'forge_token',
                  'workspace_project_id', 'forge_project_id', 'repository_id', 'subjects'}
        if not isinstance(value, dict) or set(value) != fields:
            return False
        ids = ['id', 'actor_id', 'forge_instance_id', 'workspace_project_id', 'forge_project_id', 'repository_id']
        if not all(_id(value[k]) for k in ids):
            return False
        if not isinstance(value['client_digest'], str) or re.fullmatch('[0-9a-f]{64}', value['client_digest']) is None:
            return False
        if not isinstance(value['forge_token'], str) or _FORGE_TOKEN.fullmatch(value['forge_token']) is None:
            return False
        try:
            _endpoint(value['endpoint'])
            wire.require(isinstance(value['subjects'], list) and 1 <= len(value['subjects']) <= 16)
            for subject in value['subjects']:
                wire.validate(subject, 'subject_selection')
            wire._unique_subjects(value['subjects'])
        except (ValueError, TypeError, WorklistError):
            return False
        return True

    def provision(self, actor, project, endpoint, forge_token_file, client_token_file):
        if not _id(actor) or not _id(project):
            raise ValueError('invalid release scope')
        _endpoint(endpoint)
        if not all(isinstance(p, str) and os.path.isabs(p) for p in (forge_token_file, client_token_file)):
            raise ValueError('private absolute paths required')
        token = _regular_private(forge_token_file).strip()
        if _FORGE_TOKEN.fullmatch(token) is None:
            raise ValueError('invalid release token')
        probe = {'endpoint': endpoint, 'forge_token': token}
        raw = request(probe, 'GET', self.prefix + '/capability', error_validator=wire.validate, maximum_bytes=1_000_000)
        wire.validate(raw, 'capability')
        binding = {'actor_id': actor, 'workspace_project_id': project, 'endpoint': endpoint,
                   'forge_token': token, 'forge_instance_id': raw['scope']['instance_id'],
                   'forge_project_id': raw['scope']['project_id'], 'repository_id': raw['scope']['repository_id'],
                   'subjects': raw['subjects']}
        if not self._valid_record({'id': 'probe', 'client_digest': '0' * 64, **binding}):
            raise ValueError('invalid release binding')
        wire.capability(raw, binding)
        return self._provision_binding(binding, client_token_file)

    def bound(self, binding, scope):
        if scope != (binding['actor_id'], binding['workspace_project_id']):
            raise WorklistError('DENIED')

    def _capability(self, binding):
        raw = request(binding, 'GET', self.prefix + '/capability', error_validator=wire.validate, maximum_bytes=1_000_000)
        value = wire.capability(raw, binding)
        wire.require(value['subjects'] == binding['subjects'], 'DENIED')
        return value

    @contextmanager
    def _gate(self, binding, authority=None, permission=None):
        descriptor = self._locked()
        try:
            with authority or nullcontext():
                wire.require(binding in self._bindings(), 'DENIED')
                cap = self._capability(binding)
                if permission is not None:
                    wire.require(permission in cap['permissions'], 'DENIED')
                    wire.require(cap['release_supported'] if permission == 'RELEASE' else cap['disarm_supported'], 'DENIED')
                yield
        except PermissionError:
            raise WorklistError('DENIED') from None
        finally:
            os.close(descriptor)

    def capability(self, binding):
        with self._gate(binding):
            return self._capability(binding)

    def metadata(self, binding, scope):
        self.bound(binding, scope)
        self.capability(binding)
        return {'contract_version': 'workspace-workset-release-access/v1',
                'actor_id': binding['actor_id'], 'workspace_project_id': binding['workspace_project_id'],
                'instance_id': binding['forge_instance_id'], 'project_id': binding['forge_project_id'],
                'repository_id': binding['repository_id'], 'subjects': binding['subjects']}

    def prepare(self, binding, body, *, authority):
        cap = self.capability(binding)
        try:
            wire.selection(body, cap)
        except WorklistError as error:
            if error.state == 'DENIED':
                raise
            raise WorklistError('INVALID_REQUEST') from None
        raw = request(binding, 'POST', self.prefix + '/prepare', body,
                      gate=self._gate(binding, authority), error_validator=wire.validate, maximum_bytes=1_000_000)
        self.capability(binding)
        return wire.prepared(raw, binding, body)

    def operation(self, binding, operation):
        if not _id(operation):
            raise WorklistError('INVALID_REQUEST')
        raw = request(binding, 'GET', self.prefix + '/operations/' + operation,
                      gate=self._gate(binding), error_validator=wire.validate, maximum_bytes=1_000_000)
        self.capability(binding)
        return wire.operation(raw, binding, operation_id=operation)

    def submit(self, binding, body, *, authority):
        cap = self.capability(binding)
        wire.command(body, binding, cap)
        permission = 'RELEASE' if body['intent'] == 'release' else 'DISARM'
        raw = request(binding, 'POST', self.prefix + '/commands', body,
                      gate=self._gate(binding, authority, permission), error_validator=wire.validate, maximum_bytes=1_000_000)
        self.capability(binding)
        return wire.operation(raw, binding, expected=body)
