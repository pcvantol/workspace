#if WORKSPACE_ISOLATED_TEST
import Darwin
import Foundation

struct IsolatedTestDocument: Decodable {
    let endpoint: String
    let instance_id: String
    let read_token: String
    let project_id: String
    let draft_grant: String
    let local_root: String

    static func load() throws -> IsolatedTestDocument {
        guard let path = ProcessInfo.processInfo.environment["WORKSPACE_ISOLATED_CREDENTIALS_FILE"],
              path.hasPrefix("/"), !path.contains("/../") else {
            throw ConversationError.invalidResponse
        }
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              attributes[.ownerAccountID] as? Int == Int(getuid()),
              ((attributes[.posixPermissions] as? Int) ?? 0o777) & 0o077 == 0 else {
            throw ConversationError.invalidResponse
        }
        guard let data = FileManager.default.contents(atPath: path), data.count <= 4096 else {
            throw ConversationError.invalidResponse
        }
        let document = try JSONDecoder().decode(Self.self, from: data)
        let endpoint = try ServerEndpoint(document.endpoint)
        guard endpoint.url.absoluteString == document.endpoint, endpoint.url.scheme == "http",
              ["127.0.0.1", "localhost", "::1"].contains(endpoint.url.host ?? ""),
              document.instance_id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              !document.read_token.isEmpty, document.read_token.count <= 256,
              document.draft_grant.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              !document.project_id.isEmpty, document.project_id.count <= 120,
              document.local_root.hasPrefix("/"), !document.local_root.contains("/../") else {
            throw ConversationError.invalidResponse
        }
        return document
    }
}

final class IsolatedServerCredentials: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBinding: ServerBinding?
    private var storedToken: String?

    init(_ document: IsolatedTestDocument) {
        storedBinding = ServerBinding(endpoint: document.endpoint, instanceID: document.instance_id)
        storedToken = document.read_token
    }

    func binding() throws -> ServerBinding? { lock.withLock { storedBinding } }
    func token() throws -> String? { lock.withLock { storedToken } }
    func save(binding: ServerBinding, token: String) throws {
        lock.withLock { storedBinding = binding; storedToken = token }
    }
    func forget() throws { lock.withLock { storedBinding = nil; storedToken = nil } }
}

final class IsolatedDraftGrant: DraftGrantStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DraftAccess?
    init(_ document: IsolatedTestDocument) {
        stored = DraftAccess(endpoint: document.endpoint, instanceID: document.instance_id,
                             projectID: document.project_id, token: document.draft_grant)
    }
    func load() throws -> DraftAccess? { lock.withLock { stored } }
    func save(_ access: DraftAccess) throws { lock.withLock { stored = access } }
    func forget() throws { lock.withLock { stored = nil } }
}
#endif
