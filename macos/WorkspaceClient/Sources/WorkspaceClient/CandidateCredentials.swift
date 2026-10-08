import Foundation
import CryptoKit
import Security

struct CandidateAccess: Codable, Equatable, Sendable {
    let endpoint:String
    let workspaceInstanceID:String
    let workspaceProjectID:String
    let actorID:String
    let forgeInstanceID:String
    let forgeProjectID:String
    let repositoryID:String
    let conversationID:String
    let proposalIDs:[String]
    let maximumRegistrations:Int
    let token:String
    var valid:Bool {
        AdvisoryAccess(endpoint:endpoint,workspaceInstanceID:workspaceInstanceID,workspaceProjectID:workspaceProjectID,actorID:actorID,
            forgeInstanceID:forgeInstanceID,forgeProjectID:forgeProjectID,repositoryID:repositoryID,conversationIDs:[conversationID],token:token).valid &&
        (1...16).contains(proposalIDs.count) && Set(proposalIDs).count==proposalIDs.count && proposalIDs==proposalIDs.sorted() &&
        proposalIDs.allSatisfy(WorklistWire.identifier) && (1...8).contains(maximumRegistrations)
    }
    func matches(_ c:AdvisoryConnection) -> Bool {
        valid && endpoint==c.endpoint && workspaceInstanceID==c.workspaceInstanceID && workspaceProjectID==c.workspaceProjectID && actorID==c.actorID && conversationID==c.conversationID
    }
}
protocol CandidateCredentials: Sendable {
    func load() throws -> CandidateAccess?
    func save(_ access:CandidateAccess) throws
    func forget() throws
}
struct CandidateKeychain: CandidateCredentials {
    let operations:DraftKeychainOperations
    init(operations:DraftKeychainOperations = .live) { self.operations=operations }
    private var query:[CFString:Any] {
        [kSecClass:kSecClassGenericPassword,kSecAttrService:"com.pcvantol.workspace.native-client.candidate.v1",
         kSecAttrAccount:"candidate-access",kSecAttrSynchronizable:kCFBooleanFalse as Any]
    }
    func load() throws -> CandidateAccess? {
        var q=query;q[kSecReturnData]=true;q[kSecMatchLimit]=kSecMatchLimitOne
        let (status,data)=operations.copy(q as CFDictionary)
        if status==errSecItemNotFound { return nil }
        guard status==errSecSuccess,let data else { throw CredentialError.keychain(status) }
        let v=try JSONDecoder().decode(CandidateAccess.self,from:data)
        guard v.valid else { throw CredentialError.corruptBinding };return v
    }
    func save(_ access:CandidateAccess) throws {
        guard access.valid else { throw CredentialError.corruptBinding }
        let data=try JSONEncoder().encode(access),q=query
        let updated=operations.update(q as CFDictionary,[kSecValueData:data] as CFDictionary)
        if updated==errSecSuccess { return }
        guard updated==errSecItemNotFound else { throw CredentialError.keychain(updated) }
        var entry=q;entry[kSecValueData]=data;entry[kSecAttrAccessible]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status=operations.add(entry as CFDictionary)
        guard status==errSecSuccess else { throw CredentialError.keychain(status) }
    }
    func forget() throws {
        let status=operations.delete(query as CFDictionary)
        guard status==errSecSuccess || status==errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
}
