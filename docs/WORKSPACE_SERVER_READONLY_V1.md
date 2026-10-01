# Workspace Server read-only V1 acceptance

Assignment: `L4-WORKSPACE-SERVER-READONLY-V1-20261001`. The consumer boundary is a local browser Client and own CLI reading one Workspace Server. The Server owns its instance identity and a small, explicitly configured project catalogue. The Client renders the Server response; it has no planning or execution authority. Peer Forge/EP data is unconfigured until their exact qualified authenticated HTTP operations are available.

Selected subsets are WH-CONTRACT, WH-SERVICES, WH-HTTP, WH-CLI and the local role-entrypoint and installed-wheel portions of WPK-IDENTITY/WPK-PACKAGE. WH-PEERS, full WH-Q, public distribution, system-service installation and remote HTTPS remain open. This implementation binds loopback only.

The local wheel distribution name `pcvantol-workspace-control` is an internal
candidate identity for installed tests. PyPI namespace ownership, publisher
registration and public name mapping remain WPK-IDENTITY gates.

Acceptance: an explicit private data root initializes one opaque stable instance ID and token; the same root survives a normal process restart; two roots remain independent. Versioned read-only HTTP requires bearer authentication and a pinned instance header, rejects malformed paths, input and origin, and exposes status, project catalogue and OpenAPI. A thin local CLI uses the same service. The browser uses actual HTTP responses and labels EMPTY, UNCONFIGURED, STALE, UNAVAILABLE and UNAUTHORIZED separately. A sample catalogue is explicitly demo data. Source tests, strict per-file coverage, local validation, a non-editable wheel install outside the checkout and API/CLI/browser readback form the evidence. No live peer, installer, public registry or production runtime qualification is claimed.

The optional `projects.json` is a private regular file (mode 0600) in the data root. Its schema is `{"source":"LOCAL","observed_at":"2026-10-01T15:00:00Z","projects":[{"id":"project-1","name":"Project One"}],"partial":false}`. `source` is `LOCAL` or `DEMO`; the latter is visibly labelled. No file means UNCONFIGURED. A configured empty list means EMPTY. An explicitly incomplete catalogue is PARTIAL. Observations older than five minutes are STALE. Invalid or unreadable input returns SOURCE_UNAVAILABLE. This catalogue is Workspace-owned manual data, not a peer projection or live platform status.

The bounded follow-up `L4-WORKSPACE-OPERATION-INVENTORY-V1-20261001` adds pinned,
authenticated `GET /v1/capabilities`. It names only own implemented HTTP reads
and local-only `init`/`serve` commands, with matching OpenAPI/Postman routes.
It does not expose local administration over HTTP or claim peer availability.

If the private catalogue is invalid or unreadable, authenticated Server status
still reports its own READY identity/version with `project_source=SOURCE_UNAVAILABLE`.
The project endpoint remains 503, and the browser shows a connected Server with
project information UNAVAILABLE and no project rows. Repairing the catalogue
restores normal project readback without resetting Server identity or token.
The inventory is a local WH-CONTRACT subset, not full WH-Q.
