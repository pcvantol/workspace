# Live project roadmap management — Workspace delivery DAG

**Increment:** `LIVE_PROJECT_ROADMAP_MANAGEMENT_V1`. **Status:** PLANNED.
Documentation/DAG refinement only, NO_BUMP; no live Mission, grant or execution.

[Functional design](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1.md) and
[documentary DAG](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_DAG.json) refine existing
WORKSPACE::ROADMAP_DAG_GOVERNANCE_V1, not the Forge Server admin Console.

## Owned work and exact dependencies

| Node | Delivery | Local dependencies |
| --- | --- | --- |
| PRM-W-CONTRACT | Workspace consumer and interaction contract | none |
| PRM-W-VIEW | Live overview, dependency graph and detail views | PRM-W-CONTRACT |
| PRM-W-MANAGE | Governed management, release explanations and iteration changes | PRM-W-VIEW |
| PRM-W-DECISIONS | Role-aware project modes, recommended versus committed worksets and finding disposition decisions | PRM-W-MANAGE |
| PRM-W-SYNC | Runtime and repository projection freshness, publication evidence and conflict explanations | PRM-W-VIEW |
| PRM-W-Q | Installed HTTP/browser, localization and separately scoped project-mode qualification | PRM-W-MANAGE, PRM-W-DECISIONS, PRM-W-SYNC |

The bounded [PRM-W-CONTRACT offline consumer contract](LIVE_PROJECT_ROADMAP_WC_CONTRACT_V1.md)
has documentary fixtures. It does not qualify a producer or close the full node;
all six Workspace runtime/qualification nodes remain PLANNED.
External evidence is a real producer subset, not permission to allocate peer work.

| Workspace node | Required Forge producer nodes |
| --- | --- |
| PRM-W-CONTRACT | PRM-F-CONTRACT |
| PRM-W-VIEW | PRM-F-PROJECTION, PRM-F-ELIGIBILITY |
| PRM-W-MANAGE | PRM-F-ACTIVATION, PRM-F-CHANGES |
| PRM-W-DECISIONS | PRM-F-PRIORITY, PRM-F-DELEGATION |
| PRM-W-SYNC | PRM-F-REPOSITORY |
| PRM-W-Q | PRM-F-Q |

The coordinated fifteen-node graph is acyclic: Forge does not depend on the full
Workspace UI to activate authorized work. Contract design can start independently;
live delivery needs the exact producer subsets. Read-only views can ship before
management, but must mark unsupported operations. Chat/refinement links consume
available RC contracts; full chat, installer and Console completion are not new
prerequisites. Workspace uses qualified HTTP only and never owns activation.

## Project-loop refinement and scoped rollout

`PROJECT_LOOP_AUTHORITY_2026_09_17` makes automatic facts, governed direction,
recommended order and committed execution visibly different. PRM-W-DECISIONS
adds planned MISSION_RELEASE, APPROVED_WORKLIST and DELEGATED_DEVELOPMENT views,
exact workset membership and disposition-aware finding decisions. These modes
are independent of MANUAL_RELEASE/AUTO_WHEN_ELIGIBLE and review cadence.

A mode selector cannot grant authority or replace Business/Architecture decisions.
Delegated decisions require explicit qualified producer support and real grant/
subject evidence; required personal human gates stay intact. PRM-F-DELEGATION is
needed only for the delegated portion of PRM-W-DECISIONS, not as a new prerequisite
for basic manual/worklist interactions. Full-node/full-family qualification claims
require all listed producer subsets; smaller slices label unsupported controls.

PRM-W-SYNC shows the latest Forge snapshot separately from the last protected
repository publication. A delayed or conflicting roadmap writeback cannot erase
proven delivery. No Workspace filesystem writer, second scheduler or implicit
reprioritization. A human can choose eligible authorized work other than Forge's
first recommendation; no dependency is deleted to make that choice executable.

Mission 3 remains its already defined single-Mission multi-Action canary. Its
acceptance contract, runtime, zero-retry condition and attempt identity are not
changed. These future project-loop nodes neither prove nor start another Mission.

## Shared mandatory future acceptance

PMT IDs are shared with the companion repository; keep IDs and meanings aligned.
They extend the relevant service/inner/outer/UI layers, not a second simulator.

| ID | Requirement | Layer |
| --- | --- | --- |
| PMT-01 | Typed capability/Mission/Candidate/Expected/history groups, actual zero/one/multiple active work and no phantom Mission allocation | SERVICE_UI |
| PMT-02 | Frozen revision, distinct approvals, manual/automatic release, eligibility and active lifecycle remain orthogonal | SERVICE_UI |
| PMT-03 | M2 genuinely approved/released through real services before M1; current dependency evidence unlocks M2 once without owner relay | OUTER_LOOP |
| PMT-04 | Expected or partially/unapproved Candidate never auto-starts; new Candidate still follows explicit real approvals | OUTER_LOOP |
| PMT-05 | Predecessor COMPLETE without required artifact/review/deployment evidence does not unlock dependent work | SERVICE_INNER |
| PMT-06 | Expiry, revocation, hold or policy change between eligibility and claim denies activation at the actual boundary | SERVICE_OUTER |
| PMT-07 | Routine source change revalidates assumptions without blanket reapproval; material scope change cannot reuse stale approvals | SERVICE_OUTER |
| PMT-08 | Priority and hard/speculative edges remain distinct; conflicting/cyclic/unresolved edge edits rejected; stable eligible tie-break | SERVICE_UI |
| PMT-09 | Duplicate/out-of-order completion and event delivery produce one reconciliation/context application and correct delta | SERVICE_OUTER |
| PMT-10 | Concurrent starters and lost acknowledgement preserve one activation/intake identity; uncertain EP POST is not resubmitted | SERVICE_OUTER |
| PMT-11 | Fresh process reopens pending, claimed, admitted and reconciled boundaries with same instance, authority and consumption | SERVICE_OUTER |
| PMT-12 | Cursor resync, mixed revisions, pagination, offline and source outage remain visibly stale/partial; stale command rejected | SERVICE_UI |
| PMT-13 | EP completion, Forge reconciliation and required human acceptance are independently represented | SERVICE_UI |
| PMT-14 | Expected added/split/merged/retired changes retain reasons and provenance; no silent overwrite of human/frozen work | SERVICE_OUTER |
| PMT-15 | Wrong project/actor/instance, confused-deputy requests, malicious content and secret-bearing links are denied/redacted | SERVICE_UI |
| PMT-16 | Read-only report and docs/design-only scope survive projection, successor and release; no automatic implementation expansion | INNER_OUTER_UI |
| PMT-17 | Supported serial/concurrent limits preserved; unsupported multiplicity visible, no newly enabled parallel execution | SERVICE_UI |
| PMT-18 | Unknown estimates/usage/confidence remain unknown; no progress from changing Mission counts or invented deadline | SERVICE_UI |
| PMT-19 | Five locales, both themes, desktop/phone, keyboard/touch, stable detail links, selection and clipboard failures | UI |
| PMT-20 | Refresh/sort/open/reconnect issues zero planning, intake or EP mutation requests; closing Workspace does not stop Forge | SERVICE_UI |
| PMT-21 | Versioned hold/disarm/reorder/release commands show preview and actual readback; paused Forge does not cancel admitted EP work | SERVICE_UI |
| PMT-22 | Failed/ambiguous predecessor never grants new authority or fresh repair budget under a replacement Mission | SERVICE_OUTER |
| PMT-23 | Missing API/capability or peer outage has no CLI/import/SQL/Inbox/IPC fallback; read-only rollout labels unsupported controls | SERVICE_UI |
| PMT-24 | No remaining project gap yields bounded idle and no fabricated Expected/Candidate/Mission or extra provider call | OUTER_LOOP |
| PMT-25 | Approval, dispatch, admission, running, blocked, failed, cancelled, partial delivery, reconciliation and acceptance remain distinct automatic facts | SERVICE_OUTER_UI |
| PMT-26 | Authorized repository milestone projection preserves approved direction and separate freshness; duplicate, conflict or self-generated commit cannot start work | SERVICE_OUTER_UI |
| PMT-27 | Out-of-scope reviewer findings create evidence-linked proposals, never new execution authority; urgent scoped stop is not permission to fix | OUTER_LOOP |
| PMT-28 | A current acceptance defect cannot be hidden in a follow-up Candidate to claim success; governed repair or amendment remains required | INNER_OUTER_UI |
| PMT-29 | Duplicate, rejected, deferred and accepted-risk findings preserve disposition; changed evidence may propose but not silently approve reopening | SERVICE_OUTER_UI |
| PMT-30 | Human choice of any eligible authorized item may override the recommendation without bypassing dependencies; sorting never changes committed order | SERVICE_UI |
| PMT-31 | APPROVED_WORKLIST executes only exact approved released subjects under the committed selector; high-ranked new findings cannot join or reorder it | OUTER_LOOP |
| PMT-32 | DELEGATED_DEVELOPMENT requires qualified explicit role grants and exact auditable decisions; mode selection never replaces mandatory human gates | SERVICE_OUTER_UI |
| PMT-33 | Delegation scope, expiry, revocation and consumed limits survive successor Missions, restart and mode switch; unknown authority stops release | SERVICE_OUTER |
| PMT-34 | Priority and workset amendments bind exact revisions, impact and role decisions; stale or concurrent commands cannot broaden authorization | SERVICE_UI |
| PMT-35 | Single-Mission multi-Action proof cannot qualify the project loop or alter Mission 3 acceptance; qualification slices remain separate | INNER_OUTER_UI |
| PMT-36 | Capability contribution and acceptance remain many-to-many and evidence-bound; completed Mission counts or published projections cannot prove product completion | SERVICE_UI |

The later outer-loop cases add a second positive path: create pending M2's
Candidate, real separate approvals and bounded automatic release through public
services BEFORE predecessor completion. M1 unlocks evidence, not authority. This
is not the forbidden test-driver injection of an already-approved M2. Retain the
new-Candidate path and all existing FOE cases. Inner-loop read-only/docs/design
cases retain their explicit effects; completed design cannot authorize new code.

Full qualification uses installed artifacts/new processes, real owning services,
stateful EP HTTP mocks and controlled external provider/OS fixtures; no live
credentials or paid probes in deterministic CI. Once qualified server entrypoints
exist, test the same cases through HTTP and supported own-CLI variants. Missing,
skipped, setup-failed or unsupported required cases cannot be counted PASS.

Preserve current Python/HTTP/OpenAPI/Postman, security and coverage requirements;
production coverage must be above 80% and cannot replace scenario completion.
Workspace UI requires en/nl/de/fr/es, two themes, desktop/phone and accessible
Playwright cases. Tests of documentary JSON are not those runtime/browser tests.
Mock-CI success is distinct from real EP/provider and installed-service evidence.

## Ordering, authority and resume

This is future productization; the current live canary, its approved scope and
budget are unchanged. No universal-installer, full outer-loop or graphical editor
prerequisite is introduced for basic read-only delivery. Full preapproved-Mission
progression is qualified through the later outer-loop lane, after its inner-loop
foundation. Workspace is not required to remain open.

At pickup refresh both owners' relevant source/contracts, current runtime limits
and unresolved public seams. Keep implementation, qualification and activated
policy separate. Shared source pins are historical observations, not current
service status. Use normal protected source delivery; separately authorize live
activation/configuration. Never reset a failed lineage or move parked unrelated
work into this design's scope.

## Selected workset-only graph continuation, 7 October 2026

The [plan87 selection](https://github.com/pcvantol/forge/issues/208#issuecomment-6044025195) selects only the authorized-workset dependency graph in PRM-W-VIEW over the existing list/snapshot. Full project-DAG management/decision/sync/Q nodes remain unqualified. Candidate acceptance against exact Forge2.7.68 has its own installed/native receipts; protected merge and fresh exact-main qualification remain pending; PR137 remains completed with its distinct2.7.67 evidence.

## Selected scoped hold consumer, 8 October 2026

The [plan88 mandate](https://github.com/pcvantol/forge/issues/208#issuecomment-6050026304) adds only scoped hold/unhold, current status and durable command recovery over the completed workset list/graph. [Consumer boundary](WORKSPACE_WORKLIST_HOLD_CONTROLS_V1.md) pins Forge2.7.69/e64302f and full consumer delivery gates. This is a bounded PRM-W-CONTRACT/VIEW/MANAGE qualification subset, not full management/decision/sync/Q, graph reopening, chat selection or workset activation.
