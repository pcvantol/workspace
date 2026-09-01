# Workspace Architecture

## Product boundary

Workspace owns its application experience and its product-specific state:

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
| Engineering Platform | Independent execution product. A future adapter can call its installed Local Consumer API without importing EP source. |
| TDE | Independent trusted-delivery product. Workspace may later provide only a product-local profile/configuration and evidence mapping. |
| DJConnect | Independent product; no product architecture is owned here. |
| AI-development contracts | Future generic authority; no generic contract is created or copied here. |

## Explicit non-goals

This foundation does not add application behavior, a UI stack, an EP adapter,
EP Managed execution, credentials, runtime storage, TDE implementation, or
generic governance.
