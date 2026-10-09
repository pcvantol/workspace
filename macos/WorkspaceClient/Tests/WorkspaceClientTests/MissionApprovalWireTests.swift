import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionApprovalWireTests:XCTestCase {
    func fixture(_ name:String) throws -> Data {
        let aliases=["prepared-complete":"prepared-root","compound-result":"compound-root","operation-after-refinement":"operation-superseded"]
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mission-dependency-source/")
        if name=="catalog-promoted" {
            // Synthetic catalog replay for native recovery tests, derived from its actual paired root packet.
            let p=try AdvisoryWire.object(fixture("prepared-complete"))["package"] as! [String:Any],source=p["source"] as! [String:Any],definition=p["definition"] as! [String:Any]
            let candidate=p["candidate"] as! [String:Any]
            let item:[String:Any]=["object_id":source["object_id"]!,"conversation_id":source["conversation_id"]!,"revision":source["revision"]!,"conversation_revision":source["conversation_revision"]!,"definition_digest":try AdvisoryWire.digest(definition),"definition":definition,"source_turn_id":source["turn_id"]!,"context_revision":source["context_revision"]!,"title":definition["title"]!,"summary":definition["expected_result"]!,"state":"APPROVED_WAITING","approval_supported":false,"blockers":["EXPLICIT_WORKSET_RELEASE_REQUIRED"],"questions":[],"parent_id":NSNull(),"group_id":NSNull(),"labels":[],"edges":[],"candidate_id":candidate["id"]!,"mission_id":"MISSION-0006"]
            let scope=Dictionary(uniqueKeysWithValues:["instance_id","project_id","repository_id"].map { ($0,source[$0]!) })
            return try JSONSerialization.data(withJSONObject:["contract_version":MissionConceptWire.contract,"items":[item],"next_cursor":NSNull(),"snapshot_revision":try AdvisoryWire.digest([item]),"scope":scope,"population":"AUTHORIZED_ADMITTED_CONCEPTS_ONLY","complete_portfolio":false,"read_only":true,"additional_model_calls":0])
        }
        return try Data(contentsOf:directory.appendingPathComponent((aliases[name] ?? name)+".json"))
    }
    func access() throws -> (AdvisoryAccess,String) {
        let p=try AdvisoryWire.object(fixture("prepared-complete"))["package"] as! [String:Any],s=p["source"] as! [String:Any],a=p["authority"] as! [String:Any]
        let c=s["conversation_id"] as! String
        return (.init(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),workspaceProjectID:"ws-project",actorID:(a["principal_reference"] as! String).components(separatedBy:":").last!,forgeInstanceID:s["instance_id"] as! String,forgeProjectID:s["project_id"] as! String,repositoryID:s["repository_id"] as! String,conversationIDs:[c],token:String(repeating:"C",count:43)),c)
    }
    func testActualSourcePackagesAndSupersededOriginalAreNotNewReady() throws {
        let (a,c)=try access(),prepared=try MissionApprovalWire.prepared(fixture("prepared-complete"),access:a,conversation:c,revision:2)
        XCTAssertNotNil(prepared.packageData)
        let incomplete=try MissionApprovalWire.prepared(fixture("prepared-incomplete"),access:a,conversation:c)
        XCTAssertNil(incomplete.packageData);XCTAssertFalse(incomplete.questions.isEmpty)
        for name in ["compound-result","operation-current","operation-after-refinement"] {
            let r=try MissionApprovalWire.compound(fixture(name),access:a,conversation:c,expectedDigest:prepared.digest,frozenData:prepared.packageData)
            XCTAssertEqual(r.state,"COMPLETE");XCTAssertNotNil(r.missionID)
            if name=="operation-after-refinement" { XCTAssertFalse(r.sourceFresh);XCTAssertEqual(r.currentDefinitionState,"SUPERSEDED") }
        }
        XCTAssertThrowsError(try MissionApprovalWire.prepared(fixture("prepared-complete"),access:a,conversation:c,revision:99))
        XCTAssertThrowsError(try MissionApprovalWire.compound(fixture("compound-result"),access:a,conversation:c))
    }
    func testExactFrozenMeaningSignerAndActualDecisionsRequired() throws {
        let (a,c)=try access()
        let original=try AdvisoryWire.object(fixture("operation-current"))
        for key in ["package_digest","mission_id","business_decision"] {
            var bad=original
            if key=="package_digest" { bad[key]="sha256:"+String(repeating:"0",count:64) }
            else { bad[key]=NSNull() }
            XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:bad),access:a,conversation:c))
        }
        var bad=original;var decision=bad["architecture_decision"] as! [String:Any];decision["operator_id"]="foreign";bad["architecture_decision"]=decision
        XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:bad),access:a,conversation:c))
        XCTAssertThrowsError(try MissionApprovalWire.compound(fixture("operation-current"),access:a,conversation:c,operation:"foreign"))
        var packet=try AdvisoryWire.object(fixture("prepared-complete")),pkg=packet["package"] as! [String:Any],candidate=pkg["candidate"] as! [String:Any]
        candidate["title"]="Unseen scope";pkg["candidate"]=candidate;packet["package"]=pkg
        XCTAssertThrowsError(try MissionApprovalWire.prepared(JSONSerialization.data(withJSONObject:packet),access:a,conversation:c))
    }
}
