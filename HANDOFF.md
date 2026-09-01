# Workspace handoff

This is Workspace's local handoff navigation entrypoint. It does not restate
the generic handoff contract.

1. Start with [BOOTSTRAP.md](BOOTSTRAP.md), the committed generic projection,
   and [the Workspace development extension](docs/ai-development/WORKSPACE_DEVELOPMENT_EXTENSION.md).
2. Review the [architecture](docs/ARCHITECTURE.md), [roadmap](ROADMAP.md),
   [backlog](BACKLOG.md), and [provenance](WORKSPACE_PROVENANCE.md).
3. Validate a bounded change with `bash scripts/validate.sh` and record the
   repository-specific result in the handoff.

Workspace is a first-class peer of Forge. It does not make an Engineering
Platform source checkout a runtime dependency.
