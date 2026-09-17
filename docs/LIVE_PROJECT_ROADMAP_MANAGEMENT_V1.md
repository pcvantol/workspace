# Live project roadmap management V1 — Workspace experience

**Increment:** `LIVE_PROJECT_ROADMAP_MANAGEMENT_V1`.
**Family:** `WORKSPACE::ROADMAP_DAG_GOVERNANCE_V1`.
**Status:** PLANNED / POST_AUTONOMY implementation; documentation only, NO_BUMP.

This elaborates [role-aware roadmap governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md)
and [governed progression](GOVERNED_PROGRESSION_AND_EXTERNAL_GATES.md).
The [delivery roadmap](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_ROADMAP.md) and
[documentary DAG](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_DAG.json) own Workspace work.
Forge owns the matching semantic contract at
`docs/architecture/LIVE_PROJECT_ROADMAP_MANAGEMENT_V1.md` in `pcvantol/forge`.
Source observations: Workspace `664a3eb87b7b6523d0473dc8b696e94064908940` and
Forge `77374203ada9260a9152a8cbb1be841fd070d871`, 2026-09-12.
This is a coherent functional design, not proof of an existing live dashboard.

## Product purpose and authority

Answer what the project is trying to achieve, what runs now, what may start next,
why approved work waits, what decisions are needed and what is only expected.
The roadmap includes capabilities/milestones with no known Mission yet. Missions,
Candidates and expectations link to those outcomes; do not turn every roadmap
node into an executable Mission or use separate role-specific project truths.

Workspace owns interaction, saved views and user-facing presentation. Forge owns
planning, roadmap semantics, eligibility, lifecycle decisions and the existing
activation runtime. EP owns actual admission/execution/evidence. The Forge Server
Console remains instance administration; this project interface belongs here.
Closing Workspace must not stop already-authorized Forge work. No browser timer
or Workspace scheduler starts Missions. All product interactions remain HTTP-only.

## Overview first, graph and details over the same snapshot

The default is a responsive project overview/list, not a mandatory large canvas.
Switch to Dependency graph or Changes without losing selection, filters or the
same snapshot. Header: project/milestone, actual active work, next eligible work,
attention count and last producer update with freshness. Show zero/one/multiple
active Missions honestly; do not imply newly qualified parallel execution.

| Group | Content | Primary operations |
| --- | --- | --- |
| Now active | Actual running, waiting, paused and recoverable Missions, current Action/phase and last progress | Details/evidence, owning safe pause/resume where permitted |
| Approved and planned | Frozen approved definitions or admitted pending Missions, linked without duplicates; release policy and all start conditions | Explain wait, authorize supported release, hold/disarm or propose priority change |
| Refine and decide | Candidates with actual maturity, missing information and separate Business/Architecture decision states | Refine, open role chat, approve exact revision, defer/reject |
| Expected future work | Advisory expected outcomes/Missions, confidence or uncertainty, origin and possible dependencies | Explain, request Candidate refinement, dismiss with reason within authority |
| Completed and historical | Evidence-backed success plus distinct failed/cancelled/superseded/retired outcomes | Results, provenance, original scope and change history |

Attention-needed is a facet across groups, not a lifecycle. Keep recoverable work
visible rather than hiding it as historical because a process ended. Items retain
typed stable IDs, project scope and source revision across list/graph/history.
Counts reflect explicit filters and partial data; UNKNOWN is not zero. Search,
filter and stable sort cover accessible server-side results before pagination.
Filters include capability, state, owner/repository, effect mode, decision role,
release mode and waiting reason. Saved UI layout is not execution priority.

Graph nodes distinguish capabilities, approved Missions, Candidates and Expected
Missions by text/shape as well as color. Differentiate hard dependencies, priority
preferences and speculative edges. Select a node to see its blocking chain and
required evidence. Expand a Mission into its Living Mission Graph only in a
separate level; then link to EP Actions/runs. Do not merge all three layers into
one graph. Without credible duration estimates label the view Blocking dependencies,
not an asserted completion date. No progress percentage based only on Mission count.

## Frozen and approved do not mean runnable

The detail pane separates approved subject/revision, approvals, release authority,
dependency evidence, validity/review fences, lifecycle and execution availability.
Frozen fixes goal/scope/effects/criteria and dependency requirements, not a complete
Action script. Before Mission intake show the real approved-subject reference,
not an allocated placeholder Mission ID. Transition to the actual Mission ID keeps
lineage and avoids a second card representing duplicate executable work.

Release choices are explicit MANUAL_RELEASE and AUTO_WHEN_ELIGIBLE, only where
supported and authorized. They are not display preferences. A previously approved
and released Mission can start when Forge verifies the current conditions without
another chat/start click. Dependency satisfaction alone cannot grant authority.
A manual release decision is not a repeat of valid Business/Architecture approval.

Example projections, not live facts:

```text
Approved / Automatic start authorized
Waiting for: qualified artifact from predecessor M12
Other evaluated conditions: satisfied
Next: Forge may activate once exact artifact evidence is verified

Approved / Dependencies satisfied
Blocked: execution authorization expired while waiting
Next: request the required authority renewal, not redesign the Mission
```

Show every blocker, its actual owner/evidence/freshness and allowed next action.
Distinguish dependency wait, manual release, review, hold, expiry, changed assumption,
unknown producer and EP resource/capacity wait. A recent green EP health signal
cannot establish lease availability. Display EP complete / Forge reconciling /
human acceptance pending as separate states. A supported next action comes from
the backend; absent capabilities give a disabled explanation, not a hopeful button.

## Manage work without silently rewriting the roadmap

All edits use a versioned intent and before/after impact preview: affected exact
subjects/edges, permissions, assumptions and dependent work. Send expected revision,
actor and idempotency identity; handle conflict by refreshing the proposal, not
last-write-wins. Successful readback confirms applied/approved state; request
acceptance alone is not completion. Use the owning Business/Architecture decision
where required, without duplicate micro-approvals for already covered effects.

Reordering proposes priority/sequence, not deletion of a hard dependency. A drag
that violates an edge is explained/rejected or becomes an explicit dependency
proposal; no silent graph repair. Bulk operations require exact selected subjects,
revisions and per-item outcomes; no wildcard selection expanding during refresh.
V1 may ship without bulk editing or graphical drag/drop; the same safe form-based
operations suffice. Preserve provenance when holding, disarming or superseding
approved work; do not delete approvals or reset execution consumption.

New evidence can make an approved Mission need revalidation. Show the specific
changed assumption or approval condition. Ordinary predecessor source changes
are not blanket invalidation; only the owning semantic check decides. Material
scope/effect changes require an amendment and applicable approvals. A completed
design never implicitly creates an authorized implementation Mission.

Pending hold prevents future start in its scope; pausing a Mission does not cancel
an already admitted EP run. Expose cancellation only via its qualified owning
contract with actual impact/readback. Global/project stop is separate from a
single-Mission hold. Revocation/expiry is not automatically repaired by the UI.

Candidate refinement opens the existing Business/Architect/UX conversation with
exact project/subject/context references. UX advice is not a new universal approval.
A partial chat implementation must not block a basic Candidate-detail/edit surface.
Expected work may be promoted through real Candidate services; never a one-click
conversion to approved execution. Read-only reports can satisfy research criteria
without a target Git mutation; show artifact/evidence links, not a fake merge badge.

## Since the previous Mission / snapshot

Changes are a first-class view: choose a previous Mission iteration or snapshot,
then see proven contributions, newly unlocked pending Missions, new/refined/retired
expectations, changed dependency proposals, stale assumptions and new decisions.
Each item has old/new identity/revision, reason and source links plus semantic
classification FACT/INFERENCE/FORECAST/RECOMMENDATION/DECISION. Preserve retired
and superseded history. Expectations can disappear from the current forecast but
not from explanatory history; approved work cannot disappear with them.

Refresh after material verified Action/Mission evidence, not only on Mission end.
Keep the last stable view while Forge computes a new projection and indicate it
is updating. Pagination and event application use a consistent authorized snapshot;
deduplicate events and resync an invalid cursor. Explain a partial source outage
rather than presenting mixed old/new data as a complete current graph.

A view refresh, sort, reconnect or opening a modal starts ZERO model generations,
Mission admissions or EP submissions. An explicit Reassess request, where supported,
is distinct, authorized and budgeted. Closing a tab stops its polling only, not
server work. Offline caches are redacted, scoped and read-only; old browser
eligibility never authorizes an operation after reconnect.

## Project-loop authority refinement — 17 September 2026

Refinement `PROJECT_LOOP_AUTHORITY_2026_09_17` follows the owner-requested Forge
contract addition, observed against Forge
`107936d56223a3fa9fef4b6d2ac6b831d97ff9d2` and Workspace
`eb6c656a92d71666cb493059d517fd174857855d`. These are documentary bases, not
installation or activation evidence. The interface must distinguish autonomy
inside an approved Mission from permission to select another product objective.
Mission 3 remains its separately defined single-Mission multi-Action test;
this project-loop design neither expands that test nor claims it has passed.

### Three planned modes and independent decisions

| Planned project mode | User-facing meaning | What is not implied |
| --- | --- | --- |
| MISSION_RELEASE | Autonomously execute one specifically approved and released Mission; show proposed follow-up work | Completion does not start the next Candidate |
| APPROVED_WORKLIST | Continue through an exact approved workset under its approved order or explicit selection rule | New findings do not join the workset or jump the queue |
| DELEGATED_DEVELOPMENT | Develop within explicitly delegated product goals, scope, decision roles and remaining limits | Selecting the mode creates no grant, approval, merge or deployment authority |

These are target policy terms, not existing lifecycle enums or currently enabled
controls. The design recommends MISSION_RELEASE by default but changes no active
setting. Show the effective mode, policy revision, actual grant, remaining limits
and why a requested mode is unsupported or waiting. A full-autonomy toggle without
qualified delegated decision support must not be presented as effective authority.
Required personal human gates remain visible and blocking; a model cannot sign
as the human or approve its own exception.

Keep four decisions visibly separate: approve exact scope, approve committed
priority/workset, release for start, and observe actual activation. A valid
Business/Architecture decision is not requested a second time just to release.
AUTO_WHEN_ELIGIBLE remains release of already-approved work, not permission to
approve new Candidates. Intermediate review cadence is independent of these modes.

Business evaluates value/cost/timing; Architect evaluates technical scope, risk
and dependencies. One person may hold both roles without collapsing their decision
records. Workspace routes decisions to the owning Forge service; it does not
make itself the approval authority or infer a decision from a chat sentiment.

### Recommendation versus committed execution order

Show distinct recommended and committed order, exact workset membership, per-item
approved revision, release state and selector policy. A changed recommendation
gets a reason and impact preview, not an automatic execution reorder.
The authorized user may select any eligible item instead of the top recommendation;
show blocking prerequisites rather than offering a bypass for ineligible work.
A saved list sort or drag preview is not an applied priority decision.

Default workset behavior waits on an ineligible next item. Skipping/reordering is
allowed only by its explicitly approved selector. Add/remove/reorder requests bind
exact subjects, before/after revisions, actual actor/role and idempotency identity.
Readback confirms application; stale clicks and concurrent changes cannot silently
expand the selected set. After exhaustion show idle plus proposals, not an invented
next Mission. Do not pre-check all future Candidates in a bulk approval control.

Example, not live state:

```text
M1 delivered and reconciled.
Committed next: approved M2, automatic release authorized.
New finding: Candidate C7; Forge recommends priority above M2.
Decision needed: Business/Architecture assessment and workset amendment.
Until decided: C7 does not execute or replace M2.
```

### Findings and their disposition

The Changes view distinguishes current acceptance defects from optional future
work. Moving an unmet criterion to a Candidate cannot make the current Mission
pass. Out-of-scope non-blocking findings are evidence-linked proposals, retaining
origin Action/run/candidate, impact, uncertainty and prior dispositions.

Offer authorized refine/approve/defer/reject/accept-risk actions through the owning
contracts; do not invent a universal acceptance role. Preserve duplicate links,
rejection and accepted-risk reasons. Materially new evidence may propose reopening,
not silently erase a previous decision. An urgent scoped safety stop does not grant
authority to build the suggested broader fix. Completed Mission and unresolved
non-blocking Candidates may legitimately coexist.

### Runtime facts and canonical repository publication

Display approval, admission, execution, partial results, block/failure/cancellation,
reconciliation and acceptance with their separate evidence and timestamps. Automatic
factual refresh is not roadmap direction approval. A capability can have several
contributing Missions and a Mission can contribute to several capabilities;
counts of completed Missions do not prove capability acceptance.

Show both the latest Forge runtime snapshot and the canonical repository's last
published roadmap snapshot, including source revision, projection operation and
freshness. Pending/conflicting publication does not erase proven delivery. Allow
inspection of the bounded publication diff and receipt where authorized; no browser
filesystem patch or silent human-text replacement. Repository publication is routed
through the existing authorized EP delivery owner, not a new Workspace scheduler.
A projection-only commit cannot create another product Mission or an endless update.

### Rollout and evidence

PRM-W-DECISIONS covers mode, workset and finding decisions; PRM-W-SYNC covers dual
freshness/publication evidence. Existing read-only views and basic management may
ship before full delegated mode. Each control advertises only the qualified owning
subset and actual role authority. Source docs do not enable delegation.

The shared PMT-25..36 cases extend the existing registry. Prove human-selected
non-top work, unapproved high-priority findings not entering a released workset,
expired/revoked delegation, stale amendments, all lifecycle outcomes and repository
publication conflicts. No internal approval stubs or test-driver orchestration.
Headless Forge continuation remains independent of an open Workspace tab.

## UI, API and evidence requirements

Use the common EP-aligned design system, two themes, en/nl/de/fr/es, accessible
keyboard/touch navigation, non-color-only statuses and bounded mobile detail
panels. Deep links preserve non-secret project/typed object identity; links may
reopen details but never authorize an operation. Preserve selections and unsaved
edits on refresh; clipboard/export report scope and failure honestly. Escape
untrusted roadmap/log/AI content, validate artifact/link destinations and avoid
secrets, raw private reasoning or unauthorized cross-project metadata.

Workspace Client -> own Server and Workspace Server -> Forge/EP use authenticated,
versioned HTTP. Query each owner's responsibilities; Forge is not a generic EP
proxy. No CLI/import/SQL/File Inbox/IPC shortcut on the same host or during outage.
Browser user/session and server-peer authorization stay distinct. Reuse installed
identity/pairing and F2/FH plus Workspace HTTP contracts; add only required API
subsets, with operation inventory/OpenAPI/Postman/error parity. No shadow scheduler,
state authority or direct filesystem roadmap patch from the browser.

The shared PMT acceptance registry covers real Forge service tests and Workspace
API/browser tests. Use installed artifacts, stateful EP mocks and deterministic
external provider fixtures, never internal approval/eligibility/completion stubs
that make missing implementation appear supported. The later outer-loop suite
must also prove prior real approval + bounded release -> dependency unlock -> M2
without owner relay, distinct from new Candidate -> explicit approvals -> M2.
Mock-backed success is not real provider/EP or production authority evidence.
Coverage above 80%, five-language, both-theme, desktop/phone, keyboard and negative
access tests remain complementary to all mandatory scenario families. Missing or
skipped required scenarios do not count as support. Read-only UI can ship before
management or full outer-loop work; show capability limits honestly.

No current Mission, authority, provider, queue, service, installed state, executable
programme DAG or CI workflow is changed by this design. It creates no first-live-
canary prerequisite and does not move roadmap management to the Forge admin Console.
