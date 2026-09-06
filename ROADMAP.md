# Workspace Roadmap

## Foundation

Completed: establish standalone repository identity and record the absence of prior implementation history.

## Bootstrap critical-path position

Workspace is **not** on the critical path for the first Forge → Engineering Platform → Forge autonomous-execution canary. Workspace remains the human/project control plane and projection surface; it is not planning or execution authority.

Current cross-product sequencing:

1. Engineering Platform completes P-NEUTRAL.
2. DJConnect receives/qualifies its committed B8R `.engineering-platform/repository.json`, attaches to installed CENTRAL EP and completes one real governed Engineering Action.
3. EP records `EP::STANDALONE_EP_VERIFIED`.
4. EP then proves one real bounded self-development Action against the Engineering Platform repository through CENTRAL, yielding `EP::SELF_HOSTED_ENGINEERING_VERIFIED`.
5. Forge is attached/dogfooded as a real EP-managed development repository before or during Forge execution integration.
6. Forge then integrates with the already-canonical EP P-TRANSPORT HTTP submission and run/result/evidence contracts and qualifies Forge-side reconciliation.
7. After the first Forge → EP → Forge loop is proven, Workspace joins the product critical path for installed control-plane/onboarding UX.

Workspace itself may also be attached to CENTRAL and receive a real EP-governed development Action as an additional dogfood proof. That is desirable but **non-blocking for first Forge autonomy**.

Broader EP Agent separation, generalized dispatch/multi-host scheduling and multi-repository parallel execution are follow-on productization work; Workspace must not treat them as prerequisites for the first standalone EP or Forge autonomy canary.

Project/repository identity follows B8R: the Canonical Project Authority Repository declares durable logical identity in `.engineering-platform/repository.json`. Workspace may project that identity and own mutable human-facing project state/display naming, but Workspace availability is not required for EP to attach a declared repository.

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
  -> immutable receipt/result/provenance
```

This proves EP can engineer Workspace; it does not grant Workspace execution authority and does not require Workspace to orchestrate the run itself.

`WORKSPACE_REAL_EP_DOGFOOD_PLANNED = TRUE`
`WORKSPACE_REAL_EP_DOGFOOD_BLOCKS_FIRST_FORGE_AUTONOMY = FALSE`

## Proposed repository onboarding and control plane

The first proposed Workspace control-plane capability is a bounded onboarding experience for logical projects and repositories. It would offer **Use existing repository**, **Create new repository**, **Genesis project**, and a **qualification-only repository** variant. All four are planned, not implemented. The canonical design remains in `docs/REPOSITORY_ONBOARDING.md` and must be reconciled with B8R before implementation.

Workspace presents and initiates permitted intent; Forge plans cross-project dependencies; EP CENTRAL accepts durable execution/lifecycle intent and remains execution authority. Host-local engineering remains EP-owned.

For a real admission-ready onboarding flow, consumer-facing producer qualification remains EP-owned. The current B8R project identity/attachment runtime is sufficient for direct EP dogfooding; richer onboarding/cutover UX remains a later Workspace capability.

The qualified `EP::LOCAL_CONSUMER_API_V1` remains a consumer/authentication base. Separately, P-TRANSPORT already provides canonical submission transports (HTTP, installed CLI and Server-owned File Inbox); Workspace does not own or duplicate those transports.

Multi-repository parallel mutating lanes are explicitly post-verification work. Serial real-project dogfood is sufficient for the bootstrap proofs.

## Next decisions

1. Let EP complete P-NEUTRAL and the DJConnect + EP self-development real-project proofs.
2. Let Forge complete its direct-EP dogfood and first Forge → EP → Forge loop.
3. Then decide whether repository onboarding is the first bounded Workspace product capability.
4. Reconcile `docs/REPOSITORY_ONBOARDING.md` with B8R before implementing onboarding.
5. Add Workspace direct-EP dogfood when useful; it does not block first Forge autonomy.
6. Design the installed EP adapter as a separate Workspace increment after producer contracts are qualified.

No item authorizes Workspace to implement EP execution, Forge planning, provider execution or generic governance.

## Cross-product dependency register

| Workspace capability | Cross-product relationship | Earliest dependency | Required qualification |
| --- | --- | --- | --- |
| Direct EP development dogfood | Prove EP can engineer Workspace without giving Workspace execution authority. | Installed EP standalone/self-development producer available. | Real bounded Action, validation, finalization, immutable EP evidence. Non-blocking for first Forge autonomy. |
| Onboarding/control plane | Present project topology and permitted lifecycle intent without becoming attachment/execution authority. | Qualified EP consumer-facing attachment/admission contract; Forge bootstrap only where managed composition is needed. | Workspace UX/accessibility/no-secondary-authority proof plus producer qualification. |
| Quality governance surface | Present Effective DoR/DoD/Human Gates and governed Quality Learning proposals. | Forge evidence/quality contracts plus Workspace onboarding. | Attribution, freshness/degraded-state, accessibility and no-secondary-authority proof. |
| Knowledge governance surface | Present evidence-linked Knowledge lifecycle status and permitted intents. | KB export/read contracts. | Post-V1 lineage/redaction/accessibility proof. |

The Forge labels are dependency references only. This roadmap remains canonical authority for whether, when and how Workspace develops its own surfaces.
