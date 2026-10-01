# GP-WC review and external gate consumer contract

The [versioned Workspace consumer contract](GOVERNED_PROGRESSION_WC_CONTRACT_V1.json)
and [offline fixtures](GOVERNED_PROGRESSION_WC_EXAMPLES_V1.json) define target
read models for effective review cadence, a Forge-owned review requirement,
the declared delivery target, and an external Human Gate. They are contract
evidence only. Forge/EP/CD producer bindings remain **UNQUALIFIED**; no live
policy, decision API, CD adapter, UI or deployment is supplied.

An authenticated principal sees an explicit project, subject and requirement.
Owner revision, evidence and availability travel with each projection. The
target's environment class comes from owner evidence; a changed UI label cannot
turn PROD into ACC. Effective cadence separates definition, assignment,
mandatory minimum and permitted override. A profile or visible role label is
never a grant.

Workspace may display both local review and external approval, but their
authority routes remain distinct. A Forge-owned local decision binds its exact
subject revision and operation ID. Until Forge's receipt is read back, the UI
shows pending. An external gate is shown with its actual owner and owner status;
Workspace never offers a second Approve control for that same requirement.
`OBSERVE_ONLY` has no request command. Qualified `REQUEST_AND_WAIT` can request
an external pipeline and wait, but its acknowledgement is neither approval nor
deployment proof.

Denied, unqualified, ambiguous, stale and offline actions fail closed. A lost
acknowledgement is resolved by the same operation ID without blind replay. A
stale display label cannot prevent that readback; the returned owner target
classification controls the refreshed view and later commands. A
review fence applies only to its owner-declared subject or Mission scope; a
local rejection cannot cancel already-running external work. These offline
examples do not qualify a real Forge/EP/CD producer or installed Workspace UI.
