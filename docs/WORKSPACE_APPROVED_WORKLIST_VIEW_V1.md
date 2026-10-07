# Native approved worklist — bounded read-only consumer

- Directive: `L234-NEXT-BACKLOG-DELIVERY-V1-20261007`
- Assignment: `L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002`
- Milestone: `L4-APPROVED-WORKLIST-VIEW-V1-20261007`
- r81 plan revision: `86`
- Producer JOIN: `L3-L4-APPROVED-WORKLIST-READ-V1-20261007`
- Source base: `73411de5a39d04d736b9742cf5356852582e54be`
- Branch: `codex/r81-approved-worklist-view`

The [7 October selection](https://github.com/pcvantol/forge/issues/208#issuecomment-6038111333)
authorizes one PRM-W-CONTRACT/PRM-W-VIEW read-only workset subset in the existing
native Client: exact previously approved membership/committed order, separate
execution/review/acceptance facts and verified reasons why the next member may
or may not continue. Workspace owns presentation and authenticated Server
transport; Forge owns workset governance, release, eligibility and activation.
The completed [Missions & reviews delivery](https://github.com/pcvantol/forge/issues/208#issuecomment-6020633531)
remains protected history. The new view navigates to separately authorized
existing review detail without creating a decision or widening its grant.

## Consumer and authority boundary

Only native Client → authenticated/pinned Workspace Server → qualified Forge
HTTP is admitted. The [L3 selection](https://github.com/pcvantol/forge/issues/207#issuecomment-6038082280)
owns the producer under the JOIN. A dedicated read capability binds actor,
Forge instance and explicit workset; status/review grants gain no rights.
There is no peer import, SQL/CLI fallback, general proxy or admin token.

Exact versioned schema/routes/grants, protected source pin and installed
producer qualification are external handoffs. Local presentation structs are
not a Forge wire contract. An absent/malformed capability remains unavailable;
local fixtures do not prove installed delivery. A title, sort, dependency
completion, cached observation or client-supplied actor grants no authority.

## Display and snapshot semantics

- Membership, selector and observation revisions are separate. Accepted items
  and pages belong to one exact scoped snapshot. Foreign scope, duplicate
  membership/order and mixed revisions fail closed; no silent page/cache merge.
- Local search/filter/title/identifier sorting preserves the original committed
  positions. Selection uses exact actor/instance/workset/member identity and
  resolves against the latest observation even when filtered out.
- Approval, release, eligibility, activity, engineering completion, review,
  final acceptance and completion remain independent. Engineering results do
  not imply final acceptance or unlock successor work in Workspace.
- Typed approved subjects and actual Missions are distinct. A Mission ID/detail
  reference requires the producer's real canonical binding. Project attribution
  requires actual evidence; an explicit workset without a project is sufficient.
- Verified dependency/hold/evidence/review/final-acceptance/authority/budget
  blockers carry current revisions and bounded safe references. Missing values
  remain unknown; no fabricated graph, progress percentage or deadline.
- Complete-empty within the grant, partial/stale, denied/offline/unavailable and
  no local matches are distinct. Retained offline observations are labelled
  cache; denial or scope change clears them. Cache is not execution authority.
- Native en/nl/de/fr/es, system themes, keyboard/focus, narrow windows and safe
  typed text/links are required. Existing conversation/archive/review/pairing
  behavior remains compatible.

All new navigation, search, polling and reconnect are GET-only. There is no
commit/reorder/release/hold/disarm/intake/planning/provider/EP-submit control.
Closing Workspace does not stop Forge. Review decisions retain their existing
separate authority, confirmation and receipt/current-readback semantics.

## Versioned read integration (protected producer qualified)

The L3 source proposal exposes `forge-workspace-worklist/v1` from
`forge/api/workspace-worklist-v1.json`. The protected inspected schema at Forge
`da57b7b5544028cace26bf35fbeaca855e2d14ea` (2.7.67) is blob
`a94a6b85e00402e10cc280e03d5937108619f711`, SHA256
`7674be1cd915b2976be5ace74a9f06deaf973f386b3ce8dfa4679120761f3b19`.
The [L3 owning handoff](https://github.com/pcvantol/forge/issues/208#issuecomment-6041108519)
records normal protected PR249 merge, independent reviewed candidate612ed6b,
actual exact-main noneditable installed read proof and all226 product files
verified. Protected source product tree is
`f70d4f3469441e540a7398a9a127c55f60cfa46f`; wheel SHA256 is
`74336a722e799de71617b2c2b79c89f2d56f6131e0f1d215d044a92c550f211d`.
The exact installed receipt SHA256
`3f51843ca3a282202ff5f0a20affed0a72838b7c94c9bb812af9d091c00ad9e4`
was read and checked locally. Workspace's own final acceptance remains open.
Producer activation remains `NOT_YET_QUALIFIED`; this read subset grants no
activation-family acceptance.

The owner provisions a private separate binding with `workspace-server --root
ROOT worklist-bind-issue --actor ACTOR --forge-endpoint URL --forge-instance-id
INSTANCE --forge-token-file PRIVATE_FILE --client-token-file PRIVATE_FILE`.
`worklist-bind-revoke --binding-id ID` removes only that separate read access.
The Forge bearer remains under the Server's private root; only a random hashed
Workspace client credential is distributed. Native storage has its own Keychain
service/account, separate from Server pairing, drafts and reviews.

| Workspace route | Authentication and effect |
| --- | --- |
| `GET /v1/worksets/openapi.json` | Pinned Server read bearer; own bounded contract. |
| `GET /v1/worksets` | Pinned read bearer plus `X-Workspace-Worklist-Grant`; exact authorized IDs. |
| `GET /v1/worksets/{workset_id}` | Same independent grant; one bounded snapshot, no pagination. |

Both Server and native Client validate exact fields, actor/instance/workset,
member/order uniqueness, predecessor references, canonical allocation and typed
evidence. The snapshot digest binds the producer's eleven fixed fields using
sorted compact UTF8 JSON. Python-canonical Unicode/slash fixture regression
checks native interoperability. `FINAL_BUSINESS_ACCEPTANCE.subject_id` is the
Business governance decision ID; `MISSION_COMPLETION.subject_id` is the Mission.
Neither reference is an arbitrary URL, executable link or invented project.
Missing/malformed grants never borrow existing status/review access.

An actual retained canonical Mission reference with unavailable current state
is admitted only as `PARTIAL` with no state revision, allocation proof, evidence
or detail link. Native labels the reference unconfirmed and disables review
navigation. A complete observation cannot claim unavailable current Mission
state. Only the active native tab registers its search shortcut; hidden
conversation/review/worklist tabs cannot take its keyboard focus.

A grant/scope denial or changed/removed pairing clears observations and visible
scope metadata. An absent pairing is distinct from a known paired endpoint
without a current read token. Pairing generations discard in-flight probe,
scope and snapshot replies after invalidation. Native hides any snapshot whose
observed Workspace endpoint/instance no longer matches pairing. Offline or rejected
mixed observations retain only an explicitly stale cache. Restart restores the
separate credential and reads anew; no cache creates current authority. Producer
continuation supplies next/idle; local filters never recompute it. Existing review
navigation shares its selected review key with manual review selection so that
A → manual B → reopen A always selects A without resetting view identity. It
refreshes independent review authority and matches exact actor, Forge
instance and canonical Mission before selecting a detail. It records no decision.

## Targets and proof

| Target | Required evidence |
| --- | --- |
| Local presentation/state | Immutable order, stable scoped selection, independent facts, honest empty/cache states, malformed/mixed snapshot negatives. |
| Server and native transport | Private actor/instance/workset binding, separate read grant, exact versioned GET projection, no generic proxy or canonical read-side mutation. |
| Native UI | Current list/detail, safe review navigation, five locales/themes, narrow windows, keyboard and accessible controls. |
| Installed matrix | Real noneditable Workspace/Forge packages, grants/storage/HTTP; two actors/scopes; transition/dependency/hold/evidence/final-review readbacks; revoked/expired/foreign scope/instance; partial/mixed revisions, refresh/restart/cache and no-work versus denied/offline. |
| Effect isolation | Zero new planning/decision/intake/EP/provider requests from all new reads/navigation; only declared external EP/LLM/OS-credential adapters. |
| Lifecycle | Full validation, >80.2% per changed Swift/Python production file, independent exact-head Quality/Security, fixes, versioning, protected merge, exact-main wheel/app/producer receipts, real packaged overview/filter/detail clicks and cleanup. |

Read/UI portions of PMT-01/02/05/06/08/11/12/13/15/17/18/19/20/23/25/30/31 apply;
L3 owns activation/outer-loop evidence. These subset claims do not close full
PRM-W-MANAGE/DECISIONS/SYNC/Q or a project-loop family. Actual TDE assessment is
separate from workflow success; prior observe-only debt is not blanket cleanup.

## Qualification state

`WORKSPACE_WORKLIST_DELIVERY=SOURCE_AND_CANDIDATE_QUALIFIED`; `FORGE_READ_PRODUCER_PIN=QUALIFIED_PROTECTED_MAIN`.
[Pickup](https://github.com/pcvantol/forge/issues/208#issuecomment-6038328457)
records admission and direct JOIN coordination. The integrated source adds native presentation, independent credentials,
GET-only Server transport and strict whole-snapshot validation.

Candidate `1090f2590bc1d0e4a7c902aeb912249e2bbdb3ad` /2.8.7 passed full validation:
79 native tests plus the isolated credential test, all changed executable Swift
and Python product files strictly above80.2%, source wheel/sdist parity and
ad-hoc app. Independent complete-slice Quality and Security reviews passed
that exact HEAD after two P2 fixes: repeated-target selection and pairing
removal/late-response invalidation.

Actual noneditable Workspace/Forge candidate proof verifies source/wheel/
installed bytes,17 authenticated HTTP requests with two actors/scopes, actual
empty/IDLE, expiry/revoke/hold and Serverrestart. A separate actual canonical
Mission flow supplies before/after Businessacceptance/dependency readbacks,
real packaged list/Cmd-F filter/detail/separately authorized review navigation,
restart and unchanged canonical source bytes from all new reads/clicks.
Declared private synthetic storage-fault control yields actual `PARTIAL`,
restores exact current-state document bytes, and preserves FK constraints.
Negative OS-stream membership corruption yields503 with no partial-page merge.
The consumer uses authenticated HTTP throughout; fault injection is not a
successful mocked contract, producer source change or SQL fallback. Owned
synthetic runtime roots/processes are removed after each successful run.

[PR137](https://github.com/pcvantol/workspace/pull/137) and the current owning
[#208 register](https://github.com/pcvantol/forge/issues/208) are designated for eventual
protected merge/exact-main receipts and terminal-disposition readback. Protected
merge, final exact-main qualification and terminal disposition remain pending. A final
register decision closes only this subset; no new family follows automatically.
TDE1090f25 observe workflow succeeded, but actual assessment/qualification
exits2/2 and policyFAIL: preserved product maximum complexity80 in unchanged
`review_peer.py` against policy30. New worklist validator maximum23 is reported
honestly; runtime qualified, policy is not PASS. This does not grant blanket
legacy cleanup or product activation.

Preserve historical candidates, user data and consumed budgets. Signing,
notarization, live personal Keychain, two-Mac trust, public release and production
activation remain separate r81 gates. No live EP, paid provider, real target
write, production Mission/grant, machine service or next roadmap selection.

## Selected dependency-graph continuation — plan87

## Selected native dependency graph — 7 October 2026, r81 plan revision 87

[Coordinator mandate](https://github.com/pcvantol/forge/issues/208#issuecomment-6044025195)
selects `L4-WORKLIST-DEPENDENCY-GRAPH-V1-20261007` under the same native HTTP
assignment and Work session. [Pickup plan87](https://github.com/pcvantol/forge/issues/208#issuecomment-6044087280)
binds clean base `cc98b0d726b0884617fe84d87b8df06a638cc3c8` and branch
`codex/r81-worklist-dependency-graph`. The primary iCloud checkout is preserved.
PR137 /2.8.7 is completed history, closed by its
[terminal receipt](https://github.com/pcvantol/forge/issues/208#issuecomment-6043502128).
Its earlier 2.7.67 qualification remains intact.

Product2.8.8 adds a read-only Dependencies alternative to the existing list,
with shared scoped selection/detail, exact edges, deterministic bounded geometry,
zoom/scroll-pan/fit/focus and five-language accessible native controls. It reuses
existing storage, grants, whole-snapshot validation, refresh and review navigation.
The graph never computes eligibility or dispatch; committed position stays separate.
New consumer acceptance explicitly targets Forge2.7.68 protected
`47c9f406323cbecd1c36227696f7f01b6a7b1c11`, wheelSHA256
`f5eed947d2844568e11ebfd610998dff76067ed3f4ba8b966a43e8ef3fc5a6c1`.
Implementation/tests/review/protected merge/exact-main installed and GUI
qualification are pending; equal schema does not prove this combination.
Signing/trust/release/full PRM families retain their separate gates.

Graph nodes are exact snapshot members. Directed edges use only explicit dependencies, never adjacent committed positions. The entire authorized context remains visible when filtered, with a textual filtered-context marker. PARTIAL missing predecessor references get an unavailable-observation note and no invented node/edge. Invalid/cyclic/forward/foreign complete references fail closed. A fixed-size bounded layout uses committed-order tie breaking and stable dependency columns; identical snapshots do not reshuffle. Native scrollbars/trackpad pan, zoom/fit, focus and previous/next controls supplement tab/space node navigation and the usable list alternative. All observed state/facts/reasons retain existing detail semantics; denial/pairing forget clears the source cache used by both views. No additional polling, authority or dependency store.
