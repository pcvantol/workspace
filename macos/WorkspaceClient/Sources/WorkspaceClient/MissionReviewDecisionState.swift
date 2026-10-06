import Foundation

// These are Workspace transport states, not a Forge decision record or wire schema.
struct MissionReviewIntent: Codable, Equatable {
    let operationID: UUID
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let outcome: MissionReviewOutcome
    let comment: String
}

struct MissionReviewOwnerReadback: Equatable {
    let operationID: UUID
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let outcome: MissionReviewOutcome
    let receiptID: String
    let currentSubjectRevision: String
    let fenceState: String
}

enum MissionReviewDecisionPhase: Equatable {
    case idle
    case confirming(MissionReviewIntent)
    case awaitingPersistence(MissionReviewIntent)
    case submitting(MissionReviewIntent)
    case uncertain(MissionReviewIntent)
    case recorded(MissionReviewIntent, receiptID: String, fenceState: String)
    case denied
    case stale
}

struct MissionReviewDecisionState {
    private(set) var phase: MissionReviewDecisionPhase = .idle

    mutating func prepare(item: MissionReviewItem, outcome: MissionReviewOutcome,
                          comment: String, operationID: UUID = UUID()) -> Bool {
        guard phase == .idle, item.mayOffer(outcome), comment.utf8.count <= 2_000 else { return false }
        phase = .confirming(MissionReviewIntent(
            operationID: operationID, key: item.key, subjectID: item.subjectID,
            subjectRevision: item.subjectRevision, outcome: outcome, comment: comment))
        return true
    }

    // The caller must durably save this exact intent before any HTTP submission.
    mutating func confirm() -> MissionReviewIntent? {
        guard case .confirming(let intent) = phase else { return nil }
        phase = .awaitingPersistence(intent)
        return intent
    }

    mutating func persisted(_ intent: MissionReviewIntent) -> MissionReviewIntent? {
        guard case .awaitingPersistence(let expected) = phase, expected == intent else { return nil }
        phase = .submitting(intent)
        return intent
    }

    mutating func uncertainAfterTransport() {
        guard case .submitting(let intent) = phase else { return }
        phase = .uncertain(intent)
    }

    // On restart, the same operation must be read back. This never emits a POST.
    mutating func restore(_ persistedIntent: MissionReviewIntent) {
        phase = .uncertain(persistedIntent)
    }

    func operationToReadBack() -> MissionReviewIntent? {
        guard case .uncertain(let intent) = phase else { return nil }
        return intent
    }

    mutating func applyOwnerReadback(_ readback: MissionReviewOwnerReadback,
                                     current: MissionReviewItem) -> Bool {
        let intent: MissionReviewIntent
        switch phase {
        case .submitting(let pending), .uncertain(let pending): intent = pending
        default: return false
        }
        guard readback.operationID == intent.operationID,
              readback.key == intent.key,
              readback.subjectID == intent.subjectID,
              readback.subjectRevision == intent.subjectRevision,
              readback.outcome == intent.outcome,
              !readback.receiptID.isEmpty, !readback.fenceState.isEmpty,
              current.key == intent.key,
              current.subjectID == intent.subjectID,
              current.subjectRevision == readback.currentSubjectRevision,
              current.freshness == .current else { return false }
        phase = .recorded(intent, receiptID: readback.receiptID, fenceState: readback.fenceState)
        return true
    }

    mutating func denied() { phase = .denied }
    mutating func stale() { phase = .stale }
    mutating func cancelBeforeSubmission() {
        switch phase {
        case .confirming, .awaitingPersistence: phase = .idle
        default: break
        }
    }
}
