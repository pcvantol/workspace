import Foundation
import Security
import CryptoKit

struct WorklistControlIntent: Codable, Equatable {
    let accessFingerprint: String
    let endpoint: String
    let workspaceInstanceID: String
    let actorID: String
    let request: WorklistControlRequest
    func matches(_ access: WorklistAccess) -> Bool {
        access.valid && endpoint == access.endpoint && workspaceInstanceID == access.workspaceInstanceID &&
        actorID == access.actorID && request.instance_id == access.forgeInstanceID &&
        access.worksetIDs.contains(request.workset_id) && accessFingerprint == Self.fingerprint(access) && request.valid
    }
    static func fingerprint(_ access: WorklistAccess) -> String {
        SHA256.hash(data: Data(access.token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

protocol WorklistControlCredentials: Sendable {
    func loadAccess() throws -> WorklistAccess?
    func saveAccess(_ access: WorklistAccess) throws
    func forgetAccess() throws
    func loadIntent() throws -> WorklistControlIntent?
    func saveIntent(_ intent: WorklistControlIntent) throws
    func forgetIntent() throws
}

struct WorklistControlKeychain: WorklistControlCredentials {
    private let operations: DraftKeychainOperations
    init(operations: DraftKeychainOperations = .live) { self.operations = operations }
    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.pcvantol.workspace.native-client.worklist-controls.v1",
         kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }
    private func load(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(q as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        return data
    }
    private func save(_ data: Data, account: String) throws {
        let q = query(account)
        let status = operations.update(q as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var added = q; added[kSecValueData] = data
        added[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = operations.add(added as CFDictionary)
        guard result == errSecSuccess else { throw CredentialError.keychain(result) }
    }
    private func forget(_ account: String) throws {
        let status = operations.delete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
    func loadAccess() throws -> WorklistAccess? {
        guard let data = try load("actor-control-grant") else { return nil }
        let value = try JSONDecoder().decode(WorklistAccess.self, from: data)
        guard value.valid else { throw CredentialError.corruptBinding }; return value
    }
    func saveAccess(_ access: WorklistAccess) throws {
        guard access.valid else { throw CredentialError.corruptBinding }
        try save(JSONEncoder().encode(access), account: "actor-control-grant")
    }
    func forgetAccess() throws { try forget("actor-control-grant") }
    func loadIntent() throws -> WorklistControlIntent? {
        guard let data = try load("pending-control-intent") else { return nil }
        let intent = try JSONDecoder().decode(WorklistControlIntent.self, from: data)
        guard intent.request.valid, WorklistWire.identifier(intent.actorID), intent.accessFingerprint.count == 64,
              (try? ServerEndpoint(intent.endpoint))?.url.absoluteString == intent.endpoint else { throw CredentialError.corruptBinding }
        return intent
    }
    func saveIntent(_ intent: WorklistControlIntent) throws {
        guard intent.request.valid else { throw CredentialError.corruptBinding }
        try save(JSONEncoder().encode(intent), account: "pending-control-intent")
    }
    func forgetIntent() throws { try forget("pending-control-intent") }
}

struct WorklistControlTransport: Sendable {
    let session: URLSession
    init(configuration: URLSessionConfiguration? = nil) {
        let config = configuration ?? .ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
    }
    func request(endpoint: String, instance: String, workspaceToken: String, grant: String,
                 path: String, body: Data? = nil) async throws -> Data {
        let base = try ServerEndpoint(endpoint)
        guard instance.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              grant.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              path.range(of: "^/v1/workset-controls(?:/[A-Za-z0-9][A-Za-z0-9._:-]{0,127}(?:/commands(?:/[A-Za-z0-9][A-Za-z0-9._:-]{0,127})?)?)?$", options: .regularExpression) != nil else { throw WorklistControlError.denied }
        var request = URLRequest(url: base.url.appendingPathComponent(String(path.dropFirst())), timeoutInterval: 6)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer " + workspaceToken, forHTTPHeaderField: "Authorization")
        request.setValue(instance, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(grant, forHTTPHeaderField: "X-Workspace-Worklist-Control-Grant")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WorklistControlError.unavailable }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw WorklistControlError.denied
        case 404: throw WorklistControlError.missing
        case 409: throw WorklistControlError.conflict
        case 400: throw WorklistControlError.invalid
        default: throw WorklistControlError.unavailable
        }
        guard data.count <= 1_000_000, http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true else { throw WorklistControlError.invalid }
        return data
    }
    func probe(connection: WorklistConnection, token: String) async throws -> WorklistAccess {
        guard let bearer = connection.readToken else { throw WorklistControlError.unavailable }
        let data = try await request(endpoint: connection.endpoint, instance: connection.instanceID,
            workspaceToken: bearer, grant: token, path: "/v1/workset-controls")
        let value = try WorklistControlWire.object(JSONSerialization.jsonObject(with: data), keys: ["contract_version", "instance_id", "principal_id", "workset_ids"])
        guard value["contract_version"] as? String == "workspace-worklist-control-access/v1",
              let forge = value["instance_id"] as? String, let actor = value["principal_id"] as? String,
              let worksets = value["workset_ids"] as? [String] else { throw WorklistControlError.invalid }
        let access = WorklistAccess(endpoint: connection.endpoint, workspaceInstanceID: connection.instanceID,
            forgeInstanceID: forge, actorID: actor, worksetIDs: worksets, token: token)
        guard access.valid else { throw WorklistControlError.invalid }; return access
    }
    func read(access: WorklistAccess, bearer: String, workset: String,
              intent: WorklistControlRequest? = nil) async throws -> WorklistControlObservation {
        guard access.valid, access.worksetIDs.contains(workset), intent == nil || intent?.workset_id == workset else { throw WorklistControlError.denied }
        let path = "/v1/workset-controls/" + workset + (intent.map { "/commands/" + $0.operation_id } ?? "")
        let data = try await request(endpoint: access.endpoint, instance: access.workspaceInstanceID, workspaceToken: bearer, grant: access.token, path: path)
        return try WorklistControlWire.response(data, access: access, workset: workset, expected: intent)
    }
    func submit(access: WorklistAccess, bearer: String, request body: WorklistControlRequest) async throws -> WorklistControlObservation {
        guard access.valid, body.valid, body.instance_id == access.forgeInstanceID,
              access.worksetIDs.contains(body.workset_id) else { throw WorklistControlError.denied }
        let data = try await request(endpoint: access.endpoint, instance: access.workspaceInstanceID, workspaceToken: bearer,
            grant: access.token, path: "/v1/workset-controls/" + body.workset_id + "/commands", body: body.data())
        return try WorklistControlWire.response(data, access: access, workset: body.workset_id, expected: body, result: true)
    }
}
