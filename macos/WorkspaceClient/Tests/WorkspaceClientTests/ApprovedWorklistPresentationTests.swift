import XCTest
@testable import WorkspaceClient

final class ApprovedWorklistPresentationTests: XCTestCase {
    private let scope = ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-a", worksetID: "workset-1")

    private func facts(eligible: WorklistFact = .yes, active: WorklistFact = .no,
                       engineering: WorklistFact = .unknown, final: WorklistFact = .unknown,
                       completed: WorklistFact = .no) -> WorklistFacts {
        WorklistFacts(approved: .yes, released: .yes, eligible: eligible, active: active,
                      engineeringComplete: engineering, reviewAccepted: .notRequired,
                      finalAccepted: final, completed: completed)
    }

    private func item(_ id: String = "member-a", position: Int = 0,
                      owner: ApprovedWorklistScope? = nil, revision: String = "snapshot-1",
                      title: String? = "Résumé", mission: String? = nil,
                      subject: String = "subject-1", subjectRevision: String = "r1",
                      sourceRevision: String = "source-1", facts suppliedFacts: WorklistFacts? = nil,
                      blockers: [WorklistBlockReason] = []) -> ApprovedWorklistItem {
        let owner = owner ?? scope
        return ApprovedWorklistItem(
            key: ApprovedWorklistKey(forgeInstanceID: owner.forgeInstanceID, actorID: owner.actorID,
                                    worksetID: owner.worksetID, memberID: id),
            subjectID: subject, subjectRevision: subjectRevision, committedPosition: position,
            snapshotRevision: revision, sourceRevision: sourceRevision, missionID: mission,
            projectID: nil, title: title, facts: suppliedFacts ?? facts(), blockers: blockers)
    }

    private func snapshot(_ items: [ApprovedWorklistItem], owner: ApprovedWorklistScope? = nil,
                          membership: String = "membership-1", selector: String = "selector-1",
                          revision: String = "snapshot-1", observed: String = "2026-10-07T08:00:00Z",
                          complete: Bool = true, freshness: WorklistFreshness = .current,
                          continuation: WorklistContinuation = .unknown,
                          next: String? = nil) -> ApprovedWorklistSnapshot {
        ApprovedWorklistSnapshot(scope: owner ?? scope, membershipRevision: membership,
                                selectorRevision: selector, snapshotRevision: revision,
                                observedAt: observed, completeWithinScope: complete,
                                freshness: freshness, continuation: continuation,
                                nextMemberID: next, items: items)
    }

    func testLocalOrderSearchAndFiltersPreserveCommittedMembershipAndUnknownAttribution() {
        let first = item("member-z", position: 0, title: "Zulu")
        let later = item("member-a", position: 1, mission: "mission-real",
                         blockers: [WorklistBlockReason(kind: .dependency, code: "evidence_pending", explanation: "Proof not current")])
        let untitled = item("member-m", position: 2, title: nil)
        let rows = [first, later, untitled]
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "", filter: .all, sort: .committed), rows)
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "", filter: .all, sort: .title), [untitled, later, first])
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "", filter: .all, sort: .identifier), [later, untitled, first])
        XCTAssertEqual(rows.map(\.committedPosition), [0, 1, 2])
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "  resume  ", filter: .all, sort: .committed), [later])
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "PROOF", filter: .all, sort: .committed), [later])
        XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "mission-real", filter: .all, sort: .committed), [later])
        XCTAssertTrue(ApprovedWorklistPresentation.visible(rows, search: "outside", filter: .all, sort: .committed).isEmpty)
        XCTAssertNil(first.missionID)
        XCTAssertNil(first.projectID)
        let tied = [item("b", title: "same"), item("a", title: "same")]
        XCTAssertEqual(ApprovedWorklistPresentation.visible(tied, search: "", filter: .all, sort: .title).map(\.key.memberID), ["a", "b"])
    }

    func testEngineeringResultFinalReviewEligibilityAndCompletionRemainIndependent() {
        let ready = item("ready", position: 0)
        let active = item("active", position: 1, facts: facts(eligible: .unknown, active: .yes))
        let finalWait = item("wait", position: 2, facts: facts(eligible: .no, engineering: .yes, final: .no),
                             blockers: [WorklistBlockReason(kind: .finalAcceptance, code: "final_review", explanation: nil)])
        let completed = item("done", position: 3, facts: facts(eligible: .unknown, engineering: .yes, final: .yes, completed: .yes))
        let unknown = item("unknown", position: 4, facts: facts(eligible: .unknown, active: .unknown, completed: .unknown))
        let rows = [ready, active, finalWait, completed, unknown]
        let expected: [WorklistFilter: [ApprovedWorklistItem]] = [
            .all: rows, .eligible: [ready], .active: [active], .blocked: [finalWait],
            .completed: [completed], .unknown: [unknown]]
        for filter in WorklistFilter.allCases {
            XCTAssertEqual(ApprovedWorklistPresentation.visible(rows, search: "", filter: filter, sort: .committed), expected[filter])
        }
        XCTAssertEqual(finalWait.facts.engineeringComplete, .yes)
        XCTAssertEqual(finalWait.facts.completed, .no)
        XCTAssertEqual(finalWait.facts.finalAccepted, .no)
    }

    func testSelectionUsesExactActorWorksetAndRefreshedObservationWithoutFilterLoss() {
        let prior = item()
        let current = item(revision: "snapshot-2", subjectRevision: "r2")
        let latest = snapshot([current], revision: "snapshot-2")
        XCTAssertEqual(ApprovedWorklistPresentation.selected(prior.key, in: latest), current)
        XCTAssertTrue(ApprovedWorklistPresentation.visible(latest.items, search: "hidden", filter: .all, sort: .committed).isEmpty)
        XCTAssertEqual(ApprovedWorklistPresentation.selected(prior.key, in: latest), current)
        XCTAssertNil(ApprovedWorklistPresentation.selected(nil, in: latest))
        XCTAssertNil(ApprovedWorklistPresentation.selected(prior.key, in: nil))
        for foreign in [ApprovedWorklistScope(forgeInstanceID: "forge-2", actorID: "actor-a", worksetID: "workset-1"),
                        ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-b", worksetID: "workset-1"),
                        ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-a", worksetID: "workset-2")] {
            XCTAssertNil(ApprovedWorklistPresentation.selected(item(owner: foreign).key, in: latest))
        }
        XCTAssertNil(ApprovedWorklistPresentation.selected(item("outside").key, in: latest))
    }

    func testMixedSnapshotDuplicateMemberOrderAndUnknownNextFailClosedWithoutMerging() {
        var cache = WorklistObservationCache()
        let prior = snapshot([item()], continuation: .ready, next: "member-a")
        XCTAssertTrue(cache.accept(prior, for: scope))
        let mixed = snapshot([item(), item("member-b", position: 1, revision: "snapshot-2")], revision: "snapshot-2")
        XCTAssertFalse(cache.accept(mixed, for: scope))
        XCTAssertEqual(cache.snapshot, prior)
        XCTAssertEqual(cache.availability, .stale)
        XCTAssertTrue(cache.usingLastObservation)
        for invalid in [snapshot([item(), item(position: 1)]),
                        snapshot([item(), item("member-b")]),
                        snapshot([item()], next: "outside"),
                        snapshot([item(position: -1)]), snapshot([item("")]),
                        snapshot([item(subject: "")]), snapshot([item(subjectRevision: "")]),
                        snapshot([item(sourceRevision: "")]),
                        snapshot([item()], membership: ""), snapshot([item()], selector: ""),
                        snapshot([item()], revision: ""), snapshot([item()], observed: "")] {
            XCTAssertFalse(cache.accept(invalid, for: scope))
            XCTAssertEqual(cache.snapshot, prior)
        }
        let partial = snapshot([item("member-b", position: 1, revision: "snapshot-2")],
                               revision: "snapshot-2", complete: false, continuation: .blocked)
        XCTAssertTrue(cache.accept(partial, for: scope))
        XCTAssertEqual(cache.snapshot?.items.map(\.key.memberID), ["member-b"])
        XCTAssertEqual(cache.availability, .partial)
        XCTAssertFalse(cache.usingLastObservation)
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .partial)
    }

    func testScopedEmptyPartialStaleAndOfflineCacheNeverBecomeGlobalNoWork() {
        var cache = WorklistObservationCache()
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .unavailable)
        XCTAssertTrue(cache.accept(snapshot([item()]), for: scope))
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: [item()]), .hasItems)
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .noMatches)
        cache.failed(.offline, for: scope)
        XCTAssertTrue(cache.usingLastObservation)
        XCTAssertNotNil(cache.snapshot)
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .offline)
        cache.failed(.denied, for: scope)
        XCTAssertNil(cache.snapshot)
        XCTAssertFalse(cache.usingLastObservation)
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .denied)
        cache.failed(.unavailable, for: scope)
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .unavailable)
        XCTAssertTrue(cache.accept(snapshot([], continuation: .idle), for: scope))
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .emptyGrantedWorkset)
        XCTAssertTrue(cache.accept(snapshot([], complete: false), for: scope))
        XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .partial)
        for freshness in [WorklistFreshness.stale, .unknown] {
            XCTAssertTrue(cache.accept(snapshot([item()], freshness: freshness), for: scope))
            XCTAssertEqual(ApprovedWorklistPresentation.emptyState(cache, visible: []), .stale)
        }
        let foreign = ApprovedWorklistScope(forgeInstanceID: "foreign", actorID: "actor-b", worksetID: "other")
        cache.failed(.offline, for: foreign)
        XCTAssertNil(cache.snapshot)
        XCTAssertFalse(cache.accept(snapshot([item()]), for: foreign))
        XCTAssertNil(cache.snapshot)
        for invalidScope in [ApprovedWorklistScope(forgeInstanceID: "", actorID: "actor-a", worksetID: "workset-1"),
                             ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "", worksetID: "workset-1"),
                             ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-a", worksetID: "")] {
            XCTAssertFalse(snapshot([], owner: invalidScope).isCoherent(for: invalidScope))
        }
        XCTAssertFalse(snapshot([item(owner: foreign)]).isCoherent(for: scope))
    }
}
