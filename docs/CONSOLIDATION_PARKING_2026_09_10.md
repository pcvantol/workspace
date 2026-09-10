# Workspace consolidation and parking — 10 September 2026

Increment: `FOUR_REPO_CONSOLIDATION_PARKING_2026_09_10`. Reconciled
2026-09-10. Scoped under [ROADMAP.md](../ROADMAP.md).
[Documentary DAG](CONSOLIDATION_PARKING_2026_09_10_DAG.json).

## Decision and evidence boundary

Physical repository cleanup is complete. This documentation-only, `NO_BUMP`
closure reconciles the existing Workspace consolidation record with that
result. It authorizes no product implementation, runtime run, review-provider
dispatch, release, installation, credential or policy change, Mission, Action,
or product-work merge. `execution_authorized` remains `false`.

`USER_REPORTED` is the supplied completed-cleanup evidence.
`LOCAL_READBACK_VERIFIED` is the direct checkout/ref readback before the
temporary documentation worktree was created. `SOURCE_VERIFIED` is current
GitHub readback. The transient documentation branch is bookkeeping and is
removed after its protected merge.

## Reconciled physical state

Pre-documentation main was
`fa01cdfa86a772a38a3377fc86f87b7c948de8a7`, equal locally and on
`origin/main` (`LOCAL_READBACK_VERIFIED`, `SOURCE_VERIFIED`). GitHub had no
open Workspace PR before this documentation delivery.

| Evidence | Reconciled result |
| --- | --- |
| Local worktrees | `1` |
| Removed auxiliary worktrees | `8` |
| Local feature branches | `0` |
| Unpreserved WIP | `0` |

The eight branches previously associated with delivered PRs #18-#25 and their
auxiliary worktrees were removed after physical preservation checks. No unique
local residual or active Workspace cleanup lane remains.

## Reconciled documentary nodes

| Node | Disposition | Closure / retained acceptance |
| --- | --- | --- |
| `W-LOCAL` | `RESOLVED` | One baseline worktree, zero local feature branches and zero unpreserved WIP |
| `W-MAIN` | `COMPLETE` | Baseline local `main` equals `origin/main`; final documentation delivery fast-forwards it again |
| `W-CLEANUP` | `COMPLETE` | Eight auxiliary worktrees/branches removed; no active local cleanup lane |
| `W-CONTROL-PLANE` | `PARKED` | Installed Server/Client, role-aware decision, project/Mission/Action/evidence, chat, DAG/forecast, onboarding/B8R and producer-adapter work remains under existing roadmaps |
| `W-POLICY-HYGIENE` | `PARKED` | Existing hygiene, policy and governed-progression contracts and qualification remain parked |
| `W-RELEASE` | `PARKED` | Artifact, release and installation closure plus optional direct-EP dogfood remain separately governed work |

The [main roadmap](../ROADMAP.md), [Project Hygiene](PROJECT_HYGIENE_V1_ROADMAP.md),
[Governed Progression](GOVERNED_PROGRESSION_V1_ROADMAP.md),
[Policy & Automation](POLICY_AND_AUTOMATION.md),
[Server/Client deployment](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md), and
[Repository Onboarding](REPOSITORY_ONBOARDING.md) retain their detailed scope,
dependencies and authority boundaries. This consolidation DAG does not replace
them or create a new roadmap family.

## First Forge E2E boundary

Workspace is explicitly `NOT_ON_FIRST_FORGE_E2E_CRITICAL_PATH`. The original
serial Forge Mission E2E does not acquire a dependency on `W-CONTROL-PLANE`,
`W-POLICY-HYGIENE`, `W-RELEASE`, full Workspace productization, installer
completion, subagent optimization or repository cleanup. Workspace remains a
first-class peer and later human/project control plane; it is not Forge planning
or Engineering Platform execution authority.

The cross-product consolidation index is owned by
[Forge](https://github.com/pcvantol/forge/blob/main/docs/roadmap/CONSOLIDATION_PARKING_2026_09_10.md).

## Closure

Workspace physical consolidation and local-main reconciliation are complete.
All remaining Workspace product families are explicitly parked. This closure
does not qualify or start any Workspace capability and does not start the Forge
E2E readiness audit.
