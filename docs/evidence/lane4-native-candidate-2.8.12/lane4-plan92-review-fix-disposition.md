Exact HEAD: `d5149c167c3d56c698dd9f24bbfaa9876432b06b`.

**QUALITY: CHANGES_REQUIRED**  
**SECURITY: CHANGES_REQUIRED**

One remaining **P2** affects both dispositions: [CandidateLocalStore.swift:63](/private/tmp/lane4-worklist-delivery-1090f25/macos/WorkspaceClient/Sources/WorkspaceClient/CandidateLocalStore.swift:63). If `mkdirat` succeeds and parent `fsync` fails, the directory remains. A subsequent save opens it as existing and skips that parent sync; final `fsync(dir)` does not synchronize the ancestor entry. Transport can therefore proceed without confirmed created-parent durability. Require successful ancestor synchronization on retries too.

Other earlier findings close:

- Descriptor-relative operations and ancestor no-follow protection are present.
- Completed A→B clears old presentation, preserves own form, rejects another turn’s proposal, and has a no-extra-POST control.
- Python/Swift correlate full original source, rationale, and Candidate projection on preview/register/recovery; current Candidate stays separate.
- Amended fixture and targeted negative controls are corrected.

**Validation evidence remains unconfirmed:** the available committed record reports **118 native + 1 isolated + 125 Python**, not 121. The requested exact-head log/result was not supplied; no broad tests were rerun.

Unchanged remainder retains the prior whole-slice assessment. Package/current-main finish remains separately pending.