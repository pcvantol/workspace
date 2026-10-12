import Foundation
import CryptoKit

// Workspace-owned normalized projections, not the unaccepted EP wire schema.
struct LinkedRepository: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let role: String
    let availableAttachments: Int
}
struct LinkProject: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}
struct LinkTopology: Codable, Equatable, Sendable {
    let peerID: String
    let projectID: String
    let name: String
    let authorityID: String
    let revision: Int
    let observedAt: Date
    let repositories: [LinkedRepository]
    func validate(_ access: ProjectLinkAccess, project: String) throws {
        try access.validate()
        guard peerID == access.peerID, projectID == project, access.projectIDs.contains(project),
              revision > 0, !name.isEmpty, name.count <= 120, !repositories.isEmpty,
              repositories.count <= 100, Set(repositories.map(\.id)).count == repositories.count,
              repositories.filter({ $0.role == "authority" }).map(\.id) == [authorityID],
              repositories.allSatisfy({ ProjectLinkAccess.validID($0.id) && !$0.name.isEmpty && $0.name.count <= 120 &&
                ["authority", "child"].contains($0.role) && (0...100).contains($0.availableAttachments) }) else { throw ProjectLinkError.invalid }
    }
}
struct ProjectLinkAccess: Equatable, Sendable {
    let workspaceInstanceID: String
    let actorID: String
    let peerID: String
    let projectIDs: Set<String>
    let expiresAt: Date
    let epoch: String
    static func validID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9._:-]{1,128}$", options: .regularExpression) != nil
    }
    func validate() throws {
        guard expiresAt > Date() else { throw ProjectLinkError.expired }
        guard [workspaceInstanceID, actorID, peerID, epoch].allSatisfy(Self.validID),
              projectIDs.count <= 100, projectIDs.allSatisfy(Self.validID) else { throw ProjectLinkError.invalid }
    }
    func intentKey(_ project: String) -> String {
        SHA256.hash(data: Data((storageKey + "\n" + project).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var storageKey: String {
        SHA256.hash(data: Data([workspaceInstanceID, actorID, peerID].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
enum ProjectLinkError: Error { case denied, unavailable, unsupported, expired, conflict, invalid, notFound }
struct ProjectLinkIntent: Codable, Equatable, Sendable {
    let scopeKey: String
    let projectID: String
    let expectedRevision: Int
    let operationID: String
    let authorityID: String
    func validate(_ key: String) throws {
        guard scopeKey == key, ProjectLinkAccess.validID(projectID), expectedRevision > 0,
              ProjectLinkAccess.validID(operationID), ProjectLinkAccess.validID(authorityID) else { throw ProjectLinkError.invalid }
    }
}
protocol ProjectLinkIntentStorage: Sendable {
    func load(_ key: String) throws -> ProjectLinkIntent?
    func save(_ intent: ProjectLinkIntent, key: String) throws
}
struct PrivateProjectLinkIntents: ProjectLinkIntentStorage {
    let records: PrivateLocalRecordStore
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workspace/ProjectLinkIntents")) {
        records = PrivateLocalRecordStore(root: root, namespace: "project-link")
    }
    func load(_ key: String) throws -> ProjectLinkIntent? {
        guard let data = try records.load(key) else { return nil }
        let intent = try JSONDecoder().decode(ProjectLinkIntent.self, from: data)
        try intent.validate(key); return intent
    }
    func save(_ intent: ProjectLinkIntent, key: String) throws {
        try intent.validate(key); try records.save(JSONEncoder().encode(intent), key: key)
    }
}
protocol ProjectLinkReading: Sendable {
    func access() async throws -> ProjectLinkAccess
    func discover(_ access: ProjectLinkAccess) async throws -> [LinkProject]
    func inspect(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology
    func link(_ access: ProjectLinkAccess, intent: ProjectLinkIntent) async throws -> String
    func open(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology
}
struct UnboundProjectLinkReader: ProjectLinkReading {
    func access() async throws -> ProjectLinkAccess { throw ProjectLinkError.unsupported }
    func discover(_ access: ProjectLinkAccess) async throws -> [LinkProject] { throw ProjectLinkError.unsupported }
    func inspect(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology { throw ProjectLinkError.unsupported }
    func link(_ access: ProjectLinkAccess, intent: ProjectLinkIntent) async throws -> String { throw ProjectLinkError.unsupported }
    func open(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology { throw ProjectLinkError.unsupported }
}
@MainActor
final class ProjectLinkState: ObservableObject {
    @Published private(set) var phase = "unavailable"
    @Published private(set) var projects: [LinkProject] = []
    @Published private(set) var selection: String?
    @Published private(set) var topology: LinkTopology?
    @Published private(set) var opened: LinkTopology?
    @Published private(set) var busy = false
    private(set) var access: ProjectLinkAccess?
    private let reader: any ProjectLinkReading
    private let intents: any ProjectLinkIntentStorage
    private var generation = 0
    private var expiryTask: Task<Void, Never>?
    init(reader: any ProjectLinkReading = UnboundProjectLinkReader(), intents: any ProjectLinkIntentStorage = PrivateProjectLinkIntents()) {
        self.reader = reader; self.intents = intents
    }
    func invalidate() {
        expiryTask?.cancel(); expiryTask = nil
        generation += 1; busy = false; access = nil; projects = []; selection = nil; topology = nil; opened = nil; phase = "unavailable"
    }
    func expireIfNecessary(now: Date = Date()) {
        if let access, access.expiresAt <= now { invalidate(); phase = "expired" }
    }
    private func armExpiry(_ deadline: Date, ticket: Int) {
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                if remaining <= 0 {
                    self?.expireIfNecessary()
                    return
                }
                do { try await Task.sleep(for: .seconds(min(remaining, 30)), tolerance: .zero) } catch { return }
                guard self != nil else { return }
            }
        }
    }
    private func failure(_ error: Error) {
        expiryTask?.cancel(); expiryTask = nil
        projects = []; topology = nil; opened = nil; selection = nil; access = nil
        switch error {
        case ProjectLinkError.denied: phase = "denied"
        case ProjectLinkError.expired: phase = "expired"
        case ProjectLinkError.conflict: phase = "conflict"
        case ProjectLinkError.unsupported: phase = "unsupported"
        case ProjectLinkError.invalid: phase = "invalid"
        default: phase = "unavailable"
        }
    }
    func refresh() async {
        invalidate(); let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let current = try await reader.access(); try current.validate()
            guard ticket == generation else { return }
            let values = try await reader.discover(current); try current.validate()
            guard ticket == generation else { return }
            guard values.count <= 100, Set(values.map(\.id)).count == values.count,
                  values.allSatisfy({ current.projectIDs.contains($0.id) && ProjectLinkAccess.validID($0.id) && !$0.name.isEmpty && $0.name.count <= 120 }) else { throw ProjectLinkError.invalid }
            access = current; projects = values; phase = values.isEmpty ? "empty" : "choose"
            armExpiry(current.expiresAt, ticket: ticket)
        } catch { if ticket == generation { failure(error) } }
    }
    func select(_ project: String) async {
        guard let current = access, projects.contains(where: { $0.id == project }), !busy else { return }
        generation += 1; let ticket = generation; selection = project; topology = nil; opened = nil; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try current.validate()
            let value = try await reader.inspect(current, project: project); try value.validate(current, project: project)
            guard ticket == generation else { return }; topology = value; phase = "inspect"
            armExpiry(current.expiresAt, ticket: ticket)
        } catch { if ticket == generation { failure(error) } }
    }
    func linkAndOpen() async {
        guard let current = access, let value = topology, selection == value.projectID, !busy else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            try value.validate(current, project: value.projectID)
            let key = current.intentKey(value.projectID)
            let existing = try intents.load(key)
            let intent: ProjectLinkIntent
            if let existing, existing.projectID == value.projectID {
                intent = existing
            } else {
                intent = .init(scopeKey: key, projectID: value.projectID, expectedRevision: value.revision, operationID: UUID().uuidString, authorityID: value.authorityID)
                try intents.save(intent, key: key)
            }
            let identity = try await reader.link(current, intent: intent); try current.validate()
            guard ticket == generation else { return }
            guard identity == value.projectID else { throw ProjectLinkError.invalid }
            let fresh = try await reader.open(current, project: identity); try fresh.validate(current, project: identity)
            guard ticket == generation else { return }; opened = fresh; topology = fresh; phase = "opened"
        } catch { if ticket == generation { failure(error) } }
    }
}
