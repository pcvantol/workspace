# Workspace consolidation and parking — 10 September 2026

Increment: `FOUR_REPO_CONSOLIDATION_PARKING_2026_09_10`.
Scoped record under [ROADMAP.md](../ROADMAP.md).
[Documentary DAG](CONSOLIDATION_PARKING_2026_09_10_DAG.json).

## Decision and evidence boundary

The owner requested consolidation and parking of unfinished work, not further
product implementation. This is documentation-only, NO_BUMP. The disposition
becomes canonical only through the owning protected PR merge. It authorizes no
runtime run, review-provider dispatch, product-work merge, release, installation,
credential change, policy activation or branch/worktree deletion. PARKED is not
cancellation or proof that a local process has stopped. Old handoff next-step
text does not authorize resumption. Later work needs an explicitly selected
bounded task; a missing prerequisite is recorded, not automatically built.

SOURCE_VERIFIED is GitHub evidence at the pinned observation. USER_REPORTED
is the owner's Workspace architecture report supplied in this task. The
report is now retained instead of treating the entire local inventory as
unknown. Exact worktree paths/tips, ignored files, stashes and live leases
remain independently unverified. A clean report is not deletion authority.

## Remote snapshot and documentation change

Pinned main: `bad3dd7d7dafd6c907af440a10f9da0ed7261714`.
The owner reports all PRs through #25 merged, no remote featurebranches and no
open PRs. The subsequent fresh GitHub readback has the **documentation branch
and PR #26 created by this consolidation task** in addition to main. This is
not newly discovered unmerged product work and does not contradict the earlier
snapshot. Reuse #26; do not create a duplicate consolidation PR.

[Heads](https://api.github.com/repos/pcvantol/workspace/git/matching-refs/heads/) ·
[Documentation #26](https://github.com/pcvantol/workspace/pull/26).
No current claim is made that Workspace product implementation is complete:
merged changes through #25 and an empty product PR queue are not completion of
the still-planned control-plane features. Preserve delivered source on main.

## Local report and per-branch disposition

USER_REPORTED: primary checkout on clean main, nine commits behind remote;
eight additional local featurebranches, each with a clean worktree under
`/private/tmp`. Their former remote branches were removed. PRs #18-#25 are
reported merged with corresponding squash commits on main. Thus the report
implies main plus eight auxiliary worktrees; no independent host count is
claimed. Exact full paths, current local tips and per-branch PR mapping remain
to be captured before physical cleanup.

| Branch | Disposition |
| --- | --- |
| codex/workspace-pending-recovery-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-evidence-projection-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-evidence-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-flow-parity-v2 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-operation-parity-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-published-state-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-resume-v1 | CONDITIONAL_CLEANUP_CANDIDATE |
| codex/workspace-release-source-contract-v1 | CONDITIONAL_CLEANUP_CANDIDATE |

The appropriate later action is a current per-target preservation check,
fast-forward of main if still clean/nondivergent/unowned, then separately
approved removal of confirmed redundant worktrees/branches. No command was
executed on the Mac by this documentation task. Squash ancestry alone does not
prove unmerged work; a merged PR alone does not exclude later local commits.
Do not force-delete a branch solely because git calls it unmerged.

Check actual paths, full tips versus merged PR heads, all tracked/untracked/
ignored content, stashes, locked/prunable markers and current run/PR/lease
ownership. Preserve recovery evidence before removal. Do not follow or replace
`.engineering` symlinks, copy private runtime data into Git, globally prune,
reset or stash to manufacture cleanliness. Any unique residual is parked with
its identity and content preserved, not automatically integrated.

## Scoped roadmap and retained open families

| Node | Disposition | Required future result |
| --- | --- | --- |
| W-LOCAL | OPEN_EVIDENCE_GAP | Complete the per-target host inventory and PR-head mapping; retain reported clean state separately from fresh proof |
| W-MAIN | FAST_FORWARD_CANDIDATE_NOT_EXECUTED | Current ancestry, clean main and no active owner; no checkout mutation before safety checks |
| W-CLEANUP | CONDITIONAL_NO_DELETE_AUTHORITY | Eight named targets verified redundant with retained recovery evidence and explicit cleanup scope |
| W-CONTROL-PLANE | PARKED | Installed Server/Client, role-aware decisions, project/Mission/Action/evidence views, chat, DAG/forecast UI, onboarding/B8R and producer adapter |
| W-POLICY-HYGIENE | PARKED | Existing HY-WC/HY-WO/HY-WM, POL-WC/POL-W and GP-WC/GP-W contracts and qualification |
| W-RELEASE | PARKED | Actual artifact/release/install closure and optional direct-EP dogfood, distinct from merged release-workflow source |

The [main roadmap](../ROADMAP.md), [Project Hygiene](PROJECT_HYGIENE_V1_ROADMAP.md),
[Governed Progression](GOVERNED_PROGRESSION_V1_ROADMAP.md),
[Policy & Automation](POLICY_AND_AUTOMATION.md),
[Server/Client deployment](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md), and
[Repository Onboarding](REPOSITORY_ONBOARDING.md) retain their detailed criteria
and dependencies. Quality/Knowledge governance, scenario/portfolio/forecast
surfaces remain retained, not silently cancelled. This grouping is not a new
execution programme or a replacement for those graphs.

Workspace is not required for the first serial Forge -> EP -> Forge canary.
It consumes authenticated peer evidence, never peer SQL, Forge planning or EP
execution authority. No full installer/UI gate is added to the original E2E.

Cross-product index (canonical only after its own merge):
[Forge consolidation](https://github.com/pcvantol/forge/blob/main/docs/roadmap/CONSOLIDATION_PARKING_2026_09_10.md).

## Closure

Remote source bookkeeping and owner-reported local findings are recorded.
Physical cleanup, local-main synchronization and installed/runtime proof remain
NOT_PERFORMED. Retain the eight worktrees until their final local checks; do
not infer a missing worktree or safe deletion from a remote-only inventory.
