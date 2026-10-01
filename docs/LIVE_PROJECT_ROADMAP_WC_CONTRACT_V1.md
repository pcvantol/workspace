# Live project roadmap: Workspace consumer contract V1

`PRM-W-CONTRACT` is the Workspace-owned offline consumer boundary for the
[live project roadmap](LIVE_PROJECT_ROADMAP_MANAGEMENT_V1_ROADMAP.md). It does
not implement a live view, peer adapter, release control, Mission scheduler or
project-loop qualification. The Forge `PRM-F-CONTRACT` producer subset remains
an external dependency; binding it requires a later exact contract/readback.

One project snapshot binds pagination to an owner revision. Mixed pages or an
invalid cursor are PARTIAL and STALE until a consistent resync; cached data is
read-only. Every item has a kind, typed ID, project scope, owner, revision,
availability and provenance. Capabilities, approved subjects, Candidates,
Expected work, actual Missions and history remain distinct. An Expected item
never gains a Mission ID. An approved subject is not released, eligibility is
not activation, and execution admission is a separate EP fact. An actual
Mission label requires a nonempty Mission ID and a Forge ACTIVATION receipt
bound to that exact Mission ID and approved-subject reference; a release
receipt or another Mission's receipt is insufficient.

The consumer displays separate approval, release, eligibility, activation and
execution evidence. A missing owner receipt remains unverified even if another
badge is green. Unknown counts stay unknown. Sorting or refreshing changes no
committed priority and submits no planning, Mission or EP mutation. A future
qualified command requires actor, exact project/subject/revision, stable
operation ID and authoritative owner readback. This contract cannot grant such
an operation or authorize a stale/offline projection.

The accompanying fixtures classify presentation and negative authority cases
offline. They are documentary checks, not browser or producer qualification.
