# Native scoped worklist hold consumer V1

## Selected native worklist hold controls — 8 October 2026, r81 plan88

[Owner mandate](https://github.com/pcvantol/forge/issues/208#issuecomment-6050026304)
selects `L4-NATIVE-WORKLIST-HOLD-CONTROLS-V1-20261008` under the same
`L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002` assignment and Work session.
[Pickup](https://github.com/pcvantol/forge/issues/208#issuecomment-6050146453)
binds clean base366196cdce5404862c1df8d77866ba15900c64bd /2.8.8 and
branchcodex/r81-native-worklist-hold. The primary iCloud checkout stays intact.
[Completed PR138](https://github.com/pcvantol/forge/issues/208#issuecomment-6045050571)
and its2.7.68 graph evidence remain closed history.

Product2.8.9 adds a separate scoped hold/unhold capability through the existing
native→authenticated Workspace Server→Forge HTTP path. Hold fences only future
Mission admission, including no cancellation of already admitted/not-yet-started
work. Unhold removes only the exact owned observed hold; other release/acceptance/
authority/evidence/budget conditions remain authoritative in Forge. Exact user
confirmation and durable same-ID intent precede POST. Refresh/restart reads the
operation first; explicit resume alone may reconcile the same ID/payload.
No ordinary readgrant is upgraded and no workset/scheduler store is introduced.

New consumer acceptance pins Forge2.7.69/e64302ffd2385926c1d5fad3e1417778798309aa,
wheelSHA256ac4cf14f18d49d48c23bc04fbe536f529886415b548703e7d2bdbd71f3258ab0.
L3 adviceHTTP is independent. Owning implementation/tests, independent reviews,
protected merge and exact-main installed/newGUI qualification remain pending;
prior source/producer/schema proof is not new consumer acceptance. Signing,
personal Keychain, trust, public release/operation and full PRM remain separate.

## Owner setup and authority

Provision the exact Forge control grant with the pinned installed owner CLI
`forge-workspace-worklist-control-grant --data-root ROOT issue --principal-id
ACTOR --workset-id WORKSET --expires-at UTC --token-file PRIVATE_FILE`.
Use `revoke --grant-id GRANT` for its independent revocation. Tokens never enter
command JSON, fixtures, logs or Git. This owner route is setup, not native user
administration or borrowed status/read authority.

Provision Workspace's separate private command binding using
`workspace-server --root ROOT worklist-control-bind-issue --actor ACTOR
--forge-endpoint URL --forge-instance-id INSTANCE --workset-id WORKSET
--forge-token-file PRIVATE_FILE --client-token-file PRIVATE_FILE`.
Repeat workset-id for at most16explicit existing worksets. Probe each live
control/current response; actor/instance/workset metadata must actually match.
`worklist-control-bind-revoke --binding-id ID` removes only this own capability.
No token is returned in the CLI receipt. Catalog/control-token files are private;
root locks and existing atomic/no-symlink patterns remain required.

Native credential service `com.pcvantol.workspace.native-client.worklist-controls.v1`
is separate from pairing, draft, review and GET-only worklists. Qualification
uses only the existing isolated adapter with private synthetic control_grant,
control_actor/control_forge_instance/control_workset_ids and durable own
local_root transport-intent storage. No personal Keychain is exercised.

## Exact routes and transport

Pinned Server bearer plus `X-Workspace-Worklist-Control-Grant` is mandatory.
`GET /v1/workset-controls` returns only owner-bound live command scopes.
GET/POST routes otherwise mirror the selected bounded Forge capability:
`GET /v1/workset-controls/{workset_id}`, `POST .../commands`,
`GET .../commands/{operation_id}`. Own authenticated `/v1/workset-controls/openapi.json`
exposes the separate command contract; the basic read-only API remains separate.
No arbitrary peer path/method/body proxy, SQL/CLI/import fallback or direct
native→Forge admin route. Owner binding revocation serializes with the actual
Workspace command forwarding boundary. Forge still checks live authority,
CAS/lease/provenance and its bounded64-operation journal.

Request includes the exact ten declared fields and null hold targets for hold;
unhold names the observed owned operation/control revision. Definition/workset
revisions are frozen in the confirmation. Actor comes from the authenticated
capability, not client JSON. Strict scalar/closed-shape/revision/digest/scope
checks cover current, original receipt, result and nested existing v1 worklist.
The original effect is immutable and may differ from newer current state;
recorded:false is successful original replay, not another effect.

## Native durable recovery and presentation

List/graph/detail/selection, old readcache and refresh remain shared. Control
state has no extra timer and does not create a planner/store. Confirmation
shows workset, operation, definition/expected revision, reason and exact unhold
target; the admission boundary and already admitted IDs remain explicit.
Foreign/local-owner/LEGACY_UNKNOWN holds have no unhold action. Every state and
control has en/nl/de/fr/es text, native system themes and accessible controls.

Save the actor/pairing/grant-fingerprint/scope-bound exact intent before sending.
Only matching original receipt and separate current readback establish result;
a POST acknowledgement alone is not presented as complete. Restart/poll first
uses authorized operation GET and never POSTs automatically. Duplicate clicks
are serialized. Explicit resume reads first, then reconciles only the identical
ID/payload for PENDING or authorized absence with matching frozen currentness.
Conflict never bumps a revision or silently invents a new ID. An explicit
resolve/discard action can clear a completed intent or an authorized unrecorded
local intent after fresh readback; it cannot erase an unknown PENDING canonical
operation or any producer journal. A new command still needs fresh confirmation.
Pairing/actor/workset generations fence old callbacks and credential/pending
cleanup. An uncertain single pending intent blocks new commands until resolved;
scope changes cannot repurpose it. Reads/search/sort/modes/poll/preview/status
cause no extra command, planning, provider, intake, decision or EP effect.

## Required acceptance

Full own validate, >80.2% per changed Swift/Python product file, independent exact
head Quality/Security after convergence, protected version/finalization/merge,
fresh exact-main noneditable source/wheel/installed verification and actual new
native clicks. Two actors/worksets, ordinary-read command denial, genuine
hold/future-admission fence/exact unhold, admitted work unaffected, remaining
final acceptance/release/budget gates, old receipt/current state, wrong/revoked/
expired/stale/foreign/legacy/conflict/503, duplicate/lost response, real app/Server
restart and scope/late-response fences. A genuine revoked positive command grant
must fail its positive gate. One real canonical preapproved A→B flow suffices;
no unnecessary full historical producer/FCI matrix. Only existing declared
external EP/LLM/OS/repository fixtures, both HTTP/auth/data/control products real.
TDE workflow and actual policyFAIL remain distinct; no broad debt cleanup or
suppression. Consumer delivery is pending until these actual receipts exist.
