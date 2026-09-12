# Increment-size policy and explanations — Workspace V1

**Increment:** `ADAPTIVE_ACTION_SIZING_V1`. **Status:** PLANNED, NO_BUMP.
Owner: Workspace interaction; Forge owns planning policy; EP owns execution fit.
[Local DAG](adaptive-action-sizing-v1.json) refines [Policy & Automation](POLICY_AND_AUTOMATION.md),
not another control plane or a feature moved to the Forge admin Console.
Source: Workspace `f7c64ea2ca2916bdbe60933bcc30ce405f9dfb3b` (2026-09-12).

## User experience

Offer a labelled three-position **Increment size** preference in project policy:
Smaller increments / Balanced, adaptive / Larger coherent increments. Map exactly
to SMALLER / BALANCED_ADAPTIVE / LARGER_COHERENT. Balanced is the proposed default
for a NEW qualified policy, not an automatic migration of existing configurations.
All presets adapt within the same safety floors. Avoid minimal/strong/heavy labels
that confuse decomposition with reasoning effort or risk acceptance.

Model/provider/effort, risk obligations, deadlines and budget are separate controls
or read-only owner facts. Never hide multiple changes behind the size slider.
Show effective preset, source/inherited values, pinned revision and what may be
overridden for a Mission. Unsupported owner capability is disabled with a reason;
no UI-only option that claims working sizing. Users need not choose token counts
or micromanage every Action. Advanced supported thresholds show units, ranges,
estimate/enforcement provenance and actual implications, not invented magic values.

Draft change -> authorized owner validation -> impact preview -> required decision
-> versioned activation -> authoritative readback. Use expected revision and
idempotency; reject stale writes. Changes affect future Missions by default.
Changing sizing of future unmaterialized Actions in an active Mission requires an
explicit qualified policy transition preserving scope, history and all consumption.
Never edit a dispatched Action. A mere preference change within existing valid
permission should not introduce repeated Business/Architecture approvals.

## Why this Action, why this size?

Within current Mission/Action details show intended coherent result, contribution
to criteria, repository/effect boundaries, included and deferred work, required
profile references, limiting phase, sizing reasons and source freshness. Display
estimated context/review/cycle burden with uncertainty separately from actual
per-phase timing/usage/repairs. Fit, admission and execution are different badges.
Unknown is not zero or unlimited. A high-effort model does not promise a larger
Action and an unreported vendor identity is not the requested model.

An example explanation may say: export plus validation/tests are one coherent
increment; import is deferred because it has separate recovery criteria; review
complexity is limiting, not the context window. This is illustrative, not an
assigned plan or a live performance claim. Use plain explanations backed by
bounded stored rationale, not private reasoning or complete raw prompts.

Business/Architect/UX conversations can propose meaningful Mission boundaries or
refinement. A mega-Mission with independent outcomes can be refined into separate
Missions before approval, not silently fragmented to gain new authority. A formal
assessment/design increment may resolve uncertainty without permission to implement
its findings. Preserve read-only/docs/design effects through every size preset.

A proposed different profile/cost or unsplittable scope asks for only the real
required decision; it never forces API-token purchase or uses a paid fallback.
The project roadmap shows a rolling horizon, not hundreds of frozen Actions.
Changes after evidence explain splits/coalescing; preserve old materialized history.
If resource/credential/route failure is the cause, do not tell the user that the
Action was too large. Do not represent mock evaluation as proven throughput gain.

## Delivery and tests

| Node | Local predecessors | Delivery |
| --- | --- | --- |
| AS-W-POLICY | none | Accessible three-preset policy and owner readback |
| AS-W-Q | AS-W-POLICY | Action explanation, profile/estimate/actual views and qualification |

AS-W-POLICY consumes AS-F-POLICY; AS-W-Q consumes AS-F-FEEDBACK and the relevant
qualified owner API subsets. It does not gate Forge headless delivery. Consume
Forge/EP only via authenticated HTTP through Workspace Server; own CLI remains a
thin automation/management ingress. No peer subprocess, SQL, Inbox or IPC shortcut.

Use EP-aligned design system, en/nl/de/fr/es, two themes, mobile/desktop, keyboard
operable labelled choices, accessible help/focus and unchanged selection on refresh.
Apply shared AS-T06/07/10/14/15/16/17/18/20 with browser/API negative tests and
actual owner-service contracts. Refresh, sorting and opening details cause ZERO
provider calls, fit work, policy writes or Mission starts. An explicit fit/analysis
request is separate and authorized. Preserve current coverage >80% and applicable
Playwright/localization/security gates; documentary tests are not UI proof.
All implementation stays planned; no runtime, provider, Mission or budget changes.
