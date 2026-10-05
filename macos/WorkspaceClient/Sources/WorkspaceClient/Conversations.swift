import Foundation
import CryptoKit
import Security

struct DraftAccess: Codable, Sendable, Equatable {
    let endpoint: String
    let instanceID: String
    let projectID: String
    let token: String
}

protocol DraftGrantStore: Sendable {
    func load() throws -> DraftAccess?
    func save(_ access: DraftAccess) throws
    func forget() throws
}

struct DraftKeychainOperations: Sendable {
    let copy: @Sendable (CFDictionary) -> (OSStatus, Data?)
    let update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
    let add: @Sendable (CFDictionary) -> OSStatus
    let delete: @Sendable (CFDictionary) -> OSStatus

    static let live = DraftKeychainOperations(
        copy: { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query, &result)
            return (status, result as? Data)
        },
        update: { SecItemUpdate($0, $1) },
        add: { SecItemAdd($0, nil) },
        delete: { SecItemDelete($0) }
    )
}

struct DraftGrantKeychain: DraftGrantStore {
    private let service = "com.pcvantol.workspace.native-client.drafts.v1"
    private let account = "project-draft-grant"
    private let operations: DraftKeychainOperations

    init(operations: DraftKeychainOperations = .live) { self.operations = operations }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }

    func load() throws -> DraftAccess? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(request as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data,
              let access = try? JSONDecoder().decode(DraftAccess.self, from: data),
              access.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              access.instanceID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              (try? ServerEndpoint(access.endpoint))?.url.absoluteString == access.endpoint else {
            throw CredentialError.corruptBinding
        }
        return access
    }

    func save(_ access: DraftAccess) throws {
        let data = try JSONEncoder().encode(access)
        let status = operations.update(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = operations.add(item as CFDictionary)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

    func forget() throws {
        let status = operations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }
}

struct Conversation: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let actor_id: String
    let project_id: String
    var title: String
    var focus: String
    var mode: String
    var draft: String
    let archived: Bool
    let revision: Int
    let created_at: String
    let updated_at: String
    let history: [String]
    let history_availability: String
    let state: String

    init(id: String, actor_id: String, project_id: String, title: String, focus: String,
         mode: String, draft: String, archived: Bool = false, revision: Int,
         created_at: String, updated_at: String, history: [String],
         history_availability: String, state: String) {
        self.id = id
        self.actor_id = actor_id
        self.project_id = project_id
        self.title = title
        self.focus = focus
        self.mode = mode
        self.draft = draft
        self.archived = archived
        self.revision = revision
        self.created_at = created_at
        self.updated_at = updated_at
        self.history = history
        self.history_availability = history_availability
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, actor_id, project_id, title, focus, mode, draft, archived, revision
        case created_at, updated_at, history, history_availability, state
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        actor_id = try values.decode(String.self, forKey: .actor_id)
        project_id = try values.decode(String.self, forKey: .project_id)
        title = try values.decode(String.self, forKey: .title)
        focus = try values.decode(String.self, forKey: .focus)
        mode = try values.decode(String.self, forKey: .mode)
        draft = try values.decode(String.self, forKey: .draft)
        archived = try values.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        revision = try values.decode(Int.self, forKey: .revision)
        created_at = try values.decode(String.self, forKey: .created_at)
        updated_at = try values.decode(String.self, forKey: .updated_at)
        history = try values.decode([String].self, forKey: .history)
        history_availability = try values.decode(String.self, forKey: .history_availability)
        state = try values.decode(String.self, forKey: .state)
    }

    var isOwnDraft: Bool {
        state == "DRAFT_ONLY" && history.isEmpty && history_availability == "UNQUALIFIED_FORGE" &&
        ["BUSINESS", "ARCHITECTURE", "UX"].contains(mode) && revision > 0
    }
}

struct ConversationList: Decodable, Sendable {
    let actor_id: String
    let project_id: String
    let conversations: [Conversation]
    let history_availability: String
}

struct DraftFields: Encodable, Sendable {
    let title: String
    let focus: String
    let mode: String
    let draft: String
    let expected_revision: Int?
    let request_id: String?
}

struct ArchiveCommand: Encodable, Sendable, Equatable {
    let expected_revision: Int
    let operation_id: String

    static func make(conversationID: String, archived: Bool,
                     expectedRevision: Int) -> ArchiveCommand {
        let action = archived ? "ARCHIVE" : "RESTORE"
        let command = Data("\(conversationID):\(action):\(expectedRevision)".utf8)
        let binding = SHA256.hash(data: command).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            .lowercased().prefix(16)
        return ArchiveCommand(expected_revision: expectedRevision,
                              operation_id: binding + nonce)
    }
}

enum ConversationError: Error, LocalizedError, Equatable {
    case unavailable, unauthorized, forbidden, conflict, unsupported, invalidResponse, invalidDraft

    var errorDescription: String? {
        switch self {
        case .unavailable: "Draft Server unavailable. Your unsaved text remains in this window."
        case .unauthorized: "The Server read token was rejected. Reconnect in Settings."
        case .forbidden: "This project needs its own draft grant."
        case .conflict: "A newer draft exists. Reload it before saving again."
        case .unsupported: "This Workspace Server does not support conversation archiving."
        case .invalidResponse: "The Server returned an inconsistent draft response."
        case .invalidDraft: "Enter a title and keep the draft within the field limits."
        }
    }
}

struct ConversationTransport: Sendable {
    let session: URLSession

    init(configuration supplied: URLSessionConfiguration? = nil) {
        let configuration = supplied ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    private func request<T: Decodable>(_ type: T.Type, endpoint: ServerEndpoint, readToken: String,
        instance: String, grant: String, path: String, method: String = "GET", body: Data? = nil,
        expectedStatus: Int = 200) async throws -> T {
        var request = URLRequest(url: endpoint.route(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(readToken)", forHTTPHeaderField: "Authorization")
        request.setValue(instance, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(grant, forHTTPHeaderField: "X-Workspace-Draft-Grant")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ConversationError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw ConversationError.invalidResponse }
        switch http.statusCode {
        case expectedStatus: break
        case 401: throw ConversationError.unauthorized
        case 403: throw ConversationError.forbidden
        case 409: throw ConversationError.conflict
        case 405: throw ConversationError.unsupported
        default: throw ConversationError.unavailable
        }
        guard data.count <= 1_000_000,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw ConversationError.invalidResponse
        }
        return value
    }

    func list(endpoint: ServerEndpoint, readToken: String, access: DraftAccess) async throws -> ConversationList {
        let value = try await request(ConversationList.self, endpoint: endpoint, readToken: readToken,
                                      instance: access.instanceID, grant: access.token,
                                      path: "/v1/conversations")
        guard value.project_id == access.projectID, value.history_availability == "UNQUALIFIED_FORGE",
              value.conversations.allSatisfy({ $0.project_id == access.projectID &&
                  $0.actor_id == value.actor_id && $0.isOwnDraft }),
              Set(value.conversations.map(\.id)).count == value.conversations.count else {
            throw ConversationError.invalidResponse
        }
        return value
    }

    func create(endpoint: ServerEndpoint, readToken: String, access: DraftAccess,
                fields: DraftFields) async throws -> Conversation {
        let value = try await request(Conversation.self, endpoint: endpoint, readToken: readToken,
                                      instance: access.instanceID, grant: access.token,
                                      path: "/v1/conversations", method: "POST",
                                      body: try JSONEncoder().encode(fields),
                                      expectedStatus: 201)
        guard value.project_id == access.projectID && value.isOwnDraft else {
            throw ConversationError.invalidResponse
        }
        return value
    }

    func update(endpoint: ServerEndpoint, readToken: String, access: DraftAccess,
                id: String, fields: DraftFields) async throws -> Conversation {
        guard id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw ConversationError.invalidResponse
        }
        let value = try await request(Conversation.self, endpoint: endpoint, readToken: readToken,
                                      instance: access.instanceID, grant: access.token,
                                      path: "/v1/conversations/\(id)", method: "PATCH",
                                      body: try JSONEncoder().encode(fields))
        guard value.id == id && value.project_id == access.projectID && value.isOwnDraft,
              value.revision == (fields.expected_revision ?? -1) + 1 else {
            throw ConversationError.invalidResponse
        }
        return value
    }

    func setArchived(endpoint: ServerEndpoint, readToken: String, access: DraftAccess,
                     id: String, archived: Bool, command: ArchiveCommand) async throws -> Conversation {
        guard id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              command.operation_id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw ConversationError.invalidResponse
        }
        let action = archived ? "archive" : "restore"
        let value = try await request(Conversation.self, endpoint: endpoint, readToken: readToken,
                                      instance: access.instanceID, grant: access.token,
                                      path: "/v1/conversations/\(id)/\(action)", method: "POST",
                                      body: try JSONEncoder().encode(command))
        guard value.id == id && value.project_id == access.projectID && value.isOwnDraft,
              value.revision >= command.expected_revision else {
            throw ConversationError.invalidResponse
        }
        return value
    }
}
