import Foundation
import CryptoKit
import Security

enum AdvisoryError: Error { case denied, missing, invalid, unavailable, state(String) }
struct AdvisoryAccess: Codable, Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let workspaceProjectID: String
    let actorID: String
    let forgeInstanceID: String
    let forgeProjectID: String
    let repositoryID: String
    let conversationIDs: [String]
    let token: String
    var valid: Bool {
        (try? ServerEndpoint(endpoint))?.url.absoluteString==endpoint && workspaceInstanceID.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil &&
        [workspaceProjectID,actorID,forgeInstanceID,forgeProjectID,repositoryID].allSatisfy(WorklistWire.identifier) &&
        (1...16).contains(conversationIDs.count) && Set(conversationIDs).count==conversationIDs.count &&
        conversationIDs.allSatisfy { $0.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil } &&
        token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil
    }
    var fingerprint: String { SHA256.hash(data:Data(token.utf8)).map{String(format:"%02x",$0)}.joined() }
}
struct AdvisoryConnection: Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let actorID: String
    let workspaceProjectID: String
    let conversationID: String
    let bearer: String
    let draftGrant: String
}
struct AdvisoryIntent: Codable, Equatable, Sendable {
    let fingerprint: String
    let endpoint: String
    let workspaceInstanceID: String
    let workspaceProjectID: String
    let actorID: String
    let request: AdvisoryRequest
    var cancel: AdvisoryCancelRequest?
    func matches(_ access:AdvisoryAccess, connection:AdvisoryConnection) -> Bool {
        access.valid && fingerprint==access.fingerprint && endpoint==access.endpoint && workspaceInstanceID==access.workspaceInstanceID &&
        workspaceProjectID==access.workspaceProjectID && actorID==access.actorID && request.instance_id==access.forgeInstanceID &&
        request.project_id==access.forgeProjectID && request.repository_id==access.repositoryID && access.conversationIDs.contains(request.conversation_id) &&
        connection.conversationID==request.conversation_id && connection.actorID==actorID && connection.workspaceProjectID==workspaceProjectID &&
        connection.endpoint==endpoint && connection.workspaceInstanceID==workspaceInstanceID
    }
}
protocol AdvisoryCredentials: Sendable {
    func loadAccess() throws -> AdvisoryAccess?
    func saveAccess(_ access:AdvisoryAccess) throws
    func forgetAccess() throws
    func loadIntent() throws -> AdvisoryIntent?
    func saveIntent(_ intent:AdvisoryIntent) throws
    func forgetIntent() throws
}
struct AdvisoryKeychain: AdvisoryCredentials {
    private let operations: DraftKeychainOperations
    init(operations:DraftKeychainOperations = .live) { self.operations=operations }
    private func query(_ account:String) -> [CFString:Any] {
        [kSecClass:kSecClassGenericPassword,kSecAttrService:"com.pcvantol.workspace.native-client.advisory.v1",
         kSecAttrAccount:account,kSecAttrSynchronizable:kCFBooleanFalse as Any]
    }
    private func load(_ account:String) throws -> Data? {
        var q=query(account);q[kSecReturnData]=true;q[kSecMatchLimit]=kSecMatchLimitOne
        let (status,data)=operations.copy(q as CFDictionary)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess,let data else { throw CredentialError.keychain(status) };return data
    }
    private func save(_ data:Data,account:String) throws {
        let q=query(account);let status=operations.update(q as CFDictionary,[kSecValueData:data] as CFDictionary)
        if status==errSecSuccess { return }
        guard status==errSecItemNotFound else { throw CredentialError.keychain(status) }
        var entry=q;entry[kSecValueData]=data;entry[kSecAttrAccessible]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added=operations.add(entry as CFDictionary);guard added==errSecSuccess else { throw CredentialError.keychain(added) }
    }
    private func forget(_ account:String) throws {
        let status=operations.delete(query(account) as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
    func loadAccess() throws -> AdvisoryAccess? {
        guard let data=try load("advisory-access") else { return nil }
        let access=try JSONDecoder().decode(AdvisoryAccess.self,from:data)
        guard access.valid else { throw CredentialError.corruptBinding };return access
    }
    func saveAccess(_ access:AdvisoryAccess) throws {
        guard access.valid else { throw CredentialError.corruptBinding };try save(JSONEncoder().encode(access),account:"advisory-access")
    }
    func forgetAccess() throws { try forget("advisory-access") }
    func loadIntent() throws -> AdvisoryIntent? {
        guard let data=try load("advisory-intent") else { return nil }
        let intent=try JSONDecoder().decode(AdvisoryIntent.self,from:data)
        _=try intent.request.data();guard intent.fingerprint.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil else { throw CredentialError.corruptBinding }
        return intent
    }
    func saveIntent(_ intent:AdvisoryIntent) throws { _=try intent.request.data();try save(JSONEncoder().encode(intent),account:"advisory-intent") }
    func forgetIntent() throws { try forget("advisory-intent") }
}
extension AdvisoryRequest {
    func data() throws -> Data {
        let data=try JSONEncoder().encode(self);try AdvisoryWire.validate(AdvisoryWire.object(data),kind:"request");return data
    }
    var digest:String { (try? AdvisoryWire.digest(AdvisoryWire.object(data()))) ?? "" }
}
