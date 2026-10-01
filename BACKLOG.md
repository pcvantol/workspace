# Workspace Backlog

## Owner-selected first implementation — 1 October 2026

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
