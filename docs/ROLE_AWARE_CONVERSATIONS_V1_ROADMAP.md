# Role-aware conversations V1 — Workspace delivery plan

This is the owning Workspace decomposition of role-aware conversation UX,
linked from the existing [roadmap](../ROADMAP.md) and
[role-aware governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md).
See [functional design](ROLE_AWARE_CONVERSATIONS_V1.md),
[documentary DAG](ROLE_AWARE_CONVERSATIONS_V1_DAG.json) and the
[Forge plan](https://github.com/pcvantol/forge/blob/main/docs/roadmap/ROLE_AWARE_CONVERSATIONS_V1.md).
Design is canonical after owning protected merge; all runtime nodes are PLANNED.

This refines ROLE_AWARE_GOVERNANCE_V1 and ROADMAP_DAG_GOVERNANCE_V1, rather than
adding an independent planner, approval authority or roadmap. UX is an advice
lens within the same conversation capability. The full Workspace chat is
POST_AUTONOMY, never a prerequisite for the first Forge/EP canary. Contract-first
work remains parallel non-blocking design work.

| Node | Local dependency | Qualified producer subset | Delivery and acceptance |
| --- | --- | --- | --- |
| RC-WC | None | Forge RC-FC | Versioned consumer/UX contracts and fixtures for conversation, session, context, proposal, artifact and decision projections; authenticated project/principal and capability negotiation. |
| RC-WS | RC-WC | Forge RC-FS | Conversation shell/list, modes, history, attachments/context, accessible states and reconnect; no implicit provider call or approval. |
| RC-WP | RC-WS | Forge RC-FP | Versioned proposal/artifact review, exact confirmation, existing role-routed decisions and Candidate/design handoff with receipt readback. |
| RC-WQ | RC-WP | Forge RC-FQ | Installed/API integration and deterministic Playwright acceptance for the three-mode experience, five languages, access/retention/ambiguity failures and admin/control-plane separation. |

Runtime client delivery also requires Workspace's own authenticated Server/API
and session/project state subset. Its contract is documented in
[Server/Client deployment](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md); it is not
created by these records. A universal installer, EP fleet, full policy UI or all
DAG editing features are not automatic prerequisites. Wire contracts can be
specified in parallel, but production controls stay unavailable until their
actual producer capability is qualified.

## Acceptance and release slices

Read-only history/context can be delivered independently; expose no unavailable
advice/apply/approval controls as working. Business/Architect advice may precede
UX if capability discovery makes the supported subset explicit. Full three-mode
closure requires UX-specific content/preview qualification as well as common
history/context/authority tests. Rich visual generation and running prototypes
are deferred capabilities, not a promise of the first UX text/specification slice.

Use the shared RC-T01..RC-T20 catalogue in Forge's design. RC-WQ covers the UX
parts of RC-T01..RC-T17, RC-T19 and RC-T20. Real Workspace state/API integration
must run; mock external provider and EP behavior rather than the UI's own
permission/idempotency handlers. Browser mocks alone do not qualify server
contracts. Five-language coverage is en/nl/de/fr/es, with narrow layouts,
keyboard/focus, assistive-technology framing and localized errors/confirmations.

New executable components have a >80% coverage target, plus explicit checks of
negative authorization, stale preconditions, duplicate submit, export leakage,
rendering safety and ambiguous recovery. Document tests are only documentary
guards. Playwright setup and actual browser CI are future RC-WQ delivery, not
already implemented by this documentation task.

RC-T17 joins the real Forge Candidate/governance/intake/inner-loop harness with
mocked EP when qualified; it does not make inner-loop CI depend on Workspace.
RC-T18 is later deterministic outer-loop integration: new recommendations return
to advisory chat/Candidates and still require the existing approvals. It is not
a predecessor of basic RC-WQ delivery.

## Evidence and handoff

Publish actual source/artifact/API versions, supported modes, exact-head test
results, observed failure coverage and peer contract evidence. A Forge service
PASS is not Workspace browser qualification, and an optimistic UI acknowledgement
is not a canonical decision. Keep pending peer design/runtime status explicit.

Full experience: RC-WQ plus its qualified producer subsets. Preserve existing
conversation/session references and canonical decision provenance across
upgrade/restore. Do not reset Missions, budgets or approvals. Forge Server Console
continues as instance administration; Workspace remains the human project surface.
