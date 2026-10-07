import Foundation
import Security

enum WorklistTransportError: Error, Equatable {
    case unauthorized, denied, wrongInstance, missing, unavailable, invalidResponse, inconsistentSnapshot
}

enum WorklistWire {
    static func identifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", options: .regularExpression) != nil
    }

    static func digest(_ value: String) -> Bool {
        value.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    static func exactObject(_ data: Data, keys: Set<String>) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == keys else { throw WorklistTransportError.invalidResponse }
    }
}

struct WorklistAccess: Codable, Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let forgeInstanceID: String
    let actorID: String
    let worksetIDs: [String]
    let token: String

    var valid: Bool {
        token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil &&
        workspaceInstanceID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil &&
        WorklistWire.identifier(forgeInstanceID) && WorklistWire.identifier(actorID) &&
        (1...16).contains(worksetIDs.count) && Set(worksetIDs).count == worksetIDs.count &&
        worksetIDs.allSatisfy(WorklistWire.identifier) &&
        (try? ServerEndpoint(endpoint))?.url.absoluteString == endpoint
    }
}

protocol WorklistCredentialStore: Sendable {
    func loadAccess() throws -> WorklistAccess?
    func saveAccess(_ access: WorklistAccess) throws
    func forgetAccess() throws
}

struct WorklistKeychain: WorklistCredentialStore {
    private let service = "com.pcvantol.workspace.native-client.worklists.v1"
    private let operations: DraftKeychainOperations

    init(operations: DraftKeychainOperations = .live) { self.operations = operations }

    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: "actor-read-grant", kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }

    func loadAccess() throws -> WorklistAccess? {
        var request = query
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(request as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        guard let saved = try? JSONDecoder().decode(WorklistAccess.self, from: data), saved.valid else {
            throw CredentialError.corruptBinding
        }
        return saved
    }

    func saveAccess(_ access: WorklistAccess) throws {
        guard access.valid else { throw CredentialError.corruptBinding }
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

    func forgetAccess() throws {
        let status = operations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }
}

struct ForgeWorklistScopes: Decodable, Sendable {
    let contract_version: String
    let instance_id: String
    let principal_id: String
    let workset_ids: [String]
    let read_only: Bool

    func valid(for access: WorklistAccess) -> Bool {
        contract_version == "forge-workspace-worklist-scopes/v1" &&
        instance_id == access.forgeInstanceID && principal_id == access.actorID &&
        read_only && access.valid && Set(workset_ids) == Set(access.worksetIDs) &&
        workset_ids.count == access.worksetIDs.count
    }
}

struct WorklistTransport: Sendable {
    let session: URLSession

    init(configuration supplied: URLSessionConfiguration? = nil) {
        let configuration = supplied ?? .ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    private func read(endpoint: ServerEndpoint, workspaceToken: String, instance: String,
                      grant: String, path: String) async throws -> Data {
        var request = URLRequest(url: endpoint.route(path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(workspaceToken)", forHTTPHeaderField: "Authorization")
        request.setValue(instance, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(grant, forHTTPHeaderField: "X-Workspace-Worklist-Grant")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch { throw WorklistTransportError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw WorklistTransportError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw WorklistTransportError.unauthorized
        case 403: throw WorklistTransportError.denied
        case 404: throw WorklistTransportError.missing
        case 409: throw WorklistTransportError.wrongInstance
        case 503:
            if let error = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let code = error["error"],
               ["WORKLIST_INVALID_RESPONSE", "WORKLIST_INCONSISTENT_SNAPSHOT"].contains(code) {
                throw WorklistTransportError.inconsistentSnapshot
            }
            throw WorklistTransportError.unavailable
        default: throw WorklistTransportError.unavailable
        }
        guard data.count <= 1_000_000,
              http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";", maxSplits: 1).first?.lowercased() == "application/json" else {
            throw WorklistTransportError.invalidResponse
        }
        return data
    }

    private func decodeScopes(_ data: Data) throws -> ForgeWorklistScopes {
        try WorklistWire.exactObject(data, keys: ["contract_version", "instance_id", "principal_id", "workset_ids", "read_only"])
        guard let scopes = try? JSONDecoder().decode(ForgeWorklistScopes.self, from: data) else {
            throw WorklistTransportError.invalidResponse
        }
        return scopes
    }

    func probe(endpoint: ServerEndpoint, workspaceToken: String, instance: String,
               worklistToken: String) async throws -> WorklistAccess {
        let scopes = try decodeScopes(await read(endpoint: endpoint, workspaceToken: workspaceToken,
            instance: instance, grant: worklistToken, path: "/v1/worksets"))
        let access = WorklistAccess(endpoint: endpoint.url.absoluteString, workspaceInstanceID: instance,
            forgeInstanceID: scopes.instance_id, actorID: scopes.principal_id,
            worksetIDs: scopes.workset_ids, token: worklistToken)
        guard scopes.valid(for: access) else { throw WorklistTransportError.invalidResponse }
        return access
    }

    func scopes(access: WorklistAccess, workspaceToken: String) async throws -> [String] {
        guard access.valid else { throw WorklistTransportError.denied }
        let endpoint = try ServerEndpoint(access.endpoint)
        let result = try decodeScopes(await read(endpoint: endpoint, workspaceToken: workspaceToken,
            instance: access.workspaceInstanceID, grant: access.token, path: "/v1/worksets"))
        guard result.valid(for: access) else { throw WorklistTransportError.denied }
        return result.workset_ids
    }
    func snapshot(access: WorklistAccess, workspaceToken: String, worksetID: String) async throws -> ApprovedWorklistSnapshot {
        guard access.valid, access.worksetIDs.contains(worksetID) else { throw WorklistTransportError.denied }
        let data = try await read(endpoint: ServerEndpoint(access.endpoint), workspaceToken: workspaceToken,
            instance: access.workspaceInstanceID, grant: access.token, path: "/v1/worksets/\(worksetID)")
        return try WorklistProjection.decode(data, access: access, worksetID: worksetID)
    }

}
