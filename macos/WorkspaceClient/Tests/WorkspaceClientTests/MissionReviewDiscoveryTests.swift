import XCTest
@testable import WorkspaceClient

final class MissionReviewDiscoveryTests: XCTestCase {
    private func item(mission: String = "mission-b", requirement: String = "review-2",
                      revision: String = "r2", project: String? = nil,
                      title: String? = "Résumé", action: String? = "Action delivered",
                      reason: String? = "Awaiting review",
                      phase: MissionReviewPhase = .waitingForReview,
                      authority: MissionReviewAuthority = .forge,
                      freshness: MissionReviewFreshness = .current,
                      outcomes: Set<MissionReviewOutcome> = [.approve, .reject]) -> MissionReviewItem {
        MissionReviewItem(
            key: MissionReviewKey(missionID: mission, requirementID: requirement),
            subjectID: "action-1", subjectRevision: revision, projectID: project,
            title: title, actionResult: action, waitingReason: reason, phase: phase,
            authority: authority, freshness: freshness, allowedOutcomes: outcomes,
            forgeInstanceID: "forge-1", actorID: "reviewer-1",
            subjectDigest: "sha256:" + String(repeating: "a", count: 64),
            missionStateRevision: 2, currentMissionRevision: 2,
            evidenceDigest: "sha256:" + String(repeating: "b", count: 64), policyRevision: "policy-r1")
    }

    func testSearchFilterAndDeterministicOrderWithoutProjectInference() {
        let other = item(mission: "mission-a", requirement: "review-1", title: nil,
                         phase: .decisionRecorded, outcomes: [])
        let waiting = item(project: nil)
        let items = [waiting, other]
        XCTAssertEqual(MissionReviewDiscovery.visible(items, search: "", filter: .all).map(\.key.missionID),
                       ["mission-a", "mission-b"])
        XCTAssertEqual(MissionReviewDiscovery.visible(items, search: "resume", filter: .waiting), [waiting])
        XCTAssertEqual(MissionReviewDiscovery.visible(items, search: "delivered", filter: .waiting), [waiting])
        XCTAssertEqual(MissionReviewDiscovery.visible(items, search: "review-1", filter: .recorded), [other])
        XCTAssertTrue(MissionReviewDiscovery.visible(items, search: "missing", filter: .all).isEmpty)
        XCTAssertNil(waiting.projectID)
    }

    func testSelectionSurvivesFilterAndUsesRefreshedRevision() {
        let prior = item()
        let refreshed = item(revision: "r3", freshness: .stale)
        let hidden = MissionReviewDiscovery.visible([prior], search: "not present", filter: .all)
        XCTAssertTrue(hidden.isEmpty)
        XCTAssertEqual(MissionReviewDiscovery.selected(prior.key, in: [refreshed]), refreshed)
        XCTAssertNil(MissionReviewDiscovery.selected(nil, in: [prior]))
        XCTAssertNil(MissionReviewDiscovery.selected(MissionReviewKey(missionID: "other", requirementID: "x"),
                                                     in: [prior]))
        XCTAssertFalse(refreshed.mayOffer(.approve))
    }

    func testOutcomeEligibilityFailsClosedForAuthorityFreshnessAndMissingSubject() {
        let allowed = item(outcomes: [.approve, .deferred])
        XCTAssertTrue(allowed.mayOffer(.approve))
        XCTAssertTrue(allowed.mayOffer(.deferred))
        XCTAssertFalse(allowed.mayOffer(.reject))
        XCTAssertFalse(item(authority: .external).mayOffer(.approve))
        XCTAssertFalse(item(authority: .unknown).mayOffer(.approve))
        XCTAssertFalse(item(freshness: .stale).mayOffer(.approve))
        XCTAssertFalse(item(freshness: .unavailable).mayOffer(.approve))
        XCTAssertFalse(item(phase: .finalAcceptance).mayOffer(.approve))
        XCTAssertFalse(item(phase: .engineeringResult).mayOffer(.approve))
        XCTAssertFalse(item(phase: .unknown).mayOffer(.approve))
        XCTAssertTrue(item(revision: "").mayOffer(.approve))
        let missing = MissionReviewItem(
            key: MissionReviewKey(missionID: "", requirementID: "review-2"),
            subjectID: "action-1", subjectRevision: "r2", projectID: nil, title: nil,
            actionResult: nil, waitingReason: nil, phase: .waitingForReview,
            authority: .forge, freshness: .current, allowedOutcomes: [.approve])
        XCTAssertFalse(missing.mayOffer(.approve))
    }

    func testEmptyStatesNeverClaimGlobalMissionAbsence() {
        let row = item()
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .available, all: [], visible: []),
                       .noItemsInAuthorizedScope)
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .available, all: [row], visible: []),
                       .noMatches)
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .available, all: [row], visible: [row]),
                       .hasItems)
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .unavailable, all: [row], visible: [row]),
                       .unavailable)
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .denied, all: [row], visible: [row]),
                       .denied)
        XCTAssertEqual(MissionReviewDiscovery.emptyState(access: .offline, all: [row], visible: [row]),
                       .offline)
    }
}
