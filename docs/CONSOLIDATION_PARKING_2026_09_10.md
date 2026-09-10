# Workspace consolidation and parking — 10 September 2026

Owning product: Workspace.
[Main roadmap](../ROADMAP.md) · [documentary DAG](CONSOLIDATION_PARKING_2026_09_10_DAG.json).

## Decision and evidence boundary

Owner request: inventory all four repositories, consolidate and park unfinished
work for later. This is a documentation-only `NO_BUMP` change. The disposition
becomes canonical only through the owning protected PR merge. It authorizes no
product implementation, run, review-provider dispatch, merge of product work,
release, installation, migration, credential change or ref/worktree deletion.

`PARKED` is a planning disposition, not a failed/dismissed runtime state or a
claim that local processes have stopped. No executable programme, queue, grant,
repair consumption or deployment policy is changed. Prior broad handoff “next
increment” text is not a pickup instruction while this parking decision applies.
Existing architecture and mandatory assurance remain intact. Resume requires
one explicitly selected bounded task, fresh evidence and applicable authority;
a newly found prerequisite is recorded, never automatically implemented.

The accompanying JSON is a documentary dependency graph, not scheduler input.
Its edges describe only the stated qualification/evidence relationships. Existing
product DAGs retain their detailed dependencies; grouping their open work here
does not rewrite those edges or add universal-installer/UI/optimization gates.

Source, hosted checks, user-reported local state and installed/runtime proof are
separate. No installed/runtime qualification is established by this record.
“Not observed” is not “absent”; branch age, merged PR or semantic supersession
alone is not deletion authority. Preserve main, release refs, unknown ownership,
original findings, ignored/untracked files, stashes and `.engineering` targets.

## Remote snapshot

Pinned main: `bad3dd7d7dafd6c907af440a10f9da0ed7261714`. The complete GitHub heads response on
2026-09-10 contains **only main**; the open-PR response is empty. The scoped
open non-PR issue search also returned no issues. There is no remote feature
branch to merge, close or delete at this snapshot. This says nothing about
unobserved local work or application completeness.

[Heads](https://api.github.com/repos/pcvantol/workspace/git/matching-refs/heads/) ·
[open PRs](https://api.github.com/repos/pcvantol/workspace/pulls?state=open&per_page=100).
Keep merged release/source work on main. No rollback, republishing, runtime or
installation qualification is performed by this documentation.

## Local worktrees: required evidence still open

`LOCAL_WORKTREE_INVENTORY = UNVERIFIED`. The documenting session has a Linux
container, not access to the user's Mac checkouts. No compatible local/SSH
connector was found. Container staging files are not user worktrees. The remote
head inventory cannot enumerate local branches, linked worktrees, independent
clones, stashes, uncommitted/ignored files or live EP leases/processes.

On the actual Mac, capture `git worktree list --porcelain -z`, local/ref/upstream
identities and each worktree's read-only status (including untracked/ignored
presence), stash references and `.engineering` symlink metadata. Do not follow
that symlink into runtime data. Record locks, prunable markers, missing paths,
errors and incomplete coverage. A fresh product-owned read-only lease/run check
is additionally required before changing an execution target. Preserve local
work and create no “clean” claim by reset, stash, checkout, prune or deletion.
Only after inventory and ownership/retention checks may a separate authorized
operation select a cleanup action. This documentation does not perform it.

The supplied handoff reports an earlier local main `4277d5...` and local
origin/main `4e268...`. These truncated historical anchors are not current exact
identities. The actual checkout, linked worktrees, local-only refs and dirty
state remain to be observed; do not fast-forward or reset first to hide the gap.

## All retained roadmap concerns

| DAG ID | Parked work | Required evidence on later resumption |
| --- | --- | --- |
| W-LOCAL | Local branches/worktrees/stashes/untracked/ignored and ownership | Current Mac evidence, coverage and retained unknown work |
| W-CONTROL-PLANE | Installed Server and Client, peer discovery/pairing, role-aware decisions, project/Mission/Action/evidence views, chat, roadmap-DAG governance, forecasts, onboarding/B8R and consumer adapter | Exact bounded UI/contract objective, qualified producer identities and evidence, role/provenance/accessibility tests; no planning/execution authority |
| W-POLICY-HYGIENE | HY-WC/HY-WO/HY-WM Repository Health, POL-WC/POL-W Policy & Automation, GP-WC/GP-W external gates | Existing owning contract/DAG and real Forge/EP producer qualification; read-only and destructive surfaces remain distinct |
| W-RELEASE | Actual artifact/release/install closure and optional direct-EP dogfood | Exact version/source/digest/readback; separate install/operation authority; merged workflow source is not publication |

The graph preserves these as work-family containers, not as a new detailed
implementation programme. [ROADMAP.md](../ROADMAP.md),
[Project Hygiene](PROJECT_HYGIENE_V1_ROADMAP.md),
[Governed Progression](GOVERNED_PROGRESSION_V1_ROADMAP.md),
[Policy & Automation](POLICY_AND_AUTOMATION.md),
[Server/Client deployment](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md), and
[Repository Onboarding](REPOSITORY_ONBOARDING.md) retain individual criteria and
cross-product dependency semantics. Quality/Knowledge governance and later
forecast/scenario/portfolio surfaces remain retained, not silently dropped.

Workspace is **not** required for the first serial Forge -> EP -> Forge Mission
canary. Parking is not cancellation: later work resumes from an explicitly
selected bounded item, not the first “next decision” in an old handoff. It may
consume Forge/EP authenticated evidence; it never accesses peer SQL or acquires
planning/execution authority. No new producer, credential, install or runtime
state is created to make the documentary inventory look complete.

## Closure condition

This change records all remote items observed and every open work family in the
inspected Workspace roadmap. Local physical consolidation remains incomplete
until W-LOCAL is resolved. Retain main and local work; do not create a cleanup
PR solely because no remote feature branch remains.
