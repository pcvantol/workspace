import Foundation
import CryptoKit
import Combine

struct ProjectConcept: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let actor_id: String
    let context_id: String
    let title: String
    let notes: String
    let revision: Int
    let created_at: String
    let updated_at: String
    let state: String
    static func validText(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0.value >= 32 || $0.value == 9 || $0.value == 10 }
    }
    func validate(_ context: String) throws {
        guard id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,
              actor_id.range(of:"^[A-Za-z0-9._:-]{1,128}$",options:.regularExpression) != nil,
              context_id == context, revision > 0, revision <= 1000001,
              !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              title.unicodeScalars.count <= 120, notes.unicodeScalars.count <= 10000, Self.validText(title), Self.validText(notes),
              WorksetReleaseWire.date(created_at) != nil, WorksetReleaseWire.date(updated_at) != nil,
              state == "CONCEPT_NOT_CONFIGURED" else { throw ConceptError.invalid }
    }
}
struct ConceptCommand: Codable, Equatable, Sendable {
    let title: String
    let notes: String
    let operation_id: String
    let expected_revision: Int
}
struct ConceptConnection: Equatable, Sendable {
    let access: DraftAccess
    let bearer: String
    var key: String {
        SHA256.hash(data:Data([access.endpoint,access.instanceID,access.projectID,access.token].joined(separator:"\n").utf8)).map { String(format:"%02x",$0) }.joined()
    }
}
enum ConceptError: Error { case denied, unavailable, conflict, invalid, notFound }
struct ConceptJournal: Codable, Sendable {
    let key: String
    let identity: String?
    let command: ConceptCommand
    var completed: Bool
}
protocol ConceptServing: Sendable {
    func list(_ connection: ConceptConnection) async throws -> [ProjectConcept]
    func get(_ connection: ConceptConnection, id: String) async throws -> ProjectConcept
    func save(_ connection: ConceptConnection, id: String?, command: ConceptCommand) async throws -> ProjectConcept
}
@MainActor
final class ProjectConceptState: ObservableObject {
    @Published var title = ""
    @Published var notes = ""
    @Published private(set) var items: [ProjectConcept] = []
    @Published private(set) var selected: ProjectConcept?
    @Published private(set) var phase = "connect"
    @Published private(set) var busy = false
    @Published private(set) var pending: ConceptJournal?
    private let transport: any ConceptServing
    private let records: PrivateLocalRecordStore
    private var generation = 0
    private var connection: ConceptConnection?
    var dirty: Bool { title != (selected?.title ?? "") || notes != (selected?.notes ?? "") }
    init(transport: any ConceptServing = ProjectConceptTransport(), root: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ProjectConceptIntents")) {
        self.transport = transport; records = PrivateLocalRecordStore(root:root,namespace:"project-concept")
    }
    func cancelReads() { generation += 1; busy = false }
    func invalidate() {
        generation += 1; busy = false; connection = nil; items = []; selected = nil
        pending = nil; title = ""; notes = ""; phase = "connect"
    }
    private func check(_ expected: ConceptConnection, current: @MainActor () async throws -> ConceptConnection) async throws {
        guard try await current() == expected else { throw ConceptError.denied }
    }
    private func failure(_ error: Error) {
        switch error {
        case ConceptError.denied: invalidate(); phase = "denied"
        case ConceptError.conflict: phase = "conflict"
        case ConceptError.invalid: phase = "invalid"
        default: phase = "offline"
        }
    }
    func refresh(current: @MainActor () async throws -> ConceptConnection) async {
        guard !busy else { return }; let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let active = try await current()
            guard ticket == generation else { return }
            if let connection, connection != active { invalidate(); return }
            connection = active
            let values = try await transport.list(active); try await check(active,current:current)
            guard ticket == generation else { return }
            guard values.count <= 500, Set(values.map(\.id)).count == values.count else { throw ConceptError.invalid }
            for value in values { try value.validate(active.access.projectID) }
            items = values
            if pending == nil, let data = try records.load(active.key) {
                let journal = try JSONDecoder().decode(ConceptJournal.self,from:data)
                guard journal.key == active.key else { throw ConceptError.invalid }
                if !journal.completed {
                    pending = journal; title = journal.command.title; notes = journal.command.notes
                    if let id = journal.identity { selected = values.first { $0.id == id } }
                }
            }
            phase = pending != nil ? "retry" : (dirty ? "unsaved" : (items.isEmpty ? "empty" : "ready"))
        } catch { if ticket == generation { failure(error) } }
    }
    func new(defaultTitle: String) {
        guard !busy, pending == nil else { return }
        guard !dirty else { phase = "unsaved"; return }
        generation += 1; selected = nil; title = defaultTitle; notes = ""; phase = "unsaved"
    }
    func open(_ id: String, discard: Bool = false, current: @MainActor () async throws -> ConceptConnection) async {
        guard !busy, pending == nil else { return }
        guard !dirty || discard else { phase = "unsaved"; return }
        guard let active = connection else { return }
        generation += 1; let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try await check(active,current:current)
            let value = try await transport.get(active,id:id); try value.validate(active.access.projectID)
            try await check(active,current:current)
            guard ticket == generation else { return }
            selected = value; title = value.title; notes = value.notes; phase = "saved"
        } catch { if ticket == generation { failure(error) } }
    }
    private func settle(_ journal: ConceptJournal) throws {
        var completed = journal; completed.completed = true
        let historyKey = SHA256.hash(data:Data((journal.key+journal.command.operation_id).utf8)).map { String(format:"%02x",$0) }.joined()
        // Archive first; disk failure never loses the original recovery head.
        try records.save(JSONEncoder().encode(completed),key:historyKey)
        try records.save(JSONEncoder().encode(completed),key:journal.key)
    }
    func save(current: @MainActor () async throws -> ConceptConnection) async {
        guard !busy, let active = connection else { return }
        guard title.unicodeScalars.count <= 120, notes.unicodeScalars.count <= 10000,
              !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, ProjectConcept.validText(title), ProjectConcept.validText(notes) else { phase = "invalid"; return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try await check(active,current:current)
            let journal: ConceptJournal
            if let pending { journal = pending } else {
                journal = .init(key:active.key,identity:selected?.id,
                    command:.init(title:title,notes:notes,operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_revision:selected?.revision ?? 0),completed:false)
                // Durable original immutable request precedes network dispatch.
                try records.save(JSONEncoder().encode(journal),key:active.key); pending = journal
            }
            let receipt = try await transport.save(active,id:journal.identity,command:journal.command)
            try receipt.validate(active.access.projectID); try await check(active,current:current)
            guard ticket == generation else { return }
            guard receipt.title == journal.command.title, receipt.notes == journal.command.notes,
                  receipt.revision == journal.command.expected_revision + 1,
                  journal.identity == nil || receipt.id == journal.identity else { throw ConceptError.invalid }
            let latest = try await transport.get(active,id:receipt.id); try latest.validate(active.access.projectID)
            try await check(active,current:current)
            guard ticket == generation else { return }
            try settle(journal)
            pending = nil; selected = receipt
            if latest.revision != receipt.revision { phase = "conflict"; return }
            selected = latest
            title = latest.title; notes = latest.notes
            items.removeAll { $0.id == latest.id }; items.insert(latest,at:0); phase = "saved"
        } catch ConceptError.conflict {
            if ticket == generation {
                // Definitive rejection releases editing, original journal is retained.
                do {
                    if let journal = pending { try settle(journal) }
                    pending = nil; phase = "conflict"
                } catch { phase = "offline" }
            }
        } catch { if ticket == generation { failure(error) } }
    }
}
