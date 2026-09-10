# Workspace Bootstrap

## Current pickup checkpoint — consolidation and parking, 10 September 2026

Read the [owning parking record](docs/CONSOLIDATION_PARKING_2026_09_10.md) and
[documentary dependency DAG](docs/CONSOLIDATION_PARKING_2026_09_10_DAG.json) before selecting work.
Product implementation is PARKED; old handoff next-increment wording does
not authorize resumption. The original Forge serial E2E remains a future
integration goal, not a demand to finish every installer/UI/optimization lane.
The consolidation record now reflects completed physical cleanup: all eight
auxiliary worktrees/branches were removed, leaving one local `main` worktree,
no local feature branches and no unpreserved WIP at the pre-documentation
baseline. Workspace remains `NOT_ON_FIRST_FORGE_E2E_CRITICAL_PATH`.
Existing contracts and validation/protection rules below remain intact.

## Repository identity

Workspace is the first-class repository `pcvantol/workspace`. It is not a
Forge subcomponent. Its provenance and current product maturity are recorded
in [WORKSPACE_PROVENANCE.md](WORKSPACE_PROVENANCE.md) and
[README.md](README.md).

## Local development entrypoint

Before a bounded change:

1. read the committed generic projection in
   `docs/ai-development/GENERATED_PROJECTION.md`;
2. read `docs/ai-development/WORKSPACE_DEVELOPMENT_EXTENSION.md` and then
   [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
   [ROADMAP.md](ROADMAP.md), and [AGENTS.md](AGENTS.md);
3. identify the affected Workspace product boundary and validation needed; and
4. run `bash scripts/validate.sh` before review.

The committed projection is the generic authority and requires no sibling
checkout or network access. This local entrypoint does not authorize
Engineering Platform execution.
