# Workspace Server and Client deployment target

**Status:** Canonical target architecture; implementation and qualification remain separately governed.

Workspace Server is a headless installed, independently restartable service. It owns server-authoritative Workspace project/control/governance state in a Workspace central runtime-storage root outside Git/source checkouts, with its product-owned SQL database plus files, artifacts, logs, backups and cache. It exposes a versioned HTTP API over interface-neutral Workspace application services and is launchd-managed on macOS. It projects Forge/EP truth through their versioned authenticated HTTP APIs; it does not take planning, execution, queue, lease, evidence or repository authority and never reads a peer database.

Workspace Client is a separately installable frontend for client PCs. It discovers a candidate Workspace Server through LAN DNS-SD/mDNS or a configured/unicast/tailnet bootstrap endpoint, then authenticates and pairs as a Workspace user/session client. Pairing stores a pinned Workspace Server identity and trusted endpoint in client-owned secure storage; discovery is neither authorization nor a reason to silently change a binding. The client can be installed without an EP Project Agent.

Workspace Server also uses an explicit authenticated server-peer binding for Forge/EP HTTP APIs. That trust is separate from Workspace Client↔Workspace Server user/session trust and EP Project Agent↔EP Server host trust, even on a co-located machine. Stable identities, descriptors, capability negotiation and the no-secret discovery rule follow Forge Platform's [instance contract](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/INSTANCE_DISCOVERY_AND_PAIRING_CONTRACT.md).

The first Forge→EP→Forge autonomy canary needs no Workspace UI, Workspace Client distribution, LAN discovery or universal installer completion. Those are post-canary productization; Workspace remains an independent human governance/control plane throughout.

## HTTP-only peers and thin CLI ingress

The [transport design and scoped roadmap](WORKSPACE_HTTP_API_V1.md) and
[documentary DAG](WORKSPACE_HTTP_API_V1_DAG.json) refine this existing installed
Server lane. Workspace Client -> Workspace Server, Workspace Server -> Forge,
and Workspace Server -> EP use HTTP(S) only, including co-located deployments.
There is no peer CLI/import/SQL/File Inbox shortcut or unavailable-HTTP fallback.

Workspace CLI is its own administration/AI-automation ingress, parallel to HTTP,
over shared Workspace application services. Qualified local-only init/start/
recovery uses exact identity, locks and authority without requiring a running
HTTP server; it must not create a second writer or perform peer integration.
OpenAPI, implemented routes, operation inventory and derived Postman cases stay
in parity. The WH-CONTRACT/SERVICES/HTTP/CLI/PEERS/Q nodes remain PLANNED and do
not add a current live-canary prerequisite or change existing product ownership.
