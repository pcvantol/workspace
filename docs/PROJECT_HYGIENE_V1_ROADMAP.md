# Workspace Repository Health V1 roadmap

Increment: `PROJECT_HYGIENE_AND_REPOSITORY_RECONCILIATION_V1`.
Owning design: [Repository Health, chat and reconciliation](REPOSITORY_HEALTH_AND_RECONCILIATION.md).
Parent: [Workspace Roadmap](../ROADMAP.md).
Coordinated [documentary DAG](https://github.com/pcvantol/forge/blob/main/docs/roadmap/project-hygiene-v1.json).

| Node | Deliverable | Dependencies | Status |
| --- | --- | --- | --- |
| HY-WC | Health/chat/case/decision request and projection contracts with real actor/scope and evidence classification | HY-0 coordinated documentation | PLANNED |
| HY-WO | Read-only Repository Health and chat: explain, refresh, reconcile; no automatic Mission or deletion | HY-WC, Forge HY-F | PLANNED |
| HY-WM | Scoped cleanup proposal/decision and receipt/history UX | HY-WO, Forge/EP HY-Q | PLANNED |

HY-WC may proceed contract-first in parallel with EP observation. HY-WO does not
wait for destructive command support; unsupported mutation is absent/disabled
with an explanation. HY-WM requires the actual qualified authority/conditional
cleanup/receipt path, not just a green interface mock.

Required acceptance includes project isolation, stale/partial/offline inventories,
read versus reconciliation versus delete-intent separation, no Mission allocation
for a case, frozen bulk set, cancel/stale confirmation, retained/partial outcomes,
external owner routing, en/nl/de/fr/es and accessibility, live/history parity and
source/evidence freshness. Chat and view use the same owner-backed operation.

No Workspace UI is inserted before the first Forge/EP autonomy canary. These
nodes do not implement a client filesystem scanner, second planner, policy engine
or provider credential store. The source-only increment activates nothing.
