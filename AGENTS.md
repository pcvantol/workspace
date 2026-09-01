# Workspace Agent Instructions

Start with [BOOTSTRAP.md](BOOTSTRAP.md), then inspect repository truth before
planning or changing Workspace.

Workspace is a first-class peer of Forge. Preserve these boundaries:

- Workspace owns its own product source, architecture, roadmap, governance,
  release lifecycle, and application state.
- Forge may plan or orchestrate work concerning Workspace but does not own it.
- Engineering Platform remains an external installed execution product; do not
  import its source or implement its consumer adapter without a bounded task.
- TDE remains a separate product; do not copy its implementation or product
  documents here.
- Generic AI-development contracts are consumed from the committed local
  projection in `docs/ai-development/`. Workspace owns only its local
  development extension and product semantics.

Before submitting a change, run `bash scripts/validate.sh`. Record the actual
validation and any TDE observation status in the pull request.
