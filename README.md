# Workspace

Workspace is a first-class, AI-native product for the developer and user
workspace experience: project and repository navigation, development-workflow
views, handoff surfaces, and Workspace-specific application state.

It is a peer of [Forge](https://github.com/pcvantol/forge), not a Forge
subcomponent. Forge may plan or orchestrate work concerning Workspace, but it
does not own Workspace source, architecture, roadmap, governance, or releases.

## Current maturity

This repository was established on 2026-09-01 after an evidence-based search
found no prior independent Workspace implementation history. It currently
contains product foundation and provenance only; it does not implement
Workspace behavior, an Engineering Platform adapter, or an execution runtime.

## Entry points

- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](ROADMAP.md)
- [Backlog](BACKLOG.md)
- [Provenance](WORKSPACE_PROVENANCE.md)

## Boundaries

- Engineering Platform remains an independent execution product. A later
  Workspace adapter may use an installed Engineering Platform Local Consumer
  API; Workspace must not import Engineering Platform product source.
- Technical Debt Engine remains an independent product. Workspace may later
  own only Workspace-specific TDE configuration and evidence mapping.
- Generic AI-development contracts are not defined here. Until the family
  contract repository exists, Workspace keeps only its local development
  context.
