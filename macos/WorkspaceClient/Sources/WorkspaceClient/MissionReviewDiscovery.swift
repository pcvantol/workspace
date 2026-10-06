import Foundation

// Workspace-local presentation state. Forge remains the decision authority.
enum MissionReviewFilter: String, CaseIterable {
    case all, waiting, recorded
}

enum MissionReviewPhase: String {
    case waitingForReview, decisionRecorded, engineeringResult, finalAcceptance, unknown
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

struct MissionReviewItem: Equatable {
    let key: MissionReviewKey
    let subjectID: String
    let subjectRevision: String
    let projectID: String?
    let title: String?
    let actionResult: String?
    let waitingReason: String?
    let phase: MissionReviewPhase
    let authority: MissionReviewAuthority
    let freshness: MissionReviewFreshness
    let allowedOutcomes: Set<MissionReviewOutcome>

    // UI eligibility is a second guard, never evidence of Forge authorization.
    func mayOffer(_ outcome: MissionReviewOutcome) -> Bool {
        phase == .waitingForReview && authority == .forge && freshness == .current &&
        !key.missionID.isEmpty && !key.requirementID.isEmpty &&
        !subjectID.isEmpty && !subjectRevision.isEmpty && allowedOutcomes.contains(outcome)
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
        return items.first { $0.key == key }
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
