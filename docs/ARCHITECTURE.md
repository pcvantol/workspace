# Workspace Architecture

## Product boundary

Workspace Server owns shared, server-authoritative project and team state.
Workspace Client owns human-facing UX. Together, Workspace owns its
product-specific state and experience:

- project and repository navigation;
- development-workflow, queue, run, status, and report views;
- handoff surfaces; and
- Workspace-specific architecture, roadmap, governance, and releases.

The implementation stack is intentionally undecided: no prior Workspace
application source was discovered, so this repository does not infer one.

## External boundaries

| System | Boundary |
| --- | --- |
| Forge | Peer planner/orchestrator; may consume Workspace metadata and create plans concerning it, but does not own Workspace. |
| Engineering Platform | Independent execution authority. The Engineering Platform Project Agent and its Local Project Agent API contract are EP-owned. A future Workspace consumer adapter can call an installed API without importing EP source. Workspace Client-to-local-Agent use is bounded local UX only and never direct engineering execution. |
| TDE | Independent trusted-delivery product. Workspace may later provide only a product-local profile/configuration and evidence mapping. |
| DJConnect | Independent product; no product architecture is owned here. |
| AI-development contracts | Canonical generic authority consumed through the committed offline projection; no generic contract is authored here. |

## Explicit non-goals

This foundation does not add application behavior, a UI stack, an EP adapter,
EP execution, credentials, runtime storage, TDE implementation, or generic
governance.
