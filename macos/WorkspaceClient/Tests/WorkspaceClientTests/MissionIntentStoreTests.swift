import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionIntentStoreTests: XCTestCase {
    let wire=MissionConceptWireTests()
    var connection: AdvisoryConnection { .init(endpoint:wire.access.endpoint,workspaceInstanceID:wire.access.workspaceInstanceID,actorID:wire.access.actorID,workspaceProjectID:wire.access.workspaceProjectID,conversationID:wire.conversation,bearer:"synthetic-read-root",draftGrant:String(repeating:"D",count:43)) }
    func testDurableRefinementOriginalIdentityAndClearAcrossRestart() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=PrivateMissionIntentStore(root:root),key=CandidateLocal.scopeKey(connection)
        XCTAssertNil(try store.load(key))
        let request=try MissionConceptWire.request(wire.fixture("request"),access:wire.access,conversation:wire.conversation)
        let intent=MissionTransportIntent(key:key,connectionScope:MissionTransportIntent.scope(connection),kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil)
        XCTAssertTrue(intent.matches(connection));try store.save(intent)
        let reopened=PrivateMissionIntentStore(root:root)
        XCTAssertEqual(try reopened.load(key),intent)
        try reopened.clear(key);XCTAssertNil(try store.load(key))
        let contents=try Data(contentsOf:root.appendingPathComponent("mission-"+key+".json"))
        XCTAssertFalse(String(decoding:contents,as:UTF8.self).contains("synthetic-read-root"))
    }
    func testMalformedOrCrossScopeIntentAndUnsafeRecordRefused() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let key=CandidateLocal.scopeKey(connection),store=PrivateMissionIntentStore(root:root)
        let request=try MissionConceptWire.request(wire.fixture("request"),access:wire.access,conversation:wire.conversation)
        let values=[MissionTransportIntent(key:key,connectionScope:[],kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil),MissionTransportIntent(key:key,connectionScope:MissionTransportIntent.scope(connection),kind:"unsupported",refine:nil,approvalBody:nil,frozenPackage:nil)]
        for value in values { XCTAssertThrowsError(try store.save(value)) }
        XCTAssertThrowsError(try PrivateLocalRecordStore(root:root,namespace:"../foreign").load(key))
        XCTAssertThrowsError(try store.load("../foreign"))
        let body=try wire.data(["contract_version":MissionConceptWire.contract,"operation_id":"human-approval-one","revision":1,"package_digest":"sha256:"+String(repeating:"1",count:64),"confirm":true])
        let approved=MissionTransportIntent(key:key,connectionScope:MissionTransportIntent.scope(connection),kind:"approve",refine:nil,approvalBody:body,frozenPackage:nil)
        try store.save(approved);XCTAssertEqual(try store.load(key),approved)
        let wrong=MissionTransportIntent(key:key,connectionScope:MissionTransportIntent.scope(connection),kind:"approve",refine:request,approvalBody:body,frozenPackage:nil)
        XCTAssertThrowsError(try store.save(wrong))
        let file=root.appendingPathComponent("mission-"+key+".json")
        try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path)
        XCTAssertThrowsError(try store.load(key))
        XCTAssertThrowsError(try store.clear(key))
    }
}
