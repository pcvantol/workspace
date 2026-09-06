# Workspace Roadmap

## Foundation

Completed: establish standalone repository identity and record the absence of prior implementation history.

## Bootstrap critical-path position

Workspace is **not** on the critical path for the first Forge → Engineering Platform → Forge autonomous-execution canary. Workspace remains the human/project control plane and projection surface; it is not planning or execution authority.

Current cross-product sequencing:

1. Engineering Platform completes the current P-NEUTRAL closure and qualifies the smallest existing standalone execution path.
2. EP proves one governed installed execution and records `EP::STANDALONE_EP_VERIFIED`.
3. Forge integrates with the already-canonical EP submission/status/evidence contracts, including the P-TRANSPORT HTTP submission ingress, and qualifies Forge-side reconciliation.
4. Only after the first Forge → EP → Forge loop is proven does Workspace need to join the critical path for the installed control-plane/onboarding experience.

Broader EP Agent separation, generalized dispatch/multi-host scheduling and multi-repository parallel execution are follow-on productization work; Workspace must not treat them as prerequisites for the first standalone EP or Forge autonomy canary.

Project/repository identity follows the current EP B8R authority model: the Canonical Project Authority Repository declares durable logical identity in `.engineering-platform/repository.json`. Workspace may project that identity and own mutable human-facing project state/display naming, but Workspace availability is not required for EP to attach a declared repository. This supersedes the older assumption that Workspace must manufacture the logical EP project identity.

## Proposed repository onboarding and control plane

The first proposed Workspace control-plane capability is a bounded onboarding experience for logical projects and repositories. It would offer **Use existing repository**, **Create new repository**, **Genesis project**, and a **qualification-only repository** variant. All four are planned, not implemented. The canonical design, lifecycle, GitHub/approval considerations, portable declaration boundary, and authority split are in [Repository onboarding and qualification](docs/REPOSITORY_ONBOARDING.md).

Workspace presents and initiates permitted intent; Forge plans cross-project dependencies; EP CENTRAL accepts durable execution/lifecycle intent and remains execution authority. Host-local engineering remains EP-owned. Workspace does not become an execution authority.

For a real admission-ready onboarding flow, this increment has two explicit external capability dependencies, not ownership of EP or Forge work:

- `EP::PROJECT_ATTACHMENT_AND_ADMISSION_V1` — the EP-owned qualified consumer-facing attachment/admission contract. The current B8R project identity/attachment runtime is the underlying EP authority; consumer-facing cutover/qualification remains EP-owned.
- `Forge::L1_BOOTSTRAP_EVIDENCE_CONTRACT` — the Forge-owned managed-bootstrap composition for flows that create a project-owned contract. Identity-only onboarding may use fixtures before it is qualified; it may not claim the managed bootstrap flow complete before the Forge gate passes.

The qualified `EP::LOCAL_CONSUMER_API_V1` remains a prerequisite consumer/authentication base, but is not by itself evidence that Workspace onboarding is complete. Separately, P-TRANSPORT already provides canonical submission transports (HTTP, installed CLI and Server-owned File Inbox); Workspace does not own or duplicate those transports.

Multi-repository parallel mutating lanes are explicitly post-verification work, not a prerequisite for onboarding or the first Forge autonomy canary. They require separately qualified EP-managed leases, capacity, ordering and retained evidence.

## Next decisions

1. After the first Forge → EP → Forge execution loop is qualified, decide whether repository onboarding is the first bounded Workspace product capability, including user evidence and operator roles.
2. Reconcile `docs/REPOSITORY_ONBOARDING.md` with the B8R project-identity authority before implementing onboarding.
3. Establish the cross-product registration/declaration and GitHub-integration ownership/approval contracts without duplicating EP or Forge authority.
4. Select an implementation stack only in that capability decision.
5. Define Workspace-local validation and, when evidence exists, a Workspace-specific TDE observation profile.
6. Design the installed Engineering Platform adapter as a separate, non-runtime-coupled Workspace increment after its producer contracts are qualified.

No item authorizes Workspace to implement EP execution, Forge planning, provider execution or generic governance.

## Cross-product dependency register

Forge's roadmap may identify Workspace-owned capabilities as prerequisites for a Forge workflow, but it cannot sequence or authorize Workspace work. The following entries are Workspace's own planning placeholders; they become work only through a separately governed Workspace capability decision.

| Workspace capability | Cross-product relationship | Earliest dependency | Required qualification |
| --- | --- | --- | --- |
| Onboarding/control plane | Present project topology and permitted lifecycle intent without becoming attachment/execution authority. | Qualified EP consumer-facing attachment/admission contract; Forge L1 only for managed bootstrap. | Workspace UX/accessibility/no-secondary-authority proof plus producer qualification. |
| Quality governance surface | Present Effective DoR/DoD/Human Gates, repository-governance state and governed Quality Learning proposals. | `Forge::L0_ENGINEERING_CONTRACT_FOUNDATION`, `Forge::L1_BOOTSTRAP_EVIDENCE_CONTRACT` and Forge L2–L3 quality-learning evidence, plus the Workspace onboarding/control-plane contract. | Attribution, freshness/degraded-state, accessibility and no-secondary-authority proof. |
| Knowledge governance surface | Present evidence-linked Knowledge Observation/Candidate proposals and KB lifecycle status; initiate only permitted governed intents. | KB-owned explicit evidence-export and read-only consumption contracts; additive and post-V1. | Source lineage/redaction, unavailable-KB degradation, accessibility and no-direct-certification proof. |

The Forge L4/L7 labels are dependency references only. This roadmap is the canonical authority for whether, when and how Workspace develops either surface.
