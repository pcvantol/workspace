import XCTest
@testable import WorkspaceClient

final class MissionReviewDecisionStateTests: XCTestCase {
    private let operation = UUID(uuidString: "dff33888-f15e-43fa-b15b-3a486b7494cd")!

    private func item(revision: String = "r7", freshness: MissionReviewFreshness = .current,
                      authority: MissionReviewAuthority = .forge) -> MissionReviewItem {
        MissionReviewItem(
            key: MissionReviewKey(missionID: "mission-1", requirementID: "review-1"),
            subjectID: "action-1", subjectRevision: revision, projectID: nil,
            title: "Review delivered Action", actionResult: "Delivered", waitingReason: "Review fence",
            phase: .waitingForReview, authority: authority, freshness: freshness,
            allowedOutcomes: [.approve, .reject, .amend, .deferred])
    }

    private func readback(for intent: MissionReviewIntent,
                          receipt: String = "receipt-1", currentRevision: String = "r7") -> MissionReviewOwnerReadback {
        MissionReviewOwnerReadback(operationID: intent.operationID, key: intent.key,
                                   subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
                                   outcome: intent.outcome, receiptID: receipt,
                                   currentSubjectRevision: currentRevision, fenceState: "RELEASED")
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
        XCTAssertEqual(restarted.phase, .recorded(intent, receiptID: "receipt-1", fenceState: "RELEASED"))
        XCTAssertNil(restarted.operationToReadBack())
    }

    func testReceiptAndCurrentExactReadbackRequiredForSuccess() throws {
        var state = MissionReviewDecisionState()
        XCTAssertTrue(state.prepare(item: item(), outcome: .reject, comment: "No", operationID: operation))
        let intent = try XCTUnwrap(state.confirm())
        XCTAssertEqual(state.persisted(intent), intent)
        var wrong = readback(for: intent, receipt: "")
        XCTAssertFalse(state.applyOwnerReadback(wrong, current: item()))
        wrong = readback(for: intent, currentRevision: "r8")
        XCTAssertFalse(state.applyOwnerReadback(wrong, current: item()))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item(freshness: .stale)))
        XCTAssertFalse(state.applyOwnerReadback(readback(for: intent), current: item(revision: "r8")))
        let foreign = MissionReviewOwnerReadback(operationID: UUID(), key: intent.key,
                                                 subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
                                                 outcome: intent.outcome, receiptID: "receipt-1",
                                                 currentSubjectRevision: "r7", fenceState: "RELEASED")
        XCTAssertFalse(state.applyOwnerReadback(foreign, current: item()))
        XCTAssertEqual(state.phase, .submitting(intent))
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
