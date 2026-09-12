# Workspace HTTP API and transport boundaries V1

**Increment:** `HTTP_ONLY_PEERS_AND_THIN_CLI_V1`. **Owner:** Workspace.
**Status:** design/roadmap only; implementation/qualification PLANNED; NO_BUMP.
This refines the [Server/Client target](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md)
and its existing installed Server lane, not a new planner or Console product.
[Documentary DAG](WORKSPACE_HTTP_API_V1_DAG.json).
Source pins observed 2026-09-12: Workspace
`a12d5b925da1e04b86c1142e709f6f0fb4c7f617`, Forge
`f2f1d8d8535d23323397df4ff7af8586f2c6364f`, EP
`bd4c09ff85bc82783da6efb9f1f781dfb8100e17`. No installed claim follows.

## Required product topology

```text
Workspace Client -- HTTP(S) --> Workspace Server
Workspace Server -- HTTP(S) --> Forge Server
Workspace Server -- HTTP(S) --> EP Server
Forge Server     -- HTTP(S) --> EP Server
```

Workspace calls the actual owner, not EP through a generic Forge proxy. Client
traffic terminates at Workspace Server; peer credentials and binding state stay
server-side. Every peer call is authenticated, versioned and scoped even when
all products run on one PC. Preserve human principal/delegation separately from
service identity; receiving a Workspace request is not approval or grant creation.

No peer CLI subprocess, Python runtime import, direct SQL/store, File Inbox,
shared queue or same-process shortcut, including during outages. Qualified typed
HTTP client/DTO packages are allowed; embedded peer application/storage logic is
not. Discovery only locates candidates before authenticated HTTP pairing. A
missing peer operation stays unsupported; do not implement it by shelling out.

## Workspace CLI and HTTP: own adapters, one service layer

Workspace Server follows the same semantics as Forge Server and EP: its CLI is
an administration/AI-automation ingress and HTTP is another ingress. Both are
thin adapters over Workspace-owned application services. Services own its real
project/session/navigation state, validation, authorization, idempotency and
receipts. Peer product decisions are consumed by HTTP; neither adapter gains
Forge planning or EP execution authority. File Inbox is EP-specific and need not
be added to Workspace or Forge for symmetry.

Own local CLI may invoke a declared local application/management service or use
the own HTTP API; remote CLI uses HTTP. This does not force HTTP to be running
before init/start/recovery. Local-only management commands require actual OS/
installation authority, exact instance/root and locks. Never silently spawn a
writer when HTTP is down, bypass preconditions or replace missing peer APIs with
CLI. An operation inventory declares which capabilities are HTTP_EXPOSED and
which LOCAL_ONLY_ADMIN; parity compares only supported equivalent operations.

Workspace is still the human project/governance interface. Forge Server Console
is instance administration, not its replacement. HTTP transport grants no new
Business/Architecture approval, Mission authority or direct Agent/Git operation.

## Contract and failure semantics

Versioned OpenAPI, capability/operation inventory, implemented routes and derived
Postman cases evolve together. Actor, project, expected object revision, operation
ID and correlation are explicit. Server checks actual authority at mutation time;
client-provided roles and UI selection are not trusted. Responses distinguish
accepted, applied, completed, failed, stale, denied, unsupported and uncertain.
Event cursors/readback are resumable; losing an acknowledgement reuses the same
operation identity. No replay through another ingress, secret logging or hidden
scope/account switching. Browser Origin/CSRF and data/attachment limits apply.
Remote HTTPS and any explicitly qualified local exception are visible policies,
not automatic insecure fallback. Preserve independent Workspace/Forge/EP roots.

Inactive peers allow only clearly labelled cached reads/local drafts. Reconnect
must not auto-submit drafts or approve proposals. Conversations, changes and EP
operations retain their existing owning workflows; changed versions reevaluate
applicable decisions. Queries, filters and reconnect create no AI invocation.

## Delivery roadmap / exact DAG

| Node | Internal dependencies | Required delivery/evidence |
| --- | --- | --- |
| WH-CONTRACT | none | Own API/CLI operation inventory and consumer contracts |
| WH-SERVICES | WH-CONTRACT | Own authenticated instance/project services and exact-root state |
| WH-HTTP | WH-SERVICES | Real Workspace HTTP host and OpenAPI/Postman parity |
| WH-CLI | WH-SERVICES | Thin own management/automation CLI with explicit modes |
| WH-PEERS | WH-HTTP | HTTP-only Forge and EP clients, pinned bindings and recovery |
| WH-Q | WH-CLI, WH-PEERS | Installed/API parity plus relevant browser and boundary negatives |

WH-SERVICES consumes only the required existing Workspace Server identity/state
subset. WH-PEERS requires exact Forge HTTP and EP HTTP capability evidence for
the operations being used, not every future F2 endpoint or a peer Console.
Consumer-contract design may run in parallel with producer work. No producer
runtime depends back on WH-Q. RC-WS/RC-WP and governance/health UI consume the
qualified Workspace Server/API and peer slices; no second implementation path.
The existing POST_AUTONOMY/first-canary positioning is unchanged.

## Required qualification

Reuse HT-01..HT-07 from the coordinated Forge transport contract, with real
Workspace service/auth/HTTP state and deterministic external peer/provider
fixtures. Assert no subprocess/import/SQL/Inbox peer escape in same-machine or
separate-process configurations. Test revoked/wrong-instance credentials, stale
forms, cross-project authority, duplicates, partial peer outcomes, cancellation,
HTTP downtime and local-only recovery isolation. Generated Postman/route parity
must fail on missing/unsupported contract claims. Browser tests cover actual
HTTP requests, redaction, five languages and honest cache/reconnect state.

Own-source tests cannot declare live Forge/EP qualification. Preserve existing
coverage and planned >80% executable-component requirements. This record activates
no CLI, API, workflow, provider, installation, schema, binding, grant or Mission.
