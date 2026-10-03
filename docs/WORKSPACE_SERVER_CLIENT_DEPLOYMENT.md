# Workspace Server and Client deployment target

**Status:** Canonical target architecture; implementation and qualification remain separately governed.

The current selected #208 r81 implementation is a native macOS
`Workspace.app` with local rendering and a separate Python 3.14.x Workspace
Server. The desktop app requires no Python, Server data root or source checkout.
Its configured endpoint, client-owned secure token and pinned Server identity
must survive relaunch without silently rebinding. Loopback HTTP is permissible
for local qualification; nonloopback requires HTTPS and ordinary certificate
validation. Finder launch against an installed Server was the first visible
gate. The private signed 2.8.1 two-Mac and scoped Forge-read gates, plus the
separate signed 2.8.2 candidate artifact gate, have distinct evidence below;
durable deployment trust, signed successor behavior and public distribution
remain separate open gates.

### Native local candidate and installation boundary

The native Client source lives in `macos/WorkspaceClient`. A macOS builder runs
`bash scripts/validate.sh` and `bash scripts/build_macos_app.sh OUTPUT/Workspace.app`.
The latter bundles the SwiftUI executable and macOS metadata as a `.app`;
only system frameworks are linked. The builder's local ad hoc code signature
permits a local launch but is not Developer ID signing, notarization or
remote-Keychain qualification. The Client machine only receives the completed
`.app`, not Python, a Server data root or the development checkout.

For a private Developer ID qualification candidate, the same builder accepts
`--mode developer-id`, an exact protected-main source SHA, the SHA-1 of an
existing `Developer ID Application` identity, its ten-character team ID and an existing
notarytool Keychain profile. These values and the exclusive L1/L4 signing
window must be confirmed before invoking it. The mode rejects a dirty or
non-current source or noncanonical Workspace origin, a certificate name in place
of the exact SHA-1, missing identity/profile
arguments, and occupied output paths. It requires an explicit output path in
an owner-owned private directory and writes with a restrictive umask;
each signed build also uses a fresh private Swift scratch directory, ignoring
the shared development scratch override;
the actual signer and notarization credentials are validated by signing and
notarytool in the confirmed exclusive slot. It does not
fall back to ad hoc signing. It signs with hardened runtime and a secure
timestamp, checks the signed leaf against the requested SHA-1 as well as the team
and designated requirement, submits the archive to
Apple notarization, staples the app, assesses it with Gatekeeper and emits a
final ZIP and JSON manifest bound to source SHA, bundle ID, `.v2` Keychain
service, team, notary submission, app CDHash and final ZIP SHA-256. The app is
unsandboxed and needs no entitlements; no runtime exceptions are requested.
`scripts/verify_macos_app_candidate.py` independently checks the retained ZIP
and manifest, extracts the app, and repeats signature, designated requirement,
staple, Gatekeeper, bundle/version and no-Python-link checks. Keep both files
as one private qualification artifact pair; the manifest is not a public
release receipt.
The stable bundle ID is `com.pcvantol.workspace.native-client` and the current
Keychain service is `com.pcvantol.workspace.native-client.v2`. Source/packaging
checks are distinct from an actual Developer ID signature and from signed
Keychain behavior. The latter needs real first pairing, cancellation,
quit/relaunch and a correctly signed successor with the same team/bundle
requirement. The retained `.v1` items are not automatically removed or changed.

Host access and normal macOS HTTPS trust are independent of app signing.
Only a Finder-launched copy of the exact signed artifact on the client Mac can
qualify the native two-Mac path through the separately installed Server to the
scoped Forge read. Explicit-CA curl remains transport evidence only. Public
native software publication and the Python Server/PyPI lane stay separate.

In the 2 October local candidate check, a separately installed Python 3.14.8
Server 2.5.0 ran from an isolated venv and private data root outside the
checkout. Double-clicking the packaged Client 2.5.0 in Finder opened its own
macOS window and read
`/v1/identity`, `/v1/status`, `/v1/projects` and `/v1/capabilities` over
loopback. The visible demo row, Server version/READY state and capability
inventory came from those real responses. Server stop/restart produced an
honest unavailable/cached state and then fresh readback; Client quit/relaunch
recovered its pinned binding from its own Keychain namespace. This local app
evidence was protected-delivered in #117 and its responsive Keychain UI repair
in #118. PR #119 delivered explicitly bound TLS. At that local checkpoint the
native app's two-Mac system trust and a Developer ID signed candidate were
`NOT_RUN`.

### Private signed 2.8.1 candidate and two-Mac qualification — 3 October

From exact protected Workspace main
`f7ea37e90c28a993c4055805f7d3e699e658e519`, the confirmed and since
released L1/L4 slot produced one private Developer ID signed, Apple notarized,
stapled, Gatekeeper-accepted Workspace 2.8.1 ZIP. Its SHA-256 is
`eef134edad1fe8d2f3ddc8eeff3cd04d4310525dacc388a182ff71f83f1a6312`.
The copied MacBook ZIP had identical bytes and passed strict signature, staple
and Gatekeeper checks. The owner launched that exact app in Finder; it used no
Python, local Server, Server data root or checkout on the MacBook. The
independent installed Workspace and Forge servers used Python 3.14.8 on the
Mac mini. [The candidate receipt](https://github.com/pcvantol/forge/issues/208#issuecomment-5966704367)
retains the exact build/signing evidence; it is not a public release receipt.

For this temporary private qualification, the owner trusted the exact
`192.168.1.134` leaf in the MacBook Login Keychain for SSL only. The
certificate has `CA:FALSE`; the app used normal macOS certificate and hostname
validation, with an independent MacBook default-trust curl returning HTTP 200
and `ssl_verify_result=0`. The signed app showed `CONNECTED` to its pinned
Workspace Server 2.8.1 instance and `Forge read OBSERVED` for the exact
Forge 2.7.59 / `repo-1` read scope. Availability was `AVAILABLE`, while source
freshness remained honestly **`STALE`**. After the owner quit and reopened the
same signed app, a fresh process recovered the saved `.v2` Keychain binding and
reconnected. One interim `UNAUTHORIZED` Forge card was caused by a disposable
Forge process started through its generic operations API, which does not admit
the scoped Workspace read bearer; restarting the same installed Forge instance
through its normal Server route restored `OBSERVED` without changing any token,
grant or trust setting. [The MacBook readback](https://github.com/pcvantol/forge/issues/208#issuecomment-5966912860)
records the owner-supplied screenshot observations and exact scopes. The
temporary listeners are stopped. A newly signed successor version had not yet
been qualified at that checkpoint. `CURRENT` Forge source observation,
durable host trust and public native release remain `NOT_RUN`.

### Private signed 2.8.2 candidate artifact — 3 October

Protected Workspace main `5910824dbbc4a79f2152603dc6e516c02bc99971`
contains the 2.8.2 successor source, exact Developer ID SHA-1 selection and
correct signed-certificate extraction. One fresh, exclusive L1/L4 epoch-5 slot
produced a separate private Developer ID signed, Apple notarized, stapled and
Gatekeeper-accepted 2.8.2 ZIP. Its SHA-256 is
`72cd7d3d37cfc54d43d57e82e030530f0e6de49ed42cd128da2340db2b325e07`.
Independent extraction yielded byte-identical app contents. Strict/deep
signature, bundle/team requirement, authorized DER leaf SHA-1, secure
timestamp, hardened runtime, no unexpected entitlements, Apple Accepted
submission, staple validation and Gatekeeper all passed on the extracted app.
The [private artifact receipt](https://github.com/pcvantol/forge/issues/208#issuecomment-5970356007)
binds the ZIP, manifest, source, builder and app hashes. The exclusive lock
was released and L1's shared signer/Keychain resource returned after terminal
readback.

This qualifies the **signed artifact** only. No 2.8.2 Finder launch, live
`.v2` Keychain first pairing/cancellation/relaunch, 2.8.1→2.8.2 successor
preservation, normal-trust native two-Mac HTTPS/Forge read, durable host trust
or public release was exercised by the signing slot. Those gates remain
`NOT_RUN`; the earlier MacBook evidence applies to 2.8.1 only.

### Explicit HTTPS Server

The Workspace Server continues to default to `127.0.0.1` plaintext for local
qualification. A separate-Mac deployment must name one concrete IPv4
interface, one exact DNS/IP server name, and owner-held absolute certificate
and private-key files:

```
workspace-server --root /private/workspace-root serve --port 8765 \
  --bind 192.168.1.134 --tls-server-name server.example \
  --tls-cert /private/tls/server-cert.pem --tls-key /private/tls/server-key.pem
```

The private key must be mode 0600, and the certificate name must match the
Client's HTTPS endpoint under normal macOS certificate validation. The Server
rejects wildcard interface exposure and nonloopback plaintext. Its HTTP Host
and optional Origin must match the configured HTTPS name, while bearer token
and instance pin remain required for versioned data routes. Source and
installed-wheel local TLS tests use an ephemeral test certificate trusted only
inside the test process; they do not install trust on either Mac. No production
certificate or signer/Keychain resource is used by those tests.
The authenticated OpenAPI document from an HTTPS listener advertises the
configured HTTPS authority and actual port; it never advertises a plaintext
loopback address to a remote HTTPS Client. CLI OpenAPI remains the historical
local template because it has no active listener context.

### Two-Mac transport readback

After PR #119 merged, an installed Python 3.14 Server 2.6.0 on `macmini-m6`
listened at `192.168.1.134:8766` using a disposable one-day certificate with
that IP in its SAN. The separate `MBP-van-Peter` Mac reached it over LAN. Curl
on the client Mac validated the supplied temporary certificate with
`--cacert` (`curl ssl_verify_result=0`, meaning verification succeeded)
and an authenticated, instance-pinned `GET /v1/status` returned HTTP 200 and
the Server's real READY/UNCONFIGURED response. Without the test CA, TLS failed
before HTTP; with CA, missing bearer returned 401, wrong pin 409 and foreign
Host 403. The test did not disable certificate validation or install trust in
macOS. Test state and listener were removed. This closes the two-Mac Server
HTTP transport subset only. At this #119 checkpoint, packaged `Workspace.app`
remote readback under normal macOS system trust, Developer ID signing and
Keychain/trust behavior were still `NOT_RUN`; the later private native
qualification is recorded above.

An attempted native trust setup on the client Mac could not authorize the
disposable test CA without interactive approval. The partial certificate item
was removed and default certificate validation rejected the test Server.
At that earlier checkpoint this was a concrete client trust `NOT_RUN` gate,
not a remote app result. The owner later trusted a different exact temporary
leaf for SSL as recorded above.

### First Forge read — delivered Server subset and later native qualification

The Workspace Server 2.7.0, protected-delivered in #121, exposes authenticated
`GET /v1/forge/status`. It reads only Forge Server v1 `GET /v1/instance` and
`GET /v1/status` through a separately issued read bearer. The Forge endpoint,
expected instance ID, expected repository ID and token live in one owner-held
`forge-read-binding.json` record. The local `forge-read-configure`
administration command copies a previously issued token from an absolute
owner-only file into that Workspace data root without putting it in an
argument or response. It publishes the whole record atomically under a
private configuration lock, so a concurrent read cannot combine an endpoint
with another generation's token. Replacing a binding requires both expected
current identifiers and its revision, so concurrent stale replacements fail.
This command only
configures Workspace; it never reads Forge business data.

The consumer permits HTTP only to `127.0.0.1`. Any other Forge endpoint uses
HTTPS with default certificate and hostname verification, a three-second
timeout per read, bounded JSON and no redirect following. Both responses must
attest the read grant's exact instance/repository scope; their instance IDs
and product versions must agree with the saved pin. Workspace reports its own
retrieval time separately from Forge's source observation and preserves
`CURRENT`, `STALE`, `UNKNOWN` or `UNAVAILABLE` without converting an old
observation into a fresh one. Missing/invalid binding, denied/revoked grant,
wrong instance, unverified scope, TLS failure and unavailable producer are
distinct states. The new route does not grant Client writes or Forge authority.

Forge r23's exact producer contract was protected-delivered in Forge #231.
A separately installed Python 3.14 Workspace Server read a separately installed
Forge 2.7.59 process over HTTP, returning `OBSERVED` with the exact instance and
repository scope, current source freshness and distinct retrieval time; grant
revocation yielded `UNAUTHORIZED`. This closes the local installed two-Server
subset. The 2.8.0 packaged native Client candidate was double-clicked in Finder
and showed the installed Workspace Server's authenticated Forge `OBSERVED`
response for `repo-1`, including Forge 2.7.59, `AVAILABLE` and `CURRENT`. It
recovered the saved binding after quit and relaunch. The Workspace and Forge
Servers were separately installed in Python 3.14.8 environments outside their
checkouts; this local loopback result was protected-delivered in Workspace
PR #122/main `cffba509e0a5786f55544ad61fcd9cab5a78d2bf`. A SwiftUI
`GroupBox` in the connection panel prevented this
candidate's main window from opening on the test Mac; the native panels now
use an explicit SwiftUI card. A changed ad hoc signature also left the earlier
pre-release `.v1` Keychain test item awaiting macOS access, so the candidate
uses its own `.v2` Keychain service and requires one explicit re-pair. The old
item was retained. Developer ID signed Keychain behavior and remote two-Mac
native read were `NOT_RUN` at this #122 checkpoint; their later private
qualification is recorded above. The general Forge administrator bearer is
never accepted as an implicit Workspace read grant; the consumer requires the
scoped response attestation. No Forge project/Mission membership is inferred.

`Forget Server` removes the current `.v2` binding and token only. It does not
revoke a Server token or delete the retained pre-release `.v1` items. To remove
the earlier Client test pairing, use macOS Keychain Access on that Mac, search
the exact service `com.pcvantol.workspace.native-client.v1`, and review the
`server-binding` and `server-token` account items before deleting those two
items. This is an owner action for that earlier local pairing, not part of the
current Client's automatic cleanup. A prior app with access to the `.v1`
service can still use that retained token until it is removed or invalidated
at its Server.

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
