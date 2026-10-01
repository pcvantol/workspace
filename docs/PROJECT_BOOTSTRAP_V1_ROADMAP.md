# Project bootstrap V1 — Workspace owning roadmap

**Owner:** Workspace. **Status:** all runtime/qualification nodes PLANNED. **NO_BUMP.**
This is the scoped implementation decomposition of onboarding/control plane in [ROADMAP.md](../ROADMAP.md), refining [repository onboarding](REPOSITORY_ONBOARDING.md), not a second planner or EP console. Read [the complete design](PROJECT_BOOTSTRAP_V1.md) and [non-executable DAG](PROJECT_BOOTSTRAP_V1_DAG.json).

| Node | Depends on | Deliverable / closure |
| --- | --- | --- |
| PB-W0 | none | Five-journey UX/intent contract, identity/reservation and owner/capability mapping |
| PB-W1 | PB-W0; Forge PB-F0 and EP PB-E0 contracts | Workspace Server's typed authorized HTTP projections/intents and safe draft storage; no peer CLI/SQL |
| PB-W2 | PB-W1; Forge PB-F2/PB-F7 and EP PB-E1 | Genesis/Managed create/adopt wizard with exact artifact/settings diff and role-bound plan decisions |
| PB-W3 | PB-W1; Forge PB-F4/PB-F5/PB-F7 and EP PB-E5 | Mode-correct progress/readiness, partial effects, recovery/readback and source-bound exports |
| PB-W4 | PB-W2, PB-W3; Forge PB-F6 and EP PB-E4 | History/publication-aware Genesis-to-Managed promotion, fenced activation and recovery UX |
| PB-WQ | PB-W2, PB-W3, PB-W4; qualified Forge PB-FQ and EP PB-EQ | Installed HTTP integration for all five journeys, desktop/mobile, five locales, accessibility and negative authority cases |

PB-W0 now has a versioned [Workspace intent/capability contract](PROJECT_BOOTSTRAP_W0_CONTRACT_V1.md)
and offline negative projection fixtures. This defines the five journeys and
owner boundaries but supplies no producer binding, endpoint, UI, provisioning
or installed qualification. PB-W1 and all later runtime nodes remain PLANNED.

PB-W0/W1 can advance contract-first without runtime services being complete; delivered user actions remain gated by actual compatible owner capabilities. Workspace qualification consumes peer evidence but is not a prerequisite of Forge PB-FQ or EP PB-EQ. The documentary DAG allocates Workspace work only; owner roadmaps decide peer implementation status and order.

Companions:
- Forge `docs/roadmap/PROJECT_BOOTSTRAP_V1.md` and `docs/roadmap/project-bootstrap-v1.json`.
- EP `docs/development/PROJECT_BOOTSTRAP_V1_ROADMAP.md` and `docs/development/PROJECT_BOOTSTRAP_V1_DAG.json`.
- Shared scenario catalogue: Forge `docs/architecture/PROJECT_BOOTSTRAP_QUALIFICATION_V1.md`, PB-01..PB-40.

All implementation is post-/parallel-autonomy productization as appropriate; no new edge blocks Mission 3. Design completion does not close FWV1-G003/G013 implementation or imply an installed onboarding UI. Existing policy/workset/priority authority remains unchanged.
