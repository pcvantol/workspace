import XCTest
@testable import WorkspaceClient

final class MissionReviewDecisionStateTests: XCTestCase {
    private let operation = UUID(uuidString: "dff33888-f15e-43fa-b15b-3a486b7494cd")!

    private func item(revision: String = "r7", currentMissionRevision: Int = 7,
                      freshness: MissionReviewFreshness = .current,
                      authority: MissionReviewAuthority = .forge) -> MissionReviewItem {
        MissionReviewItem(
            key: MissionReviewKey(missionID: "mission-1", requirementID: "review-1"),
            subjectID: "action-1", subjectRevision: revision, projectID: nil,
            title: "Review delivered Action", actionResult: "Delivered", waitingReason: "Review fence",
            phase: .waitingForReview, authority: authority, freshness: freshness,
            allowedOutcomes: [.approve, .reject, .amend, .deferred],
            forgeInstanceID: "forge-1", actorID: "reviewer-1",
            subjectDigest: "sha256:" + String(repeating: "a", count: 64),
            missionStateRevision: 7, currentMissionRevision: currentMissionRevision,
            evidenceDigest: "sha256:" + String(repeating: "b", count: 64), policyRevision: "policy-r1")
    }

    private func readback(for intent: MissionReviewIntent,
                          receipt: String = "receipt-1", currentRevision: Int = 7) -> MissionReviewOwnerReadback {
        MissionReviewOwnerReadback(operationID: intent.operationID, key: intent.key,
                                   subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
                                   outcome: intent.outcome, receiptID: receipt,
                                   forgeInstanceID: intent.forgeInstanceID, actorID: intent.actorID,
                                   currentMissionRevision: currentRevision, fenceState: .released)
    }

    func testExplicitConfirmAndDurableIntentPrecedeOneSubmission() throws {
        var state = MissionReviewDecisionState()
        XCTAssertTrue(state.prepare(item: item(), outcome: .approve, comment: "Ready", operationID: operation))
        XCTAssertFalse(state.prepare(item: item(), outcome: .approve, comment: "Duplicate"))
        XCTAssertNil(state.operationToReadBack())
        let intent = try XCTUnwrap(state.confirm())
        XCTAssertNil(state.confirm())
        XCTAssertNil(state.persisted(MissionReviewIntent(operationID: UUID(), key: intent.key,
                                                         subjectID: intent.subjectID,
                                                         subjectRevision: intent.subjectRevision,
                                                         outcome: intent.outcome, comment: intent.comment)))
        XCTAssertEqual(state.persisted(intent), intent)
        XCTAssertNil(state.persisted(intent))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item()))
        state.submissionAcknowledged()
        XCTAssertEqual(state.operationToReadBack(), intent)
        XCTAssertEqual(state.phase, .awaitingOwnerReadback(intent))
        XCTAssertEqual(intent.operationID, operation)
        let encoded = try JSONEncoder().encode(intent)
        XCTAssertEqual(try JSONDecoder().decode(MissionReviewIntent.self, from: encoded), intent)
    }

    func testLostResponseAndRestartOnlyReadBackSameOperation() throws {
        var state = MissionReviewDecisionState()
        XCTAssertTrue(state.prepare(item: item(), outcome: .deferred, comment: "Wait", operationID: operation))
        let intent = try XCTUnwrap(state.confirm())
        XCTAssertEqual(state.persisted(intent), intent)
        state.uncertainAfterTransport()
        XCTAssertEqual(state.operationToReadBack(), intent)
        XCTAssertNil(state.confirm())
        var restarted = MissionReviewDecisionState()
        restarted.restore(intent)
        XCTAssertEqual(restarted.operationToReadBack(), intent)
        XCTAssertFalse(restarted.prepare(item: item(), outcome: .deferred, comment: "Again"))
        XCTAssertTrue(restarted.applyOwnerReadback(readback(for: intent), current: item()))
        XCTAssertEqual(restarted.phase, .recorded(intent, receiptID: "receipt-1", fenceState: .released))
        XCTAssertNil(restarted.operationToReadBack())
    }

    func testReceiptAndCurrentExactReadbackRequiredForSuccess() throws {
        var state = MissionReviewDecisionState()
        XCTAssertTrue(state.prepare(item: item(), outcome: .reject, comment: "No", operationID: operation))
        let intent = try XCTUnwrap(state.confirm())
        XCTAssertEqual(state.persisted(intent), intent)
        state.submissionAcknowledged()
        var wrong = readback(for: intent, receipt: "")
        XCTAssertFalse(state.applyOwnerReadback(wrong, current: item()))
        wrong = readback(for: intent, currentRevision: 8)
        XCTAssertFalse(state.applyOwnerReadback(wrong, current: item()))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item(freshness: .stale)))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item(currentMissionRevision: 8)))
        let foreign = MissionReviewOwnerReadback(operationID: UUID(), key: intent.key,
                                                 subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
                                                 outcome: intent.outcome, receiptID: "receipt-1",
                                                 forgeInstanceID: intent.forgeInstanceID, actorID: intent.actorID,
                                                 currentMissionRevision: 7, fenceState: .released)
        XCTAssertFalse(state.applyOwnerReadback(foreign, current: item()))
        let wrongRequirement = MissionReviewOwnerReadback(
            operationID: intent.operationID,
            key: MissionReviewKey(missionID: intent.key.missionID, requirementID: "review-elsewhere"),
            subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
            outcome: intent.outcome, receiptID: "receipt-1",
            forgeInstanceID: intent.forgeInstanceID, actorID: intent.actorID,
            currentMissionRevision: 7, fenceState: .released)
        XCTAssertFalse(state.applyOwnerReadback(wrongRequirement, current: item()))
        let wrongSubject = MissionReviewOwnerReadback(
            operationID: intent.operationID, key: intent.key,
            subjectID: "action-elsewhere", subjectRevision: intent.subjectRevision,
            outcome: intent.outcome, receiptID: "receipt-1",
            forgeInstanceID: intent.forgeInstanceID, actorID: intent.actorID,
            currentMissionRevision: 7, fenceState: .released)
        XCTAssertFalse(state.applyOwnerReadback(wrongSubject, current: item()))
        let wrongOutcome = MissionReviewOwnerReadback(
            operationID: intent.operationID, key: intent.key,
            subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
            outcome: .approve, receiptID: "receipt-1",
            forgeInstanceID: intent.forgeInstanceID, actorID: intent.actorID,
            currentMissionRevision: 7, fenceState: .released)
        XCTAssertFalse(state.applyOwnerReadback(wrongOutcome, current: item()))
        XCTAssertEqual(state.phase, .awaitingOwnerReadback(intent))
        XCTAssertTrue(state.applyOwnerReadback(readback(for: intent), current: item()))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item()))
    }

    func testDeniedStaleExternalAndCancellationFailClosed() {
        var state = MissionReviewDecisionState()
        XCTAssertFalse(state.prepare(item: item(authority: .external), outcome: .approve,
                                     comment: "No", operationID: operation))
        XCTAssertFalse(state.prepare(item: item(freshness: .stale), outcome: .approve,
                                     comment: "No", operationID: operation))
        XCTAssertFalse(state.prepare(item: item(), outcome: .approve,
                                     comment: String(repeating: "x", count: 2_001), operationID: operation))
        XCTAssertTrue(state.prepare(item: item(), outcome: .amend, comment: "Revise", operationID: operation))
        state.cancelBeforeSubmission()
        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.prepare(item: item(), outcome: .amend, comment: "Revise", operationID: operation))
        _ = state.confirm()
        state.cancelBeforeSubmission()
        XCTAssertEqual(state.phase, .idle)
        state.denied()
        XCTAssertFalse(state.prepare(item: item(), outcome: .approve, comment: "No", operationID: operation))
        XCTAssertNil(state.confirm())
        state.stale()
        XCTAssertNil(state.operationToReadBack())
        state.uncertainAfterTransport()
        XCTAssertEqual(state.phase, .stale)
    }
}
