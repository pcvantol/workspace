# Workspace development extension

Workspace retains first-class peer identity, its product architecture/roadmap,
foundation-level TDE observation status, and its future installed-Engineering
Platform adapter boundary.

Workspace Server owns shared, server-authoritative project and team state.
Workspace Client owns human UX. A Client may run without an EP Project Agent,
and an EP Project Agent may run without a Client. A Client-to-local-Agent
connection is bounded local UX only; Workspace never directly executes
engineering work or bypasses EP admission.

The EP Local Project Agent API contract is owned by
`pcvantol/engineering-platform`. Workspace owns only a future consumer/adapter
implementation. No protocol is defined here.
