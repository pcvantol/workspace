# Role-Aware Governance and Roadmap/DAG Management

> **Deployment sequencing:** Workspace Server/Client installation, discovery
> and pairing are a Workspace productization lane, not an authority prerequisite
> for the first Forge→EP→Forge autonomy canary. See
> [Workspace Server and Client deployment target](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md).

## Status

Architecture direction for Workspace. This document defines core product concepts and authority boundaries; not every capability described here is a V1 critical-path requirement.

## Product intent

Workspace should be the human control plane where people with different responsibilities understand project state, see the decisions relevant to them and make governed decisions using evidence projected at the appropriate level of abstraction.

The core principle is:

> Present the right decision to the right role, with the smallest evidence package that is sufficient for that decision, while preserving links to canonical underlying evidence.

Workspace is not a planner or execution engine. Forge reasons, forecasts and proposes. Engineering Platform executes and produces execution evidence. Workspace turns those facts and proposals into role-appropriate comprehension and governed human decisions.

## Shared project intelligence, multiple role projections

Business Workspace, Architect Workspace and Engineering Workspace are different views of the same canonical project state and Forge Project Intelligence.

```text
                  canonical project state
                           |
            Forge reasoning + EP evidence
                           |
                           v
                    decision needed
                           |
                    classify decision
                           |
       +-------------------+-------------------+
       |                   |                   |
       v                   v                   v
 Business Owner        Architect         Engineering/Security
       |                   |                   |
 business evidence    architecture       technical evidence
 projection           evidence           projection
       |               projection              |
       +-------------------+-------------------+
                           |
                           v
                   canonical decision
```

## Workspace surfaces

### Business Workspace

Answers primarily:

- Where does my project stand?
- What is done, active and still expected at a high level?
- What is blocking the intended outcome?
- When is completion likely and how confident is that forecast?
- Which business-level decisions require my attention?

Illustrative projection only — labels and values below are not current EP
status. A live Workspace projection must cite freshly resolved producer
evidence and distinguish facts from forecasts and recommendations:

```text
Project: <project>
Overall progress       <evidence-backed projection>
Current milestone      <fresh producer-owned frontier>
Expected completion    <forecast + confidence>
Known blockers         <evidence-backed count>

Done
  <completed capabilities with provenance>

Now
  <fresh producer-owned frontier>

Next
  <dependency-ordered future capabilities>
```

Business Workspace deliberately suppresses schema versions, run IDs, trigger definitions and low-level validation details unless the user drills down.

### Architect Workspace

Answers primarily:

- Why is the work sequenced this way?
- What are the technical/cross-product dependencies?
- What is currently on the critical path?
- Which dependencies can be removed, added or parallelized?
- What Expected Missions and Mission Candidates does Forge see?
- Which architecture or roadmap proposals need an architect decision?

This surface may show the capability DAG, dependency edges, producer/consumer contracts, critical-path impact, risk, evidence provenance and Forge reasoning.

### Engineering / Security Workspace

Answers primarily:

- Which Missions/Actions/runs need attention?
- Which exact-head validation or security evidence is missing/conflicting?
- Which technical approvals actually require an engineering/security authority?

This view may expose exact commits, tests, negative matrices, receipts and relevant canonical EP evidence.

## Decision classification and role routing

Workspace treats a human gate as a first-class `Decision` with a `decision_type` and one or more `required_roles`.

Examples:

- `BUSINESS_SCOPE_CHANGE` -> Business Owner;
- `ARCHITECTURE_DEPENDENCY_CHANGE` -> Project Architect;
- `PROJECT_PRIORITY_CHANGE` -> Business Owner or delegated portfolio role;
- `HIGH_RISK_EXECUTION` -> Architect + Security Authority where policy requires;
- `ENGINEERING_EXCEPTION` -> Engineering/Security authority;
- evidence-only completion transition -> normally no human decision.

Role routing is more than access control: it determines the decision framing and evidence projection.

## Decision Evidence Package

Every non-trivial human decision should be backed by a bounded `Decision Evidence Package`.

A package contains:

- decision identity and type;
- affected project/scope;
- required role(s);
- claims that must be proven for the decision;
- canonical evidence references;
- context-specific summarized projection;
- conflicting or missing evidence;
- uncertainty/confidence where relevant;
- Forge recommendation and reasoning, clearly marked as recommendation rather than fact;
- before/after impact for roadmap or DAG changes;
- decision provenance after approval/rejection/amendment/deferral.

Workspace must never replace canonical evidence with an AI summary. The summary is a projection with traceable evidence references.

## Evidence semantics

Every projected statement is labeled semantically as one of:

- `FACT` — directly supported by canonical evidence;
- `INFERENCE` — Forge interpretation;
- `FORECAST` — probabilistic future projection;
- `RECOMMENDATION` — proposed choice/change;
- `DECISION` — human/governance outcome.

This distinction must remain visible enough that users do not mistake a forecast or recommendation for proven project state.

## Roadmap and DAG Management

Roadmap/DAG Management is a core Workspace capability, especially in Business and Architect Workspace.

Workspace should eventually support:

- canonical roadmap view;
- capability DAG view;
- critical-path view;
- execution/status overlays from EP;
- Expected Mission and Mission Candidate overlays from Forge;
- Forge-generated Roadmap/DAG Change Proposals;
- proposal before/after diff;
- impact and forecast projection;
- approve / reject / amend / defer;
- decision audit/provenance;
- automatic refresh after new canonical evidence.

Workspace does not directly mutate canonical roadmap/DAG state from drag/drop or form edits. User interaction creates governed intent/proposals which Forge validates against project context and dependency semantics before canonical approval/mutation.

## Example architecture decision

```text
Decision
Remove generalized Agent Separation as predecessor of STANDALONE_EP_VERIFIED?

Current DAG
Installer -> Agent Separation -> Canary

Proposed DAG
Installer --------------------> Canary
Agent Separation -------------> post-standalone

FACT
- current execution path can perform the bounded standalone canary
- P-TRANSPORT is qualified

INFERENCE
- generalized Agent topology is no longer a prerequisite for this gate

FORECAST
- critical path may shorten by one capability

RECOMMENDATION
- accept the proposed dependency removal

[Approve] [Amend] [Reject] [Defer]
```

## Business and architecture decisions use different projections

The same underlying change can have different projections.

Architect Workspace may show exact dependency edges, capability contracts and qualification evidence.

Business Workspace may show only:

```text
Planning improvement proposed
Expected completion may move earlier
Business scope unchanged
Architecture risk: low
```

The decision is routed to the role whose authority is relevant; other roles may receive an informational projection without an approval control.

## Relationship to Forge Mission concepts

Workspace visualizes but does not own Forge planning concepts:

- `Expected Mission` — dynamic, non-canonical likely future work inferred from Project Context;
- `Mission Candidate` — advisory concrete possible next Mission;
- `Mission` — governed canonical work;
- `Roadmap Change Proposal` — advisory change to canonical roadmap/DAG structure.

Expected Missions may appear/disappear as knowledge changes and must not be shown as committed backlog. Mission Candidates must not be shown as approved work until governed into a Mission.

## Core architecture capability families

### `WORKSPACE::ROLE_AWARE_GOVERNANCE_V1`

- decision classification;
- role routing;
- Decision Evidence Packages;
- context-specific projections;
- single-role and multi-role Human Gates;
- approve / reject / amend / defer;
- decision provenance and history.

### `WORKSPACE::ROADMAP_DAG_GOVERNANCE_V1`

- Business project-status projection;
- Architect capability/DAG projection;
- critical-path visualization;
- Expected Mission / Mission Candidate overlays;
- Forge Roadmap/DAG Change Proposals;
- proposal diff and impact;
- governed approval/amend/reject/defer;
- refresh from EP/Forge evidence.

These are core product directions, but full implementation is not required before the first Forge -> EP -> Forge autonomy canary.

## V1 preparation versus later productization

### Establish early

- stable project/capability/dependency/proposal identities;
- decision-type and required-role taxonomy seam;
- evidence references and provenance model;
- `FACT / INFERENCE / FORECAST / RECOMMENDATION / DECISION` semantics;
- Decision Evidence Package contract;
- approve/reject/amend/defer lifecycle semantics;
- Business/Architect/Engineering projection boundary.

### Can follow after first machine autonomy loop

- interactive DAG editing;
- advanced completion forecasting UI;
- continuous automatic reordering proposals;
- complex multi-party approval policy editor;
- automatic low-risk roadmap changes;
- portfolio-level business forecasting;
- rich scenario simulation.

## Non-goals

- Workspace does not become Forge planning authority.
- Workspace does not become EP execution authority.
- Role projections do not create new underlying facts.
- A human-facing summary is never sufficient evidence when the governing contract requires canonical producer evidence.
- Human approval is not required for routine evidence ingestion or engineering repair loops that policy already authorizes.

## Live roadmap and approved-pending management — functional refinement

`LIVE_PROJECT_ROADMAP_MANAGEMENT_V1` now details this existing family in the
[functional design](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1.md),
[scoped roadmap](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_ROADMAP.md) and
[documentary DAG](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_DAG.json). One snapshot
combines capabilities, active Missions, approved pending work, Candidates,
Expected work and history, with an attention facet and iteration-change view.

Frozen revision, approvals, automatic release authority, current eligibility and
actual activation are distinct. Existing Forge services can activate explicitly
preapproved/released Missions after current evidence and safety gates, without
another owner message; Workspace does not approve them or schedule them. A new
Candidate still needs real approvals. HTTP-only peers, separate EP admission,
unchanged budgets and immutable history remain. Six Forge and four Workspace
planned nodes share twenty-four future qualification families. This adds no
implementation, live grant, executable programme or first-canary dependency.
