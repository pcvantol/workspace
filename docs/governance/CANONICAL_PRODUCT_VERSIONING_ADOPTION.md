# Canonical product versioning adoption

Workspace adopts Forge Platform's [canonical product versioning policy](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/CANONICAL_PRODUCT_VERSIONING.md), policy v1.

`product-version.json` (`product=workspace`, `schema_version=1`, `version`) is
Workspace's only product-release version source. Its committed `2.3.0` baseline
is not publication evidence and does not alter Workspace architecture, future
EP adapter contracts or external protocols.

The helper has a read-only check, a read-only `--plan`, and explicit
patch/minor or exact-release apply. An apply requires an operation ID, policy
revision, source-event lineage, expected source HEAD and expected baseline. It
persists a small tracked `.version-operations/<operation-id>.json` receipt
alongside the only allowed projection, `product-version.json`. Repeating the
same operation is idempotent; changed inputs are a conflict. If interruption
occurs after the manifest replacement but before its receipt, the same
operation can only recover the already-determined result, never derive another
bump.

The helper rejects wrong product identity, boolean schema values, malformed
SemVer and duplicate JSON keys, and writes each file through temp-file
replacement. It validates the operation before writes, but two replacements
are not a multi-file transaction: no partial local result may be published.
The delivery route must commit the manifest and receipt together, then qualify
that exact SHA. The helper does not commit, push, publish, qualify a release or
decide compatibility.

The workflow is intentionally read-only. A token-created version commit has a
new SHA that needs its own protected qualification and cannot safely represent
exactly-once processing of push events. Automatic allocation stays disabled
until the existing protected delivery route commits and qualifies the complete
operation. Builds consume only the committed version. A candidate patch number
is not release compatibility or publication authority; major changes require an
explicit approved exact-release operation.

For the current foundation-only product there is no package artifact or
installed runtime to verify. `--verify-release-source` is a read-only guard for
a future authorized publication route: it accepts only `release-X.Y.Z`, requires
that exact canonical version, and requires the candidate HEAD to equal (not
merely descend from) the externally approved source revision. It neither
authorizes a branch nor publishes an artifact. Workspace presently has no
repository-local protected version-preparation dispatcher, GitHub App, or EP
qualification integration capable of committing a prepared operation and
binding hosted qualification evidence to its resulting SHA.
