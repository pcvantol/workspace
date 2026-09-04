# Workspace Roadmap

## Foundation

Completed: establish standalone repository identity and record the absence of
prior implementation history.

## Proposed repository onboarding and control plane

The first proposed Workspace control-plane capability is a bounded onboarding
experience for logical projects and repositories. It would offer **Use existing
repository**, **Create new repository**, **Genesis project**, and a
**qualification-only repository** variant. All four are planned, not
implemented. The canonical design, lifecycle, GitHub/approval considerations,
portable declaration boundary, and authority split are in
[Repository onboarding and qualification](docs/REPOSITORY_ONBOARDING.md).

Workspace would present and initiate permitted intent; Forge would plan
cross-project dependencies; EP CENTRAL would accept durable lifecycle intent
and remain execution authority; and EP Project Agents would perform the
host-local clone/checkout/worktree/toolchain/provider work. The future GitHub
integration and approval policy require their own bounded contracts.

Multi-repository parallel mutating lanes are explicitly post-verification work,
not a prerequisite for onboarding. They require standalone EP verification and
EP-managed leases, capacity, ordering, and retained qualification evidence.

## Next decisions

1. Decide whether repository onboarding is the first bounded Workspace product
   capability, including the relevant user evidence and operator roles.
2. Establish the cross-product registration, EP declaration-schema, and
   GitHub-integration ownership/approval contracts without implementing them
   in this foundation.
3. Select an implementation stack only in that capability decision.
4. Define Workspace-local validation and, when evidence exists, a
   Workspace-specific TDE observation profile.
5. Design the future installed Engineering Platform adapter as a separate,
   non-runtime-coupled increment.

No item authorizes implementation, Engineering Platform integration, or
AI-development-contract promotion by itself.

## Cross-product dependency register

Forge's roadmap may identify Workspace-owned capabilities as prerequisites for
a Forge workflow, but it cannot sequence or authorize Workspace work. The
following entries are Workspace's own planning placeholders; they become work
only through a separately governed Workspace capability decision.

| Workspace capability | Cross-product relationship | Earliest dependency | Required qualification |
| --- | --- | --- | --- |
| Quality governance surface | Present Effective DoR/DoD/Human Gates, repository-governance state and governed Quality Learning proposals. | Forge L0/L1 evidence and the Workspace onboarding/control-plane contract. | Attribution, freshness/degraded-state, accessibility and no-secondary-authority proof. |
| Knowledge governance surface | Present evidence-linked Knowledge Observation/Candidate proposals and KB lifecycle status; initiate only permitted governed intents. | Approved KB evidence-export and read-only consumption contracts. | Source lineage/redaction, unavailable-KB degradation, accessibility and no-direct-certification proof. |

The Forge L4/L7 labels are dependency references only. This roadmap is the
canonical authority for whether, when and how Workspace develops either
surface.
