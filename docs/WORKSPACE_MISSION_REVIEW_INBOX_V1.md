# Native Missions & reviews — selected consumer boundary

`DIRECTIVE_ID=L4-MISSION-REVIEW-INBOX-V1-20261006`  
`ASSIGNMENT=L4-WORKSPACE-NATIVE-CLIENT-HTTP-V1-20261002`  
`OWNER_REGISTER=pcvantol/forge#208`  
`R81_PLAN_REVISION=85`  
`NODE_SUBSET=GP-WC/GP-W_LOCAL_SERIAL_REVIEW`  
`PRODUCER_JOIN=L4-L3-GP-REVIEW-INBOX-V1-20261006`

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

The review consumer capability is **not present on the pinned Forge main**
`aec9c5c678209f216cdf2a62c5a2fdc0b76d196d` (2.7.65). On that source,
`WORKSPACE_READ` accepts only `GET /v1/instance` and `GET /v1/status`.
`GET /v1/missions/{mission_id}/progression` and
`POST /v1/missions/{mission_id}/progression-decisions` use the ADMIN route and
an admin principal. Their existence does not authorize Workspace use. No
admin token, broad proxy, actor-name substitution, SQL/CLI fallback or
project-attribution guess may bridge this gap.

### Exact producer join required from L3

L3's sole Forge writer owns the smallest versioned consumer seam, without
interrupting its selected FCI work or changing the existing status grant:

1. An owner-provisioned, revocable capability/principal bound to Forge
   instance, authenticated actor, explicit Mission set or verified project
   scope, role and expiry; independent actors/scopes cannot borrow one another's
   reviews. An allowed empty subset is distinguishable from a global empty set.
2. A bounded read of authorized Mission identity and current review
   requirements, exact Action/result and subject/evidence/policy revisions,
   blocker/fence scope, supported outcomes, status and safe typed evidence
   references. Unknown facts remain unknown. The producer identifies the
   review authority and distinguishes final Mission acceptance and external
   gates; external gates never gain a local Approve control.
3. One decision command bound to actual authenticated principal, capability,
   Forge instance, Mission/requirement/subject, expected revisions, outcome
   and durable operation ID. The owning service rechecks these at mutation
   time, returns a receipt, and makes an identical operation safely replayable.
4. A readback by that same operation ID and a current requirement/fence read
   after lost response or restart. A conflicting payload for an existing
   operation fails closed; Workspace never sends a fresh decision identity as
   a blind retry. Supported owner provisioning/revocation and negative HTTP
   examples are part of the handoff.

The exact wire schema, route names, producer source pin and qualification
receipt must come from L3. Workspace will map only that qualified contract;
this document does not assert a Forge endpoint or grant already exists. The
separate coordinator post to Forge #207 has not been published at this
checkpoint; this Workspace record does not claim L3 acknowledgement.

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

`PRODUCER_BINDING=UNQUALIFIED` and `INTEGRATED_DELIVERY=NOT_RUN` at selection.
Independent Workspace implementation/tests may proceed. A fixture-only view,
disabled decision controls or source tests are not evidence of the installed
vertical result.
