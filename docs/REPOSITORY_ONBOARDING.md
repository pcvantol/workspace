# Workspace repository onboarding and qualification

## Status and purpose

**Status: proposed.** This document is the canonical Workspace product design
for presenting and initiating project/repository onboarding. It records intent
and boundaries only. It does not establish an implemented Workspace UI, a
GitHub integration, an Engineering Platform (EP) protocol, an EP repository
schema, or permission to provision external resources.

Workspace is the user- and project-control plane above Forge planning and EP
execution: it gives people one place to understand project topology and to
start permitted lifecycle actions. “Above” describes the user experience and
control-plane composition, never an authority to bypass Forge, CENTRAL, EP, or
the Project Agent. The product boundaries remain defined in
[Architecture](ARCHITECTURE.md), and sequencing remains in the
[roadmap](../ROADMAP.md).

## Intended onboarding choices

The planned Workspace onboarding surface offers these mutually distinct entry
points:

| Choice | Planned outcome | Intended use |
| --- | --- | --- |
| **Use existing repository** | Register an already-existing GitHub repository in a logical project and request eligible Agent attachment. | Adopt an existing codebase without recreating its Git history. |
| **Create new repository** | Request governed GitHub provisioning, then register the created repository in the logical project. | Start a normal new repository under an approved owner/namespace. |
| **Genesis project** | Create a logical project and its initial canonical project/repository topology, then request an initial repository bootstrap. | Start a new product with no prior repository. |
| **Qualification-only repository** | Create or attach an explicitly disposable repository used solely for a bounded installed-product qualification. | Prove a route without attaching a canonical product repository. |

The choices are plans, not current Workspace capabilities. A future product
decision must define their request/API model, the EP-owned repository contract,
supported GitHub settings, user roles, approval thresholds, retention, and
failure/recovery behavior.

## Logical and physical authority

The future flow separates a logical declaration from the physical host work.
This prevents a browser, a planner, or a local Agent from silently becoming the
authority for every concern.

| Concern | Planned authority | Not the authority |
| --- | --- | --- |
| User-facing project/repository control and topology presentation | Workspace Server and Client | A local checkout or Project Agent |
| Cross-project planning, dependencies, and proposed lane intent | Forge | Workspace UI or a GitHub repository |
| Accepted project/repository intent, execution admission, durable lifecycle state, and EP evidence | EP CENTRAL / EP Server | Forge, Workspace, or a Project Agent |
| GitHub resource provisioning from accepted intent | A future governed CENTRAL-backed GitHub integration, with Workspace/Forge as permitted requesters | A Project Agent acting on its own initiative |
| Clone, checkout, worktree, local toolchain, provider-host readiness, and local credential use | EP Project Agent on the selected host | Workspace, Forge, or CENTRAL directly accessing the host filesystem |

Workspace may initiate a permitted request and show its state. Forge may
produce the related plan. Neither may issue a direct Agent filesystem command,
admit an execution, allocate a repository lease, or turn a proposed repository
into a provisioned resource without the applicable CENTRAL decision and
operator controls.

## Portable repository declaration

The intended logical declaration is a portable,
repository-relative `.engineering-platform/repository.json`. It describes the
logical project/repository relationship that EP can consume when the repository
is attached. It must be safe to carry in Git and must not encode facts that
only make sense on one machine or in one installation.

The eventual EP-owned schema may include stable logical identifiers, a
repository role, and non-secret source/provider references. It must not include
any of the following:

- `server_url` or other CENTRAL endpoint/address;
- `agent_id` or host identity;
- `local_path`, clone path, worktree path, or IDE path; or
- credentials, access tokens, private keys, cookies, or other secrets.

EP owns the schema and validation rules; this document does not define them.
Host attachment and credentials remain local Agent/secure-store concerns.
This boundary also allows a repository to move between eligible hosts without
rewriting a server- or machine-bound declaration.

## Disposable qualification lifecycle

A qualification-only repository is intentionally not a shortcut around
canonical project governance. Its planned lifecycle is:

```text
explicit qualification purpose and scope
  → approved create or attach request
  → GitHub repository provisioned or verified
  → portable logical declaration and project registration
  → Project Agent clone/checkout/attachment and host preflight
  → installed product qualification through the canonical route
  → durable, redacted evidence and disposition recorded
  → archive or delete under the approved retention policy
```

The qualification record must identify that the repository is disposable and
must retain the relevant logical identity, exact artifact/revision context,
outcome, and redacted evidence. It must not retain credentials or treat a
successful qualification as authorization to use the same repository as a
canonical product repository. Archive versus deletion, retention duration, and
any evidence export are future operator-policy decisions.

## GitHub integration and operator governance

GitHub is a future external resource provider, not a new project authority.
Before implementation, the owning product contracts must define:

- who may request use, creation, archive, and deletion;
- which organization/account, namespace, visibility, naming, default-branch,
  protection, and template choices are permitted;
- when a request needs explicit operator approval, including all destructive
  disposal actions;
- how CENTRAL records idempotency, the accepted intent, provider result, and
  redacted audit/evidence; and
- how failed, partially provisioned, or manually changed resources are shown
  and recovered without guessing their authority.

Workspace should show the request, approval, provisioning, attachment, and
qualification states clearly. It must not expose provider credentials to a
client, implement approval policy locally, or claim that a GitHub-side change
has succeeded until the governing service records it.

## Relationship to project topology and lanes

One logical project can have one canonical project authority repository and
zero or more child repositories. Workspace presents this multi-project/multi-
repository topology; Forge plans dependencies across it; EP CENTRAL admits and
records executable work; and Project Agents supply local physical capability.

Multi-repository parallel mutation is deliberately later. It may begin only
after standalone EP verification and requires EP-managed repository leases,
capacity-aware admission, dependency ordering, and qualification evidence. The
initial safety rule remains one mutating lane per repository. Same-repository
worktree or declared-disjoint-scope parallelism is a separate later proposal.

For the cross-product sequencing and constraints, see the Forge Platform
[MVP roadmap](https://github.com/pcvantol/forge-platform/blob/main/docs/roadmap/MVP_1_0.md#post-verification-multi-repository-parallel-lane-execution)
and its [project/repository/Agent ADR](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/adr/ADR-0002-project-repository-host-agent-model.md).

## Decision checkpoints

No implementation should start from this design alone. The next bounded
decisions are to establish the owner and contract for repository registration,
the EP-owned declaration schema, the GitHub integration/approval model, and
the first limited Workspace onboarding experience. Each must be reviewed as a
separate proposed-to-implemented change with its own validation and evidence.
