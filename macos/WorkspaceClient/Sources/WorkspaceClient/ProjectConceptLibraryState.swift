import Foundation
import CryptoKit

struct ConceptLifecycleCommand: Codable, Equatable, Sendable {
    let operation_id: String
    let expected_revision: Int
    let lifecycle: String
}
struct ConceptLifecycleJournal: Codable, Sendable {
    let key: String
    let identity: String
    let command: ConceptLifecycleCommand
    let snapshot: ProjectConcept
    var completed: Bool
}
extension ProjectConceptState {
    var selectedIsArchived: Bool { selected?.lifecycle == "ARCHIVED" || selectedLifecycleHint == "ARCHIVED" }
    var visibleItems: [ProjectConceptSummary] {
        items.filter { ($0.lifecycle ?? "ACTIVE") == libraryTab && (searchQuery.isEmpty || $0.title.range(of:searchQuery,options:[.caseInsensitive,.diacriticInsensitive],locale:.current) != nil) }
    }
    var libraryEmptyMessage: String? {
        guard inventoryLoaded, !busy, ["saved","ready","empty","unsaved"].contains(phase), visibleItems.isEmpty else { return nil }
        return !searchQuery.isEmpty ? "noTitles" : libraryTab == "ARCHIVED" ? "archiveEmpty" : "activeEmpty"
    }
    var lifecycleBlocked: Bool { busy || dirty || pending != nil || selected == nil || phase == "conflict" || !inventoryLoaded }
    func restoreLifecycle(_ active: ConceptConnection) throws {
        if pendingLifecycle == nil, let data = try lifecycleRecords.load(active.key) {
            let journal = try JSONDecoder().decode(ConceptLifecycleJournal.self,from:data)
            guard journal.key == active.key, journal.identity == journal.snapshot.id,
                  journal.command.expected_revision == journal.snapshot.revision,
                  journal.snapshot.library_version == "project-concept-library/1", journal.snapshot.lifecycle != nil,
                  journal.command.lifecycle != journal.snapshot.lifecycle,
                  ["ACTIVE","ARCHIVED"].contains(journal.command.lifecycle),
                  journal.command.operation_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else { throw ConceptError.invalid }
            try journal.snapshot.validate(active.access.projectID)
            if !journal.completed {
                guard pending == nil else { throw ConceptError.invalid }
                pendingLifecycle = journal; selected = journal.snapshot; title = journal.snapshot.title; notes = journal.snapshot.notes
            }
        }
    }
    private func settleLifecycle(_ journal: ConceptLifecycleJournal) throws {
        var completed = journal; completed.completed = true
        let key = SHA256.hash(data:Data((journal.key+journal.command.operation_id).utf8)).map { String(format:"%02x",$0) }.joined()
        try lifecycleRecords.save(JSONEncoder().encode(completed),key:key)
        try lifecycleRecords.save(JSONEncoder().encode(completed),key:journal.key)
    }
    func move(current: @MainActor () async throws -> ConceptConnection) async {
        guard !lifecycleBlocked, let active = connection, let concept = selected else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try await check(active,current:current)
            let journal: ConceptLifecycleJournal
            if let pendingLifecycle { journal = pendingLifecycle } else {
                journal = .init(key:active.key,identity:concept.id,
                    command:.init(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_revision:concept.revision,lifecycle:concept.lifecycle == "ARCHIVED" ? "ACTIVE" : "ARCHIVED"),snapshot:concept,completed:false)
                try lifecycleRecords.save(JSONEncoder().encode(journal),key:active.key); pendingLifecycle = journal
            }
            let receipt = try await transport.move(active,id:journal.identity,command:journal.command)
            try receipt.validate(active.access.projectID); try await check(active,current:current)
            guard ticket == generation else { return }
            guard receipt.id == journal.identity, receipt.actor_id == journal.snapshot.actor_id, receipt.context_id == journal.snapshot.context_id, receipt.revision == journal.command.expected_revision+1,
                  receipt.lifecycle == journal.command.lifecycle, receipt.library_version == "project-concept-library/1",
                  receipt.title == journal.snapshot.title, receipt.notes == journal.snapshot.notes,
                  receipt.created_at == journal.snapshot.created_at else { throw ConceptError.invalid }
            let latest = try await transport.get(active,id:receipt.id); try latest.validate(active.access.projectID)
            guard latest.actor_id == journal.snapshot.actor_id else { throw ConceptError.invalid }
            try await check(active,current:current)
            guard ticket == generation else { return }
            try settleLifecycle(journal); pendingLifecycle = nil
            if latest.revision != receipt.revision || latest.lifecycle != receipt.lifecycle { phase = "conflict"; return }
            selected = latest; selectedLifecycleHint = latest.lifecycle; title = latest.title; notes = latest.notes; libraryTab = latest.lifecycle ?? "ACTIVE"
            items.removeAll { $0.id == latest.id }; items.insert(latest.summary,at:0); phase = "saved"
        } catch ConceptError.conflict {
            if ticket == generation {
                do { if let journal = pendingLifecycle { try settleLifecycle(journal) }; pendingLifecycle = nil; phase = "conflict" }
                catch { phase = "offline" }
            }
        } catch { if ticket == generation { failure(error) } }
    }
}
