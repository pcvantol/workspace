# Workspace Bootstrap

## Repository identity

Workspace is the first-class repository `pcvantol/workspace`. It is not a
Forge subcomponent. Its provenance and current product maturity are recorded
in [WORKSPACE_PROVENANCE.md](WORKSPACE_PROVENANCE.md) and
[README.md](README.md).

## Local development entrypoint

Before a bounded change:

1. inspect the current branch, `HEAD`, remote state, and working-tree status;
2. read [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
   [ROADMAP.md](ROADMAP.md), and [AGENTS.md](AGENTS.md);
3. identify the affected product boundary and validation needed; and
4. run `bash scripts/validate.sh` before review.

This is temporary repository-local development guidance pending the future
family AI-development contract authority. It creates no generic authority and
does not authorize Engineering Platform Managed execution.
