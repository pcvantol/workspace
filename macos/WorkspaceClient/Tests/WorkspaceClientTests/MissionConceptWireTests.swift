import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionConceptWireTests: XCTestCase {
    var access: AdvisoryAccess { .init(endpoint: "http://127.0.0.1:12345/", workspaceInstanceID: String(repeating: "a", count: 32), workspaceProjectID: "ws-project", actorID: "alice", forgeInstanceID: "forge-one", forgeProjectID: "project-one", repositoryID: "repo-one", conversationIDs: [String(repeating: "a", count: 32)], token: String(repeating: "C", count: 43)) }
    let conversation = String(repeating: "a", count: 32)
    func fixture(_ key: String) throws -> [String: Any] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mission-concepts/wire.json")
        return (try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any])[key] as! [String: Any]
    }
    func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    func testClosedPreviewAndScopeCannotEnableApproval() throws {
        let cap = try fixture("capability")
        XCTAssertEqual(try MissionConceptWire.capability(data(cap), access: access).maximum_turns, 8)
        let request = try MissionConceptWire.request(fixture("request"), access: access, conversation: conversation)
        XCTAssertEqual(request.contract_version, MissionConceptWire.contract)
        for (key, value) in [("readiness_qualified", true as Any), ("extra", "authority" as Any), ("context_revision", "sha256:"+String(repeating: "0", count: 64) as Any), ("conversation_ids", [String(repeating: "b", count: 32)] as Any), ("instance_id", "foreign" as Any)] {
            var bad=cap;bad[key]=value
            XCTAssertThrowsError(try MissionConceptWire.capability(data(bad), access: access))
        }
        XCTAssertThrowsError(try MissionConceptWire.request(fixture("request"), access: access, conversation: String(repeating: "b",count:32)))
        var bad=try fixture("request"); bad["selected_sources"]=[["source_id":"same","version":"sha256:"+String(repeating:"a",count:64)],["source_id":"same","version":"sha256:"+String(repeating:"a",count:64)]]
        XCTAssertThrowsError(try MissionConceptWire.request(bad,access:access,conversation:conversation))
        XCTAssertThrowsError(try AdvisoryWire.check(true,["type":["integer","null"]],definitions:[:]))
        try AdvisoryWire.check(NSNull(),["type":["integer","null"]],definitions:[:])
    }
    func testSubstantiveQuestionsAndRealDependencyReferences() throws {
        let source = try fixture("record")["outcome"] as! [String:Any]
        let d = (source["output"] as! [String:Any])["definition"] as! [String:Any]
        XCTAssertEqual(try MissionConceptWire.definition(d,allowedDependencies:[]).title,"Invoice portal")
        var incomplete=d;incomplete["acceptance_criteria"]=[];incomplete["questions"]=["Investigate or build?"]
        XCTAssertEqual(try MissionConceptWire.definition(incomplete).questions.count,1)
        incomplete["questions"]=[];XCTAssertThrowsError(try MissionConceptWire.definition(incomplete))
        for (key,value) in [("scope",["same","same"] as Any),("dependencies",["foreign"] as Any),("signer","invented" as Any),("title","password=secret" as Any)] {
            var bad=d;bad[key]=value;XCTAssertThrowsError(try MissionConceptWire.definition(bad,allowedDependencies:[]))
        }
    }
    func testExactOriginalTurnAndObservedBoundedUsage() throws {
        let r=try fixture("record"), request=try MissionConceptWire.request(r["request"]!,access:access,conversation:conversation)
        XCTAssertEqual(try MissionConceptWire.observation(data(fixture("turn")),kind:"turn",access:access,conversation:conversation,expected:request).currentRevision,1)
        for key in ["request_digest","context"] {
            var bad=r;bad[key]=key=="request_digest" ? "sha256:"+String(repeating:"0",count:64):["foreign":true]
            XCTAssertThrowsError(try MissionConceptWire.turn(bad,access:access,conversation:conversation))
        }
        var bad=r;var outcome=r["outcome"] as! [String:Any];outcome["usage"]=NSNull();outcome["usage_status"]="NOT_REPORTED";bad["outcome"]=outcome
        XCTAssertThrowsError(try MissionConceptWire.turn(bad,access:access,conversation:conversation))
        bad=r;bad["outcome"]=NSNull();XCTAssertThrowsError(try MissionConceptWire.turn(bad,access:access,conversation:conversation));bad["status"]="FAILED";_ = try MissionConceptWire.turn(bad,access:access,conversation:conversation)
        var envelope=try fixture("turn");envelope["current_revision"]=0
        XCTAssertThrowsError(try MissionConceptWire.observation(data(envelope),kind:"turn",access:access,conversation:conversation))
        var history=try fixture("history");XCTAssertEqual(try MissionConceptWire.history(data(history),access:access,conversation:conversation).turns.count,1)
        history["turns"]=[r,r];XCTAssertThrowsError(try MissionConceptWire.history(data(history),access:access,conversation:conversation))
    }
    func testAuthorizedCatalogHasNoFabricatedMissionOrMixedSnapshot() throws {
        let c=try fixture("catalog")
        let good=try MissionConceptWire.catalog(data(c),access:access)
        XCTAssertFalse(good.complete_portfolio);XCTAssertFalse(good.items[0].approval_supported);XCTAssertNil(good.items[0].mission_id)
        for (key,value) in [("title","unrelated" as Any),("summary","unrelated" as Any),("definition_digest","sha256:"+String(repeating:"0",count:64) as Any),("conversation_id",String(repeating:"b",count:32) as Any),("mission_id","fabricated" as Any),("revision",2 as Any)] {
            var bad=c;var items=c["items"] as! [[String:Any]];items[0][key]=value;bad["items"]=items
            XCTAssertThrowsError(try MissionConceptWire.catalog(data(bad),access:access))
        }
        XCTAssertThrowsError(try MissionConceptWire.catalog(data(c),access:access,expectedSnapshot:"sha256:"+String(repeating:"0",count:64)))
        var paged=c;paged["next_cursor"]=1;_ = try MissionConceptWire.catalog(data(paged),access:access,expectedSnapshot:good.snapshot_revision)
        paged["next_cursor"]=true;XCTAssertThrowsError(try MissionConceptWire.catalog(data(paged),access:access))
        paged["next_cursor"]=3;XCTAssertThrowsError(try MissionConceptWire.catalog(data(paged),access:access))
        paged=c;paged["items"]=(c["items"] as! [Any]) + (c["items"] as! [Any])
        XCTAssertThrowsError(try MissionConceptWire.catalog(data(paged),access:access))
    }
}
