import Foundation

// Workspace-local presentation state. Forge remains the decision authority.
enum MissionReviewFilter: String, CaseIterable {
    case all, waiting, recorded
}

enum MissionReviewPhase: String {
    case waitingForReview, decisionRecorded, engineeringResult, finalAcceptance
    case noReview, externalGate, unknown
}

enum MissionReviewAuthority: String {
    case forge, external, unknown
}

enum MissionReviewFreshness: String {
    case current, stale, unavailable
}

enum MissionReviewOutcome: String, CaseIterable, Codable {
    case approve, reject, amend
    case deferred = "defer"
}

struct MissionReviewKey: Hashable, Codable {
    let missionID: String
    let requirementID: String
}

enum MissionEvidenceKind: String {
    case actionResult, forgeReceipt, sourceRevision
}

struct MissionEvidenceReference: Equatable {
    let kind: MissionEvidenceKind
    let identifier: String
}

struct MissionReviewItem: Equatable {
    let forgeInstanceID: String
    let actorID: String
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let subjectDigest: String
    let missionStateRevision: Int
    let currentMissionRevision: Int
    let evidenceDigest: String
    let policyRevision: String
    let lifecycleState: String
    let decisionID: String?
    let decisionDigest: String?
    let decisionOutcome: MissionReviewOutcome?
    let projectID: String?
    let title: String?
    let actionResult: String?
    let waitingReason: String?
    let requiredRole: String?
    let blockingScope: String?
    let policySource: String?
    let evidence: [MissionEvidenceReference]
    let observedAt: String?
    let phase: MissionReviewPhase
    let authority: MissionReviewAuthority
    let freshness: MissionReviewFreshness
    let allowedOutcomes: Set<MissionReviewOutcome>

    init(key: MissionReviewKey, subjectID: String, subjectRevision: String,
         projectID: String?, title: String?, actionResult: String?, waitingReason: String?,
         phase: MissionReviewPhase, authority: MissionReviewAuthority,
         freshness: MissionReviewFreshness, allowedOutcomes: Set<MissionReviewOutcome>,
         requiredRole: String? = nil, blockingScope: String? = nil,
         policySource: String? = nil, evidence: [MissionEvidenceReference] = [],
         observedAt: String? = nil, forgeInstanceID: String = "", actorID: String = "",
         subjectDigest: String = "", missionStateRevision: Int = 0,
         currentMissionRevision: Int = 0,
         evidenceDigest: String = "", policyRevision: String = "",
         lifecycleState: String = "", decisionID: String? = nil,
         decisionDigest: String? = nil, decisionOutcome: MissionReviewOutcome? = nil) {
        self.forgeInstanceID = forgeInstanceID
        self.actorID = actorID
        self.key = key
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.subjectDigest = subjectDigest
        self.missionStateRevision = missionStateRevision
        self.currentMissionRevision = currentMissionRevision
        self.evidenceDigest = evidenceDigest
        self.policyRevision = policyRevision
        self.lifecycleState = lifecycleState
        self.decisionID = decisionID
        self.decisionDigest = decisionDigest
        self.decisionOutcome = decisionOutcome
        self.projectID = projectID
        self.title = title
        self.actionResult = actionResult
        self.waitingReason = waitingReason
        self.requiredRole = requiredRole
        self.blockingScope = blockingScope
        self.policySource = policySource
        self.evidence = evidence
        self.observedAt = observedAt
        self.phase = phase
        self.authority = authority
        self.freshness = freshness
        self.allowedOutcomes = allowedOutcomes
    }

    // UI eligibility is a second guard, never evidence of Forge authorization.
    func mayOffer(_ outcome: MissionReviewOutcome) -> Bool {
        phase == .waitingForReview && authority == .forge && freshness == .current &&
        !key.missionID.isEmpty && !key.requirementID.isEmpty &&
        !forgeInstanceID.isEmpty && !actorID.isEmpty && !subjectDigest.isEmpty && missionStateRevision > 0 &&
        !evidenceDigest.isEmpty && !policyRevision.isEmpty && allowedOutcomes.contains(outcome)
    }
}

enum MissionReviewEmptyState: Equatable {
    case unavailable, denied, offline, noItemsInAuthorizedScope, noMatches, hasItems
}

enum MissionReviewListAccess {
    case available, unavailable, denied, offline
}

enum MissionReviewDiscovery {
    static func visible(_ items: [MissionReviewItem], search: String,
                        filter: MissionReviewFilter) -> [MissionReviewItem] {
        let needle = normalized(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return items.filter { item in
            let included = switch filter {
            case .all: true
            case .waiting: item.phase == .waitingForReview
            case .recorded: item.phase == .decisionRecorded
            }
            guard included else { return false }
            guard !needle.isEmpty else { return true }
            return [item.key.missionID, item.key.requirementID, item.subjectID,
                    item.title ?? "", item.actionResult ?? "", item.waitingReason ?? ""]
                .contains { normalized($0).contains(needle) }
        }.sorted { left, right in
            if left.key.missionID != right.key.missionID {
                return left.key.missionID < right.key.missionID
            }
            return left.key.requirementID < right.key.requirementID
        }
    }

    static func selected(_ key: MissionReviewKey?, in items: [MissionReviewItem]) -> MissionReviewItem? {
        guard let key else { return nil }
        return items.first { $0.key == key } ?? items.first { $0.key.missionID == key.missionID }
    }

    static func emptyState(access: MissionReviewListAccess, all: [MissionReviewItem],
                           visible: [MissionReviewItem]) -> MissionReviewEmptyState {
        switch access {
        case .unavailable: return .unavailable
        case .denied: return .denied
        case .offline: return .offline
        case .available:
            if all.isEmpty { return .noItemsInAuthorizedScope }
            return visible.isEmpty ? .noMatches : .hasItems
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }
}
