# Policy & Automation: Workspace consumer contract V1

`POL-WC` is an offline, Workspace-owned consumer contract under
[`POL-0`](POLICY_AND_AUTOMATION.md). The machine-readable contract and fixtures
pin the intended projection and failure vocabulary. They do not assert that an
owner policy endpoint, grant, decision or activation exists. `POL-W` and
cross-product `POL-Q` remain PLANNED.

Workspace may display owner-qualified definitions, assignments, effective
resolutions, run snapshots, proposals, decisions and activation receipts as
separate objects. Every projection identifies its owner, exact scope,
revision/digest where applicable, availability and freshness. The owner,
not a Workspace role label or cached projection, enforces any command.
Presentation of a proposal or impact preview never implies activation. A
cross-owner view can be partially active; it must show each owner's actual
receipt separately. Existing grants, consumed budgets and in-flight run
snapshots are not rewritten by a new policy revision.

Future commands require a qualified authenticated owner HTTP operation, an
authenticated actor, exact scope, expected revision and stable operation ID.
Loss of acknowledgment calls for readback of that same operation when the owner
is reachable, not blind retry. While offline, the operation remains uncertain
and its identity is kept for later readback. Missing owner receipts remain
pending. Offline or stale projections
can explain prior state but cannot authorize a change. There is no peer SQL,
CLI fallback, local grant, source import, direct provider call or execution
route in this contract.

`scripts/validate_policy_automation_wc.py` checks contract invariants and
classifies deterministic positive and negative fixtures. Its result is
documentary test evidence only; it does not qualify owner producers or the UI.
