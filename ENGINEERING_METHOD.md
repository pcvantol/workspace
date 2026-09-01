# Workspace Engineering Method

Generic change, validation, handoff, branch, and repository-governance rules
are supplied by the committed AI-development projection. Workspace changes
must additionally remain bounded to one clear Workspace product, architecture,
governance, or maintenance objective.

For the current foundation maturity, validation is limited to the tracked
documentation and repository contract checks in `scripts/validate.sh`.
Workspace has no application runtime, test suite, build pipeline, or TDE
evidence profile yet. Do not claim those capabilities until an implementation
increment establishes them.

Use squash merge, resolve review conversations, and delete merged branches.
