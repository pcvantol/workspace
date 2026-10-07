import Foundation

// Workspace-local observation/presentation types, not a Forge wire contract or authority.
struct ApprovedWorklistScope: Equatable, Codable {
    let forgeInstanceID: String
    let actorID: String
    let worksetID: String
}

struct ApprovedWorklistKey: Equatable, Hashable {
    let forgeInstanceID: String
    let actorID: String
    let worksetID: String
    let memberID: String
}

enum WorklistFact: String, Codable {
    case yes, no, unknown, notRequired
}

struct WorklistFacts: Equatable {
    let approved: WorklistFact
    let released: WorklistFact
    let eligible: WorklistFact
    let active: WorklistFact
    let engineeringComplete: WorklistFact
    let reviewAccepted: WorklistFact
    let finalAccepted: WorklistFact
    let completed: WorklistFact
}

enum WorklistReasonKind: String {
    case dependency, hold, evidence, review, finalAcceptance, authority, budget, unknown
}

struct WorklistBlockReason: Equatable {
    let kind: WorklistReasonKind
    let code: String
    let explanation: String?
}

struct WorklistEvidenceReference: Equatable, Hashable {
    let kind: String
    let subjectID: String
    let digest: String
}

struct ApprovedWorklistItem: Equatable {
    let key: ApprovedWorklistKey
    let subjectID: String
    let subjectRevision: String
    let committedPosition: Int
    let snapshotRevision: String
    let sourceRevision: String
    let missionID: String?
    let projectID: String?
    let title: String?
    let facts: WorklistFacts
    let blockers: [WorklistBlockReason]

    var executionState: String = "UNKNOWN"
    var reviewState: String = "UNKNOWN"
    var effectMode: String = "UNKNOWN"
    var dependencies: [String] = []
    var evidence: [WorklistEvidenceReference] = []
    var reviewDetailAvailable = false
    var missionBindingVerified = false

    var displayTitle: String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return key.memberID
        }
        return title
    }
}

enum WorklistFreshness { case current, stale, unknown }
enum WorklistContinuation { case ready, blocked, idle, unknown }

struct ApprovedWorklistSnapshot: Equatable {
    let scope: ApprovedWorklistScope
    let membershipRevision: String
    let selectorRevision: String
    let snapshotRevision: String
    let observedAt: String
    let completeWithinScope: Bool
    let freshness: WorklistFreshness
    let continuation: WorklistContinuation
    let nextMemberID: String?
    let items: [ApprovedWorklistItem]

    var installationID: String = ""
    var worksetRevision: Int = 0
    var activationSupport: String = "UNKNOWN"
    var continuationReasons: [String] = []

    func isCoherent(for expected: ApprovedWorklistScope) -> Bool {
        guard scope == expected, !scope.forgeInstanceID.isEmpty,
              !scope.actorID.isEmpty, !scope.worksetID.isEmpty,
              !membershipRevision.isEmpty, !selectorRevision.isEmpty,
              !snapshotRevision.isEmpty, !observedAt.isEmpty else { return false }
        guard Set(items.map(\.key.memberID)).count == items.count,
              Set(items.map(\.committedPosition)).count == items.count,
              items.allSatisfy({ validMember($0) }) else { return false }
        if let nextMemberID, !items.contains(where: { $0.key.memberID == nextMemberID }) {
            return false
        }
        return true
    }

    private func validMember(_ item: ApprovedWorklistItem) -> Bool {
        item.key.forgeInstanceID == scope.forgeInstanceID &&
        item.key.actorID == scope.actorID && item.key.worksetID == scope.worksetID &&
        !item.key.memberID.isEmpty && !item.subjectID.isEmpty &&
        !item.subjectRevision.isEmpty && !item.sourceRevision.isEmpty &&
        item.committedPosition >= 0 && item.snapshotRevision == snapshotRevision
    }
}

enum WorklistAvailability { case available, unavailable, denied, offline, partial, stale }
enum WorklistEmptyState { case hasItems, noMatches, emptyGrantedWorkset, unavailable, denied, offline, partial, stale }
enum WorklistFilter: String, CaseIterable { case all, eligible, active, blocked, completed, unknown }
enum WorklistSort: String, CaseIterable { case committed, title, identifier }

struct WorklistObservationCache {
    private(set) var snapshot: ApprovedWorklistSnapshot?
    private(set) var availability: WorklistAvailability = .unavailable
    private(set) var usingLastObservation = false

    @discardableResult
    mutating func accept(_ candidate: ApprovedWorklistSnapshot,
                         for expected: ApprovedWorklistScope) -> Bool {
        if snapshot?.scope != expected { snapshot = nil }
        guard candidate.isCoherent(for: expected) else {
            availability = .stale
            usingLastObservation = snapshot != nil
            return false
        }
        snapshot = candidate
        usingLastObservation = false
        availability = !candidate.completeWithinScope ? .partial :
            candidate.freshness == .current ? .available : .stale
        return true
    }

    mutating func failed(_ state: WorklistAvailability, for expected: ApprovedWorklistScope) {
        if state == .denied || state == .unavailable || snapshot?.scope != expected {
            snapshot = nil
        }
        availability = state
        usingLastObservation = snapshot != nil
    }
}

enum ApprovedWorklistPresentation {
    static func visible(_ items: [ApprovedWorklistItem], search: String,
                        filter: WorklistFilter, sort: WorklistSort) -> [ApprovedWorklistItem] {
        let needle = normalized(search.trimmingCharacters(in: .whitespacesAndNewlines))
        return items.filter { item in
            guard included(item, filter: filter) else { return false }
            guard !needle.isEmpty else { return true }
            let text = [item.key.memberID, item.subjectID, item.missionID ?? "", item.title ?? ""] +
                item.blockers.flatMap { [$0.code, $0.explanation ?? ""] }
            return text.contains { normalized($0).contains(needle) }
        }.sorted { left, right in
            let leftValue = sort == .title ? normalized(left.displayTitle) : left.key.memberID
            let rightValue = sort == .title ? normalized(right.displayTitle) : right.key.memberID
            if sort != .committed && leftValue != rightValue { return leftValue < rightValue }
            if left.committedPosition != right.committedPosition {
                return left.committedPosition < right.committedPosition
            }
            return left.key.memberID < right.key.memberID
        }
    }

    static func selected(_ key: ApprovedWorklistKey?,
                         in snapshot: ApprovedWorklistSnapshot?) -> ApprovedWorklistItem? {
        guard let key, let snapshot else { return nil }
        return snapshot.items.first { $0.key == key }
    }

    static func emptyState(_ cache: WorklistObservationCache,
                           visible: [ApprovedWorklistItem]) -> WorklistEmptyState {
        switch cache.availability {
        case .unavailable: return .unavailable
        case .denied: return .denied
        case .offline: return .offline
        case .partial: return .partial
        case .stale: return .stale
        case .available:
            guard let snapshot = cache.snapshot else { return .unavailable }
            if snapshot.items.isEmpty { return .emptyGrantedWorkset }
            return visible.isEmpty ? .noMatches : .hasItems
        }
    }

    private static func included(_ item: ApprovedWorklistItem, filter: WorklistFilter) -> Bool {
        switch filter {
        case .all: true
        case .eligible: item.facts.eligible == .yes
        case .active: item.facts.active == .yes
        case .blocked: !item.blockers.isEmpty || item.facts.eligible == .no
        case .completed: item.facts.completed == .yes
        case .unknown: item.facts.eligible == .unknown && item.facts.active != .yes && item.facts.completed != .yes
        }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }
}
