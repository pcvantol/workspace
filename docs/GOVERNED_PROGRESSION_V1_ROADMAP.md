# Workspace governed progression roadmap

Scoped under [Workspace Roadmap](../ROADMAP.md) and the existing policy/governance
surfaces. Increment: `GOVERNED_PROGRESSION_AND_DELIVERY_AUTHORITY_V1`.
Design: [governed progression and external gates](GOVERNED_PROGRESSION_AND_EXTERNAL_GATES.md).
The shared documentary DAG is
`pcvantol/forge:docs/roadmap/governed-progression-v1.json`.

| Node | Owner | Depends on | Acceptance / status |
| --- | --- | --- | --- |
| GP-0 | Four product owners | none | Coordinated architecture; no active policy |
| GP-WC | Workspace | GP-0 | PLANNED: scoped settings/proposal and local/external requirement/decision consumer contracts |
| GP-W | Workspace | GP-WC, GP-Q | PLANNED: owner-backed review policy and decision UI, no duplicate external approval or local authority |
| GP-X | Forge/EP integration with declared external owner | GP-Q, GP-DC | External live proof consumed by Workspace before claiming real CD gate support |

GP-Q is the qualified Forge/EP progression/binding seam; GP-DC is the declared
project-owned delivery target/authority contract. Workspace does not own their
implementation or actual readiness.

```text
GP-0 -> GP-WC --+
GP-Q ----------+-> GP-W
GP-Q + GP-DC -> GP-X -> authoritative external evidence for the live view
```

Contract/fixture design may proceed independently. General external-CD support
is not required to deliver the first local progression UI; any displayed live
external gate needs the corresponding GP-X proof. Existing POL-WC/POL-W and
role-aware governance remain the parent capability families, not duplicate UIs.
Full Workspace UI is not a new first-Mission-canary gate. No executable programme
DAG, runtime schema, grants or budgets change in this documentary increment.
