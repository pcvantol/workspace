import Foundation

// These are Workspace transport states, not a Forge decision record or wire schema.
struct MissionReviewIntent: Codable, Equatable {
    let operationID: UUID
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let forgeInstanceID: String
    let actorID: String
    let subjectDigest: String
    let missionStateRevision: Int
    let evidenceDigest: String
    let policyRevision: String
    let outcome: MissionReviewOutcome
    let comment: String

    init(operationID: UUID, key: MissionReviewKey, subjectID: String, subjectRevision: String,
         outcome: MissionReviewOutcome, comment: String, forgeInstanceID: String = "",
         actorID: String = "",
         subjectDigest: String = "", missionStateRevision: Int = 0,
         evidenceDigest: String = "", policyRevision: String = "") {
        self.operationID = operationID
        self.key = key
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.forgeInstanceID = forgeInstanceID
        self.actorID = actorID
        self.subjectDigest = subjectDigest
        self.missionStateRevision = missionStateRevision
        self.evidenceDigest = evidenceDigest
        self.policyRevision = policyRevision
        self.outcome = outcome
        self.comment = comment
    }
}

struct MissionReviewOwnerReadback: Equatable {
    let operationID: UUID
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let outcome: MissionReviewOutcome
    let receiptID: String
    let forgeInstanceID: String
    let actorID: String
    let currentMissionRevision: Int
    let fenceState: MissionReviewFenceState

    init(operationID: UUID, key: MissionReviewKey, subjectID: String,
         subjectRevision: String, outcome: MissionReviewOutcome, receiptID: String,
         forgeInstanceID: String = "", actorID: String = "", currentMissionRevision: Int = 0,
         fenceState: MissionReviewFenceState) {
        self.operationID = operationID
        self.key = key
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.outcome = outcome
        self.receiptID = receiptID
        self.forgeInstanceID = forgeInstanceID
        self.actorID = actorID
        self.currentMissionRevision = currentMissionRevision
        self.fenceState = fenceState
    }
}

enum MissionReviewFenceState: Equatable {
    case blocked, released
}

enum MissionReviewDecisionPhase: Equatable {
    case idle
    case confirming(MissionReviewIntent)
    case awaitingPersistence(MissionReviewIntent)
    case submitting(MissionReviewIntent)
    case awaitingOwnerReadback(MissionReviewIntent)
    case uncertain(MissionReviewIntent)
    case recorded(MissionReviewIntent, receiptID: String, fenceState: MissionReviewFenceState)
    case denied
    case stale
}

struct MissionReviewDecisionState {
    private(set) var phase: MissionReviewDecisionPhase = .idle

    mutating func prepare(item: MissionReviewItem, outcome: MissionReviewOutcome,
                          comment: String, operationID: UUID = UUID()) -> Bool {
        guard phase == .idle, item.mayOffer(outcome),
              !comment.isEmpty, comment.count <= 512,
              !comment.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        phase = .confirming(MissionReviewIntent(
            operationID: operationID, key: item.key, subjectID: item.subjectID,
            subjectRevision: item.subjectRevision, outcome: outcome, comment: comment,
            forgeInstanceID: item.forgeInstanceID, actorID: item.actorID,
            subjectDigest: item.subjectDigest,
            missionStateRevision: item.missionStateRevision,
            evidenceDigest: item.evidenceDigest, policyRevision: item.policyRevision))
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
        let intent: MissionReviewIntent
        switch phase {
        case .submitting(let pending), .awaitingOwnerReadback(let pending): intent = pending
        default: return
        }
        phase = .uncertain(intent)
    }

    // A POST acknowledgement is pending evidence, never a recorded decision.
    mutating func submissionAcknowledged() {
        guard case .submitting(let intent) = phase else { return }
        phase = .awaitingOwnerReadback(intent)
    }

    // On restart, the same operation must be read back. This never emits a POST.
    mutating func restore(_ persistedIntent: MissionReviewIntent) {
        phase = .uncertain(persistedIntent)
    }

    func operationToReadBack() -> MissionReviewIntent? {
        switch phase {
        case .uncertain(let intent), .awaitingOwnerReadback(let intent): return intent
        default: return nil
        }
    }

    mutating func applyOwnerReadback(_ readback: MissionReviewOwnerReadback,
                                     current: MissionReviewItem) -> Bool {
        let intent: MissionReviewIntent
        switch phase {
        case .awaitingOwnerReadback(let pending), .uncertain(let pending): intent = pending
        default: return false
        }
        guard readback.operationID == intent.operationID,
              readback.key == intent.key,
              readback.subjectID == intent.subjectID,
              readback.subjectRevision == intent.subjectRevision,
              readback.outcome == intent.outcome,
              !readback.receiptID.isEmpty,
              readback.forgeInstanceID == intent.forgeInstanceID,
              readback.actorID == intent.actorID,
              current.key.missionID == intent.key.missionID,
              current.forgeInstanceID == intent.forgeInstanceID,
              current.actorID == intent.actorID,
              readback.currentMissionRevision == current.currentMissionRevision,
              current.currentMissionRevision >= intent.missionStateRevision,
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

    mutating func resetAfterRecorded() {
        switch phase {
        case .recorded, .denied, .stale: phase = .idle
        default: break
        }
    }
}
