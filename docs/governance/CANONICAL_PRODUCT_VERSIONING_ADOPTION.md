# Canonical product versioning adoption

Workspace adopts `BOOTSTRAP_RELEASE_CADENCE_V2` through
`workspace-bootstrap-release-cadence-v2`. V1 receipts remain immutable
historical evidence and are never reinterpreted.

A bounded engineering increment defaults to `PATCH`; documentation-only work
is explicit `NO_BUMP`; only an explicit capability boundary is `MINOR`; and
`MAJOR`/`EXACT` require applicable authority. Repair, requalification and the
protected merge are evidence for the same operation, never another allocation.

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
installed runtime to verify. The protected release workflow produces one exact
GitHub Release source bundle only after it qualifies the selected current
`main` SHA. Before any source-bundle publication mutation, it retains a
`workspace-release-<version>-<full-source-sha>` operation whose immutable
identity binds `workspace-production-release-v2`, the full protected-main
source SHA and the source-bundle SHA-256. Its `QUALIFIED` receipt is an asset
on a GitHub **draft** Release, not merely a short-lived Actions artifact. The
operation is serialized, refuses changed bytes or provenance under the same
identity, and is byte-compared with that draft receipt immediately before
publication. An existing GitHub Release or asset without the original matching
receipt fails closed.

The operation moves through `PREPARED`, `QUALIFIED`, `PUBLISHED`, optional
`CLEANUP_PENDING`, and `RELEASE_COMPLETE`. GitHub Release asset readback and a
digest comparison are prerequisites for `PUBLISHED`; a separately retained
release receipt records `RELEASE_COMPLETE` only after the operation-local
readback/download paths have been cleaned. A cleanup failure remains visible as
`CLEANUP_PENDING` and can be resumed using the same exact release identity.
`PUBLISHED` therefore never implies that cleanup or release closure succeeded.

The draft-qualified receipt, public source-bundle readback and subsequent
receipts provide durable publication evidence and make an interrupted run
resumable with the same operation and bytes. A source bundle is first uploaded
only to its matching draft Release; that release is made public only after its
qualified identity has been rechecked. `PUBLISHED` records the subsequent
public name-and-digest readback, while `RELEASE_COMPLETE` is recorded only after
the exact operation-local download and bundle paths have been removed. The
terminal transition can use the already-recorded digest after that cleanup; it
does not select a new artifact. No release, publication, installation, or
live-runtime qualification has been executed by this source change.

`--verify-release-source` is a read-only legacy candidate guard: it accepts
only `release-X.Y.Z`, requires that exact canonical version, and requires the
candidate HEAD to equal (not merely descend from) the externally approved source
revision. The production workflow uses the separate
`--verify-main-release-source` route, so a release branch may freeze a candidate
but cannot remain the exclusive source of a published Workspace version. Neither
helper authorizes publication. Workspace presently has no repository-local
protected version-preparation dispatcher, GitHub App, or EP qualification
integration capable of committing a prepared operation and binding hosted
qualification evidence to its resulting SHA.

Engineering Platform PR [#105](https://github.com/pcvantol/engineering-platform/pull/105)
is merged as a source-level bounded version-preparation adapter. It still does
not prove an installed writer, an active grant, protected merge delivery or
artifact publication.
