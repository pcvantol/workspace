# Role-aware conversations V1 — Workspace delivery plan

This is the owning Workspace decomposition of role-aware conversation UX,
linked from the existing [roadmap](../ROADMAP.md) and
[role-aware governance](ROLE_AWARE_GOVERNANCE_AND_ROADMAP_DAG.md).
See [functional design](ROLE_AWARE_CONVERSATIONS_V1.md),
[documentary DAG](ROLE_AWARE_CONVERSATIONS_V1_DAG.json) and the
[Forge plan](https://github.com/pcvantol/forge/blob/main/docs/roadmap/ROLE_AWARE_CONVERSATIONS_V1.md).
Design is canonical after owning protected merge. The full-family runtime nodes remain
PLANNED; bounded delivered subsets are reconciled by their receipts below; the 4 October r81 revision selects only a Workspace-owned RC-WC/RC-WS
presentation and unsent-draft subset for product 2.8.3.

The 5 October r81 plan revision 84 selects reversible archive/restore on product
2.8.5. Archive state belongs to the Workspace presentation record and preserves
the same conversation identity and unsent text. Active/Archived/All combines
with delivered discovery controls. Archive and restore require expected revision
and a durable operation ID; retries, concurrent writes, revoked grants and scope
changes fail without a second effect or text loss. Existing records migrate to
active and older text updates preserve archive state. This adds no provider,
Forge session, Mission, approval or AI-send behavior.

The 5 October r81 plan revision 83 selects one continuation on product 2.8.4:
find and resume already authorized drafts through local search, mode filtering
and stable sorting, without changing draft authority or invoking a provider.
An open conversation and unsaved editor text survive list changes. Distinct
empty, no-match, missing-access, offline and stale states, list reset, keyboard
focus and five-language copy are included. Real packaged create/rename clicks
remain a separate UI acceptance check alongside state and installed HTTP tests.
The signed successor and two-Mac gates remain separate L1-dependent work.

The [RC-WC Workspace consumer contract](ROLE_AWARE_CONVERSATIONS_WC_CONTRACT_V1.md)
now supplies offline target projections, capability negotiation and negative
interaction fixtures. Forge RC-FC binding and live UI/API qualification are
still unqualified/planned.

The selected own subset uses [Workspace conversation draft HTTP V1](WORKSPACE_CONVERSATION_DRAFT_HTTP_V1.md):
native project/conversation navigation, own titles/focus/mode/draft, explicit
project/actor draft grants beyond the read bearer, idempotent create and
revision-guarded updates. The native app may cache only unsaved local text in
its private owner-held directory; confirmed drafts and navigation belong to
Workspace Server. This does not make Forge session history or AI advice
available. Business and Architect are modes of one conversation; UX remains
an optional contract mode. No load, search, reconnect or mode change invokes
a provider. Source validation, exact-head independent review, protected
merge, isolated installed-wheel/Server and ad-hoc native GUI HTTP readback
are separate delivery evidence gates.

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

## Selected native textual advice — r81 plan89

The [8October mandate](https://github.com/pcvantol/forge/issues/208#issuecomment-6055010173)
selects the bounded BUSINESS/ARCHITECTURE RC-WC/RC-WS consumer subset on
Workspace2.8.10, against pinned qualified Forge2.8.0/88f7560. See the
[owning implementation/qualification boundary](WORKSPACE_NATIVE_ADVISORY_CHAT_V1.md).
This extends delivered draft/archive UX with explicit send and canonical history,
not Candidate/apply/UX/provider execution or full-family closure. [PR140/plan89 terminal](https://github.com/pcvantol/forge/issues/208#issuecomment-6057361472)
closes protected/exact-main installed/newGUI acceptance for that subset. Older draft/hold/graph receipts
remain closed; no new L3Candidate or signing predecessor.

## Selected native advice inspector — r81 plan90

[8October selection](https://github.com/pcvantol/forge/issues/208#issuecomment-6058224232)
adds bounded native selected-turn details, separate answer categories, frozen
context and exact-version source metadata to the delivered2.8.10 chat.
Workspace2.8.11 uses the same qualified2.8.0 producer, auth and bounded history;
no new producer dependency or generation by inspection. Missing/ambiguous/current
version mismatches are explicit, and denial/offline/scope changes clear all
inspection presentation. See [selected consumer boundary](WORKSPACE_NATIVE_ADVISORY_INSPECTOR_V1.md).
New own source/reviews/protected/installed/UI qualification remains pending;
this neither reopens PR140 nor closes the full RC-WC/RC-WS/RC-WQ family.

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
