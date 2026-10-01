# Workspace Server read-only V1 acceptance

Assignment: `L4-WORKSPACE-SERVER-READONLY-V1-20261001`. The consumer boundary is a local browser Client and own CLI reading one Workspace Server. The Server owns its instance identity and a small, explicitly configured project catalogue. The Client renders the Server response; it has no planning or execution authority. Peer Forge/EP data is unconfigured until their exact qualified authenticated HTTP operations are available.

Selected subsets are WH-CONTRACT, WH-SERVICES, WH-HTTP, WH-CLI and the local role-entrypoint and installed-wheel portions of WPK-IDENTITY/WPK-PACKAGE. WH-PEERS, full WH-Q, public distribution, system-service installation and remote HTTPS remain open. This implementation binds loopback only.

The local wheel distribution name `pcvantol-workspace-control` is an internal
candidate identity for installed tests. PyPI namespace ownership, publisher
registration and public name mapping remain WPK-IDENTITY gates.

Acceptance: an explicit private data root initializes one opaque stable instance ID and token; the same root survives a normal process restart; two roots remain independent. Versioned read-only HTTP requires bearer authentication and a pinned instance header, rejects malformed paths, input and origin, and exposes status, project catalogue and OpenAPI. A thin local CLI uses the same service. The browser uses actual HTTP responses and labels EMPTY, UNCONFIGURED, STALE, UNAVAILABLE and UNAUTHORIZED separately. A sample catalogue is explicitly demo data. Source tests, strict per-file coverage, local validation, a non-editable wheel install outside the checkout and API/CLI/browser readback form the evidence. No live peer, installer, public registry or production runtime qualification is claimed.

Every handled HTTP method requires exactly one Host for the Server's actual loopback
port (`127.0.0.1` or `localhost`). If Origin is supplied, it must appear once
and match that Host's HTTP origin. Other, missing or duplicate authorities are
denied before public Client assets, identity and authenticated routes; this
keeps the loopback browser boundary from trusting a re-bound DNS name.
HEAD follows the corresponding GET status and headers without a response body;
other recognized non-GET methods remain read-only rejections.

Protected reads require one unambiguous bearer Authorization header and one
instance-pin header. Duplicate values, even if identical, are rejected before
reading product state; missing or wrong single values retain their existing
unauthorized/wrong-instance responses. Public Client assets and identity do not
require either header.

The own `instance.json` created by `init` has exactly `instance_id` (32
lowercase hexadecimal characters) and a timezone-aware `created_at` timestamp.
Startup rejects malformed, duplicate-key, missing/extra-field or ambiguous
identity state. It does not reset or silently replace the identity/token; a
valid restored file keeps the same browser pin across restart.

The private `token` file has exactly one canonical URL-safe 32-byte random
value (43 encoded characters) and one trailing newline, as written by `init`.
Whitespace, extra lines, invalid characters or noncanonical encoding make
startup fail closed. The Server does not print the token, regenerate it or
weaken authentication when its file is malformed.

The optional `projects.json` is a private regular file (mode 0600) in the data root. Its schema is `{"source":"LOCAL","observed_at":"2026-10-01T15:00:00Z","projects":[{"id":"project-1","name":"Project One"}],"partial":false}`. `source` is `LOCAL` or `DEMO`; the latter is visibly labelled. No file means UNCONFIGURED. A configured empty list means EMPTY. An explicitly incomplete catalogue is PARTIAL. Observations older than five minutes are STALE. Invalid or unreadable input returns SOURCE_UNAVAILABLE. This catalogue is Workspace-owned manual data, not a peer projection or live platform status.

The top-level object requires exactly `source`, `observed_at`, and `projects`,
with optional boolean `partial` (default false). Unknown or missing fields
make the source unavailable; they cannot silently masquerade as live peer
evidence or override the documented local catalogue meaning.

`GET /v1/projects` preserves that primary `state` and also returns independent
`partial` and `stale` booleans. A stale, incomplete catalogue has primary state
STALE with `partial:true` and `stale:true`; the browser displays both labels.
The local `workspace-server --root ROOT projects` read uses the same service
projection and emits one JSON object; invalid sources exit nonzero with no
project JSON on stdout. It is a private-root owner read, not peer transport.
When its list is empty, the browser also labels EMPTY. An unconfigured source
returns both flags false. The Server's own status remains READY and its
`project_source` retains the primary catalogue state.

Project IDs must be unique within one catalogue. Repeated names are allowed;
names are labels, not identity. Duplicate IDs make the source unavailable
rather than choosing an arbitrary row or displaying an ambiguous project list.
Duplicate JSON object keys at any level are also invalid: a second `source`
or project `id` cannot silently replace the first and alter provenance or
identity. The Server rejects such a catalogue as SOURCE_UNAVAILABLE.

The bounded follow-up `L4-WORKSPACE-OPERATION-INVENTORY-V1-20261001` adds pinned,
authenticated `GET /v1/capabilities`. It names only own implemented HTTP reads
and local-only `init`/`serve` commands, with matching OpenAPI/Postman routes.
The local `workspace-server --root ROOT capabilities` command returns the same
instance-bound inventory object as HTTP through the shared product function.
It does not contact a Server or peer and cannot change any operation exposure.
The local `workspace-server --root ROOT openapi` command returns the same own
API contract as authenticated `GET /v1/openapi.json` after validating private
instance state. It requires no running Server and grants no new HTTP operation.
The local browser now renders this authenticated inventory after a successful
instance-pinned connection. It labels HTTP reads and local-only administration
separately and continues to label peer operations UNQUALIFIED. Failed reads,
wrong instances and forgotten bindings clear previously displayed operations;
the Client adds no operation or peer authority.
Forgetting the local browser binding also clears the token input immediately;
reconnection requires the operator to enter the private-root token again.
It does not expose local administration over HTTP or claim peer availability.

If the private catalogue is invalid or unreadable, authenticated Server status
still reports its own READY identity/version with `project_source=SOURCE_UNAVAILABLE`.
The project endpoint remains 503, and the browser shows a connected Server with
project information UNAVAILABLE and no project rows. Repairing the catalogue
restores normal project readback without resetting Server identity or token.
The inventory is a local WH-CONTRACT subset, not full WH-Q.
