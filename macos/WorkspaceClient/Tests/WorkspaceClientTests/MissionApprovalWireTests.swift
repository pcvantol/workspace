import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionApprovalWireTests:XCTestCase {
    func fixture(_ name:String) throws -> Data {
        let aliases=["prepared-complete":"natural-prepared-complete","prepared-incomplete":"natural-prepared-incomplete","compound-result":"natural-compound-result","operation-current":"natural-operation-current","operation-after-refinement":"natural-operation-superseded"]
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mission-installed-481b2f6/")
        if name=="catalog-promoted" { return try Data(contentsOf:directory.appendingPathComponent("natural-catalog-promoted.json")) }
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
    func testActualInstalledLogicalReadyAndHeldAreNotPhysicalExecutionReady() throws {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mission-installed-481b2f6/")
        let prepared=try AdvisoryWire.object(Data(contentsOf:directory.appendingPathComponent("readiness-prepared-complete.json"))),p=prepared["package"] as! [String:Any],source=p["source"] as! [String:Any],authority=p["authority"] as! [String:Any]
        let c=source["conversation_id"] as! String
        let a=AdvisoryAccess(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),workspaceProjectID:"own",actorID:(authority["principal_reference"] as! String).components(separatedBy:":").last!,forgeInstanceID:source["instance_id"] as! String,forgeProjectID:source["project_id"] as! String,repositoryID:source["repository_id"] as! String,conversationIDs:[c],token:String(repeating:"C",count:43))
        let ready=try MissionApprovalWire.compound(Data(contentsOf:directory.appendingPathComponent("readiness-operation-ready.json")),access:a,conversation:c)
        XCTAssertEqual(ready.presentationState,"READY_FOR_GOVERNED_ACTIVATION")
        XCTAssertFalse(try XCTUnwrap(ready.readiness).execution_ready)
        let held=try MissionApprovalWire.compound(Data(contentsOf:directory.appendingPathComponent("readiness-operation-held.json")),access:a,conversation:c)
        XCTAssertEqual(held.presentationState,"APPROVED_WAITING")
        XCTAssertTrue(try XCTUnwrap(held.readiness).blockers.contains("WORKSET_HELD"))
    }

    func testRehashedCanonicalOrLifecycleEvidenceCannotChangeReceiptMeaning() throws {
        let (a,c)=try access(),original=try AdvisoryWire.object(fixture("operation-current"))
        for key in ["subject_id","subject_revision","operator_id","installation_id","capability","decision_id"] {
            var bad=original,receipt=bad["business_decision"] as! [String:Any],canonical=receipt["canonical_decision"] as! [String:Any]
            canonical[key]=key=="subject_revision" ? "sha256:"+String(repeating:"0",count:64):key=="capability" ? "ARCHITECTURE_APPROVAL":"foreign"
            receipt["canonical_decision"]=canonical;receipt["canonical_decision_digest"]=try AdvisoryWire.digest(canonical);bad["business_decision"]=receipt
            XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:bad),access:a,conversation:c))
        }
        var bad=original,receipt=bad["architecture_decision"] as! [String:Any],evidence=receipt["lifecycle_evidence"] as! [String:Any]
        evidence["recommendation_id"]="foreign";receipt["lifecycle_evidence"]=evidence;receipt["lifecycle_evidence_digest"]=try AdvisoryWire.digest(evidence);bad["architecture_decision"]=receipt
        XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:bad),access:a,conversation:c))
    }

    // Declared unit receipt transformation; not a new canonical decision or installed proof.
    func testUnicodeLifecycleReceiptUsesPinnedUTF8Digest() throws {
        let (access,conversation)=try self.access()
        var raw=try AdvisoryWire.object(fixture("operation-current"))
        var receipt=raw["business_decision"] as! [String:Any]
        var evidence=receipt["lifecycle_evidence"] as! [String:Any]
        let rationale="Évaluation explicite du périmètre déjà approuvé."
        receipt["rationale"]=rationale;evidence["rationale"]=rationale
        receipt["lifecycle_evidence"]=evidence
        receipt["lifecycle_evidence_digest"]=try AdvisoryWire.digest(evidence,ascii:false)
        raw["business_decision"]=receipt
        XCTAssertEqual(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:raw),access:access,conversation:conversation).state,"COMPLETE")
        receipt["lifecycle_evidence_digest"]=try AdvisoryWire.digest(evidence)
        raw["business_decision"]=receipt
        XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:raw),access:access,conversation:conversation))
    }

}
