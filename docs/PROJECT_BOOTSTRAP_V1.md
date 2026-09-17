# Project bootstrap V1 — Workspace experience and contracts

**Increment:** `PROJECT_BOOTSTRAP_AND_ARTIFACT_MANIFEST_V1`. **Owner:** Workspace.
**Status:** canonical target design after protected merge; implementation/installed UI qualification **PLANNED**. **NO_BUMP.**

This refines [repository onboarding](REPOSITORY_ONBOARDING.md) and the onboarding/control-plane lane in the [Workspace roadmap](../ROADMAP.md). See [scoped roadmap](PROJECT_BOOTSTRAP_V1_ROADMAP.md) and [documentary DAG](PROJECT_BOOTSTRAP_V1_DAG.json). Forge owns the detailed portable artifact manifest at `pcvantol/forge:docs/architecture/PROJECT_BOOTSTRAP_AND_ARTIFACT_MANIFEST_V1.md`; EP owns execution/provisioning at `pcvantol/engineering-platform:docs/engineering/PROJECT_BOOTSTRAP_EXECUTION_V1.md`. The shared PB-01..PB-40 catalogue resides with Forge. Workspace does not create a competing artifact schema or bootstrap state machine.

Source basis on 2026-09-17: Workspace `92da171c97dc3f67cc844125b08cf8a2a0e56a1e`, Forge `eee7f8dadd5b2df9e836627b43de4928a46eeb35`, EP `d7fe0af363fb36f1f819fedc7a63919e01b88e66`. Existing Forge storage-init is not a project scaffolder. Existing EP Genesis and B8R attachment are reusable foundations, not proof that this complete UI/API journey exists. No runtime, grant, installation or Mission is changed by this design.

## 1. Five distinct journeys, not a single ambiguous Init button

| User choice | What the user selects | Owning outcome and important restriction |
| --- | --- | --- |
| New local Genesis project | Product purpose and an eligible host's missing/empty local target, or unborn local Git | Common project/engineering foundation with local Git evidence; no remote contact/publication |
| Adopt local Genesis work | Existing local target and explicit content/identity adoption | Preserve existing work/history; unknown ownership or dirty content must be resolved before mutation |
| New Managed project | Repository provider, owner/namespace, name and explicit visibility | Qualified remote birth and governance, not merely a successful create API response |
| Adopt Managed repository | Existing remote identity, project mapping and intended checkout attachment | Drift preview and protected adoption; never treat a README-only repository as empty |
| Promote Genesis to Managed | Existing local project plus explicit destination/publication decision | Same IDs/history with remote governance and attachment proof; no silent mode flag change |

A qualification-only purpose is separately identified with explicit retention/deletion authority. It is not the default project type and is not automatically disposable. Mode, Governance Profile, technology template and autonomy/release settings are separate fields. No automatic fallback between Genesis and Managed when a remote/tool/credential is unavailable.

## 2. Application boundary and supported capabilities

Workspace Client talks to Workspace Server over authenticated HTTP. Workspace Server talks to Forge for product planning/governance and directly to EP for EP-owned provisioning/attachment/effects as applicable to the accepted workflow. It never shells to either peer, reads their databases, writes a checkout or implements its own GitHub executor. Browser clients receive no reusable peer or repository-host credentials.

At session start query the versioned capability inventory and exact peer instance/project scope. A button is offered only when its owning operation is supported and authorized; unavailable capability is shown explicitly, not a private endpoint guess. Thin CLI and HTTP target equivalent owning services, but local-only administration is not automatically remotely exposed. Browser init of a new project is distinct from server storage/installation initialization.

Workspace persists only its own draft/conversation/preferences and references to owning plans, decisions and operation results. Source truth for portable identity remains EP's committed `.engineering-platform/repository.json`; display names do not allocate that identity. Forge's artifact mapping references it. Reservations before the first commit are visibly provisional, not registered canonical topology. Draft creation or viewing a sample doesn't allocate a Mission.

## 3. Guided flow and exact review model

### Step A — Describe the product

Collect purpose, intended users, desired outcome, non-goals, constraints, existing assets and important unknowns. Offer optional Solution Templates as advisory starting points, not already-approved Missions or implementation. Separate user statements from inferred suggestions and approved decisions. Do not require the user to fabricate an entire finished architecture just to save a draft.

Choose the authority repository relationship and any child repository mappings. Reuse matching existing identity only after owning verification. Creating a fork/new product is an explicit separate choice, not automatic adoption of copied declarations. Show that a child repo receives its own contract/declaration while referencing authority-owned Vision/roadmap.

### Step B — Choose Genesis or Managed and target

For Genesis, explain local-only effects and identify the actual eligible EP host/placement. A browser's current directory or arbitrary client upload path is not the host target. Use an owning scoped inventory/file-selection capability; restrict returned path detail to the authorized operator and keep it out of portable repo artifacts. Distinguish absent, empty, unborn, existing, dirty, nested or occupied targets. Any existing remote is disclosed but not contacted or modified by a Genesis operation.

For Managed, require explicit provider account/namespace/name/visibility; no implicit public repository. Validate actual resource identity and distinguish missing/unborn from existing history. Show denied scopes or unsupported mandatory provider features before submitting effects. Do not expose a generic admin credential or ask users to paste bearer values into project forms.

### Step C — Profiles and contract

Show installed baseline version/hash/provenance, supported stack options, artifact mapping, effective validation/assurance and repo-governance profile. Describe inherited versus project-specific policy and exceptions. Optional license choice is explicit; no default legal/publication decision. Genesis still has local engineering safeguards; remote controls read NOT_APPLICABLE_GENESIS, not green PASS. Unsupported required local checks remain blockers.

The default project behaviour is governed Mission selection. The three project-autonomy modes from the existing live-roadmap design remain explicit: per-Mission release; execute a bounded approved workset; delegated full autonomy within a separately authorized boundary. Recommended priority is not committed priority. Selecting a template, importing a repo or choosing auto-when-eligible doesn't grant new approvals. Bootstrap never enables autonomous reviewer-driven follow-up work.

### Step D — Review a frozen plan

Render a before/after artifact tree and per-file diff, plus a separate remote-settings diff. Use Forge's canonical manifest as the sole file selection source. Show required/common versus conditional assets, existing equivalent mapped paths, before hashes/ABSENT, output digests, affected permissions/refs, prospective ID mapping and unresolved decisions. Typical common documents are README/BOOTSTRAP/AGENTS, product Vision, architecture, roadmap/DAG and portable engineering/baseline contracts; the detail view derives the actual paths from the versioned plan rather than hardcoding a second template list.

Surface whether an artifact is project-owned, immutable pinned baseline or source-bound projection. Existing differing documents aren't marked safe to overwrite merely because generated versions exist. Preserve unrelated dirty/staged/untracked work; let the owner resolve a blocked preparation instead of auto-stash/commit/delete. No raw secrets or unbounded file contents in previews.

Approvals bind the exact plan digest/revision and classified effect set. Route product direction to Business/Architecture and resource creation/publication to the actual provisioning authority. One user can hold multiple authorized roles, but the distinct decisions remain recorded. Do not turn local draft acceptance or chat affirmation into an owner receipt. Changing target, visibility, history refs, baseline, plan bytes or material policy invalidates incompatible approval and requires refreshed review.

### Step E — Submit and track

Submit the existing frozen operation with stable idempotency/correlation identity and expected revision. Disable duplicate UI submission as a convenience, not as the sole duplicate-effect protection. After reconnect/lost response, read the same owning operation; never start a second request with a new key to resolve uncertainty.

The activity view shows selected mode, reserved versus committed identity, plan version, actual stage/effects, receipts, authorizations, blockers and safe next actions. Physical mutation, repository-governance qualification, attachment availability and Forge project readiness are separate. ACCEPTED/HTTP 200 is not READY; technical completion is not Mission acceptance. Polling/events carry scoped cursor/snapshot and freshness; stale projections cannot enable mutation controls.

### Step F — Enter the project

After owning readback, show the exact canonical local/remote repository, materialized contract/baseline and verified readiness vector. Genesis shows local commit/reconciliation, not PR/remote-CI badges. Managed shows actual remote/governance/check evidence. Remaining product questions and advisory Candidates are visible. The next action is refine/select/approve a Mission via the existing separate lifecycle, not automatic feature execution.

## 4. Genesis-to-Managed promotion is an explicit wizard

Promotion begins from the existing Genesis project, not a new-product form. Display stable IDs, current local HEAD/refs, destination and expected remote state. Explain that publication can disclose all selected historical commits, not just the current file tree. Require scope-appropriate confirmation of visibility, licensing and sensitive-history findings before any push. Ignore rules do not prove old commits safe.

Show the proposed retained ancestry, new Managed CI/security/settings artifacts and resulting policy change separately. A diverged/unrelated existing remote is a conflict; no UI 'continue' may authorize implicit force push or squash of history. Required history rewrite or data disposal is a separately reviewed migration. Display actual owning quiescence/fence and current operation, not a local UI lock as proof that no writers exist.

Track remote transfer, real governance readback, attachment and Forge mode activation. Do not switch the project badge to Managed on request acceptance or first push. During uncertainty, disclose effects already observed and keep applicable editing/execution controls fenced. Cancel after a push is a cancellation request, not a claim the remote data has been undisclosed. Existing Genesis history remains available with original mode/qualification; no manufactured historic PRs or reset approvals.

Recovery offers read/reconcile or a separately authorized corrective plan from the owner service. It does not run local SQL, delete the remote or restart a second project. A safely reconciled incomplete promotion may leave the same project in Genesis with the partial remote effect recorded.

## 5. Error, security and accessibility contract

Provide meaningful empty/loading/unsupported/offline/denied/stale/conflict/partial/failed/cancel-pending states for every step. Preserve the user's draft and references when an owner is unavailable, but don't replace its state with optimistic local success. Explain who owns the blocker and which actions are currently authorized. Do not translate machine IDs/enums in exported machine data; translate human labels/explanations in en/nl/de/fr/es.

Use accessible labelled controls, keyboard review/approval, focus restoration after async updates, screen-reader announcements for meaningful stage changes and responsive desktop/mobile artifact diffs. Avoid colour-only status and default selections that conceal destructive/public effects. Long trees/diffs are bounded/paginated with visible completeness, stable snapshot and safe download. Tests include stale tab, double-click, filter/target change during response, expired session and cross-project access denial.

Document/export views use the owning operation's exact snapshot, mode and provenance. No endpoint, host placement, credential or confidential history is included merely because it is available to the server. Bootstrap telemetry is operation-scoped and separate from subsequent Mission usage. New findings become proposals; a security block cannot silently authorize a new remediation Mission.

## 6. Qualification and delivery boundary

Workspace PB-WQ tests the actual installed Client/Server and real HTTP boundaries to qualified owner slices, plus controlled denied/partial/replay fixtures. It does not claim installed Forge/EP capability from mocks alone. Qualify all five journeys, blueprint changes invalidating approvals, no secondary template/identity authority, history-safe promotion and all user-visible states on desktop/mobile/five locales. PB-33..PB-35 are UX-focused families; PB-22..PB-32 and PB-36..PB-40 provide cross-product guardrails.

The current update supplies design, scoped roadmap and documentary DAG only. No buttons, endpoints, database, permissions, policies, provider work, repository creation, runtime service, version or Mission 3 change is implemented. Workspace remains optional for headless Forge/EP bootstrap, and this programme is not added before the current inner-Mission canary.
