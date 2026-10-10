"""Bounded CLI parity for the same private draft/release capability routes."""
import json
from .service import _regular_private, _unique_json_object


def execute(service, args):
    draft = _regular_private(args.draft_grant_file).strip()
    scope = service.conversation_scope(draft)
    transport = service.workset_releases
    binding = transport.access(_regular_private(args.release_token_file).strip())
    transport.bound(binding, scope)
    action = args.command.removeprefix('workset-release-')
    if action == 'access':
        return transport.metadata(binding, scope)
    if action == 'capability':
        return transport.capability(binding)
    if action == 'operation':
        return transport.operation(binding, args.operation_id)
    body = json.loads(_regular_private(args.request_file), object_pairs_hook=_unique_json_object)
    authority = service.advisory_forward_scope(draft, scope)
    if action == 'prepare':
        return transport.prepare(binding, body, authority=authority)
    return transport.submit(binding, body, authority=authority)
