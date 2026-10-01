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
The generated OpenAPI contract lists HTTP 403 for this Host/Origin denial on
every declared read, including the public identity route.
HEAD follows the corresponding GET status and headers without a response body;
other recognized non-GET methods remain read-only rejections.
GET and HEAD accept only origin-form targets beginning with one `/`. An
absolute-form URI or `//` authority target is INVALID_PATH (400), even with a
valid loopback Host header; its embedded authority cannot be ignored while
serving a public or authenticated route.
The target must also omit query and fragment delimiters entirely. Even an
empty trailing `?` or `#` is INVALID_PATH (400) rather than an alias for a
declared read route. The Server rejects these before public or protected route
dispatch, after checking Host and Origin.

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
For configured catalogue data, the browser shows the exact Server-provided
`observed_at` alongside its state and source. It does not replace the source
spelling with the browser's current time. An unconfigured catalogue, reconnect,
failed read or forgotten binding shows no observation; stale/partial labels and
rows retain their existing semantics.
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
The contract lists `200`, malformed-path `400`, and Host/Origin `403` for public
`GET /v1/identity`. It does not advertise bearer, instance-pin, or source errors
for that public read. Protected reads additionally list ambiguous-credentials
`400`, unauthorized `401`, wrong-instance `409`, and source-unavailable `503`,
matching the HTTP handler's guarded read path.
The checked-in Postman collection is generated from the same own OpenAPI reads
with `python3 scripts/project_postman.py --write`. Required validation runs its
`--check` mode, so route, method, base URL or authentication drift fails before
delivery. Unsupported future security or method forms require an explicit
projection update instead of silently emitting incomplete requests.
Each implemented GET response now references an own machine-readable OpenAPI
schema for identity, status, project catalogue, capability inventory or the
top-level OpenAPI document. Documented error responses reference the common
`{"error": string}` shape. The contract describes these local read results;
it does not advertise peer operations or qualify the full WH-CONTRACT parent.
The catalogue's `observed_at` is a plain string in this schema because the
current service accepts timezone-aware ISO 8601 spellings, including ISO week
dates, and echoes the source spelling. It is not restricted to RFC 3339.
The local browser now renders this authenticated inventory after a successful
instance-pinned connection. It labels HTTP reads and local-only administration
separately and continues to label peer operations UNQUALIFIED. Failed reads,
wrong instances and forgotten bindings clear previously displayed operations;
the Client adds no operation or peer authority.
The local `workspace-client --url` launcher exits nonzero with a clear error
when the OS browser launcher reports failure or raises an OS/browser error.
Its success exit means the browser accepted the open request; it does not
assert that a Server connection or authenticated read completed.
Before accepting a local binding, the Client requires a canonical own identity
and checks that authenticated Server status names that same instance. An
inconsistent status is WRONG INSTANCE; it clears displayed readbacks and cannot
create or replace the saved pin. This is local consistency checking, not remote
pairing or an additional trust grant.
An authenticated capability inventory naming another instance is also WRONG
INSTANCE: the Client clears capability and project rows, keeps its existing
binding intact and requires a later consistent read before displaying data.
Forgetting the local browser binding also clears the token input immediately;
reconnection requires the operator to enter the private-root token again.
It does not expose local administration over HTTP or claim peer availability.

If the private catalogue is invalid or unreadable, authenticated Server status
still reports its own READY identity/version with `project_source=SOURCE_UNAVAILABLE`.
The project endpoint remains 503, and the browser shows a connected Server with
project information UNAVAILABLE and no project rows. Repairing the catalogue
restores normal project readback without resetting Server identity or token.
If a protected project read instead returns 401 or 409 after a successful
status read, the browser clears old rows and labels UNAUTHORIZED or WRONG
INSTANCE respectively. Other failed project responses are UNAVAILABLE, not
falsely classified as token failure.
The inventory is a local WH-CONTRACT subset, not full WH-Q.
