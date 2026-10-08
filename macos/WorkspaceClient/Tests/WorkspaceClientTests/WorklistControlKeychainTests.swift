import Foundation
import Security
import XCTest
@testable import WorkspaceClient

private final class ControlKeychainBackend: @unchecked Sendable {
    var records: [String:Data] = [:]
    var copyFailure: OSStatus?
    var updateFailure: OSStatus?
    var addFailure: OSStatus?
    var deleteFailure: OSStatus?
    var services: [String] = []
    func account(_ query: CFDictionary) -> String {
        let q=query as! [CFString:Any];services.append(q[kSecAttrService] as? String ?? "")
        return q[kSecAttrAccount] as! String
    }
    var operations: DraftKeychainOperations {
        .init(copy:{ q in
            let account=self.account(q)
            if let failure=self.copyFailure { return (failure,nil) }
            return self.records[account].map { (errSecSuccess,$0) } ?? (errSecItemNotFound,nil)
        },update:{ q,values in
            let account=self.account(q)
            if let failure=self.updateFailure { return failure }
            guard self.records[account] != nil else { return errSecItemNotFound }
            self.records[account]=(values as NSDictionary)[kSecValueData] as? Data;return errSecSuccess
        },add:{ q in
            let account=self.account(q)
            if let failure=self.addFailure { return failure }
            self.records[account]=(q as NSDictionary)[kSecValueData] as? Data;return errSecSuccess
        },delete:{ q in
            let account=self.account(q)
            if let failure=self.deleteFailure { return failure }
            self.records.removeValue(forKey:account);return errSecSuccess
        })
    }
}

final class WorklistControlKeychainTests: XCTestCase {
    func testSeparateAccessAndDurableIntentWithoutLiveKeychain() throws {
        let backend=ControlKeychainBackend();let store=WorklistControlKeychain(operations:backend.operations)
        let access=WorklistProjectionTests.access
        XCTAssertNil(try store.loadAccess());XCTAssertNil(try store.loadIntent())
        try store.saveAccess(access);try store.saveAccess(access);XCTAssertEqual(try store.loadAccess(),access)
        let helper=WorklistControlTests()
        let current=try WorklistControlWire.current(helper.current(),access:access,workset:"workset-a")
        let request=WorklistControlRequest(current:current,intent:"hold",reason:"USER_REQUEST")
        let intent=WorklistControlIntent(accessFingerprint:WorklistControlIntent.fingerprint(access),endpoint:access.endpoint,
            workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,request:request)
        try store.saveIntent(intent);try store.saveIntent(intent)
        XCTAssertEqual(try store.loadIntent(),intent)
        XCTAssertFalse(String(decoding:try JSONEncoder().encode(intent),as:UTF8.self).contains(access.token))
        XCTAssertTrue(intent.matches(access))
        let foreign=WorklistAccess(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,forgeInstanceID:access.forgeInstanceID,actorID:"other",worksetIDs:access.worksetIDs,token:access.token)
        XCTAssertFalse(intent.matches(foreign))
        try store.forgetAccess();try store.forgetIntent();XCTAssertNil(try store.loadAccess());XCTAssertNil(try store.loadIntent())
        XCTAssertTrue(backend.services.allSatisfy { $0=="com.pcvantol.workspace.native-client.worklist-controls.v1" })
        for account in ["actor-control-grant","pending-control-intent"] {
            backend.records[account]=Data("wrong".utf8)
            if account=="actor-control-grant" { XCTAssertThrowsError(try store.loadAccess()) }
            else { XCTAssertThrowsError(try store.loadIntent()) }
        }
        let invalid=WorklistAccess(endpoint:"http://127.0.0.1/",workspaceInstanceID:"bad",forgeInstanceID:"forge",actorID:"actor",worksetIDs:[],token:"bad")
        XCTAssertThrowsError(try store.saveAccess(invalid))
        let badRequest=WorklistControlRequest(current:current,intent:"arm",reason:"USER_REQUEST")
        let badIntent=WorklistControlIntent(accessFingerprint:intent.accessFingerprint,endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,request:badRequest)
        XCTAssertThrowsError(try store.saveIntent(badIntent));XCTAssertThrowsError(try badRequest.data())
    }
    func testBackendFailuresCannotAuthorizeOrEraseIntent() throws {
        let backend=ControlKeychainBackend();let store=WorklistControlKeychain(operations:backend.operations)
        backend.copyFailure=errSecAuthFailed;XCTAssertThrowsError(try store.loadAccess());backend.copyFailure=nil
        backend.updateFailure=errSecAuthFailed;XCTAssertThrowsError(try store.saveAccess(WorklistProjectionTests.access));backend.updateFailure=nil
        backend.addFailure=errSecAuthFailed;XCTAssertThrowsError(try store.saveAccess(WorklistProjectionTests.access));backend.addFailure=nil
        try store.saveAccess(WorklistProjectionTests.access)
        backend.deleteFailure=errSecAuthFailed;XCTAssertThrowsError(try store.forgetAccess())
        XCTAssertNotNil(try store.loadAccess())
    }
}
