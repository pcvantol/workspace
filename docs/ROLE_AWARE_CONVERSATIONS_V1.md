# Role-aware conversations V1 — Workspace experience

## Status and ownership

Increment: `ROLE_AWARE_CONVERSATIONS_V1`; coordinated contract target version `1`.
Design/documentation only, canonical after this repository's protected merge.
No frontend, backend, model invocation, credential, runtime migration or approval
is implemented by this increment. All new delivery nodes remain PLANNED.

This refines [role-aware governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md),
[Workspace architecture](ARCHITECTURE.md) and the [roadmap](../ROADMAP.md).
It preserves Business, Architect and Engineering/Security projections and adds
UX as an advice lens, NOT a fourth approval workspace or a mandatory gate.
The [Forge service contract](https://github.com/pcvantol/forge/blob/main/docs/architecture/ROLE_AWARE_CONVERSATIONS_V1.md)
owns reasoning/session/proposal semantics. Workspace owns the user experience
and its conversation/navigation state; EP owns engineering execution.

Source pins: Workspace `f220f61ce214416287d6c696d63642dbe0e7d2a7`, Forge
`e7633814d4c1bc8ad1e4b25435ab9f064f0438c9`, observed 2026-09-12. These are
historical design inputs, not peer runtime status. An unmerged peer design is
pending coordination. [Delivery plan](ROLE_AWARE_CONVERSATIONS_V1_ROADMAP.md).

## Information architecture

Project navigation gains **Conversations / Gesprekken**. Project overview,
Vision/Portfolio, Candidate, roadmap/DAG, design artifact and Mission detail
may open a conversation with an explicit focus reference. No Mission is needed
to ask a question, explore a design or receive an assessment.

The conversation list provides title, project, last activity, focus, last advice
mode, active request/attention state and archive state. Search/filter by title,
text where permitted, mode, focus, activity and archived state; sort by latest
activity or title. Source scope and permission-limited results are explicit.
Conversation search is not a provider invocation.

A conversation screen has:

- header: project/focus, title, mode, freshness and active operation;
- transcript: attributed user/advisor turns, timestamps, source references and
  visible FACT/INFERENCE/FORECAST/RECOMMENDATION/DECISION distinctions;
- context panel: included/excluded evidence, attachments, revisions, gaps;
- proposal/artifact panel: versioned drafts, differences, decisions and receipts;
- composer: message, supported attachments, visible advice mode and request bounds.

On narrow screens these are accessible tabs/drawers rather than compressed
columns. The design is functional, not a selected frontend technology stack.
Workspace continues to own that stack decision; do not infer one from EP's UI.
The existing shared design-system direction is reused where qualified, without
copying EP execution controls or making the Server Console the conversation UI.

## Three modes within shared project conversations

One conversation may use BUSINESS, ARCHITECTURE and UX advice modes. A turn
records its original mode; changing mode affects the next submitted turn only.
It does not create a new project, duplicate canonical records or grant permission.
Separate named conversations remain useful for different objectives; explicit
links/handoff packets connect them without silently importing private history.

| Mode | Primary user tasks | Typical reviewable result |
| --- | --- | --- |
| Business | Explore value and intended outcome, clarify users/assumptions, prioritize opportunities, challenge scope, refine Vision/Portfolio/Candidates | Business rationale, alternatives, success measures or Candidate/roadmap proposal. |
| Architect | Inspect feasibility and existing architecture, compare alternatives, review dependencies/critical path, refine technical boundaries and acceptance criteria | Findings, ADR/design options, refinement or dependency-change proposal. |
| UX | Explore user journeys and interaction behavior, navigation/content, accessibility, localization and design-system fit | User flow, wireframe specification, copy variants, review artifact or UX criteria. |

Labels may be Business chat, Architect chat and UX chat, but these are views of
one conversation capability, not isolated truth stores. AI advisor attribution
is distinct from the authenticated human actor and that actor's actual roles.
A suggestion to consult another advisor does not itself run a second model.
There is no mandatory Business -> UX -> Architect pipeline.

A UX recommendation is not a UX approval. Existing project-specific human
review obligations are displayed with owner, exact artifact revision and status.
No new UX grant or third universal Mission approval is introduced. Solo still
has separately recorded Business and Architecture decisions, even when the same
person performs both.

## Primary journeys

### Explore without committing work

Select project and mode, inspect automatically proposed context, submit a
question and receive cited advice. The result can stand on its own. A user can
copy/export the permitted result or save a proposal draft; none creates a Mission,
a Git commit, an approval or a programme execution grant.

A read-only analysis result is a successful advisory outcome when it answers the
question with attributable evidence. It is not automatically a formal EP
assessment execution. Unsupported formal read-only Mission paths remain visible
as unavailable; never invent a write scope to make them appear supported.

### Business idea to a governed Candidate

Discuss an outcome, inspect the structured proposal, edit assumptions/scope and
save the draft. **Create Candidate** submits an idempotent governed intent and
then reads the actual Candidate back. **Request Business decision** or an
eligible explicit approval refers to that exact revision. Candidate creation,
business approval, architecture approval and execution authorization remain
separate operations, even when several are available to the same person.

### Architecture/design refinement and handoff

Open a Candidate or a project-level architecture topic. Compare proposed changes
with current canonical artifacts, refine constraints and unresolved questions,
and route the proposal to the proper owner. A completed advice session is not
an approved design or a completed Mission. A design-only Mission handoff states
that implementation is excluded unless explicitly part of the approved outcome.

The handoff view contains linked conversation/session IDs, source revisions,
artifact revisions/digests, approved decisions, objective, exclusions, criteria
and unresolved questions. Engineering uses normal Mission Intake and EP, not a
new "execute this chat" shortcut. Any new successor must stay inside the existing
approved Mission boundary; optional implementation becomes a new proposal.

### UX collaboration

Supply a user goal and authorized screenshots/design assets. Review user flows,
empty/error/loading/offline states, accessibility and copy in context. Compare
artifact revisions, annotate a selected element or passage, and request bounded
reassessment. A UX -> Architect handoff preserves exact assets and open questions;
Business receives outcome/scope implications where needed, not a duplicate gate.

The initial slice supports text/structured design specifications and safe preview
of supported uploaded artifacts. Generating images, running prototypes or using
external design tools is capability-gated future work. Do not claim external
research, generated visuals or interactive previews when none were produced.

### Resume and resolve conflicts

Reopening uses durable conversation/session references and cursors. Display the
existing pending request rather than sending it again. Offline mode permits
labelled cached reads and local drafts only; it neither silently submits on
reconnect nor enables approval/apply. When sources or a proposal change, show
which revision changed, refresh and require a current applicable decision rather
than silently rebasing approval.

## Commands and confirmation semantics

| User operation | Effect and required readback |
| --- | --- |
| New/rename/archive conversation | Workspace presentation state only; does not stop provider/Mission work. |
| Change mode/context | Next-turn draft setting; no model call and no new authorization. |
| Send / request reassessment | One bounded Forge turn with stable idempotency and explicit provider-policy bounds. |
| Stop response | Requests cancellation of the same operation; show acknowledged, pending or uncertain outcome. |
| Edit/fork prior message | New linked turn/history branch; never overwrites decision-linked evidence or silently replays tools. |
| Save draft | Durable advisory draft, distinct from canonical Product state and Git. |
| Apply / create Candidate | Typed owner-bound intent with expected versions; only actual receipt/readback shows success. |
| Approve/reject/amend/defer | Existing role-aware decision over one exact proposal/artifact revision; revision changes reevaluate approvals. |
| Copy / download / export | Explicit permitted content only; source access, redaction and export policy are rechecked. |
| Delete / redact conversation | Owner-specific retention flow; explain any retained canonical decisions/provenance. No cross-owner deletion or Mission cancellation. |

The proposal detail shows before/after, affected scope and owner, rationale,
sources/freshness, unknowns, required roles and delivery/validation consequences.
Before a protected action, freeze the proposal revision/digest. The server
rechecks actor authority and preconditions; an enabled button is not authority.
A natural-language "yes" can confirm one unambiguously presented exact decision
through the same typed route. Ambiguous confirmation asks which proposal;
it never approves every pending card or both approval stages. Do not require
extra repetitive confirmation when an existing exact approval already covers
the operation. Clearly separate **Save draft**, **Apply**, **Approve** and
**Request execution**; permissions or capabilities may make some unavailable.

Multi-owner changes retain separate receipts and show partial completion honestly.
A pending/failed apply is not visually identical to approved or applied state.
A lost response resolves the same operation ID before any reattempt.

## Context and artifact interaction

Context panel shows project/focus and effective access scope; selected Vision,
Portfolio, architecture, roadmap, repository revisions, design-system assets,
EP evidence references and deliberately selected prior conversation excerpts.
The user may narrow proposed context. Broadening requires actual permission and
policy; a UI selection is insufficient. Missing or stale sources are labelled.
Derived summaries retain source references and cannot erase contradictions.

Attachments show media type, upload/processing state, revision, origin and safe
preview. Content is untrusted and sanitized, with bounded size/type and secret
handling. Unsupported, infected/suspicious or inaccessible content is not sent
to the provider. Preview, export and cross-conversation linking recheck access.
Model/provider/system secrets and private reasoning transcripts are never
exposed in the context drawer, logs, clipboard or exports.

Artifact review provides version comparison and references to comments/decisions.
A response may contain a useful document/design draft without a Git change.
**Deliver to repository** creates a proposal for existing governed engineering;
Workspace does not push files or invoke an EP Agent directly. Preview approval
remains bound to that revision and does not certify a later implementation.

## UI states, safety and recovery

Distinguish empty conversation, unsent draft, submitting, admitted, queued,
reasoning, provisional stream, result ready, cancelled, cancel pending,
permission denied, unsupported, failed, stale/conflict, offline and uncertain.
Every state offers the valid next operation and its owner, not raw exceptions.
Session COMPLETE means advice complete only. Invocation MAY_HAVE_HAPPENED has
no blind regenerate/model-fallback button; recovery/status is the same operation.

No automatic provider call on load, poll, reconnect, filter, mode switch, modal
open or notification. Provider availability/model policy belongs to Forge's own
services/configuration. Show effective configured capabilities and bounds, with
a link to the authorized administration surface where appropriate; do not reuse
EP installation paths/auth or force a separate paid API account.

Notifications distinguish ready advice, pending decision, conflict and provider
attention. Coalesce repeated events; dismissing a notice does not repair the
owning failure. Streaming text cannot expose an executable unvalidated proposal.
Markdown/links/previews must not execute arbitrary scripts or circumvent access.

## Persistence and API boundary

Workspace Server stores project-scoped conversation navigation, titles, user
preferences and presentation references. Forge stores the admitted reasoning
sessions, context/provider/result provenance and authoritative proposals and
decisions. Persist turn/request IDs before submit; drafts and acknowledged server
records remain distinguishable. Forge and Workspace never share SQL or silently
create editable duplicate authorities. APIs expose versioned capabilities;
unavailable contract versions disable relevant commands with explanation.

Read models include ConversationSummary, ConversationDetail, ContextManifest,
SessionProjection, ProposalProjection, ArtifactRevision and DecisionProjection.
These are target names, not shipped endpoints. Commands/events reuse the owning
versioned application envelope: actor/project, correlation, idempotency,
expected revision and cursor. Workspace never shells out to Forge CLI, reads
Forge/EP DBs or sends engineering commands directly to a host filesystem.

Retention distinguishes local drafts, admitted transcripts/results, cached
projections and decision-linked provenance. Archive is reversible navigation;
deletion/redaction reports exact affected owner records and retained evidence.
Restore never invents approval or retries a provider. Closing Workspace does
not stop Forge or EP; Forge Server Console remains the admin interface.

## Accessibility, language and verification

All user-facing states, errors, actions, proposals and confirmation framing
support en/nl/de/fr/es. User-authored text retains its language; translated
summaries are labelled projections, not new authoritative artifact revisions.
Use shared design tokens/components where adopted, responsive layouts,
keyboard/focus restoration, screen-reader labels and non-disruptive streaming
announcements. Do not rely on color-only role/state meaning or browser alert().

Future qualification uses real Workspace request/readback/state handling and
Forge contract fixtures; external provider and EP are mocked. Playwright covers
conversation creation, mode change, history/context, proposal review, exact
confirmations, failure/reconnect and accessibility in all five languages.
Changed/new executable components must meet a >80% coverage target, with
critical authorization, idempotency and no-side-effect branches explicitly
covered; aggregate coverage never substitutes for those cases. This documentary
increment supplies only offline design guards, not browser/runtime proof.

## Shared acceptance catalogue and ownership

The full scenario definitions RC-T01 through RC-T20 live in the Forge service
contract. Workspace's graph references those IDs rather than redefining results.

| Scenario IDs | Workspace obligations |
| --- | --- |
| RC-T01, RC-T02, RC-T03 | Business/Architect/UX flows distinguish advice, artifact, proposal and approval. |
| RC-T04, RC-T05 | Mode switch, handoff, edit/fork/archive and resumed history preserve context/provenance. |
| RC-T06, RC-T07 | Duplicate/lost-response/timeout/cancel/ambiguity states do not regenerate. |
| RC-T08, RC-T09, RC-T10 | Stale and cross-project context, source access and untrusted attachments/rendering fail safely. |
| RC-T11, RC-T12 | Exact scoped confirmation and Solo's separate approval stages; no privilege from mode. |
| RC-T13, RC-T14 | Design-only delivery handoff and read-only advice do not become implicit code/Git changes. |
| RC-T15, RC-T16 | Provisional/unsupported/offline/restart/retention behavior remains honest and recoverable. |
| RC-T17 | Qualified Candidate/decision API projection connects to real Forge intake/inner-loop fixture without second authority. |
| RC-T18 | Later outer-loop recommendation is advisory; no unattended approval of the next Mission. |
| RC-T19, RC-T20 | Five-language accessible browser parity; Console/Workspace boundaries and continued headless operation. |

`CHAT_TRANSCRIPT_IS_AUTHORITY = FALSE`
`ADVISOR_KIND_IS_AUTHORIZATION_ROLE = FALSE`
`UX_REVIEW_REQUIRED_FOR_EVERY_MISSION = FALSE`
`CHAT_DIRECT_REPOSITORY_MUTATION = FALSE`
`CHAT_CREATES_EXECUTION_AUTHORITY = FALSE`
`ROLE_CHAT_REQUIRED_FOR_FIRST_CANARY = FALSE`
