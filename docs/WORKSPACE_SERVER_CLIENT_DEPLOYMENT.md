# Workspace Server and Client deployment target

**Status:** Canonical target architecture; implementation and qualification remain separately governed.

The current selected #208 r81 implementation is a native macOS
`Workspace.app` with local rendering and a separate Python 3.14.x Workspace
Server. The desktop app requires no Python, Server data root or source checkout.
Its configured endpoint, client-owned secure token and pinned Server identity
must survive relaunch without silently rebinding. Loopback HTTP is permissible
for local qualification; nonloopback requires HTTPS and ordinary certificate
validation. Finder launch against an installed Server is the first visible
gate. A real two-Mac link, app signing/Keychain trust and qualified Forge reads
remain distinct gates.

### Native local candidate and installation boundary

The native Client source lives in `macos/WorkspaceClient`. A macOS builder runs
`bash scripts/validate.sh` and `bash scripts/build_macos_app.sh OUTPUT/Workspace.app`.
The latter bundles the SwiftUI executable and macOS metadata as a `.app`;
only system frameworks are linked. The builder's local ad hoc code signature
permits a local launch but is not Developer ID signing, notarization or
remote-Keychain qualification. The Client machine only receives the completed
`.app`, not Python, a Server data root or the development checkout.

In the 2 October local candidate check, a separately installed Python 3.14.8
Server 2.5.0 ran from an isolated venv and private data root outside the
checkout. Double-clicking the packaged Client 2.5.0 in Finder opened its own
macOS window and read
`/v1/identity`, `/v1/status`, `/v1/projects` and `/v1/capabilities` over
loopback. The visible demo row, Server version/READY state and capability
inventory came from those real responses. Server stop/restart produced an
honest unavailable/cached state and then fresh readback; Client quit/relaunch
recovered its pinned binding from its own Keychain namespace. This local
candidate evidence awaits protected merge. The Server still binds only
loopback; two-Mac HTTPS, trust, authorization and a Developer ID signed
candidate remain `NOT_RUN`.

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

## Installable software distribution — PyPI target

The owner-requested [PyPI distribution roadmap](WORKSPACE_PYPI_DISTRIBUTION_V1.md)
and [WPK delivery DAG](WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json) replace GitHub
source-bundle delivery as the target channel for installable Workspace software.
Keep Server/Client role mapping explicit; GitHub may retain historical releases
and evidence but is not an implicit software fallback. Names, wheel/sdist
packaging, Trusted Publishing, exact registry readback and installer consumption
remain PLANNED. No publication, stack choice or runtime delivery is claimed.
