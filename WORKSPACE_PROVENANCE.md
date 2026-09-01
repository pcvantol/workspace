# Workspace Provenance

## Decision

**Classification:** `D — NO_IMPLEMENTATION_HISTORY_EXISTS`

The canonical repository is `pcvantol/workspace`, created on 2026-09-01 with
`main` as its default branch. This is a new foundation repository, not a
history extraction or a replacement for Forge.

## Evidence

- `pcvantol/workspace` did not exist when the Phase 1C search began.
- GitHub searches under `pcvantol` found no Workspace, Forge Genesis, or
  Workspace prototype repository.
- The local `djconnect-workspace-polish` directory is non-Git and contains
  only `.DS_Store`.
- The only source directory named `forge/workspace` is a deliberately deferred
  namespace containing only `__init__.py`.
- Forge documents a Workspace product model and peer relationship, but no
  standalone Workspace implementation.

## Source and architecture provenance

| Field | Value |
| --- | --- |
| Prior implementation source | None found |
| Prior implementation SHA / root commit | Not applicable |
| Architecture source | Phase 1C authority decision plus Forge Workspace model (`docs/architecture/workspace-foundation.md`) as peer-boundary evidence only |
| Roadmap source | No pre-existing Workspace roadmap found |
| Promotion method | Minimal new repository foundation; no source history to promote |
| Known exclusions | Forge source/runtime, Engineering Platform source/runtime, TDE product docs/implementation, DJConnect product architecture, generic AI-development contracts |

## Relationships

Forge and Workspace are first-class peers. Forge may consume Workspace project
metadata or plan work for Workspace, but does not become the Workspace source,
governance, release, roadmap, or architecture authority.

Future Engineering Platform interaction is intentionally limited to:

```text
Workspace source -> Workspace consumer adapter -> Installed Engineering Platform
```

No adapter, consumer registration, credential, scope, or Engineering Platform
runtime integration is implemented by this repository foundation.
