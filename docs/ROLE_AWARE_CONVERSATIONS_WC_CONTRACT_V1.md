# RC-WC Workspace conversation consumer contract

The [versioned contract](ROLE_AWARE_CONVERSATIONS_WC_CONTRACT_V1.json) and
[offline examples](ROLE_AWARE_CONVERSATIONS_WC_EXAMPLES_V1.json) make the
Workspace-owned consumer boundary of RC-WC testable. They name target read
models and interaction outcomes, not Forge endpoint paths or a shipped chat.
Forge RC-FC producer bindings remain **UNQUALIFIED**. The existing
[delivery roadmap](ROLE_AWARE_CONVERSATIONS_V1_ROADMAP.md) retains its external
predecessor and all RC-W runtime nodes remain planned.

Workspace owns conversation navigation and presentation references. Forge owns
context, admitted sessions, proposals, artifact revisions and decisions.
Every projection carries its owner and availability. Context and decisions
retain source revisions and owner evidence; a displayed card does not become
an authoritative record. Requests use an authenticated principal and an
explicit or unambiguous project; advice mode never grants an operator role.

The consumer separates qualified and authorized capability from unsupported,
unqualified, denied and offline states. Loading, filtering, polling,
reconnecting, opening a modal or changing mode never invokes a provider.
Explicit send requires a stable operation ID and a qualified authorized
capability. After a lost response, the same operation is read back; absent an
ID the outcome remains uncertain and cannot be replayed blindly. Offline
drafts do not submit on reconnect.

A decision refers to an exact proposal/artifact revision and an owner receipt.
Pending receipt, stale revision and denied access are separate UI results.
Advice completion, transcript state and UX mode provide no approval or
engineering execution authority. These fixtures are offline contract tests;
they do not prove installed UI, Forge service behavior or runtime integration.
