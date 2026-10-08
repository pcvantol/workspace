import Foundation
import Security
import XCTest
@testable import WorkspaceClient

final class AdviceKeychainBackend:@unchecked Sendable {
    var records:[String:Data]=[:]
    var failure:OSStatus?
    var services:[String]=[]
    func account(_ q:CFDictionary) -> String {
        let query=q as! [CFString:Any];services.append(query[kSecAttrService] as! String);return query[kSecAttrAccount] as! String
    }
    var operations:DraftKeychainOperations {
        .init(copy:{q in let key=self.account(q);if let f=self.failure{return(f,nil)};return self.records[key].map{(errSecSuccess,$0)} ?? (errSecItemNotFound,nil)},
              update:{q,v in let key=self.account(q);if let f=self.failure{return f};guard self.records[key] != nil else{return errSecItemNotFound};self.records[key]=(v as NSDictionary)[kSecValueData] as? Data;return errSecSuccess},
              add:{q in let key=self.account(q);if let f=self.failure{return f};self.records[key]=(q as NSDictionary)[kSecValueData] as? Data;return errSecSuccess},
              delete:{q in let key=self.account(q);if let f=self.failure{return f};self.records.removeValue(forKey:key);return errSecSuccess})
    }
}
final class AdvisoryKeychainTests:XCTestCase {
    func testSeparateDurableAccountsAndFailuresWithoutLiveKeychain() throws {
        let backend=AdviceKeychainBackend(),store=AdvisoryKeychain(operations:backend.operations),helper=AdvisoryTests()
        XCTAssertNil(try store.loadAccess());XCTAssertNil(try store.loadIntent())
        try store.saveAccess(helper.access);try store.saveAccess(helper.access);XCTAssertEqual(try store.loadAccess(),helper.access)
        let record=try AdvisoryWire.turn(helper.fixture("record"),access:helper.access,conversation:helper.connection.conversationID)
        let intent=AdvisoryIntent(fingerprint:helper.access.fingerprint,endpoint:helper.access.endpoint,workspaceInstanceID:helper.access.workspaceInstanceID,workspaceProjectID:helper.access.workspaceProjectID,actorID:helper.access.actorID,request:record.request,cancel:nil)
        try store.saveIntent(intent);try store.saveIntent(intent);XCTAssertEqual(try store.loadIntent(),intent)
        XCTAssertTrue(intent.matches(helper.access,connection:helper.connection));XCTAssertFalse(String(decoding:try JSONEncoder().encode(intent),as:UTF8.self).contains(helper.access.token))
        try store.forgetAccess();try store.forgetIntent();XCTAssertNil(try store.loadAccess());XCTAssertNil(try store.loadIntent())
        XCTAssertTrue(backend.services.allSatisfy{$0=="com.pcvantol.workspace.native-client.advisory.v1"})
        backend.records["advisory-access"]=Data("bad".utf8);XCTAssertThrowsError(try store.loadAccess())
        backend.records["advisory-intent"]=Data("bad".utf8);XCTAssertThrowsError(try store.loadIntent())
        backend.failure=errSecAuthFailed
        XCTAssertThrowsError(try store.loadAccess());XCTAssertThrowsError(try store.saveAccess(helper.access));XCTAssertThrowsError(try store.forgetAccess())
        XCTAssertThrowsError(try store.saveIntent(intent));XCTAssertThrowsError(try store.forgetIntent())
        backend.failure=nil;backend.records.removeAll();try store.saveAccess(helper.access)
    }
}
