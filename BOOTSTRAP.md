# Workspace Bootstrap

## Active owner priority — 6 October 2026, r81 plan revision 85

The owner selected the native **Missions & reviews** overview and bounded
decision inbox under the existing LANE_4 assignment in
[Forge #208](https://github.com/pcvantol/forge/issues/208#issuecomment-6012171755).
The [owning consumer boundary](docs/WORKSPACE_MISSION_REVIEW_INBOX_V1.md)
defines the local GP-WC/GP-W serial review subset, acceptance and exact Forge
producer dependency. Workspace presents authorized Mission/review facts and
transports one explicit decision; Forge remains the review authority. The
existing Forge `WORKSPACE_READ` grant cannot access progression, and no
qualified review producer binding has been delivered. Preserve that gap as an
open dependency while implementing independent Workspace source and tests.
Archive/restore in 2.8.5 and its receipt below remain delivered history.

## Delivered owner priority — 5 October 2026, r81 plan revision 84

The owner selected reversible conversation archive/restore under the same
LANE_4 assignment in [Forge #208](https://github.com/pcvantol/forge/issues/208#issuecomment-6001515742).
Product 2.8.5 adds Workspace-owned archive state to the existing private draft
record, with Active/Archived/All filtering, explicit restore of the same ID,
revision and operation-ID guards, migration of existing records to active, and
safe save/discard/cancel handling for unsaved text. Archive/filter/reconnect
never invokes a provider or changes Forge/Mission state. Delivery requires the
normal protected merge, independent exact-head review, strict per-file coverage,
installed Server/native HTTP readback and real packaged archive/restore clicks.
Signing, Keychain successor, two-Mac trust and release remain separate L1-gated
work. Revision 83 below is delivered history.

## Delivered owner priority — 5 October 2026, r81 plan revision 83

Under the same LANE_4 assignment, the owner selected a native conversation-list
continuation in [Forge #208](https://github.com/pcvantol/forge/issues/208#issuecomment-5989057256).
Product 2.8.4 combines existing local text search with an All/Business/Architect/UX
filter and deterministic title/last-changed sorting. The selected conversation
and unsaved editor text must survive list changes, with explicit empty, no-match,
access, offline and stale states in five languages. This is a Workspace-only
GUI/source milestone over the existing authenticated draft route. Qualify the
actual packaged create/rename clicks separately from Swift state and HTTP tests;
record any native UI attachment limitation honestly. Protected merge, exact-main
installed Server/native ad-hoc readback and independent review are its delivery
gates. Signing, Keychain successor, two-Mac trust and release remain separate
L1-gated work. The previous 2.8.3 milestone below is delivered history.

## Active owner priority — 4 October 2026, r81 plan revision 82

The owner selected a Workspace-owned Business/Architect conversation and native
GUI subset under the **same** `L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002`
assignment ([#208 directive](https://github.com/pcvantol/forge/issues/208#issuecomment-5983751078)).
Implement own project/actor-scoped navigation, titles, advice-mode choice and
unsent drafts through authenticated Workspace Server HTTP, with local offline
editor preservation and honest unavailable Forge state. This source milestone
uses product version 2.8.3. Full Forge advice, canonical sessions, proposals,
apply and Mission handoff remain unqualified. The milestone's delivery boundary
is protected Workspace main plus an isolated installed Server wheel and native
ad-hoc app readback. Signing, live Keychain successor, two-Mac trust and public
release remain separate r81 gates. See [the narrow contract](docs/WORKSPACE_CONVERSATION_DRAFT_HTTP_V1.md)
and [owning plan](docs/ROLE_AWARE_CONVERSATIONS_V1_ROADMAP.md).

## Active owner priority — 2 October 2026

LANE_4 #208 r81 selects `L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002` as one
vertical product delivery. The first gate is Workspace-owned Python 3.14.x
only, including package metadata and validation/build/observe/release jobs.
The next visible result is a Finder-launched, locally rendered macOS
`Workspace.app` showing real HTTP responses from a separately installed
Workspace Server. The app needs no Python, local Server, Server data root or
checkout on the client Mac. The installed local Server/browser proof below is
delivered groundwork, not a native or remote acceptance pass.

Use the existing [backlog](BACKLOG.md), [roadmap](ROADMAP.md),
[HTTP DAG](docs/WORKSPACE_HTTP_API_V1_DAG.json) and
[distribution DAG](docs/WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json) for the
selected sequence and open gates. Do not reopen the terminal r80/#115. Preserve
the installer and peer boundaries and keep Workspace outside the current first
installer release DoD.

## Active lane and selected scope — 1 October 2026

Workspace now has its own LANE_4 / ARCHITECT_4 under the owner's four-product
lane decision. Read [the bounded first slice](docs/WORKSPACE_LANE_4_START_V1.md),
[the updated owning backlog](BACKLOG.md) and
[the LANE_4 register](https://github.com/pcvantol/forge/issues/208).
The portfolio transition is proposed in
[Forge #209](https://github.com/pcvantol/forge/pull/209); use its protected
canonical four-lane plan and all four current registers before effects.

At that historical checkpoint only `L4-WORKSPACE-SERVER-READONLY-V1-20261001` was selected: own Server
identity/state, authenticated HTTP, thin CLI, minimal read-only browser surface
and installed-wheel proof. Its owning HTTP/distribution DAGs retain every
existing hard dependency and unqualified implementation status. This selection
supersedes the historical parking below only for this bounded scope; unrelated
families remain parked or unselected. The entry document itself claimed no
implementation or Work-session start; the later same-assignment source and
pickup evidence are recorded in [BACKLOG.md](BACKLOG.md) and #208. Verify local
writers and resources before any further implementation effect.

LANE_1 retains the existing installer, LANE_2 retains EP and its active r30,
and LANE_3 owns Forge. This Workspace slice neither takes their source/host
holds nor adds Workspace to the current first-installer release requirements.

## New-project bootstrap and promotion design

Read [Project bootstrap V1](docs/PROJECT_BOOTSTRAP_V1.md), the reconciled
[repository onboarding contract](docs/REPOSITORY_ONBOARDING.md),
[scoped roadmap](docs/PROJECT_BOOTSTRAP_V1_ROADMAP.md) and
[documentary DAG](docs/PROJECT_BOOTSTRAP_V1_DAG.json) for both Genesis and
Managed project creation/adoption, plus explicit history-preserving promotion.
The design consumes Forge's exact artifact manifest and EP's qualified
operation/readback contracts through HTTP. All PB-W runtime nodes remain
PLANNED. This does not implement a UI, create a project/Mission, activate
permissions, change package versions or add a Mission-3 prerequisite.

## Historical pickup checkpoint — consolidation and parking, 10 September 2026

Read the [owning parking record](docs/CONSOLIDATION_PARKING_2026_09_10.md) and
[documentary dependency DAG](docs/CONSOLIDATION_PARKING_2026_09_10_DAG.json) before selecting work.
Product implementation was PARKED at that checkpoint; old handoff next-increment
wording does not authorize resumption. The selected 1 October scope above is
its explicit bounded exception, not a blanket removal of parking. The original
Forge serial E2E remains a future integration goal, not a demand to finish every
installer/UI/optimization lane.
The consolidation record reflects completed physical cleanup: all eight
auxiliary worktrees/branches were removed, leaving one local `main` worktree,
no local feature branches and no unpreserved WIP at the pre-documentation
baseline. This is historical evidence, not a fresh local inventory. Workspace
remains `NOT_ON_FIRST_FORGE_E2E_CRITICAL_PATH`.
Existing contracts and validation/protection rules below remain intact.

## Repository identity

Workspace is the first-class repository `pcvantol/workspace`. It is not a
Forge subcomponent. Its provenance and current product maturity are recorded
in [WORKSPACE_PROVENANCE.md](WORKSPACE_PROVENANCE.md) and
[README.md](README.md).

## Local development entrypoint

Before a bounded change:

1. read the committed generic projection in
   `docs/ai-development/GENERATED_PROJECTION.md`;
2. read `docs/ai-development/WORKSPACE_DEVELOPMENT_EXTENSION.md` and then
   [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
   [ROADMAP.md](ROADMAP.md), and [AGENTS.md](AGENTS.md);
3. identify the affected Workspace product boundary and validation needed; and
4. run `bash scripts/validate.sh` before review.

The committed projection is the generic authority and requires no sibling
checkout or network access. This local entrypoint does not authorize
Engineering Platform execution.
