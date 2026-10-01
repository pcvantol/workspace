# Workspace Engineering Method

Generic change, validation, handoff, branch, and repository-governance rules
are supplied by the committed AI-development projection. Workspace changes
must additionally remain bounded to one clear Workspace product, architecture,
governance, or maintenance objective.

The selected read-only Server slice adds its own runtime tests and wheel build.
`scripts/validate.sh` runs repository contracts, runtime tests, strict >80.2%
executable-line coverage per Workspace product module, and a built-wheel
metadata/asset/role check with a fresh non-editable installation outside the
checkout. The existing required CI invokes this same entrypoint. The wheel
build resolves declared build dependencies through pip; the generic contract
projection check remains offline. Live peer, installer and public release
evidence are not established by this slice.

Use squash merge, resolve review conversations, and delete merged branches.
