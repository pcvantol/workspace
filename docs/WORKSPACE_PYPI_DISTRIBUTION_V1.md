# Workspace PyPI distribution V1

**Owner:** Workspace. **Status:** PLANNED product-backlog/roadmap refinement.
**Recorded:** 13 September 2026. **Version effect:** NO_BUMP documentation only.
[Delivery DAG](WORKSPACE_PYPI_DISTRIBUTION_V1_DAG.json).

## Baseline and owner decision

At source `36d294836cb653361fda3972de38acce3d2970f8`, the
[production workflow](../.github/workflows/workspace-production-release.yml)
qualifies a Git source archive for GitHub Release publication. It is not an
installed Workspace wheel. The [architecture](ARCHITECTURE.md) leaves the
application stack undecided and the [deployment target](WORKSPACE_SERVER_CLIENT_DEPLOYMENT.md)
separates Server and Client. Source-bundle qualification does not prove either
runtime, and this record does not claim publication or installation.

The owner requests PyPI, rather than GitHub Release source bundles, as the
canonical distribution channel for installable Workspace software. Implement
that transition through the existing product-owned release-operation flow;
do not add a parallel publisher. Existing source-bundle versions and receipts
remain immutable historical evidence. GitHub may retain tags, release notes
and qualification/closure receipts, but is not a silent alternative source of
new installable Workspace packages after cutover.

WPK-IDENTITY must resolve available, owner-controlled PyPI project names and a
versioned mapping of distribution names, import packages, entrypoints and
Server/Client roles. Do not assume the generic name `workspace` is available,
use an unrelated project, or publish a placeholder source archive as a working
application. Both requested roles must have an explicit distribution plan;
one distribution with supported role entrypoints or separate distributions is
a packaging decision, not a new runtime authority. PyPI distribution does not
silently choose the entire frontend stack. Any genuine native-client packaging
incompatibility requires an explicit owning decision rather than silently
leaving Client on the old GitHub-only route or omitting it.

## Acceptance

WPK-PACKAGE supplies build metadata, wheel and sdist for the selected Python
distribution(s), canonical product-version projection, licensed packaged assets,
correct dependencies/entrypoints and declared Python/platform compatibility.
Build/install the wheel outside the source checkout in an isolated product
venv and prove the advertised Server/Client slice works without implicit source
imports. A rebuild from sdist must be installable and semantically qualified;
bitwise reproducibility is claimed only when separately proven. Match the
qualified managed-Python identity when entering a Platform composition.

WPK-PUBLISH replaces the source-bundle publication stage, preserving the
existing exact-main, version-operation, candidate, quality/security and
immutable artifact/receipt gates. Reuse the canonical cross-product semantics
already used by Forge and EP, with product-specific adapters rather than
copying divergent workflow logic. Use PyPI Trusted Publishing with an explicitly
registered repository/workflow/environment identity and scoped OIDC permission.
The package namespace and publisher must actually be configured before release;
this design neither enrolls a publisher nor stores credentials.

WPK-READBACK verifies the exact published wheel AND sdist bytes/digests and
metadata, re-downloads and installs the published wheel outside checkout, and
binds registry, version, source, runtime qualification and artifact evidence.
Keep PREPARED, QUALIFIED, PUBLISHED, CLEANUP_PENDING and RELEASE_COMPLETE
semantically distinct. A post-publication cleanup failure cannot erase the
publication fact or cause another version allocation; resume the same operation.
Same-version/different-byte conflicts, partial uploads, lost acknowledgements,
revoked publisher and retry after publication are explicit negative cases.
Never upload rebuilt different bytes under an existing identity.

WPK-CONSUMER supplies qualified artifact identities for Forge Platform's signed
composition, documentation and supported install instructions. No hardcoded
unqualified package, implicit network-latest dependency, GitHub-bundle fallback
or source checkout becomes a production installation. A composition can consume
only the roles and exact artifacts actually qualified; client-only installation
must not imply an EP Agent or local server. Readback/publication and real
installation remain separate evidence.

## Sequence and future qualification

WPK-IDENTITY -> WPK-PACKAGE -> WPK-PUBLISH -> WPK-READBACK -> WPK-CONSUMER.
All nodes are PLANNED. Identity/packaging work need not wait for complete UI;
publication of a usable role requires that role's real installed entrypoints,
assets, dependencies and API capabilities. There is no reverse dependency on
Platform installer completion and no first Forge autonomy-canary prerequisite.

| Case | Future evidence |
| --- | --- |
| WPK-T01 | Role/name/version mapping, metadata and isolated wheel/sdist installation with no checkout imports. |
| WPK-T02 | Exact main/version/qualification checks; wrong publisher/environment/scope fails closed. |
| WPK-T03 | Partial publication, acknowledgement loss, same-version conflict and idempotent operation resume. |
| WPK-T04 | Download hashes, published-wheel install and retained cleanup failure/closure evidence. |
| WPK-T05 | Composition consumes only qualified PyPI identities, including client-only; no GitHub software fallback. |
| WPK-T06 | Workflow projections retain canonical semantics and required controls without independent version allocation. |

Reference for future adapter implementation: [PyPI Trusted Publishing](https://docs.pypi.org/trusted-publishers/)
and [publisher configuration](https://docs.pypi.org/trusted-publishers/adding-a-publisher/).
No workflow, package version, runtime, credentials, publisher, release, service
or current Mission is changed here. Documentary tests are not packaging or
publication qualification.
