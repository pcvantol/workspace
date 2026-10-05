# Workspace conversation draft HTTP V1

## Authority and boundary

Product 2.8.3 added a Workspace-owned draft and navigation subset to the existing
native Client and separately installed Workspace Server. The Server owns
conversation ID, actor/project scope, title, focus, advice-mode selection and
**unsent** draft text. This is not a Forge session transcript. The response
always returns `state=DRAFT_ONLY`, `history=[]` and
`history_availability=UNQUALIFIED_FORGE`. The Client renders those fields as
plain text. It has no send, proposal, apply or Mission endpoint.

Product 2.8.5 adds one reversible `archived` presentation flag. It changes only
Workspace navigation. The conversation ID, editable fields, `DRAFT_ONLY` state
and absence of Forge history remain unchanged.

Every draft read and write requires the existing read bearer and pinned
`X-Workspace-Instance` **plus** an independent
`X-Workspace-Draft-Grant`. The read bearer alone never confers draft access.
The owner of a private Server data root issues a token locally with
`workspace-server --root ROOT conversation-grant-issue --actor ACTOR --project PROJECT`.
A grant is bound to exactly one actor and one currently listed project. The
Server stores only its SHA-256 digest in a private `0600` grant file. The
owner can revoke all grants for that actor/project with
`conversation-grant-revoke`. The Server rechecks the current project source on
each operation and fails closed if it is absent, stale or no longer lists the
project. There is no Forge, provider or peer grant in this mechanism.

The native app keeps the separate grant in its own device-only Keychain item.
It stores only the current **unsaved local editor text** in a private owner-held
Application Support directory. The local cache is scoped to the exact Server
endpoint, instance, project and draft grant; the grant itself is not written
there. Explicitly saved conversation records remain in the private Server
SQLite store and survive Server restart. Normal app use does not require
Python, a local Server, its data root or a checkout on the client Mac. The
nightly isolated qualification uses a controlled credential adapter and
never accesses existing live Keychain items.

## Routes

The previous read-only V1 contract remains unchanged at `/v1/openapi.json`.
The draft-specific machine-readable contract is at
`GET /v1/conversations/openapi.json` with the read bearer and instance pin.

| Method | Path | Result |
| --- | --- | --- |
| GET | `/v1/conversations` | List only the grant's actor/project records. |
| POST | `/v1/conversations` | Create one unsent draft, HTTP 201. |
| GET | `/v1/conversations/{id}` | Read one own record. |
| PATCH | `/v1/conversations/{id}` | Replace editable fields at an expected revision. |
| POST | `/v1/conversations/{id}/archive` | Hide one own record from the active list. |
| POST | `/v1/conversations/{id}/restore` | Restore the same own record. |

Create accepts exactly `title` (1–120 characters), `focus` (0–240), `mode`
(`BUSINESS`, `ARCHITECTURE` or `UX`), `draft` (0–10,000) and a client-generated
lowercase 32-hex `request_id`. Repeating the same create request ID and body
for the same actor/project returns the existing record without a second
conversation. Reusing it with different content returns `DRAFT_CONFLICT`.

PATCH accepts the same four editable fields and `expected_revision`, an
integer at least 1. It increments the revision only if the expected one is
current. A stale revision returns HTTP 409 `DRAFT_CONFLICT`; the native editor
retains local text for review rather than overwriting the newer Server record.
PATCH never changes `archived`, so a pre-2.8.5 client cannot accidentally
restore an archived record.

Archive and restore accept exactly `expected_revision` and a client-generated
lowercase 32-hex `operation_id`. The transition increments the record revision.
Repeating the same operation ID with the same command returns current record
truth without a second transition. Reusing an operation ID for a different
command returns `DRAFT_CONFLICT`. A replayed old archive after a later restore
cannot restore old state. A stale expected revision, including a concurrent
text edit or opposite transition, returns `DRAFT_CONFLICT`. The record and its
operation receipt commit in one SQLite transaction and survive Server restart.
Existing stores gain `archived=false` during compatible schema migration.
The Server retains a bounded recent operation-receipt window per actor/project.
After compaction, a replayed transition with an old expected revision still
fails closed, while a replayed no-op remains a no-op; neither can reapply state.
All IDs are lowercase 32-hex. JSON must be one bounded object without
duplicate keys; request bodies are limited to 48,000 bytes. The Server never
interprets HTML or Markdown and never logs tokens or draft content.

Host/Origin denial is HTTP 403; invalid read bearer 401; wrong instance 409;
missing/invalid draft grant 403; unknown or other-scope record 404; invalid
input 400; stale or unavailable project source and private-store failure 503.
The `Cache-Control: no-store` response header applies to all routes. There
is no fallback to peer CLI/import/SQL or a local model.

## Qualified scope and pending producer

The Workspace-owned RC-WC/RC-WS presentation/draft subset can be qualified
independently via the installed Server wheel and native ad-hoc app. Forge
RC-FC/RC-FS conversation producer bindings are still unqualified. Until the
real versioned capability, authority, source and negative receipts exist,
live advisor turns, canonical history, proposals, approvals, apply and Mission
handoff remain unavailable. Choosing a mode changes only the next unsent
draft; it grants no right and starts no provider operation. The full RC-WC,
RC-WS, RC-WP and RC-WQ nodes remain open.
