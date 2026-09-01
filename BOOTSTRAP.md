# Workspace Bootstrap

## Repository identity

Workspace is the first-class repository `pcvantol/workspace`. It is not a
Forge subcomponent. Its provenance and current product maturity are recorded
in [WORKSPACE_PROVENANCE.md](WORKSPACE_PROVENANCE.md) and
[README.md](README.md).

## Local development entrypoint

Before a bounded change:

1. read the committed generic projection in
   `docs/ai-development/GENERATED_PROJECTION.md`;
2. read `docs/ai-development/WORKSPACE_DEVELOPMENT_EXTENSION.md` and then
   [README.md](README.md), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
   [ROADMAP.md](ROADMAP.md), and [AGENTS.md](AGENTS.md);
3. identify the affected Workspace product boundary and validation needed; and
4. run `bash scripts/validate.sh` before review.

The committed projection is the generic authority and requires no sibling
checkout or network access. This local entrypoint does not authorize
Engineering Platform execution.
