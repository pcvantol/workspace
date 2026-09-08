# Governed progression and external Human Gates

Increment: `GOVERNED_PROGRESSION_AND_DELIVERY_AUTHORITY_V1`.
Documentation target only; canonical on owning main after merge. No application
UI, policy API, external adapter, grant or deployment is implemented here.
This elaborates [Policy & Automation](POLICY_AND_AUTOMATION.md) and
[role-aware governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md).
Shared semantics live in
`pcvantol/forge:docs/architecture/GOVERNED_PROGRESSION_AND_DELIVERY_AUTHORITY.md`.
See [the scoped roadmap](GOVERNED_PROGRESSION_V1_ROADMAP.md).

## One human control plane, not one human authority

Workspace presents the right decision to the right role with canonical evidence.
Forge owns Mission/progression requirements and domain decision validation;
EP owns engineering execution and assurance; the declared CD/target owner owns
external approval/deployment/publication. Workspace records the human interaction
and relays permitted commands to the actual owner. It cannot create domain
approval merely by displaying an enabled button or editing its own projection.

The three visible families are distinct:

| Family | Examples | Decision presentation |
| --- | --- | --- |
| Pre-Mission lifecycle | Business approval, Architecture approval | Separate auditable decisions; Solo can assign the same person but cannot erase either approval |
| Engineering review cadence | After Action/Intent/Capability, at Mission end | Forge-owned requirement, exact subject/evidence, roles and continuation scope |
| Delivery/promotion | Publish/install/deploy, store submission, PROD promotion | Resolve declared authority first; external gates stay external |

Mission Intake is admission of an already approved Mission, not Candidate
creation. Automated EP quality/security reviews and technical checks are not
human review cadence or external deployment approvals.

## Project and Mission settings

In Policy & Automation expose project defaults, mandatory minimum obligations,
permitted Mission overrides, supported cadence/scope and effective interpretation.
A prototype can run continuously until its required final review; a production
Mission can require human review after every Action before another starts.
The same organization can use both profiles. A profile is not an identity,
authorization grant or proof of implemented runtime support.

At Mission selection show: inherited rule, proposed override, allowed range,
reason, required decision roles, mandatory exceptional gates and effective result.
A more permissive Mission override requires an explicitly allowed higher-scope
rule and authorized actor. Unsupported values are unavailable, not UI-only
settings. Mission text cannot disable security, EP assurance or external PROD
requirements. Review cadence and Mission-end acceptance are separate controls.

The UI proposes a versioned assignment/change with expected revision and impact.
Forge's owning policy service validates/activates it; Workspace does not write
Forge/EP SQL or bypass repository-owned policy. In-flight changes require an
explicit controlled transition; history, consumed budget and pending decisions
are not silently rewritten.

## Decision inbox and review fence

Show the exact boundary, blocking scope, reviewed Action/evidence, policy source,
required role, expiry/freshness and allowed outcomes: approve/reject/amend/defer.
A confirmed command binds requirement/subject revision and decision identity.
Stale commands must be rejected by the owner, not silently applied to newer work.
After an Action, evidence can be complete while Mission progression waits for
review. Do not portray this as a failed EP run or unfinished implementation.

After approval, the owning service returns accepted decision/progression evidence;
only then may the display show the fence released. A UI click or optimistic local
state is not permission for successor dispatch. Reopen/restart preserves the same
pending decision. Review scope is explicit; a Mission-scoped fence need not halt
unrelated projects, and it cannot cancel already running EP/CD work.

Mission engineering outcome and human end-acceptance must both be visible where
required. Deferring acceptance does not erase evidence-proven delivery; a required
unresolved acceptance must not be shown as unconditional Mission completion.

## Environment-aware delivery without duplicating CD approvals

Display stable target identity and environment class TST/ACC/PROD/custom,
artifact/source/version, requested operation and separate trigger, approval and
delivery owners. Labels alone are not trust. A PROD target cannot be renamed
ACC in the UI to bypass requirements. Store upload, review submission and actual
public release are different stages and evidence facts.

Example target policy: TST/ACC automatically progress; PROD requires the existing
organization/CD production approval. Another project may require additional
non-production gates. These are illustrative profiles, not new active settings.

When Forge maps a requirement to an existing external gate, render for example:

```text
Production deployment
Owner: existing project CD / production approval
State: waiting for external decision
Artifact / target: exact qualified references
Forge progression: waiting for authoritative delivery evidence
Action: open trusted delivery/approval details
```

Do NOT show a Workspace Approve button for the same external gate. A mapping is
not an approval; distinguish pending, approved, rejected, deferred, expired,
superseded, unavailable and actually deployed/verified. A green trigger job is
not an external approval or deployment result. Display source and freshness;
unavailable readback never turns into cached permission.

Two approvals are allowed for distinct obligations explicitly required by policy,
for example Workspace-presented business release approval plus external SRE
production approval. Preserve separate requirement/authority identities. Neither
duplicate one obligation nor collapse real separation of duties by matching labels.

`OBSERVE_ONLY` is the safe default. `REQUEST_AND_WAIT` may expose a permitted
request action when the owning service reports actual scoped trigger capability.
Trigger permission does not confer approval/deployment permission. An external
pipeline can be requested before its own approval if it safely waits at that
gate; Workspace must not demand a circular prerequisite or enable the protected
side effect itself. No production/store credentials are placed in a client.

Use verified deep-links without secrets or arbitrary untrusted destinations.
Workspace is not a privileged proxy that approves on behalf of whoever clicks.
External cancellation/rollback remains a separate authorized owner operation;
a Forge pause or local rejection does not stop an already executing pipeline.

## Consumer contracts and qualification

Consume owner-provided requirement/authority bindings, effective policy, decision
status and verified result references through authenticated scoped APIs. Never
reconstruct approval from Console HTML, logs, a pipeline name or a model summary.
Changed artifact/target/pipeline/subject revisions invalidate the displayed action
until the owning service requalifies. Idempotent decisions/commands and duplicate
or out-of-order external observations must not create repeated approvals.

Required later tests: project/Mission override bounds; prototype versus after-EA
cadence; correct role/subject; stale decision; restart preserves review; wrong
project/target; no external Approve control; separate business/SRE decisions;
request permission distinct from approve; actual owner result before UI success;
changed artifact invalidates decision; denied/unavailable producer; localized
and accessible local/external gate views; no credential/SQL/authority leakage.
All UI/consumer implementation remains PLANNED. Full Workspace UI is not a new
prerequisite for the first serial Forge Mission canary.
