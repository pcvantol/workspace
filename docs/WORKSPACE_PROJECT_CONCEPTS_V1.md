# Workspace Projectconcepten V1 — plan99

Assignment L4-PROJECT-CONCEPTS-V1-20261012 / mandate6118583726.
Current concept budget consumed1/max3/remaining2. Initial implementation.
Same writer/session; merged basea6aad520bed9f1c2f7119b393435b8c739f030b3.
Plan98/PR160 PARKED on0212f898bb049c7019e4f8c602decc09b891c595,
LINK consumed2/max3/remaining1; not closed or merged. Predecessors96/97 CLOSED.
Candidate2.8.22 explicitly allocated by normal exact-version operation because
PR160 reserves2.8.21. No release asset/signing/publication authority inferred.

## Product route

Projectconcepten → Nieuw idee → title + freely written notes → explicit save →
find saved entry → reopen → edit/save, with stable own concept identity.
Always “Concept — not configured yet”. Neither a canonical project nor Mission,
execution authorization or engineering readiness. No fake chat, provider, EP,
Forge, repo creation/attachment/adoption/scan or hidden promotion control.

Native labels in en/nl/de/fr/es; native system appearance, wrapping/scrolling,
minimum560px shell and keyboard Save. Create/update timestamps are actual Server
records. Technical IDs and tokens are not concept input fields.

## Ownership and current actor authority

The Server owns content in separate project_concepts_v1 and immutable receipt
project_concept_operations_v1 tables in existing private conversations.sqlite3.
Existing chat records stay unchanged. Existing actor/context pairing (DraftAccess
and ConversationStore grants) is reused, not a new identity/token issuer. The
context is an own Workspace pairing boundary, not concept ID or EP registration.
The concept routes do not require an EP/Forge connection or project catalogue
read. They retain the narrower current actor/context, never all-actor scope.
Existing pairing setup remains outside the idea editor; no token field added.

Own bearer + pinned instance + singular X-Workspace-Draft-Grant are required.
Existing cross-process forward_grant fence serializes current reads/writes AND
response publication with grant revocation. Wrong actor/context cannot read or
edit another concept. Concept text is untrusted data, never executable content.

## Owning HTTP contract (V1)

- GET /v1/project-concepts: actor_id/context_id/concepts, at most500 metadata summaries; no notes.
- POST /v1/project-concepts: title, notes, operation_id, expected_revision0.
- GET /v1/project-concepts/{own hex32 ID}: one currently authorized record.
- PATCH /v1/project-concepts/{ID}: same closed body, expected_revision>=1.

Detail record: id,actor_id,context_id,title,notes,revision,created_at,updated_at,state.
List summaries omit notes; all500 maximum Unicode titles/context IDs remain within
2,000,000bytes even under existing ASCII-escaped JSON. Full notes remain in detail.
state=CONCEPT_NOT_CONFIGURED. Title1–120 Unicode scalars (nonblank), notes<=10000;
control characters except newline/tab rejected. IDs/operation IDs are randomhex32,
not derived from names/URL/path. Receipt limit4096 per actor/context. Body<=64000
bytes; bounded literal paths/JSON duplicate keys/framing. Error projections are
redacted:401 own auth,403 pairing denied,404 scoped absence,409 stale/original
request conflict,400 malformed input,503 store unavailable. No delete/export/API
collaboration or revision-history UI is selected.

## Durability and storage allocation

Schema V1 is a unique bounded extension, not copied from parked PR160. Existing
private SQLite ownership/checks retained. Schema allocation marker contains only
schema_version1, no content/identity/credential. Initialized source loss must fail
unavailable; cannot become healthy empty or initialize replacement. First empty
list creates no DB. Migration is additive and tested only on synthetic copies.
Existing stored messages/preferences/history are retained.

A serialized immediate SQLite transaction binds operationID to exact request
and immutable completed record. Replay precedes stale-write comparison, never
updates twice. Stale revision cannot silently overwrite a concurrent edit.
Client journals the exact request before dispatch through existing private record
primitive, scope-keyed by pairing binding (opaque hash; no persisted credentials).
Lost answer/restart replays original request. After receipt, authorized current
readback is required; drift shows conflict and preserves text. User can explicitly
open the saved version to replace unsaved text. Other concept selection/new action
cannot silently discard dirty edits. Known denial hides protected content;
unavailable/conflict retains permitted unsaved text, never claims saved success.
Late response generation guards prevent wrong-screen publication.

## Compact actual qualification matrix / initial state

1. Create/save/list/reopen/edit with same identity and real timestamps.
2. Native app restart AND separate Server OS-process restart.
3. Lost success answer/original replay and duplicate click, no extra row/revision.
4. Stale writes, concept switch/late reply, other actor and real revoke fence.
5. Empty list, long Unicode/five languages, limits, actual unavailable/corrupt/lost
   store and connection; retain eligible unsaved content, honest status.
6. No provider/peer/project/Mission effect. Existing audit is not suppressed.

Own-source actual HTTP/private-SQLite tests and native/URLProtocol tests are
DEVELOPMENT evidence, not final installed acceptance. Full strict executable
coverage>80.2% per changed production file, independent complete Q/S/UX, normal
CI, protected match-head merge, nonempty reviewed finalization and NEW exact-main
installed wheel/native GUI/screenshots are required. TDE actual artifact separate.

Installed tests only own isolated roots/actors/concepts with normal existing
owner pairing. Before start record exact source/artifacts, finite operation/test
window, storage capacity, scope and cleanup stop bound. No user credentials/data,
old plan96 grants, EP/Forge service, paid provider, new host or signing changes.
All failures retained. One bounded guard refault must make the relevant test red.
No old Mission matrix repetition or blind retry-until-green.

## Integrated correction round1

Booked once before edits via6119044322 after all three complete90d1b71
initial reviews failed. Admission0/3 preserved; current consumed1/max3/remaining2.
Transient connection phases suspend current publication while retaining eligible
same-binding editor/recovery; known denied/forget/rebinding clears protected data.
Visible save status follows actual dirty editor immediately, preserving stronger
conflict/offline/recovery errors. Lists are bounded metadata summaries, note bodies
only in authorized detail. Initial real packaged GUI created/saved a concept and
confirmed saved-status defect after unsent edit; failure screenshots retained.

Within the same integrated round1 package, the directly reused SQLite primitive
now has explicit read-only/existing-only URI modes for concepts. Controlled loss
at the actual open cannot create a replacement; legacy default callsites retain
their behavior. Repeated completed Save without edits is a native no-op (same
concept/revision), alongside immutable pending replay. No new correction booked.
