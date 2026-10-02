# Workspace

Workspace is a first-class, AI-native product for the developer and user
workspace experience: project and repository navigation, development-workflow
views, handoff surfaces, and Workspace-specific application state.

It is a peer of [Forge](https://github.com/pcvantol/forge), not a Forge
subcomponent. Forge may plan or orchestrate work concerning Workspace, but it
does not own Workspace source, architecture, roadmap, governance, or releases.

## Current maturity

This repository was established on 2026-09-01 after an evidence-based search
found no prior independent Workspace implementation history. The selected
LANE_4 slice now supplies an own read-only Server, thin CLI and browser Client.
It does not implement an Engineering Platform adapter or execution runtime.

## Local read-only Server

Create a private absolute data root, initialize it once, then start the Server:

```sh
mkdir -m 700 /absolute/private/workspace-data
workspace-server --root /absolute/private/workspace-data init
workspace-server --root /absolute/private/workspace-data inspect
workspace-server --root /absolute/private/workspace-data serve --port 8765
```

Open `http://127.0.0.1:8765/` using `workspace-client --url http://127.0.0.1:8765`.
The Client asks for the token in the root's private `token` file; it keeps the
token in the current page only. The Server listens on loopback. The optional
private `projects.json` catalogue format and state semantics are documented in
[the read-only Server contract](docs/WORKSPACE_SERVER_READONLY_V1.md).
`inspect` reads the private initialization state as `UNINITIALIZED`, `INCOMPLETE`
or `READY` without printing the token or changing files. An incomplete root
requires operator investigation; `init` refuses to overwrite it.
`workspace-server --root /absolute/private/workspace-data projects` prints the
same own catalogue projection as `GET /v1/projects`; invalid or unreadable
catalogue data exits nonzero without printing project rows. This local command
requires ownership of the private root and is not a Forge/EP transport.
Authenticated `GET /v1/capabilities` lists own HTTP reads and local-only
administration commands for the pinned instance. It makes no peer-availability
claim.
`workspace-server --root /absolute/private/workspace-data capabilities` reads
the same own inventory under private-root ownership without contacting a peer.
The local browser displays these own capabilities after connection, including
the HTTP/local-only distinction and the unqualified peer boundary.
`workspace-server --root /absolute/private/workspace-data openapi` prints the
same own API contract as authenticated `GET /v1/openapi.json`, using only the
installed package and private-root ownership; it does not start a Server.

## Entry points

- [Architecture](docs/ARCHITECTURE.md)
- [Proposed repository onboarding and qualification](docs/REPOSITORY_ONBOARDING.md)
- [Roadmap](ROADMAP.md)
- [Backlog](BACKLOG.md)
- [Provenance](WORKSPACE_PROVENANCE.md)
- [Development bootstrap](BOOTSTRAP.md)
- [Handoff navigation](HANDOFF.md)

## Boundaries

- Engineering Platform remains an independent execution product. A later
  Workspace adapter may use an installed Engineering Platform Local Consumer
  API; Workspace must not import Engineering Platform product source.
- Technical Debt Engine remains an independent product. Workspace may later
  own only Workspace-specific TDE configuration and evidence mapping.
- Generic AI-development contracts are not defined here. The committed local
  projection and Workspace development extension provide offline development
  navigation without requiring another checkout.
