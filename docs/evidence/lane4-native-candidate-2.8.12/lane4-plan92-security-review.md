HEAD: `9dcf16d1d392cab7191a16636f13489e3890e888`
Base: `3c29fc377abf2dac5b5aec49dfbac2897fa7e8f6`

**SECURITY=P2 — two actionable storage findings.**

1. **Ancestor symlinks and directory replacement are not fenced.** [CandidateLocalStore.swift:51](/private/tmp/lane4-worklist-delivery-1090f25/macos/WorkspaceClient/Sources/WorkspaceClient/CandidateLocalStore.swift:51) checks only the final directory; subsequent absolute-path opens and rename resolve ancestors again. `O_NOFOLLOW` protects only the final component. A symlinked ancestor or directory replacement can redirect private drafts and pending intents. **Fix:** validate the directory chain without following symlinks, pin a verified directory descriptor, and use descriptor-relative `openat`/`renameat`/`unlinkat`.

2. **Pending-intent persistence is atomic but lacks directory durability.** [CandidateLocalStore.swift:84](/private/tmp/lane4-worklist-delivery-1090f25/macos/WorkspaceClient/Sources/WorkspaceClient/CandidateLocalStore.swift:84) synchronizes the temporary file and renames it without synchronizing the containing directory. A crash can lose the persisted original intent after transport has begun, undermining restart recovery and the pending-original fence. **Fix:** synchronize the pinned directory after rename and propagate failure before permitting transport.

No P1 found. The selected consumer routes retain separate Candidate authority; this review found no approval/start fallback or locale-derived authority.

Read-only source review only: no edits, delegation, credentials, memory access, tests, or escalation. The recorded `118 native + 1 isolated + 125 Python` and coverage PASS claims were not independently rerun. Installed, package, and fresh exact-main evidence gates remain separate.