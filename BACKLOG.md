# Workspace Backlog

## r81 plan revision 82 — own conversation drafts and native GUI

The 4 October owner directive in [Forge #208](https://github.com/pcvantol/forge/issues/208#issuecomment-5983751078)
prioritizes a complete Workspace-owned Business/Architect conversation draft
slice in the **existing** r81 assignment. Product 2.8.3 adds one native
“Gesprekken” flow over Workspace Server HTTP: project-scoped conversation
navigation, editable title and focus, Business/Architecture choice with UX
retained as an optional mode, explicit draft save, revision conflicts, local
unsaved-text recovery and status/context disclosure. The Server holds own
project/actor-isolated records in private SQLite; its existing read bearer
requires a separate explicit draft grant for both draft reads and writes.
Request IDs make create retries idempotent. The [draft HTTP contract](docs/WORKSPACE_CONVERSATION_DRAFT_HTTP_V1.md)
describes routes and authority. The existing read-only routes and Forge read
keep their meanings.

This is a **Workspace-owned RC-WC/RC-WS subset**. No qualified Forge
conversation producer exists for live advice, canonical history, proposals,
apply or Mission handoff, so those remain unavailable. The source change
requires protected PR, exact-head Quality/Security review, full validation,
then isolated installed-wheel/native ad-hoc GUI HTTP readback. Those gates
must be reported separately; source presence alone does not qualify the
installed subset. The private 2.8.2 candidate and its exact bytes/binding
remain historical and must not be relabelled as the 2.8.3 GUI app. New
Developer ID signing, signed `.v2` successor, live Keychain, two-Mac HTTPS,
durable trust and public release remain `NOT_RUN` until their own evidence.

## Selected product delivery — native Client over Server HTTP, 2 October 2026

The owner selected #208 r81,
`L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002`, as the active LANE_4 delivery.
It supersedes free selection of small local follow-ups. The existing installed
read-only Server/browser/packaging evidence remains a delivered subset. This is
one assignment with protected milestones, ending only when the independently
installed Server and macOS app are qualified to their stated gates.

1. **Python support gate:** Workspace-owned Python Server/package supports
   `>=3.14,<3.15` only. Verify wheel metadata, isolated install and relevant
   validation, build, observe and release jobs on 3.14; remove positive 3.10
   maintenance. Preserve existing data and versioned API semantics.
2. **First visible native gate:** package `Workspace.app` with its own window,
   settings and lifecycle and bundled rendering. The client has its own
   versioned HTTP transport, explicit endpoint, secure token storage and pinned
   Server identity. Prove a Finder launch and actual responses from a separate
   installed 3.14 Server. No Python, server/root, checkout or browser-launcher
   requirement on the client Mac. Timeouts, cancellation, reconnection and
   honest freshness/error display are acceptance criteria. Nonloopback traffic
   uses HTTPS with normal certificate validation.
3. **Two-Mac gate:** qualify actual client-Mac to server-Mac host, trust and
   authorization. Record absent host, certificate trust or signing resources
   as `NOT_RUN`; local readback is not remote proof. Test the packaged app and
   use a signed candidate when macOS Keychain/trust behavior is qualified.
4. **First Forge read:** connect real producer read information through
   Workspace Server HTTP only, against exact qualified producer contracts.
   No CLI/import/SQL/File-Inbox shortcut or whole Forge/EP canary dependency.

The existing WH/WPK DAGs own dependencies. Public PyPI Server distribution and
public native app distribution remain separate evidence gates; do not infer
either from a source build or a private qualification candidate. Other quality
and UI improvements remain candidates after this selected delivery.

The same r81 continues under the owner directive
`L4-NATIVE-SIGNING-AND-REMOTE-UNBLOCK-V1-20261002`. As of 3 October, the
Python 3.14-only gate (#116), local Finder app/installed-Server/Forge read
(#122), native safety gates (#123), Developer ID builder (#124) and subsequent
native fixes (#125/#126) are protected-delivered. An exclusive, now released
L1/L4 slot produced one **private** Workspace 2.8.1 Developer ID signed,
notarized, stapled and Gatekeeper-accepted candidate from exact main
`f7ea37e90c28a993c4055805f7d3e699e658e519`. Its ZIP SHA-256 is
`eef134edad1fe8d2f3ddc8eeff3cd04d4310525dacc388a182ff71f83f1a6312`;
independent local and MacBook byte/signature readbacks are in
[#208](https://github.com/pcvantol/forge/issues/208#issuecomment-5966704367).

The owner opened those signed bytes in Finder on the MacBook. The app used
normal macOS HTTPS trust for the explicitly trusted temporary leaf at
`192.168.1.134`, its saved `.v2` Keychain token and pinned Workspace Server
instance, and displayed Server 2.8.1 `READY` plus scoped Forge 2.7.59
`OBSERVED` / `AVAILABLE` / **`STALE`** via the separately installed Python
3.14 Server. After quit and Finder relaunch, the same signed app automatically
reconnected; a corrected disposable Forge Server route restored the same
scoped read without re-pairing. These are private native two-Mac, first-pair
and same-signed-bytes relaunch passes, recorded in
[#208](https://github.com/pcvantol/forge/issues/208#issuecomment-5966912860).
The temporary listeners are stopped. A genuinely new signed successor,
`CURRENT` Forge source observation, durable deployment trust and public native
release remained `NOT_RUN` at that 2.8.1 checkpoint.

Protected 2.8.2 source on main
`5910824dbbc4a79f2152603dc6e516c02bc99971` now has a separate private
Developer ID signed, notarized, stapled and Gatekeeper-accepted ZIP, SHA-256
`72cd7d3d37cfc54d43d57e82e030530f0e6de49ed42cd128da2340db2b325e07`.
The exact epoch-5 L1/L4 slot was activated, used once, independently read back
and released; [#208 records the artifact and gate evidence](https://github.com/pcvantol/forge/issues/208#issuecomment-5970356007).
This closes the **signed 2.8.2 candidate artifact** gate. Running those new
signed bytes, `.v2` first pairing/cancellation/relaunch and preservation across
the 2.8.1→2.8.2 successor, native two-Mac HTTPS/Forge read on 2.8.2,
`CURRENT` Forge source, durable deployment trust and public native release are
separate `NOT_RUN` gates. The shared signer/Keychain resource was returned to
LANE_1; any further live use needs a new exact ACK.

### Native Client and two-Mac transport milestones

Protected PR #117 delivered the local 2.5.0 milestone. Its test bundle opens
as a real macOS window and reads identity,
status, projects and capabilities over HTTP from a separate installed Python
3.14.8 Workspace Server 2.5.0. A restart recovered the saved binding from the
Client's own Keychain namespace. An interrupted Server showed `UNAVAILABLE`
with the prior observation visibly cached; reconnect recovered, and the sample
project became `STALE` after the Server's five-minute window. The Swift transport
suite and packaged binary/signature checks passed locally and in hosted macOS
CI. At this 2.5.0 checkpoint it was local proof, not a public/signed
distribution or two-Mac PASS. A
fresh ad hoc build exposed a blocking Keychain read before the app window
appeared when macOS awaited access for the changed signature. PR #118
protected-delivered the responsive Keychain lifecycle with visible cancellation
and pending-access tests. Signed candidate Keychain behavior was then `NOT_RUN`.
PR #119 protected-delivered the explicit-interface HTTPS Server and an
installed-wheel certificate/Host/auth/pin qualifier. A separate MacBook Pro
then read this installed Server on the Mac mini over LAN HTTPS with explicit
test-certificate trust: valid bearer and instance pin returned 200; untrusted
certificate, missing bearer, wrong pin and foreign Host failed closed. This
closed the disposable two-Mac HTTP transport gate, not the packaged app's
system macOS trust or Developer ID/Keychain qualification. Those native gates
were `NOT_RUN` at that checkpoint; the later private qualification is recorded
above.

The first Forge read is bounded to Forge Server v1 `GET /v1/instance` and
`GET /v1/status` only. Forge LANE_3 r23 protected-delivered the separately
provisioned, instance/repository-bound read bearer in Forge #231/main
`31e6b1c`, with `forge-workspace-status-read/v1` packaged schema SHA-256
`2886c76fa24c772929e13c79fe0eb1ffdc2daa0fc61a045dfa0e95158a681f73`.
Project index, roadmap and Mission detail are later candidates. The Workspace
Server 2.7.0, protected-delivered in Workspace #121/main `d2b85a8`, adds a separate owner-held read binding, authenticated
`GET /v1/forge/status`, and fail-closed instance, repository scope, version and
freshness checks. At Workspace candidate `6dae6c4`, a separately built and
installed Python 3.14 Forge main wheel and Workspace wheel returned an actual
`OBSERVED` HTTP response with Forge 2.7.59 `AVAILABLE`/`CURRENT`, matching
instance and repository, a separate retrieval timestamp, no Forge database
mutation from reads, and `UNAUTHORIZED` after grant revocation. The Forge
schema and producer negative qualifier also passed on that installed wheel.
This is a **protected-delivered local installed two-Server consumer subset**.
At that checkpoint it was not the packaged app's Forge readback or two-Mac
readback, remote HTTPS qualification, or full `WH-PEERS`/`WH-Q` parent
completion. An earlier MacBook attempt to add an ephemeral test CA was denied
without interactive authorization and that partial item was removed. The
owner later trusted the exact temporary leaf for SSL and qualified the signed
native route as recorded above; full parent completion remains open.

The 2.8.0 native Client candidate reads `GET /v1/forge/status` through its
pinned Workspace Server binding and keeps Forge availability, source freshness
and retrieval time distinct. Its packaged app was double-clicked in Finder,
recovered its own saved binding and visibly displayed `CONNECTED`, Workspace
Server 2.8.0 `READY`, and Forge 2.7.59 `OBSERVED` / `AVAILABLE` / `CURRENT`
for the exact `repo-1` scope. Both servers ran from isolated Python 3.14.8
installations outside the checkout; the app used only their HTTP routes.
Workspace PR #122 protected-delivered this **local packaged Finder readback
gate** on main `cffba509e0a5786f55544ad61fcd9cab5a78d2bf`. At that
checkpoint the next native gate was the two-Mac app readback under normal
macOS HTTPS trust. That local result alone did not close Developer ID signing,
signed Keychain behavior or full peer qualification.
The pre-release Keychain service moved from `.v1` to `.v2` because a changed
ad hoc signature left the old test item awaiting macOS access. The old item
is retained, not silently rebound or deleted; that candidate needed explicit
re-pairing once. Signed-candidate Keychain behavior was then `NOT_RUN`; the
later same-signed-bytes first pairing and relaunch are recorded above.
`Forget Server` removes only the current `.v2` pairing; the deployment guide
records the exact manual cleanup boundary for retained pre-release `.v1` items.

## Historical first implementation — 1 October 2026

The owner selected independent Workspace development as LANE_4 alongside the
ongoing Forge Platform installer. The bounded assignment is
`L4-WORKSPACE-SERVER-READONLY-V1-20261001`, recorded in
[the LANE_4 register](https://github.com/pcvantol/forge/issues/208).
See [the owning scope and delivery boundary](docs/WORKSPACE_LANE_4_START_V1.md).

This selects only the own Server identity/state, authenticated HTTP, thin CLI,
minimal read-only browser surface and installed-wheel proof. Existing nodes
`WH-CONTRACT`, `WH-SERVICES`, `WH-HTTP`, `WH-CLI` and the applicable
`WPK-IDENTITY` / `WPK-PACKAGE` role subsets retain their dependencies and
unqualified implementation status. The existing HTTP and distribution DAGs
remain canonical; this is not a second backlog.

Implementation is not claimed by this selection. A single Work executor must
reconcile actual local writers/resources, this protected owning entry and all
four lane registers before effects. No production, account, system-service,
credential, reboot, peer-source or public-package publication authority is
added. Full peer/UI qualification and public distribution remain separate
uncompleted gates. Workspace is not added to the first installer release DoD.

### Protected delivery checkpoint

The bounded read-only Server, own CLI, browser Client, tests and wheel builder
were protected-merged in Workspace PR #35 at
`7d41bfad14a349ebed724773b5e1e4e213f3549b`. Candidate and main evidence,
including the installed-wheel browser proof and independent read-only review,
is in [the LANE_4 register](https://github.com/pcvantol/forge/issues/208).
See [the slice contract](docs/WORKSPACE_SERVER_READONLY_V1.md). This is not a
public package, system installation or live peer qualification. The HTTP and
distribution DAG parent nodes remain PLANNED until their full gates are met.

### LANE_4 CI qualification follow-up

The owner's continuation selected the bounded #208 r2 quality gate:
`L4-WORKSPACE-CI-GATES-V1-20261001`. The existing `scripts/validate.sh` now
runs executable-line coverage with Python's standard-library tracer and fails
unless every Workspace product module strictly exceeds 80.2%. It also builds
the declared wheel, checks canonical version/role/assets, and installs it
non-editably in a fresh environment outside the checkout. PR #36 was
protected-merged at `05ec6d305ab1f1ca732fd7f44c072e0bed8448f2`; its
exact-main validation and TDE observation are recorded in #208. This does not
qualify WH-PEERS, public WPK distribution or a system installation.

### LANE_4 sdist roundtrip follow-up

The #208 r3 assignment `L4-WORKSPACE-SDIST-ROUNDTRIP-V1-20261001` closes a
specific WPK-PACKAGE gap: the canonical sdist now includes the version source,
and required validation rebuilds an isolated wheel from that archive, compares
product files and role metadata with the direct wheel, then installs the rebuilt
wheel without checkout imports. This is candidate evidence until protected
delivery; it does not qualify a public PyPI identity, publisher, full
WPK-PACKAGE parent, or bitwise reproducibility.

### LANE_4 PB-W0 contract-first follow-up

The #208 r4 assignment `L4-WORKSPACE-PB-W0-CONTRACT-V1-20261001` adds a
machine-readable five-journey onboarding intent/capability contract, owning
boundary mapping and offline negative examples. This is contract source only,
not an installed onboarding UI, exact Forge/EP producer binding, project
reservation, provisioning effect or closure of PB-W1 and later nodes.

### LANE_4 HY-WC contract-first follow-up

The #208 r5 assignment `L4-WORKSPACE-HY-WC-CONTRACT-V1-20261001` adds a
machine-readable scoped Repository Health/chat request and evidence projection
contract. The same chat/view intent boundary distinguishes read/refresh, case,
cleanup proposal and engineering proposal; offline negatives guard no Mission
allocation, no deletion, no unknown-as-healthy and external owner routing. This
does not bind qualified Forge/EP producers or implement HY-WO/HY-WM UI/effects.

### LANE_4 own operation-inventory follow-up

The #208 r6 assignment `L4-WORKSPACE-OPERATION-INVENTORY-V1-20261001` adds
authenticated, instance-pinned `GET /v1/capabilities` for the installed
read-only Server. It declares implemented HTTP_EXPOSED reads and LOCAL_ONLY_ADMIN
`init`/`serve` modes from one operation table, with OpenAPI/Postman and real
installed-wheel parity. This is a local WH-CONTRACT subset, not live
Forge/EP peer availability or full WH-Q qualification.

## Historical foundation and remaining candidates

The repository foundation originally authorized no product implementation.
That historical restriction is now superseded only for the explicitly selected
slice above; unrelated future work remains unselected or parked.

The proposed repository-onboarding control-plane experience documented in
[docs/REPOSITORY_ONBOARDING.md](docs/REPOSITORY_ONBOARDING.md) remains a later
candidate requiring its own bounded decision. It must remain separate from EP
execution, the EP-owned portable declaration schema, and the future governed
GitHub provisioning integration.

Future backlog items must be evidence-backed, bounded, and preserve the
peer relationship with Forge and the independent ownership of Engineering
Platform and TDE.
