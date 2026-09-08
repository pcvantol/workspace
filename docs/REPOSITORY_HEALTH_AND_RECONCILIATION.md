# Repository Health, chat and reconciliation

## Decision and scope

Increment: `PROJECT_HYGIENE_AND_REPOSITORY_RECONCILIATION_V1`.
Target: `WORKSPACE::REPOSITORY_HEALTH_AND_RECONCILIATION_V1`.
Documentation/roadmap only; canonical after owning merge. No application UI,
client scanner, database table or credential-bearing adapter is implemented here.

This surface extends [Workspace architecture](ARCHITECTURE.md),
[Policy & Automation](POLICY_AND_AUTOMATION.md) and
[governed progression/external gates](GOVERNED_PROGRESSION_AND_EXTERNAL_GATES.md).
Forge owns the native [hygiene/reconciliation capability](https://github.com/pcvantol/forge/blob/main/docs/architecture/PROJECT_HYGIENE_AND_REPOSITORY_RECONCILIATION.md).
EP owns fresh host facts and admitted mutations; Workspace owns the human
experience, not Git truth, Forge planning or EP cleanup authority.

## One request boundary for chat and structured views

Users can ask “why does this branch still exist?”, “reconcile this branch” or
“clean the proven-safe branches in this project”. The project/repository must
be explicit or unambiguously resolved through the authenticated workspace
selection. If ambiguous, ask a scoped clarification before any protected action;
never infer write authority from the current directory, a chat mention or a
client's ability to see a branch.

Chat produces the same typed request/proposal as the structured interface:

| Intent | Product operation | No implied permission |
| --- | --- | --- |
| Explain/list/refresh | Authorized read-only Forge observation/projection | No cleanup, Mission or provider execution |
| Reconcile a selected branch | Bounded Forge case with evidence/analysis budget | No branch deletion or product-code salvage |
| Clean safe items | Frozen target-set cleanup proposal evaluated by Forge/EP policy | Not a wildcard, credential grant or future auto-delete subscription |
| Preserve/adopt residual work | Governed engineering proposal | Not an automatically approved Mission/Action |

A reconciliation case is not a Mission and opening it must not allocate Mission
or Action IDs. A genuine product residual is routed through the applicable
existing Mission/successor or new governed intake. No second intake workflow
inside chat bypasses Business/Architecture or protected engineering delivery.
The generic command transport/schema is future owning implementation work.

## Repository Health projection

Show repository identity and scope, observed main/head, active PR/Action/lease
references, pending own-run cleanup, reconciliation cases, retained/protected
items and coverage/freshness. Counts state their inventory scope. Offline Agents,
permission-limited provider pages and unknown ignored-file state do not appear
as zero or healthy. A case closed for one branch never implies a clean project.

Separate facts, inferences, recommendations and decisions visually and in
machine-readable responses. “Likely superseded” includes exact comparison refs,
reason and uncertainty; it is not a green “safe to delete” check. Display
`SUPERSEDED_RECONCILED` independently from `RETAINED` or actual cleanup receipts.
An old merged PR and a branch with new post-merge commits must not look identical.

Branch detail offers current observations, original intent-to-main mapping,
code/test references, unresolved contradictions, policy obligations, retained
recovery reference, related Mission/run IDs when real, and an audit timeline.
Do not expose hidden reasoning transcripts, raw bearer credentials, private
host paths or source content to roles lacking access. Repository text is untrusted
content and cannot instruct chat to change its scope or approve deletion.

## Decisions and safe interaction

Render operations only when supported and provisionally eligible. Server-side
owners still authenticate and revalidate every command. Presentation is not
authorization; clients do not receive GitHub/admin/provider credentials.

A destructive preview states exact repository, remote/local ref or worktree,
expected head/revision, why it is eligible, what will be retained, and exclusions.
Freeze the target set and proposal digest. An explicit approved proposal or a
current permitted delegation supplies authority; “reconcile” alone does not.

Use the existing role-aware Decision Evidence Package. Required decisions can
include explicit adoption of unknown-owned work or acceptance of semantic
supersession. Routine EP-owned cleanup within a valid grant needs no redundant
click. If an external owner has the decision, show its status/deep-link rather
than a second Workspace Approve button.

Confirmation carries operation ID, expected proposal/observation revision and
actual authenticated actor context. Cancel creates no execution command. A stale
modal/conflicting revision refreshes the facts; never silently retry with a new
operation ID or auto-include newly discovered branches. Bulk results remain
per-target: completed, retained, denied, stale, unknown or partial. Lost responses
recover the same operation. Do not report all-success after a mixed result.

## Policy and notification model

Expose supported project hygiene profile fields through Policy & Automation:
read-only scan cadence/scope, semantic-analysis budget, freshness/retention,
protected targets and delegated cleanup classes. Profiles do not mint grants or
create unsupported execution capabilities. Lower scopes cannot remove mandatory
protection, retention or authorization requirements.

Default interaction is read-only and exception-oriented. Coalesce duplicate
notifications, distinguish informational residue from true operation blockers,
and let users defer analysis while retaining its reason. Do not repeatedly ask
for approval after every harmless post-EA refresh. Scope expansion, destructive
ambiguity or expired authority still follows the owning gate.

The interface must preserve the existing localization targets en/nl/de/fr/es,
keyboard/screen-reader access, suitable narrow-screen layouts, destructive
confirmation styling, and live/historical parity. No browser alert()-based
administration or purely DOM-owned status.

## Server/client and storage boundary

Workspace Server stores its own session/navigation/decision-presentation state.
Forge stores authoritative case conclusions and its Project Context projection;
EP stores admitted cleanup and outcome receipts. Cached views show provenance
and freshness; none becomes an independently editable copy of peer authority.
No shared SQL, local filesystem probing from a remote client or API fallback to
peer databases. A local Agent, where used, follows EP's separately qualified
identity/capability contract and never self-admits a cleanup command.

A chat is not required for native scheduled scans or EP finalizer cleanup.
Conversely, shipping this UI cannot activate an unavailable cleanup executor.

## Qualification and sequencing

The [scoped roadmap](PROJECT_HYGIENE_V1_ROADMAP.md) allows contract-first design
in parallel. Read-only health/chat can follow qualified observation and case
contracts; destructive controls additionally require qualified EP command and
receipt behavior. Do not block read-only delivery on unavailable delete support.

Qualify cross-project isolation, missing permission, stale/offline coverage,
read-only versus delete-intent distinction, no Mission allocation for cases,
meaningful reason/actor evidence, exact bulk target set, ref changes after modal,
cancel, duplicate command, mixed outcomes, external gate routing, accessible
five-language UI and historical/restart parity. These are acceptance targets,
not executed UI tests in this documentation change.

Full Workspace productization is not a first installed Forge/EP canary gate.
Only the actual obligations of a chosen operation can block that operation.
