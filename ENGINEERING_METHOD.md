# Workspace Engineering Method

Workspace changes are pull-request based and must be bounded to one clear
product, architecture, governance, or maintenance objective. Repository
evidence is authoritative over prior conversations.

For the current foundation maturity, validation is limited to the tracked
documentation and repository contract checks in `scripts/validate.sh`.
Workspace has no application runtime, test suite, build pipeline, or TDE
evidence profile yet. Do not claim those capabilities until an implementation
increment establishes them.

Use squash merge, resolve review conversations, and delete merged branches.
