# Policy & Automation — Workspace governance surface

## Decision and delivery status

Increment: `POLICY_GOVERNANCE_AND_EFFECTIVE_PROFILES_V1`.
This is Workspace's target UX/consumer architecture in one coordinated four-repo
**documentation and roadmap increment**. It is canonical design only on owning
`main`; an open proposal is `PENDING_PR`. No frontend, HTTP route, runtime store,
policy engine, configuration or permission change is implemented by this document.

Source baseline: Workspace main `c8240c39f295f3c976955a7cfd04a08c0147470b`,
observed 2026-09-08. Existing [architecture](ARCHITECTURE.md) explicitly records
that the application stack remains undecided; [role-aware governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md)
and the [roadmap](../ROADMAP.md) define the human control-plane direction.
This proposal extends that direction, not an already qualified settings page.

Shared logical policy vocabulary is maintained by Forge at
`docs/architecture/POLICY_GOVERNANCE_AND_EFFECTIVE_PROFILES.md`, proposal
[Forge #50](https://github.com/pcvantol/forge/pull/50).
EP's owning profile contract is
`docs/engineering/POLICY_GOVERNANCE_AND_ASSURANCE_PROFILES.md`, proposal
[EP #103](https://github.com/pcvantol/engineering-platform/pull/103).
Owning main revisions, not Workspace copies, control policy meaning.

## Product boundary

Workspace provides one **Policy & Automation / Beleid & automatisering** experience.
Forge owns planning/progression and version/release policies; EP owns execution,
review/quality/security/validation/repair/provider policy; Forge Platform owns
artifact/deployment compatibility and installation policy. Workspace owns the
human interaction, its own UX/session preferences and its read models, not the
policy enforcement of those peers.

```text
Workspace Client -> Workspace Server: actor/session + requested scoped intent
Workspace Server -> owning product API: authenticated actor/decision reference
Owning product -> validated decision/activation/effective-policy receipt
Workspace -> shared and historical projection, never a second authority
```

The architecture does not require all three server roles to be installed or online.
Missing owners are shown unavailable; unsupported capability is not an editable
setting. No cross-product SQL, direct provider commands, secret export or
standalone policy administrator daemon is introduced.

## Catalogue and administration domains

| Display family | Owning decision/enforcement | Display/interaction scope |
| --- | --- | --- |
| Autonomy and pause boundaries | Forge | Continuous or supported Action/Intent/Mission review profiles and their consequences |
| Governance participation | Forge's declared profile and relevant owning authority | Roles/approval matrix, Solo responsibility composition, actual grant references |
| Planning/model preferences | Forge | Cost/latency/reasoning preferences and bounded planning-provider configuration |
| Execution assurance | EP | Applicable validation, independent quality/security criteria, policy-derived dispositions, repair ceiling |
| Execution operations | EP | Permitted timeout/capacity/queue preferences within qualified capability; operator-only actions |
| Versions and releases | Forge for planning; product repository for version source; EP for execution | Impact, planned version, reservation versus commit/build/publication, major decision and artifact evidence |
| Deployment/composition | Forge Platform | Selected components, compatible policy/API/artifact requirements, owner activation/installation receipts |
| Workspace preferences | Workspace | Presentation/session preferences; they grant no planning or execution authority |

Each entry shows owner, scope, definition source, revision/digest, supported
runtime, current activation, allowed changes, required roles, evaluated origin
and evidence freshness. Label hardcoded baselines and implementation limits
honestly instead of presenting every code constant as a working configuration API.

## Distinguish what can be edited

- INVARIANT: protected architecture/security rule, no ordinary toggle.
- GOVERNED_POLICY: change proposal with versioning, validation and authority.
- OPERATIONAL_CONFIGURATION: supported owner API, range limits and operator audit.
- AUTHORIZATION_GRANT: a separate concrete, time/scoped permission decision.
- RUNTIME_FACT: observed or consumed state; not a settings field.
- IMPLEMENTATION_LIMIT: actual qualified capability, not a numeric UI override.

For example, a review profile permitting up to three repairs and a run that has
consumed two are separate rows. Editing a preference cannot reset consumption,
increase an existing grant, renew expiry, enable unsupported parallel execution
or change what an old run was assessed against.

## Required views

### Catalogue and effective policy

Offer installation/project/repository/component/Mission/Action/run context where
the owning policy family supports it. Show explicit values, inherited requirements,
source definitions and resolution explanation. Do not assume that the most local
scope wins: ceilings combine restrictively, obligations accumulate and allowlists
intersect according to owner-defined typed rules.

The detail view explains **why allowed?** and **why waiting?** Distinguish policy
conflict, grant/expiry, missing capability, EP lease/capacity, remaining budget,
technical qualification and temporarily unreachable owner. A single red/green
badge cannot stand in for these independent conditions.

Show definition, assignment, activation and per-run snapshot separately.
Do not show a draft as active, a recommendation as a decision or a candidate
version as an already published release.

### Proposal, comparison and impact

Editing supported fields creates a proposal with exact old/new revisions and an
expected-version precondition. Source-owned repository changes follow the existing
engineering/review route; Workspace never becomes their direct file/SQL writer.

Impact preview is produced by the appropriate owning evaluator, with Forge
planning impact when relevant. It identifies changed obligations, affected future
work, in-flight snapshot treatment, existing grants, incompatible runtimes and
which changes require a genuine role decision. Preview remains advisory until
approved and activated by the owner.

A policy-changing Action is reviewed under the previously approved policy.
The proposed replacement cannot authorize itself or remove its own review gates.

### Decisions and activation

Reuse existing decision types, required-role semantics and Decision Evidence
Packages. The owner determines who can propose, approve, activate or revoke;
visibility of a button or a local role label is not authority. Solo may assign
multiple responsibilities to one authenticated person but must retain distinct
required decisions and provenance.

Flow: draft -> validate -> impact -> required approve/reject/amend/defer decisions
-> immutable revision -> owner activation receipt. Routine policy evaluation,
requalification or bounded iteration under a still-valid grant is not a new
human approval. Major/security/scope expansion remains a real decision.

For a cross-owner changeset show per-owner accepted/active revisions and partial
failure explicitly. There is no atomic transaction across service databases.
Dependent new work waits for its required compatible activation vector; unrelated
work need not stop. Rollback creates a new audited activation of known content,
never removes history, revives a revoked grant or returns consumed budget.

### Audit and historical execution

A historical run displays its exact effective policy/evaluator/source snapshot,
review identities, immutable observations and resolution links, repair IDs/counts
and receipt evidence. New defaults never recolor legacy runs into fabricated PASS.
Missing old evidence is NOT_RECORDED or UNRESOLVED, not zero findings.

Policy history includes actor, role/evidence, diff, scope, decision and activation
receipts. Runtime revocation/expiry remains visible separately from the pinned
snapshot; a formerly valid profile cannot hide a current denial of new writes.

No new LLM call is needed to render stored rationale or a step-modal.

## Workflow administration is constrained configuration

V1 exposes supported lifecycle profiles and extension points, not a free-form
workflow designer. It cannot move security review after publication, skip required
validation, allow a reviewer to mutate, expand target scope or create an unbounded
repair loop. Arbitrary scripts, custom executable evaluators or raw shell commands
are not configuration fields. Tooling configuration belongs to its governed
repository/product contract.

A later visual designer requires a separately qualified lifecycle-schema validator.
It is not a prerequisite for the current policy contracts, native release planning
or the first Forge -> EP -> Forge Mission canary.

## Client/server trust and owner API contract

Workspace Client uses the established user/session relationship to Workspace
Server. Service-peer authentication must preserve actor, scope and required
decision evidence; it must not turn a low-privilege user into an ambient service
administrator. Owner APIs validate every write and expected revision server-side.
Producer credentials do not grant EP operator/policy-management rights.

The logical interfaces needed are catalogue, definition/assignment/effective reads,
proposal validation, impact, decision submission, controlled activation/revocation
and history. This document does not assert endpoint names or API availability.
When implemented, use versioned authenticated contracts and qualified client/server
parity; do not shell out to Forge CLI, EP tools or a peer's database.

Render owner/capability-unavailable and stale-cache states with provenance and age.
Cached projections can explain history but cannot authorize writes. Never silently
switch to another discovered instance or direct SQL when a peer is unavailable.
Return no provider secrets to clients; expose redacted references where authorized.

## Localization, accessibility and run evidence

Use existing role-aware project contexts, modal/accessibility conventions and
en/nl/de/fr/es. Keep the relationship to the normal live/historical run view:
clicking the quality step should show the same current/profile/repair evidence
as the receipt, including short actual correction descriptions and unresolved
findings. Non-blocking findings stay visible without making delivery look failed.

Impact/approval dialogs distinguish proposal from activation and show destructive
or security-impacting effects explicitly. Never present missing evidence as a
successful preview or a unavailable owner as a new default profile.

## Roadmap/DAG and qualification

| ID | Owning Workspace deliverable | Dependencies | Status |
| --- | --- | --- | --- |
| POL-0 | Adopt common classifications/authority and this UX target | none | Documentation proposal in this increment |
| POL-WC | Versioned effective-policy/proposal/decision consumer contract and offline fixtures | POL-0 | PLANNED, parallel/non-blocking |
| POL-W | Real Policy & Automation UI and authenticated owner adapters | POL-WC and cross-product POL-Q | PLANNED, POST_AUTONOMY |

Contract-first POL-WC requires no running UI. POL-W additionally depends on the
qualified owner policy binding/evaluation/receipt semantics (POL-Q); it does not
create that authority. Native Forge release operations (VR-F/VR-Q) and installer
composition (POL-P) remain separate owning lanes. The cross-product documentary
DAG is `pcvantol/forge:docs/roadmap/policy-governance-v1.json`.

Future acceptance: unauthorized/cross-project edits denied server-side; stale
revision conflicts; no grant or budget reset; no lower-scope weakening; policy
self-approval denied; partial owner activation visible; unavailable/stale owner
cannot authorize; historical snapshot parity; exact receipt/review/repair display;
localization/accessibility; no credential leakage or new workflow engine.

The root [roadmap](../ROADMAP.md) is the Workspace scheduling authority. Existing
#14 only versions this repository and remains a separate proposal requiring
reconciliation with native Forge release management; it does not implement this
policy UI. This documentation grants no permission to merge, publish or deploy.
