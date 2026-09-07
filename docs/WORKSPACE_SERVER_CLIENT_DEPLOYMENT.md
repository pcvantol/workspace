# Workspace Server and Client deployment target

**Status:** Canonical target architecture; implementation and qualification remain separately governed.

Workspace Server is a headless installed, independently restartable service. It owns server-authoritative Workspace project/control/governance state in a Workspace central runtime-storage root outside Git/source checkouts, with its product-owned SQL database plus files, artifacts, logs, backups and cache. It exposes a versioned HTTP API over interface-neutral Workspace application services and is launchd-managed on macOS. It projects Forge/EP truth through their public APIs; it does not take planning, execution, queue, lease, evidence or repository authority and never reads a peer database.

Workspace Client is a separately installable frontend for client PCs. It discovers a candidate Workspace Server through LAN DNS-SD/mDNS or a configured/unicast/tailnet bootstrap endpoint, then authenticates and pairs as a Workspace user/session client. Pairing stores a pinned Workspace Server identity and trusted endpoint in client-owned secure storage; discovery is neither authorization nor a reason to silently change a binding. The client can be installed without an EP Project Agent.

Workspace Server also uses an explicit authenticated server-peer binding for Forge/EP APIs. That trust is separate from Workspace Client↔Workspace Server user/session trust and EP Project Agent↔EP Server host trust, even on a co-located machine. Stable identities, descriptors, capability negotiation and the no-secret discovery rule follow Forge Platform's [instance contract](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/INSTANCE_DISCOVERY_AND_PAIRING_CONTRACT.md).

The first Forge→EP→Forge autonomy canary needs no Workspace UI, Workspace Client distribution, LAN discovery or universal installer completion. Those are post-canary productization; Workspace remains an independent human governance/control plane throughout.

