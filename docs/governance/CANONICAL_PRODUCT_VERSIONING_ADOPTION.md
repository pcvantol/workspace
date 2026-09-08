# Canonical product versioning adoption

Workspace adopts Forge Platform's [canonical product versioning policy](https://github.com/pcvantol/forge-platform/blob/main/docs/architecture/CANONICAL_PRODUCT_VERSIONING.md), policy v1.

`product-version.json` (`product=workspace`, `schema_version=1`, `version`) is
Workspace's only product-release version source. Its committed `2.3.0` baseline
is not publication evidence and does not alter Workspace architecture, future
EP adapter contracts or external protocols.

The helper has a read-only check and explicit patch/minor or exact-release
apply with an optional expected baseline. It rejects wrong product identity,
boolean schema values, malformed SemVer and duplicate JSON keys, and writes the
single manifest through temp-file replacement. It does not commit, push,
publish, qualify a release or decide compatibility.

The workflow is intentionally read-only. A token-created version commit has a
new SHA that needs its own protected qualification and cannot safely represent
exactly-once processing of push events. Automatic allocation stays disabled
until the existing protected delivery route binds an operation ID, policy
revision, lineage and expected head. Builds consume only the committed version.
