# Workspace repository onboarding and qualification

## Status and scope

**Status:** canonical target design; implementation and installed qualification remain PLANNED. This record and the [detailed project-bootstrap design](PROJECT_BOOTSTRAP_V1.md) define Workspace's product experience, not an executed onboarding operation or permission to provision resources. The [scoped roadmap](PROJECT_BOOTSTRAP_V1_ROADMAP.md) and [documentary DAG](PROJECT_BOOTSTRAP_V1_DAG.json) decompose the onboarding/control-plane lane of [ROADMAP.md](../ROADMAP.md).

The detailed contract resolves the formerly unspecified artifact-preview, Genesis/Managed adoption and promotion design. It does not claim runtime closure of those capabilities. EP B8R already owns committed project/repository identity and authenticated attachment; this replaces only this document's older wording that the declaration schema/registration were entirely future. A complete create/adopt/promotion product journey still requires new qualified composition.

## Entry points

| Choice | Target outcome |
| --- | --- |
| New Genesis project | Common local product/engineering foundation in an approved missing/empty target or unborn Git; no remote effects |
| Adopt local Genesis work | Explicitly reviewed local content/identity mapping, preserved history and local qualification |
| New Managed repository | Approved remote birth, project foundation and verified host governance |
| Adopt Managed repository | Actual remote inventory/drift review, protected changes and B8R attachment; no history recreation |
| Promote Genesis to Managed | Same project/authority IDs and ancestry, explicit publication and remote-governance proof |

Qualification-only is an independent purpose with explicit disposable-resource retention/deletion policy, not a mode or generic cleanup authorization. The exact target/effects are approved before execution. A remote failure cannot silently change mode. A local directory is selected through the eligible EP host, not inferred from the browser machine.

## Owning boundaries

Workspace owns human-facing drafts, conversations, views and permitted intents; Forge owns product meaning, artifact/contract selection, desired policy and readiness interpretation; EP owns accepted effect authorization, repository-host/local mutation, leases, validation, attachment and evidence. Project Agents provide scoped physical capabilities, not logical topology authority. Forge and Workspace do not command Agent filesystems directly or use peer CLI/import/SQL as a substitute for HTTP.

Logical identity stays in the EP-owned `.engineering-platform/repository.json`, using its supported packaged schema. Project and repository IDs and the single authority-repository relationship are portable; paths, server/Agent identities and credentials are not. Workspace display naming is not identity. Before a first commit, a reserved name/ID is shown as provisional; canonical registration follows validated committed declaration evidence. The detailed companion specifies how this avoids an identity/permission circular dependency.

## End-to-end experience

Describe product -> choose Genesis/Managed and target -> inspect/adoption mapping -> select installed baseline and profiles -> preview exact artifact and settings changes -> obtain applicable scoped decisions -> submit the same stable operation -> observe owning effects/readback -> show mode-specific readiness -> separately refine/approve a first Mission.

The authoritative artifact manifest and file contents are Forge-owned, not a second Workspace hardcoded template. Users see common product/engineering documents, conditional host assets, before/after hashes, source provenance and unresolved questions. Edits invalidate incompatible decisions. Existing project-owned files and dirty/staged/untracked work are preserved, never auto-overwritten or committed.

Genesis uses local validation and commit/reconciliation evidence, no fake remote CI/PR success. Managed birth has a reviewed absent-resource boundary before ordinary protected work; it cannot bypass existing branch rules. Managed adoption reads back real governance rather than treating requested settings as compliance. Promotion discloses selected history/privacy/license/visibility, preserves ancestry and switches effective mode only after full qualified result.

## Recovery, qualification and portability

Persist owning operation/plan/decision references, not a parallel execution queue. Duplicate request, lost acknowledgement, reconnect and cancellation read back the same operation. Partial effects, privacy-sensitive publication and unresolved ownership stay visible; no silent fresh repo, automatic remote deletion, force-push or database repair. Accepted, delivered, governance-qualified, project-ready and Mission-accepted are separate outcomes.

Qualification-only resources keep explicit purpose/identity, exact candidate/artifact/proof and eventual disposition. Deletion/archive needs its own applicable approval and cannot be inferred from a green test. User production projects are not disposable fixtures.

Multi-repository projects have one authority repo and independent children/results. No cross-repo atomicity or new parallel-mutation permission is implied. The first headless bootstrap and existing Mission-3 canary do not wait for Workspace UI. See [the PB-01..PB-40 test coverage mapping](PROJECT_BOOTSTRAP_V1_ROADMAP.md) for installed HTTP/UX, accessibility, five-language and failure-path qualification. Source checkout independence and safe portable manifests are mandatory; development repositories are not runtime template authorities.
