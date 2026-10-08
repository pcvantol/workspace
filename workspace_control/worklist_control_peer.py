"""Separate private hold capability; no canonical command/workset storage."""
import http.client
import json
import os
import ssl
from .forge_peer import _endpoint
from .review_peer import _id, _unique_pairs
from .service import _regular_private
from .worklist_peer import WorklistError, WorklistReadTransport, _ids, _FORGE_TOKEN, _MAX_RESPONSE
from .worklist_control_contract import validate_request, validate_readback, validate_result

def control_request(binding, method, path, body=None):
    """Only fixed internal hold routes and validated closed request bodies."""
    scheme, host, port = _endpoint(binding["endpoint"])
    connection = (http.client.HTTPSConnection(host, port, timeout=5,
                                              context=ssl.create_default_context())
                  if scheme == "https" else http.client.HTTPConnection(host, port, timeout=5))
    try:
        payload = None if body is None else json.dumps(body, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
        connection.request(method, path, body=payload, headers={"Authorization": "Bearer " + binding["forge_token"],
                           "Accept": "application/json", "Content-Type": "application/json"})
        response = connection.getresponse()
        errors = {400: "INVALID_REQUEST", 401: "UNAUTHORIZED", 403: "DENIED", 404: "NOT_FOUND",
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


class WorklistControlTransport(WorklistReadTransport):
    def __init__(self, root, root_fd):
        super().__init__(root, root_fd, namespace="worklist-control")

    def provision(self, actor_id, endpoint, forge_instance_id, workset_ids, forge_token_file, client_token_file):
        if not _id(actor_id) or not _id(forge_instance_id) or not _ids(workset_ids, 16):
            raise ValueError("invalid control scope")
        _endpoint(endpoint)
        if not all(isinstance(path, str) and os.path.isabs(path) for path in (forge_token_file, client_token_file)):
            raise ValueError("control token paths must be absolute")
        token = _regular_private(forge_token_file).strip()
        if _FORGE_TOKEN.fullmatch(token) is None:
            raise ValueError("invalid control token")
        binding = {"actor_id": actor_id, "endpoint": endpoint, "forge_instance_id": forge_instance_id,
                   "forge_token": token, "workset_ids": workset_ids}
        for workset in workset_ids:
            self.readback(binding, workset)
        return self._provision_binding(binding, client_token_file)

    def scopes(self, binding):
        # Validate live authority for every explicit scope; no global Forge discovery.
        for workset in binding['workset_ids']:
            self.readback(binding, workset)
        return {'contract_version': 'workspace-worklist-control-access/v1',
                'instance_id': binding['forge_instance_id'], 'principal_id': binding['actor_id'],
                'workset_ids': binding['workset_ids']}

    def _path(self, binding, workset):
        if not _id(workset) or workset not in binding['workset_ids']:
            raise WorklistError('DENIED')
        return '/v1/workset-controls/' + workset

    def readback(self, binding, workset, operation=None):
        path = self._path(binding, workset)
        if operation is not None:
            if not _id(operation): raise WorklistError('DENIED')
            path += '/commands/' + operation
        return validate_readback(control_request(binding, 'GET', path), binding, workset, operation)

    def submit(self, binding, workset, body):
        path = self._path(binding, workset) + '/commands'
        try: request = validate_request(body, binding, workset)
        except WorklistError: raise WorklistError('INVALID_REQUEST') from None
        # Serialize local binding revocation with the actual command admission boundary.
        lock = self._locked()
        try:
            if binding not in self._bindings():
                raise WorklistError('DENIED')
            return validate_result(control_request(binding, 'POST', path, request), binding, workset, request)
        finally:
            os.close(lock)
