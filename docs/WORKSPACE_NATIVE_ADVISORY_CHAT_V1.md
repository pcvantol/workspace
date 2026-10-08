# Native textual advisory consumer V1

## Selected native Business/Architect chat — 8 October 2026, r81 plan89

[Mandate](https://github.com/pcvantol/forge/issues/208#issuecomment-6055010173)
selects L4-NATIVE-ADVISORY-CHAT-V1-20261008 under directive
L34-NATIVE-CHAT-CANDIDATE-CONTINUATION-V1-20261008 and the existing
L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002 assignment/Work session.
[Pickup](https://github.com/pcvantol/forge/issues/208#issuecomment-6055534439)
binds clean base94579dac44be4ef14328be356e81e04f4a00a6f4 /2.8.9 and
branchcodex/r81-native-advisory-chat, one admitted Workspace writer. Primary
checkout, history/budgets and closed PR139/plan88 remain intact.

Bounded product2.8.10 adds explicit textual BUSINESS/ARCHITECTURE send,
authorized canonical history/cursor, immutable snapshot/durable same-turn
recovery and cancel-intention through own authenticated Server into pinned
Forge2.8.0/88f7560f271a2bc2b0af68de0300d0d784cf6315. WheelSHA256
424ae4cc555c2ee07f6acc8c9b3c865b971363a5a02b2d8f79d364d4fa7251a6,
wire-schemaSHAfc4750604a4f063d11a1680d9d5ca77ade4784cff53692b40692e86d6c26e7ef.
Workspace stores presentation/drafts and necessary private transport intent;
Forge remains canonical advice/consumption authority. Existing draftgrants and
advisory capability are separate. No provider on reads/mode/search/reconnect,
no Candidate/apply/approval/Mission/repository operation. UX drafts remain
usable but generation is unsupported. Source pins are observations, and
provider_stopped:false/NOT_REPORTED/live-model-NOT_QUALIFIED remain explicit.

Full owning validation/per-file>80.2%, independent exact-head Quality/Security,
protected merge/finalization and fresh exact-main noneditable installed/new
packaged GUI proof remain pending. L2, new L3Candidate API, PR258 and signing
are not dependencies; newer Forge main is not the selected pin. See the
[consumer boundary](docs/WORKSPACE_NATIVE_ADVISORY_CHAT_V1.md). Existing
2.7.67/2.7.68/2.7.69 receipts and separate open signing/trust/release gates stay.

## Setup and actor authority

Forge owner issues its separate advice grant with the normal pinned
`forge-advisory-grant ... issue --principal-id ACTOR --project-id PROJECT
--repository-id REPOSITORY --conversation-id EXISTING_WORKSPACE_ID ...` CLI.
Use the actual existing Workspace conversation IDs; creating a draft grants
no Forge authority. The producer capability omits principal metadata, so the
trusted setup owner pairs the actual private issuance receipt with the actual
private token file: append token_sha256=SHA256(token.strip().encode()) and
write the receipt to a private owner-held0600 regular file. This assertion is
privileged owner setup, never consumer actor/role JSON. Receipt principal must
match the actual Workspace actor; token hash/scope must match the issued token.
Renewal retains producer consumption and does not reset a conversation budget.
No Forge private store/source/SQL is read by Workspace.

`workspace-server --root ROOT advisory-bind-issue --actor ACTOR --project
WORKSPACE_PROJECT --forge-endpoint URL --forge-grant-receipt-file PRIVATE
--forge-token-file PRIVATE --client-token-file NEW_PRIVATE` validates existing
own actor/project/conversations and real live capability. One explicit private
binding per actor/Forge instance. Revoke using `advisory-bind-revoke --binding-id
ID`; actual forwarding and revoke serialize at the byte-forwarding boundary,
while long provider waits do not prevent a cancellation intent. Current binding
is rechecked before returning a mutation result. No tokens appear in receipts.

Own `/v1/advisory/access` returns only authenticated private binding metadata;
the five exact Forge routes are transported through the same own namespace.
Root Server bearer/instance plus BOTH current Workspace draftgrant and separate
advisorygrant are required. The Workspace actor/project comes from existing
live draft authority; requests do not contain actor/roles/model. Conversation
must belong to that scope and be explicitly permitted. Catalogue freshness,
producer authority/context ACL and revocation remain failclosed.

## Closed wire and native recovery

The exact committed external JSON schema is a consumer projection, never a
producer implementation import. Python and native validate strict scalar/
closed shapes, UTF-ASCII canonical digest joins, current versus original turn,
exact instance/project/repository/conversation/lens/context/source references,
usage bounds and safe literal output. Schema drift is an owning offline gate.
Typed busy/budget/stale/uncertain/denied/unsupported/offline errors stay distinct.

Explicit send freezes the editor string/lens and current permitted context in
one durable turn-ID before POST. Local edits/save/discard are unchanged; sending
does not clear or overwrite the editor. POST acknowledgement is not completion:
exact authenticated turn GET must prove admitted outcome. Reopen, refresh and
restart only GET; explicit recovery alone may submit identical ID/payload under
current authority. Authorized absence requires exact frozen context/revision;
no silent revision increase/new ID/automatic resend. Uncertainty remains until
proved; cancel records only scope/CAS/request-bound intent with provider_stopped
false and never restores spent budget. Namespace/keychain/private isolated
pending storage is separate; no transcript is persisted as an editable copy.

History is fresh authorized presentation with1..4item pages, max8displayed
turns. Denial, source/actor/pairing change and offline failure clear transcript/
capability presentation while local draft and durable uncertain transportintent
remain. Old callback generations cannot update new UI or credential cleanup.
Archive/restore only changes existing Workspace presentation, never Forge turns
or ongoing generation. Both lenses share one conversation, not approval roles.

Pinned Forge returns404 before the first admitted turn instead of allocating a
transcript during a read. With a live capability and no previous/pending turn,
native shows this absence explicitly and uses the producer's initial CAS0 only
on explicit send. It does not invent a canonical history record. Missing exact
turn readback with a durable intent stays uncertain; explicit same-ID recovery
checks the frozen context and CAS, including this initial absent-transcript
case. Registered binding and Workspace draft authority are rechecked after
outstanding reads so a revoked grant cannot return a previously fetched result.

## Qualification boundary

This selected RC-WC/RC-WS text subset is not RC-WP/Candidate promotion, UX
provider, streaming/attachments/export/tools or full RC-WQ/family closure.
Both installed products/auth/storage/request/result/recovery/HTTP remain real;
only explicit external model/OS/repository transport is deterministic. Qualify
Business→Architect continuity, drafts/history/cursor/restart, twoactors/scopes,
wrong/revoked/expired/stale/foreign/unsafe-result denial, duplicate/loss/same-ID
recovery, cancel/uncertainty/budget and zero unrequested generation/governance/
EP effects. Genuine revoked-positive grant must fail. Full own validate, strict
perfile>80.2%, independent Q/S, protected merge/finalization and actual fresh
exact-main packaged GUI/service proof are mandatory. No live paid/login probe,
personal Keychain, live EP, signing/trust/public/operational activation. TDE
workflow and actual policyFAIL remain separate. All acceptance still pending.
