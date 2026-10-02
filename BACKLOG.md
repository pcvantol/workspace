# Workspace Backlog

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

The existing WH/WPK DAGs own dependencies. Public PyPI Server distribution,
native app signing/distribution and remote host qualification remain separate
evidence gates; do not infer them from a source build. Other quality and UI
improvements remain candidates after this selected delivery.

### Native Client and two-Mac transport milestones

Protected PR #117 delivered the local 2.5.0 milestone. Its test bundle opens
as a real macOS window and reads identity,
status, projects and capabilities over HTTP from a separate installed Python
3.14.8 Workspace Server 2.5.0. A restart recovered the saved binding from the
Client's own Keychain namespace. An interrupted Server showed `UNAVAILABLE`
with the prior observation visibly cached; reconnect recovered, and the sample
project became `STALE` after the Server's five-minute window. The Swift transport
suite and packaged binary/signature checks passed locally and in hosted macOS
CI. This is local proof, not a public/signed distribution or two-Mac PASS. A
fresh ad hoc build exposed a blocking Keychain read before the app window
appeared when macOS awaited access for the changed signature. PR #118
protected-delivered the responsive Keychain lifecycle with visible cancellation
and pending-access tests. Signed candidate Keychain behavior remains `NOT_RUN`.
PR #119 protected-delivered the explicit-interface HTTPS Server and an
installed-wheel certificate/Host/auth/pin qualifier. A separate MacBook Pro
then read this installed Server on the Mac mini over LAN HTTPS with explicit
test-certificate trust: valid bearer and instance pin returned 200; untrusted
certificate, missing bearer, wrong pin and foreign Host failed closed. This
closes the disposable two-Mac HTTP transport gate, not the packaged app's
system macOS trust or Developer ID/Keychain qualification. Those native gates
remain `NOT_RUN` without an accepted trust chain and signer.

The first Forge read is now bounded to Forge Server v1 `GET /v1/instance` and
`GET /v1/status` only. Forge LANE_3 r23 is building a separately provisioned,
instance/repository-bound read-only bearer; Workspace consumption remains
`NOT_RUN` until that exact producer contract and installed readback are
qualified. Project index, roadmap and Mission detail are later candidates.
The Workspace Server 2.7.0 candidate adds a separate owner-held read binding,
the authenticated `GET /v1/forge/status` projection and fail-closed checks for
Forge's instance, repository-scoped read grant, response version and freshness.
Its local and isolated installed-wheel tests are candidate evidence only;
the actual Forge read stays `NOT_RUN` until Forge r23 is protected, its exact
installed producer contract is pinned, and Workspace independently reads it.
The MacBook's attempt to add an ephemeral test CA to its login trust settings
was denied without interactive authorization. No trust item remains; the
packaged app's remote readback remains `NOT_RUN`.

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
