# Workspace Roadmap

## Business, Architect and UX conversations — designed productization lane

`ROLE_AWARE_CONVERSATIONS_V1` is specified in the
[functional design](docs/ROLE_AWARE_CONVERSATIONS_V1.md),
[owning delivery roadmap](docs/ROLE_AWARE_CONVERSATIONS_V1_ROADMAP.md) and
[documentary DAG](docs/ROLE_AWARE_CONVERSATIONS_V1_DAG.json). It refines existing
role-aware governance with one project conversation capability and three advice
modes, shared context/history, proposals, artifact review and explicit handoff.
UX Advisor adds advice, not a new mandatory Mission approval stage.

`RC-WC -> RC-WS -> RC-WP -> RC-WQ` consumes the corresponding qualified Forge
contract/session/proposal/service subsets RC-FC/FS/FP/FQ under existing F6.
All runtime nodes remain PLANNED. Contract-first work is parallel non-blocking;
full Workspace delivery is POST_AUTONOMY. No edge is added to the first live
canary, and neither full policy UI nor the universal installer is a prerequisite.
Twenty shared scenario families distinguish future runtime/Playwright proof
from the offline documentary guards in this increment. RC-T18 joins the later
outer-loop CI programme; it does not block basic conversation delivery.

## Repository Health and reconciliation chat — documented target

`WORKSPACE::REPOSITORY_HEALTH_AND_RECONCILIATION_V1` is specified in the
[Repository Health/chat design](docs/REPOSITORY_HEALTH_AND_RECONCILIATION.md)
and [scoped roadmap](docs/PROJECT_HYGIENE_V1_ROADMAP.md), coordinated with
Forge's documentary Project Hygiene DAG. Workspace presents evidence-backed
observations, cases, proposals and decisions; Forge owns reasoning and EP owns
host facts and admitted cleanup. Asking about/reconciling an old branch does
not automatically allocate a Mission or authorize deletion.

Sequence: `HY-0 -> HY-WC -> HY-WO -> HY-WM`. HY-WO additionally consumes Forge
HY-F observations/cases; HY-WM requires qualified Forge/EP HY-Q command/receipt
semantics. Read-only health/chat can ship without destructive controls. All
implementation nodes remain PLANNED. Preserve actual actor/project scope,
partial/stale inventory, exact confirmation sets and per-target audit outcomes.
The full UI is not a first-canary prerequisite; no runtime configuration,
credentials, policy activation, version or executable programme DAG changes here.

## Governed progression and existing external delivery gates

The coordinated `GOVERNED_PROGRESSION_AND_DELIVERY_AUTHORITY_V1` increment adds
[project/Mission review cadence and external Human Gate design](docs/GOVERNED_PROGRESSION_AND_EXTERNAL_GATES.md)
and the [GP-WC/GP-W roadmap](docs/GOVERNED_PROGRESSION_V1_ROADMAP.md).
Workspace presents effective settings and owner-backed decisions, but does not
choose Forge progression or take over a project's CD approval/deployment.
Prototype Mission-end review and production after-Action review are configurable
profiles within approved bounds. TST/ACC/PROD are target-bound classifications.
An external production gate is shown with its owner/status/deep-link, not a
second Workspace approval. All implementation remains PLANNED; this documentary
sub-DAG does not modify the executable bootstrap programme or add rich UI/CD
integration ahead of the first machine canary.

## Policy & Automation — documented governance lane

The coordinated `POLICY_GOVERNANCE_AND_EFFECTIVE_PROFILES_V1` increment defines
[Policy & Automation / Beleid & automatisering](docs/POLICY_AND_AUTOMATION.md).
Workspace owns catalogue/effective-policy explanations, scoped change/impact,
role-routed decisions, activation status and historical audit views. Forge, EP
and Forge Platform remain the owners of their policy definitions and enforcement.
A policy is not a grant; consumed repair budget is not an editable preference.

Local DAG: `POL-0 -> POL-WC -> POL-W`; POL-W additionally requires cross-product
POL-Q (qualified owner binding/evaluation/receipt contracts). POL-WC is a planned
contract-first parallel lane, POL-W is planned post-autonomy UI. These are target
milestones, not existing application features or newly created runtime authority.
The coordinated documentary DAG lives at
`pcvantol/forge:docs/roadmap/policy-governance-v1.json`.

Native Forge release management and EP assurance feed the same view; independent
product/component versions and actual published artifacts remain distinct.
Pending Workspace #14 is repository-versioning work, not this management feature.
No implementation, workflow, package version, grant or executable programme DAG
changes here. Full policy UI is not a prerequisite for the first machine canary.

## Installed Workspace Server and Client lane

Workspace will deliver a headless installed Server with its own central runtime
storage root, versioned HTTP application API, stable identity and macOS launchd
lifecycle, plus a separately installable Workspace Client for client PCs.
Client/server and server-peer discovery uses candidate-only LAN DNS-SD/mDNS or
configured/unicast/tailnet bootstrap followed by authenticated pinned pairing;
discovery never authorizes or silently changes an existing binding. Client
trust, EP Agent trust and server-peer trust remain separate.

This is a post-autonomy productization lane: the first Forge→EP→Forge canary
does not require Workspace UI, client distribution or universal installer
completion. See [Workspace Server and Client deployment target](docs/WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md).

## Foundation

Completed: establish standalone repository identity and record the absence of prior implementation history.

## Bootstrap critical-path position

Workspace is **not** on the critical path for the first Forge → Engineering Platform → Forge autonomous-execution canary. Workspace remains the human/project control plane and projection surface; it is not planning or execution authority.

Current cross-product sequencing is a **read-only dependency projection**, not
an independent status authority. Resolve EP and Forge status at their fresh
remote `origin/main` revisions during an Architect session; this sequence says
which producer conditions precede another, not whether a peer condition is
currently active or complete.

1. EP-owned P-NEUTRAL closure precedes EP-owned P-INSTALLER-V1 qualification.
2. Engineering Platform qualifies P-INSTALLER-V1 as an EP Server-only installed-product boundary.
3. DJConnect receives/qualifies its committed B8R `.engineering-platform/repository.json`, attaches to installed CENTRAL EP and completes one real governed Engineering Action.
4. EP records `EP::STANDALONE_EP_VERIFIED`.
5. EP then proves one real bounded self-development Action against the Engineering Platform repository through CENTRAL, yielding `EP::SELF_HOSTED_ENGINEERING_VERIFIED`.
6. Forge is attached/dogfooded as a real EP-managed development repository before or during Forge execution integration.
7. Forge then integrates with the already-canonical EP P-TRANSPORT HTTP submission and run/result/evidence contracts and qualifies Forge-side reconciliation.
8. After the first Forge → EP → Forge loop is proven, Workspace joins the product critical path for installed human control-plane capabilities.

Workspace itself may also be attached to CENTRAL and receive a real EP-governed development Action as an additional dogfood proof. That is desirable but **non-blocking for first Forge autonomy**.

Broader EP Agent separation, generalized dispatch/multi-host scheduling and multi-repository parallel execution are follow-on productization work; Workspace must not treat them as prerequisites for the first standalone EP or Forge autonomy canary.

Project/repository identity follows B8R: the Canonical Project Authority Repository declares durable logical identity in `.engineering-platform/repository.json`. Workspace may project that identity and own mutable human-facing project state/display naming, but Workspace availability is not required for EP to attach a declared repository.

## Core product direction — role-aware project governance

Workspace should become the canonical human interaction surface for project understanding and governed decisions. The architecture is defined in `docs/ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md`.

The product principle is:

> the right decision, routed to the right role, with evidence projected at the level relevant to that role while preserving canonical provenance.

Workspace uses shared Forge Project Intelligence and EP evidence, but exposes different projections:

- **Business Workspace** — project outcome, progress, forecast, high-level remaining work, risks/blockers and business decisions;
- **Architect Workspace** — capability DAG, technical/cross-product dependencies, critical path, Expected Missions, Mission Candidates and Forge Roadmap/DAG Change Proposals;
- **Engineering/Security Workspace** — Missions/Actions/runs, exact-head qualification, technical exceptions, receipts and security evidence where human attention is actually required.

This is more than RBAC: decision classification determines who should decide and what evidence is sufficient for that decision.

## Role-aware decision architecture

Planned core capability family:

`WORKSPACE::ROLE_AWARE_GOVERNANCE_V1`

Architecture seams:

- decision identity and `decision_type`;
- one or more `required_roles`;
- `Decision Evidence Package` with canonical evidence references;
- context-specific evidence projection;
- `FACT / INFERENCE / FORECAST / RECOMMENDATION / DECISION` classification;
- approve / reject / amend / defer semantics;
- single-role and multi-role Human Gates;
- immutable decision provenance/audit history.

Routine evidence ingestion, milestone completion backed by already-authoritative evidence, bounded engineering repairs and qualification retries must not become unnecessary human approval gates.

## Roadmap and DAG Management

Roadmap/DAG Management is a core Workspace direction, especially for Business Owner and Architect roles.

Planned capability family:

`WORKSPACE::ROADMAP_DAG_GOVERNANCE_V1`

The mature surface should provide:

- current canonical roadmap/capability DAG;
- critical-path view;
- EP execution/status/evidence overlay;
- Forge Expected Mission and Mission Candidate overlays;
- Forge-generated Roadmap/DAG Change Proposals;
- before/after DAG/roadmap diff;
- impact, risk and forecast projection;
- role-routed approve/reject/amend/defer;
- decision provenance;
- automatic refresh after new canonical evidence.

Workspace does **not** become the planning engine. Forge derives project context, expected work, candidate work, forecasts and roadmap insights. Workspace renders and governs those proposals. Direct drag/drop or edits create governed intent/proposals rather than silently rewriting canonical roadmap authority.

## Forge planning concepts in Workspace

Workspace preserves these distinctions:

- **Expected Mission** — dynamic, confidence-bearing Forge inference about likely future work; non-canonical and allowed to appear/disappear as project knowledge changes;
- **Mission Candidate** — advisory concrete possible next Mission;
- **Mission** — selected/governed canonical work;
- **Roadmap Change Proposal** — Forge-proposed change to approved roadmap/DAG structure; advisory until approved.

Expected Missions must never look like committed backlog. Mission Candidates must never look approved until promoted through governance.

## Business versus Architect projection

Business Workspace should primarily answer:

```text
Where is the project?
What is done/current/next at a high level?
What blocks the intended outcome?
When is completion likely and how confident is that forecast?
Which business decisions require me?
```

Architect Workspace should primarily answer:

```text
Why is this the sequence?
What are the technical dependencies and producer gates?
What is on/off the critical path?
What work does Forge expect or recommend?
Which DAG/architecture changes require an architect decision?
```

Both are projections of the same canonical project state and Forge Project Intelligence, not separate roadmaps.

## V1 preparation versus later Workspace productization

The full governance UI is **not required for the first Forge -> EP -> Forge machine canary**. However, the following architecture seams should be established early so V1 contracts do not block later core functionality:

- stable project/capability/dependency/proposal identifiers;
- decision type and required-role taxonomy seam;
- canonical evidence-reference/provenance contract;
- Decision Evidence Package contract;
- claim semantic classification;
- approve/reject/amend/defer lifecycle;
- Business/Architect/Engineering projection boundary.

Can follow after first machine autonomy loop:

- rich interactive DAG editing;
- probabilistic completion forecasting UI;
- automatic roadmap reorder proposals;
- scenario planning;
- complex multi-party approval policy configuration;
- increasingly automatic low-risk roadmap state updates;
- portfolio-level forecasting.

## Real-project Workspace dogfood

When selected, Workspace dogfood follows the same EP product boundary as other repositories:

```text
committed Workspace .engineering-platform/repository.json
  -> EP validates + attaches to CENTRAL
  -> canonical P-TRANSPORT submission
  -> admission/run
  -> real bounded Workspace repository mutation
  -> Workspace canonical validation
  -> finalization
  -> immutable EP evidence
```

This proves EP can engineer Workspace; it does not grant Workspace execution authority and does not require Workspace to orchestrate the run itself.

`WORKSPACE_REAL_EP_DOGFOOD_PLANNED = TRUE`
`WORKSPACE_REAL_EP_DOGFOOD_BLOCKS_FIRST_FORGE_AUTONOMY = FALSE`

## Proposed repository onboarding and control plane

A bounded onboarding experience for logical projects/repositories remains planned. It may offer **Use existing repository**, **Create new repository**, **Genesis project**, and a **qualification-only repository** variant. The canonical design remains in `docs/REPOSITORY_ONBOARDING.md` and must be reconciled with B8R before implementation.

Workspace presents and initiates permitted intent; Forge plans and reasons about project dependencies; EP CENTRAL accepts durable execution/lifecycle intent and remains execution authority. Host-local engineering remains EP-owned.

For a real admission-ready onboarding flow, consumer-facing producer qualification remains EP-owned. The current B8R project identity/attachment runtime is sufficient for direct EP dogfooding; richer onboarding/cutover UX remains a later Workspace capability.

The qualified `EP::LOCAL_CONSUMER_API_V1` remains a consumer/authentication base. Separately, P-TRANSPORT already provides canonical submission transports (HTTP, installed CLI and Server-owned File Inbox); Workspace does not own or duplicate those transports.

Multi-repository parallel mutating lanes are explicitly post-verification work. Serial real-project dogfood is sufficient for the bootstrap proofs.

## Next decisions

1. Reconcile the fresh EP-owned P-NEUTRAL/P-INSTALLER-V1 status and the DJConnect + EP self-development real-project proofs.
2. Reconcile the fresh Forge-owned direct-EP dogfood and first Forge → EP → Forge loop status.
3. In parallel, stabilize the shared Project Intelligence / Decision Evidence / roadmap-DAG identity contracts without making the full Workspace UI a bootstrap blocker.
4. After the first reliable machine loop, select a bounded first Workspace governance surface — likely project status + role-routed decision inbox + Architect DAG projection.
5. Reconcile `docs/REPOSITORY_ONBOARDING.md` with B8R before implementing onboarding.
6. Add Workspace direct-EP dogfood when useful; it does not block first Forge autonomy.
7. Design the installed EP adapter as a separate Workspace increment after producer contracts are qualified.

No item authorizes Workspace to implement EP execution or become Forge planning authority.

## Cross-product dependency register

| Workspace capability | Cross-product relationship | Earliest dependency | Required qualification |
| --- | --- | --- | --- |
| Role-aware Governance foundation | Route decisions/evidence without taking over Forge/EP authority. | Stable Forge proposal/evidence identities; can start contract-first before live loop. | Role/evidence/provenance/no-secondary-authority contract tests. |
| Roadmap/DAG Governance | Present canonical plan plus Forge insights/proposals and govern human plan changes. | Forge Project Intelligence contracts; full live status improves after Forge/EP reconciliation. | Diff/provenance/role-routing/no-silent-mutation qualification. |
| Business project-status/forecast projection | High-level outcome/progress/forecast view. | Project Completion Model + enough historical/live evidence for honest forecasting. | Attribution/confidence/degraded-state validation. |
| Architect DAG projection | Technical dependency/critical-path view with Forge insights. | Stable roadmap/DAG identities + Roadmap Change Proposal contract. | Dependency provenance, impact projection and approval semantics. |
| Direct EP development dogfood | Prove EP can engineer Workspace without giving Workspace execution authority. | Installed EP standalone/self-development producer available. | Real bounded Action, validation, finalization, immutable EP evidence. Non-blocking for first Forge autonomy. |
| Onboarding/control plane | Present project topology and permitted lifecycle intent without becoming attachment/execution authority. | Qualified EP consumer-facing attachment/admission contract; Forge bootstrap only where managed composition is needed. | Workspace UX/accessibility/no-secondary-authority proof plus producer qualification. |
| Quality governance surface | Present Effective DoR/DoD/Human Gates and governed Quality Learning proposals. | Forge evidence/quality contracts plus Workspace onboarding. | Attribution, freshness/degraded-state, accessibility and no-secondary-authority proof. |
| Knowledge governance surface | Present evidence-linked Knowledge lifecycle status and permitted intents. | KB export/read contracts. | Post-V1 lineage/redaction/accessibility proof. |

The Forge labels are dependency references only. This roadmap remains canonical authority for whether, when and how Workspace develops its own surfaces.
