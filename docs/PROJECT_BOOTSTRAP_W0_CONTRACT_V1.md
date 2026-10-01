# PB-W0 Workspace onboarding intent contract

This contract-first slice defines the five user choices and the capability
families a future Workspace Client/Server must ask the owning products to
qualify. The machine-readable contract is
[`PROJECT_BOOTSTRAP_W0_CONTRACT_V1.json`](PROJECT_BOOTSTRAP_W0_CONTRACT_V1.json).
It is not an API endpoint, a producer capability declaration, a project
reservation, or a permission grant. Exact Forge/EP operation names, versions,
authentication and evidence must be bound by PB-W1 from qualified producers.

Each journey has a target class, required owner capability families and an
effect owner. Workspace may save a draft and present intent; EP owns repository
and host effects, Forge owns the artifact plan and project-readiness meaning.
The Client offers submission only from a fresh, exact-scope capability snapshot
with a qualified owner operation, frozen plan digest, applicable decision
receipts and stable operation ID. Unsupported, unavailable, denied or stale
capability must remain visible and cannot trigger a mode fallback or guessed
endpoint. A lost acknowledgement reads back the same operation.

New and adopted Genesis journeys forbid remote effects. Managed creation and
adoption need an explicit remote scope and approval. Promotion additionally
requires history-publication review and preserves existing project/repository
identity. Before owner readback, new identities are provisional; a Workspace
display name is never the EP-owned committed declaration. Accepted work is not
project readiness, and entering a project does not start a Mission.

The contract uses symbolic capability **families** deliberately: it declares
what the UI needs to know and which owner must supply it, while PB-W1 remains
blocked on compatible Forge PB-F0 and EP PB-E0 contracts. No producer API,
runtime, UI, provider, credentials, public repository or installation is
implemented by PB-W0.
