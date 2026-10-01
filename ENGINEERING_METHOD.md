# Workspace Engineering Method

Generic change, validation, handoff, branch, and repository-governance rules
are supplied by the committed AI-development projection. Workspace changes
must additionally remain bounded to one clear Workspace product, architecture,
governance, or maintenance objective.

The selected read-only Server slice adds its own runtime tests and wheel build.
`scripts/validate.sh` runs repository contracts and runtime tests. The
assignment's local qualification also measures executable-line coverage per
production module and builds/installs the wheel outside the checkout. The
existing CI runs repository validation; its coverage/build gate is still open.
Live peer, installer and public release evidence are not established by this
slice.

Use squash merge, resolve review conversations, and delete merged branches.
