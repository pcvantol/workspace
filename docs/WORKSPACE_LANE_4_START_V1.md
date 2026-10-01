# Workspace lane 4 — first independent vertical slice

Owner decision: 1 October 2026. Register: [LANE_4 / Forge #208](https://github.com/pcvantol/forge/issues/208). Portfolio allocation: [Forge four-lane proposal #209](https://github.com/pcvantol/forge/pull/209), canonical routing at `pcvantol/forge:docs/roadmap/FOUR_LANE_DEVELOPMENT_V1.md` after protected merge.

```
ASSIGNMENT_ID = L4-WORKSPACE-SERVER-READONLY-V1-20261001
REGISTRATION_REVISION = 1
PLAN_REVISION = 1
SELECTION = OWNER_SELECTED
IMPLEMENTATION = NOT_STARTED_BY_THIS_DOCUMENT
RUNTIME_QUALIFICATION = NOT_CLAIMED
WORK_SESSION_STARTED = FALSE
FIRST_INSTALLER_RELEASE_DEPENDENCY = FALSE
```

## Decision and historical parking

The owner explicitly selected Workspace development alongside the unfinished Forge Platform installer. This decision releases only the bounded own Server/HTTP/CLI/read-only surface described here from the historical 10 September parking. It does not unpark every roadmap family, implement a scheduler or authorize peer/runtime/production effects. The historical parking record and provenance stay intact. The implementation stack remains an owning implementation decision; no unverified existing app is assumed.

LANE_1 owns Forge Platform, LANE_2 EP with its current r30 unchanged, LANE_3 Forge, and LANE_4 Workspace. Before Work effects, verify this owning entry is protected-merged, read all four registers and local writer/worktree/resource state, and register one pickup. A waiting peer lane or an empty PR list is not a resource grant.

## Complete first outcome

Deliver stable Workspace-owned Server identity/state under explicit safe private roots, authenticated versioned read-only HTTP services, a thin own CLI and a minimal browser Client surface backed by the real server. Server owns shared state; Client owns human UX. Preserve that separation even if the first Client assets are served by the Server.

Show real own server/version/status and available project information. EMPTY, UNCONFIGURED, UNAVAILABLE, unauthorized, partial and stale remain distinct. A labelled synthetic example is only test/demo evidence. Never substitute peer SQL, imported peer code, peer CLI or File Inbox for authenticated supported HTTP.

Build the declared wheel and install non-editably in a fresh environment outside the checkout. Prove actual API/CLI/browser behavior, wrong identity/auth rejection, safe paths, normal supervised restart with stable identity/state and two-instance isolation. Read-only endpoints cannot allocate a Mission, admit an EP Action or change a peer roadmap. Keep provider/production credentials out of this first slice.

## Canonical scope and evidence

The existing HTTP DAG keeps all node IDs and dependency edges. Select applicable `WH-CONTRACT`, `WH-SERVICES`, `WH-HTTP`, `WH-CLI` work plus necessary `WPK-IDENTITY` / `WPK-PACKAGE` role subsets. Existing Server identity/state and owned role-entrypoint gates still apply. A selected subset is not qualification of a whole parent.

All implementation nodes remain PLANNED until actual evidence supports their owning status. Full `WH-PEERS` / `WH-Q`, public `WPK-PUBLISH` / `WPK-READBACK` / `WPK-CONSUMER`, role decisions/conversations, rich DAG management, project creation and installed system-service/installer integration remain open. No public distribution before owning package names and the approved publishing route.

The initial package proves local installed bytes, not a public PyPI release. Workspace may be added to a later Forge Platform composition only after separately selected product distribution/deployment contracts and consumer acceptance. The current first-production installer does not acquire a Workspace dependency or reduced DoD.

## Delivery and resources

One active Workspace mutating assignment and one isolated source writer. No source changes in Forge, EP, Forge Platform or their registers. Required independent read-only reviews may share the exact candidate; their evidence is not self-approved.

Use private disposable state, foreground processes and agreed unprivileged capacity. Do not consume the installer/r30 test accounts, Keychain namespace, signer or host window. No new account, launchd service, reboot, production CENTRAL, Mission-3, reset or T0 is authorized. Necessary concrete external approvals remain visible; no routine extra approval for the selected implementation/tests/review fixes/protected delivery.

The same assignment includes entry reconciliation, implementation/refactoring, automated tests, real reviews, protected merge, installed-wheel acceptance and exact owned cleanup. Run `bash scripts/validate.sh`, preserve all applicable security/version/projection gates, and strictly exceed 80.2% executable-line coverage per changed production source file. Report actual tests and blocked/not-run boundaries; do not claim a native or installer PASS from fixtures.

The portfolio's existing VERTICAL_SLICE_DELIVERY_V1 applies. Exact first-assignment criteria and future handoffs remain in #208 and the owning backlog/DAG, not in a second copied backlog. Completion does not automatically start another assignment or Mission.
