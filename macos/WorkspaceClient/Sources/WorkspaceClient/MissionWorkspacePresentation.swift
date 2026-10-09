import Foundation

// Presentation of authorized producer observations, never a planner or readiness evaluator.
struct MissionDefinitionCard: Identifiable, Equatable, Codable {
    let id: String
    let revision: Int
    let title: String
    let value: String
    let outcome: String
    let scope: [String]
    let exclusions: [String]
    let criteria: [String]
    let questions: [String]
    let changes: [String]
    let group: String
    let labels: [String]
    var status: String
    var objective: String? = nil
    var architectureChoices: [String]? = nil
    var consequences: [String]? = nil
    var risks: [String]? = nil
    var remainingDecisions: [String]? = nil
    var blockers:[String]? = nil
}

struct MissionRelation: Equatable, Codable {
    let predecessor: String
    let dependent: String
    let reason: String
    let proposed: Bool
}

struct MissionChatLine: Identifiable, Equatable, Codable {
    let id: String
    let role: String
    let text: String
}

struct MissionWorkspaceObservation: Equatable, Codable {
    let scopeKey: String
    let project: String
    let cards: [MissionDefinitionCard]
    let relations: [MissionRelation]
    let complete: Bool
    var transcript: [MissionChatLine]? = nil

    // Unknown endpoints may belong to a later page; never fabricate a node or title.
    var visibleRelations: [MissionRelation] {
        let ids = Set(cards.map(\.id))
        return relations.filter { ids.contains($0.predecessor) && ids.contains($0.dependent) }
    }
    func matching(search: String, status: String?) -> [MissionDefinitionCard] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return cards.filter { card in
            (status == nil || card.status == status) &&
                (query.isEmpty || (card.title + " " + card.value).localizedCaseInsensitiveContains(query))
        }
    }
    func selected(_ id: String?) -> MissionDefinitionCard? {
        cards.first { $0.id == id }
    }
    func neighbors(_ id: String?) -> Set<String> {
        guard let id, selected(id) != nil else { return [] }
        return Set(visibleRelations.filter { $0.predecessor == id || $0.dependent == id }
            .flatMap { [$0.predecessor, $0.dependent] })
    }
}
