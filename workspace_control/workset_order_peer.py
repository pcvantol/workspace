"""Separate finite order authority and exact original command forwarding."""
from contextlib import contextmanager
import json
import os
from .advisory_http import request
from .forge_peer import _endpoint
from .review_peer import _id
from .service import _regular_private
from .worklist_peer import WorklistReadTransport, WorklistError, _FORGE_TOKEN
from .workset_activity_peer import _check_subjects
from . import workset_order_contract as wire


class WorksetOrderTransport(WorklistReadTransport):
    scope_field = 'worksets'

    def __init__(self, root, root_fd):
        super().__init__(root, root_fd, namespace='workset-order')

    def _valid_record(self, value):
        fields = {'id', 'client_digest', 'actor_id', 'workspace_project_id', 'endpoint', 'forge_token',
                  'forge_instance_id', 'forge_project_id', 'repository_id', 'installation_id',
                  'worksets', 'permissions', 'expires_at', 'maximum_amendments'}
        if type(value) is not dict or set(value) != fields:
            return False
        try:
            wire.require(all(_id(value[k]) for k in ['id', 'actor_id', 'workspace_project_id', 'forge_instance_id', 'forge_project_id', 'repository_id', 'installation_id']))
            import re
            wire.require(type(value['client_digest']) is str and re.fullmatch('[0-9a-f]{64}', value['client_digest']))
            wire.require(type(value['forge_token']) is str and _FORGE_TOKEN.fullmatch(value['forge_token']))
            _endpoint(value['endpoint'])
            _check_subjects(value['worksets'])
            wire.require(value['permissions'] in (['READ'], ['READ', 'REORDER']))
            wire.require(type(value['maximum_amendments']) is int and 1 <= value['maximum_amendments'] <= 16)
            from datetime import datetime
            wire.require(type(value['expires_at']) is str and datetime.fromisoformat(value['expires_at'].replace('Z', '+00:00')).utcoffset() is not None)
        except (ValueError, TypeError):
            return False
        return True

    def provision(self, actor, project, endpoint, receipt_file, forge_token_file, client_token_file):
        wire.require(_id(actor) and _id(project), 'INVALID_REQUEST')
        _endpoint(endpoint)
        wire.require(all(os.path.isabs(p) for p in [receipt_file, forge_token_file, client_token_file]), 'INVALID_REQUEST')
        receipt = json.loads(_regular_private(receipt_file))
        wire.require(receipt['state'] == 'ACTIVE' and receipt['principal_id'] == actor and receipt['profile_id'] == 'solo', 'DENIED')
        binding = {'actor_id': actor, 'workspace_project_id': project, 'endpoint': endpoint,
                   'forge_token': _regular_private(forge_token_file).strip(),
                   'forge_instance_id': receipt['instance_id'], 'forge_project_id': receipt['project_id'],
                   'repository_id': receipt['repository_id'], 'installation_id': receipt['installation_id'],
                   **{k: receipt[k] for k in ['worksets', 'permissions', 'expires_at', 'maximum_amendments']}}
        wire.require(self._valid_record({'id': 'probe', 'client_digest': '0' * 64, **binding}), 'INVALID_REQUEST')
        self.capability(binding)
        for subject in binding['worksets']:
            self.current(binding, subject['workset_id'])
        self.capability(binding)
        return self._provision_binding(binding, client_token_file)

    def _request(self, binding, suffix='/capability', method='GET', body=None):
        return request(binding, method, wire.BASE + suffix, body, error_validator=wire.validate, maximum_bytes=1_000_000)

    def capability(self, binding):
        return wire.capability(self._request(binding), binding)

    @contextmanager
    def gate(self, binding, scope):
        descriptor = self._locked()
        try:
            wire.require(binding in self._bindings() and scope == (binding['actor_id'], binding['workspace_project_id']), 'DENIED')
            yield self.capability(binding)
        finally:
            os.close(descriptor)

    def subject(self, binding, workset):
        wire.require(_id(workset) and any(s['workset_id'] == workset for s in binding['worksets']), 'DENIED')

    def current(self, binding, workset):
        self.subject(binding, workset)
        return wire.current(self._request(binding, '/' + workset), binding, workset)

    def preview(self, binding, workset, body):
        self.subject(binding, workset)
        try: wire.validate(body, 'preview_request')
        except WorklistError as error: raise WorklistError('INVALID_REQUEST') from error
        result = self._request(binding, '/' + workset + '/preview', 'POST', body)
        self.capability(binding)
        return wire.preview(result, binding, workset, body['proposed_order'])

    def operation(self, binding, workset, operation):
        self.subject(binding, workset)
        wire.require(_id(operation), 'INVALID_REQUEST')
        return wire.operation(self._request(binding, '/' + workset + '/operations/' + operation), binding, workset, operation)

    def confirm(self, binding, workset, body):
        self.subject(binding, workset)
        try: wire.command(body, binding, workset)
        except WorklistError as error:
            if error.state == 'INVALID_RESPONSE': raise WorklistError('INVALID_REQUEST') from error
            raise
        cap = self.capability(binding)
        wire.require(cap['reorder_supported'] and 'REORDER' in cap['permissions'], 'DENIED')
        result = self._request(binding, '/' + workset + '/confirm', 'POST', body)
        self.capability(binding)
        return wire.operation(result, binding, workset, body['operation_id'], body)
