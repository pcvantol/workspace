import CryptoKit
import Darwin
import Foundation

struct LocalDraftSnapshot: Codable, Equatable, Sendable {
    let scopeHash: String
    let selectedID: String?
    let title: String
    let focus: String
    let mode: String
    let draft: String
    let savedRevision: Int?
    let requestID: String
}

protocol LocalDraftStore: Sendable {
    func load(scopeHash: String) throws -> LocalDraftSnapshot?
    func save(_ snapshot: LocalDraftSnapshot) throws
    func remove(scopeHash: String) throws
}

struct PrivateLocalDraftCache: LocalDraftStore {
    let root: URL

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Workspace/Drafts", isDirectory: true)) {
        self.root = root
    }

    static func scopeHash(_ access: DraftAccess) -> String {
        let source = [access.endpoint, access.instanceID, access.projectID, access.token].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func file(_ key: String) throws -> URL {
        guard key.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw ConversationError.invalidResponse
        }
        return root.appendingPathComponent("local-\(key).json", isDirectory: false)
    }

    private func checkRoot() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let attributes = try manager.attributesOfItem(atPath: root.path)
        guard values.isDirectory == true, values.isSymbolicLink != true,
              attributes[.ownerAccountID] as? Int == Int(getuid()),
              ((attributes[.posixPermissions] as? Int) ?? 0o777) & 0o077 == 0 else {
            throw ConversationError.unavailable
        }
    }

    private func checkFile(_ url: URL) throws -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return false }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              attributes[.ownerAccountID] as? Int == Int(getuid()),
              ((attributes[.posixPermissions] as? Int) ?? 0o777) & 0o077 == 0 else {
            throw ConversationError.unavailable
        }
        return true
    }

    func load(scopeHash: String) throws -> LocalDraftSnapshot? {
        try checkRoot()
        let url = try file(scopeHash)
        guard try checkFile(url) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 48_000,
              let snapshot = try? JSONDecoder().decode(LocalDraftSnapshot.self, from: data),
              snapshot.scopeHash == scopeHash,
              snapshot.requestID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              snapshot.title.count <= 120, snapshot.focus.count <= 240,
              snapshot.draft.count <= 10_000, ["BUSINESS", "ARCHITECTURE", "UX"].contains(snapshot.mode) else {
            throw ConversationError.invalidResponse
        }
        return snapshot
    }

    func save(_ snapshot: LocalDraftSnapshot) throws {
        try checkRoot()
        let target = try file(snapshot.scopeHash)
        if try checkFile(target) { /* Existing private file may be atomically replaced. */ }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 48_000 else { throw ConversationError.invalidDraft }
        let temporary = root.appendingPathComponent(".local-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ConversationError.unavailable }
        defer { _ = Darwin.unlink(temporary.path) }
        do {
            try data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                    guard written > 0 else { throw ConversationError.unavailable }
                    offset += written
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw ConversationError.unavailable }
        } catch {
            _ = Darwin.close(descriptor)
            throw error
        }
        guard Darwin.close(descriptor) == 0,
              Darwin.rename(temporary.path, target.path) == 0 else {
            throw ConversationError.unavailable
        }
    }

    func remove(scopeHash: String) throws {
        try checkRoot()
        let target = try file(scopeHash)
        guard try checkFile(target) else { return }
        guard Darwin.unlink(target.path) == 0 else { throw ConversationError.unavailable }
    }
}
