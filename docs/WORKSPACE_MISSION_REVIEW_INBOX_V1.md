# Native Missions & reviews — selected consumer boundary

- `DIRECTIVE_ID=L4-MISSION-REVIEW-INBOX-V1-20261006`
- `ASSIGNMENT=L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002`
- `OWNER_REGISTER=pcvantol/forge#208`
- `R81_PLAN_REVISION=85`
- `NODE_SUBSET=GP-WC/GP-W_LOCAL_SERIAL_REVIEW`
- `PRODUCER_JOIN=L4-L3-GP-REVIEW-INBOX-V1-20261006`

The owner selected this next result in [Forge #208](https://github.com/pcvantol/forge/issues/208#issuecomment-6012171755).
Workspace owns the native presentation and authenticated Server transport.
Forge owns Mission/review requirements, authorization, decision validation,
receipts, continuation and final acceptance. The existing 2.8.5 conversation
archive/restore result stays delivered.

## Concrete user result

A currently authorized user opens **Missions & reviews** and sees only the
producer-bound Mission subset available to that actor. The inbox identifies
which review waits, why, the completed Action result, the exact requirement and
subject/evidence revision, required role, freshness and supported outcomes.
The user inspects bounded, safe evidence references and explicitly confirms
one decision: approve, reject, request amendment or defer, when Forge permits
that outcome. The UI reports success only after the same Forge decision
operation has a receipt and a current authoritative requirement/fence readback.

The list distinguishes engineering outcome, review wait, continuation and
Mission-end acceptance. A visible empty scoped set never claims there are no
Missions globally. Unknown project attribution, percentages, deadlines and
active execution are not inferred from labels, paths or local project choice.

## Selected transport and authority

```text
native Workspace.app
  -> authenticated, pinned Workspace Server HTTP
  -> separately provisioned, revocable, scoped Forge review HTTP capability
  -> Forge requirement/decision service and durable receipt/readback
```

The native Client never receives a Forge credential. The existing Workspace
read bearer and Forge status grant retain their current meanings. Workspace
Server must bind its authenticated client actor and selected instance/scope to
the Forge-issued subject authority; an actor or role string in client JSON is
not proof. Forge rechecks role, revocation, expiry, policy, subject and evidence
revision when recording a decision. Workspace stores at most transport intent
for recovery; it creates no second approval record or Mission store.

The earlier Forge `WORKSPACE_READ` grant still accepts only status reads. The
separate [Forge review producer contract](https://github.com/pcvantol/forge/blob/f4d3b269d54fd302a586cd8f41421c4d15e8c4d5/docs/architecture/FORGE_WORKSPACE_MISSION_REVIEW_HTTP_V1.md)
was protected-merged at `f4d3b269d54fd302a586cd8f41421c4d15e8c4d5`.
The [installed producer receipt](https://github.com/pcvantol/forge/issues/207#issuecomment-6016125785)
reports 14/14 real HTTP cases on the exact-main Forge wheel, two isolated
actors/scopes, replay and negatives. L3's FCI task remains separate.

### Exact producer join consumed by Workspace 2.8.6

Forge's owner provisions a private, revocable `forge-workspace-review-grant`
for one installed instance, authenticated actor, 1–32 existing Mission IDs and
expiry. Workspace's owner binds that Forge bearer to the same actor and Forge
instance with `workspace-server review-bind-issue`. The command probes the
actual Forge inbox, checks its exact actor/instance/Mission scope, writes a
separate private Workspace review token and stores the Forge token only under
the private Server root. The native app stores the Workspace token in its own
review Keychain account. The normal pinned Server read bearer is required as
well. Forge revocation is authoritative on every subsequent request.

| Method | Workspace Server route | Forge contract |
| --- | --- | --- |
| `GET` | `/v1/reviews` | `forge-workspace-review-inbox/v1`, exact scoped list |
| `GET` | `/v1/reviews/missions/{mission_id}` | Exact current item and fence |
| `POST` | `/v1/reviews/missions/{mission_id}/decisions` | `forge-workspace-review-decision/v1`, exact revisions and durable operation ID |
| `GET` | `/v1/reviews/missions/{mission_id}/decisions/{operation_id}` | `forge-workspace-review-operation/v1`, same-principal receipt |

Workspace Server requires both its pinned read bearer and the separate
`X-Workspace-Review-Grant` header. It validates every returned actor, Mission,
instance, requirement and operation digest, and stores only the outbound
transport intent in a private SQLite record before POST. The Client also saves
the exact intent before POST. After a lost response or restart it reads the
same operation ID and current Mission item. A 404 offers only an explicit retry
of the same operation and reason; a 409 reads back first and never turns a
conflict into optimistic success. Forge alone records the review decision and
releases any successor. Final acceptance and external gates never gain a local
Approve action.

## Workspace acceptance and evidence

| Area | Required result |
| --- | --- |
| Server | Authentication, instance pin, actor/scope isolation, producer-response validation, bounded safe text/evidence, denial and offline states, no credential exposure. Reads cause zero decision/provider/dispatch effects. |
| Decision | Explicit single confirmation, exact expected revisions and operation ID, no optimistic success, duplicate/concurrent/lost-response/restart recovery through the same Forge operation. Reject/amend/defer never cancel already running EP work. |
| Native | Authorized list and detail; search/filter/selection preservation; keyboard, focus and narrow-window behavior; system themes and en/nl/de/fr/es; existing conversation, pairing and Forge-status regressions covered. |
| Integration | Two isolated actor/scopes; real noneditable installed Workspace and Forge services, private storage, authentication, authorization, review logic and HTTP; positive approval/fence readback, reject/amend/defer and all relevant negative cases. Only external EP/LLM/OS boundaries may use declared test adapters. |
| Delivery | Full `bash scripts/validate.sh`; strict >80.2% executable-line coverage for each changed Swift and Python production file; independent exact-head Quality/Security; protected PR/merge; exact-main wheel and packaged ad-hoc app; real new GUI clicks and receipt/readback. TDE observation is reported separately. |

All test instances, principals and credentials are synthetic and disposable.
Signing/notarization, live Keychain successor, two-Mac trust, public release
and operational activation remain separate r81 gates. This subset does not
implement full GP, PRM, POL or external GP-X/CD support, create a Mission,
alter progression policy, perform EP submission or trigger a provider.

## Current qualification state

`PRODUCER_BINDING=QUALIFIED_FORGE_MAIN_F4D3B26` and
`WORKSPACE_INTEGRATED_DELIVERY=IN_PROGRESS`. The Workspace source tests cover
the native and Server safety states, but source tests and a fixture-only view
are not the installed vertical result. Exact-main two-product and real packaged
GUI qualification, exact-head independent review, protected merge and TDE
observation are recorded separately in the Workspace PR.
