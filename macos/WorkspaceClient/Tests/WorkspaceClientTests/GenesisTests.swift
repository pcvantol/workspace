import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

// Explicit source-only doubles, never installed Forge or real GUI acceptance.
actor GenesisFixture:GenesisServing {
    nonisolated let source:ConceptBaselineResult
    nonisolated let concept:ProjectConcept
    nonisolated let connection:ConceptConnection
    private var accessObject:[String:Any]
    private var object:[String:Any]
    private var created=false
    private var lost=false
    private var denied=false
    private var posts=0
    private var available=true
    init()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/genesis-source-only.json")
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        source=try JSONDecoder().decode(ConceptBaselineResult.self,from:JSONSerialization.data(withJSONObject:root["source"]!))
        concept=try JSONDecoder().decode(ProjectConcept.self,from:JSONSerialization.data(withJSONObject:root["concept"]!))
        connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:concept.context_id,token:String(repeating:"c",count:43)),bearer:"own-only")
        accessObject=root["access"] as! [String:Any];object=root["result"] as! [String:Any]
    }
    func setLost() {lost=true}
    func setDenied(_ value:Bool) {denied=value}
    func setUnavailable(_ value:Bool) {available = !value}
    func expireAccess(after seconds:Double) {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        accessObject["expires_at"]=f.string(from:Date().addingTimeInterval(seconds))
    }
    func count()->Int {posts}
    func access(_ connection:ConceptConnection,concept:String,source:String) async throws -> GenesisAccess {
        if denied {throw ConceptError.denied};if !available {throw ConceptError.unavailable}
        return try JSONDecoder().decode(GenesisAccess.self,from:JSONSerialization.data(withJSONObject:accessObject))
    }
    func result(_ connection:ConceptConnection,concept:String,action:String,operation:String?,body:Data?) async throws -> GenesisEnvelope {
        if denied {throw ConceptError.denied};if !available {throw ConceptError.unavailable}
        if let body {
            let cmd=try JSONSerialization.jsonObject(with:body) as! [String:Any];posts+=1;created=true
            var result=object["result"] as! [String:Any];var p=result["plan"] as! [String:Any]
            object["operation_id"]=cmd["operation_id"]
            if action=="plans" {
                object["plan_operation_id"]=cmd["operation_id"];object["kind"]="PLAN";p["operation_id"]=cmd["operation_id"];result["plan"]=p
                accessObject["plans"]=[["operation_id":cmd["operation_id"]!,"plan_id":p["plan_id"]!,"plan_revision":p["plan_revision"]!]]
            } else {
                object["kind"]="DECISION"
                let d:[String:Any]=["decision_id":"synthetic-effect", "decision_revision":1,"principal_id":"human","grant_id":"effect-grant","human_binding":["operator_id":"human","operator_binding_version":1,"installation_id":"fixture"],"operation_id":cmd["operation_id"]!,"plan_id":p["plan_id"]!,"plan_digest":p["plan_digest"]!,"purpose":"GENESIS_BOOTSTRAP_EFFECT_ONLY/1.0","decision":cmd["decision"]!,"reason":cmd["reason"]!,"occurred_at":"2026-10-19T00:00:00Z","request_digest":String(repeating:"a",count:64),"decision_digest":String(repeating:"b",count:64)]
                result["effect_history"]=[d];result["effect_decision_revision"]=1;result["original_decision"]=d;result["effect_decision_currently_applicable"]=(cmd["decision"] as? String)=="APPROVE_EFFECT"
            }
            object["result"]=result;accessObject["latest"]=object
            if lost {lost=false;throw ConceptError.unavailable}
        }
        guard created else {throw ConceptError.notFound}
        return try JSONDecoder().decode(GenesisEnvelope.self,from:JSONSerialization.data(withJSONObject:object))
    }
}

@MainActor final class GenesisTests:XCTestCase {
    func root()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func testOriginalPlanAndSeparateDecisionNoEffects()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});XCTAssertNotNil(state.access);XCTAssertNil(state.result)
        await state.prepare(peer.concept,source:peer.source,target:"local",current:{c});XCTAssertNotNil(state.result);XCTAssertNil(state.pending)
        let selection=try XCTUnwrap(state.result?.selection_digest)
        await state.decide(peer.concept,source:peer.source,decision:"APPROVE_EFFECT",reason:"Synthetic separate effect decision",expectedSelection:selection,current:{c})
        XCTAssertTrue(try XCTUnwrap(state.result).result.effect_decision_currently_applicable);XCTAssertFalse(try XCTUnwrap(state.result).result.execution_authorized)
        let count=await peer.count();XCTAssertEqual(count,2);state.conceal()
    }
    func testLostSuccessClientReopenReadsSameWithoutAnotherPOST()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let c=peer.connection
        let first=GenesisState(root:root,transport:peer);await first.load(peer.concept,source:peer.source,current:{c});await peer.setLost();await first.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let pending=try XCTUnwrap(first.pending);XCTAssertNil(first.result);first.conceal()
        let restarted=GenesisState(root:root,transport:peer);await restarted.load(peer.concept,source:peer.source,current:{c});XCTAssertNil(restarted.pending);XCTAssertEqual(restarted.result?.operation_id,pending.operation)
        let count=await peer.count();XCTAssertEqual(count,1);restarted.conceal()
    }
    func testInvalidTargetAndStaleConfirmationNeverPOST()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"foreign",current:{c});let count=await peer.count();XCTAssertEqual(count,0)
        await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        await state.decide(peer.concept,source:peer.source,decision:"APPROVE_EFFECT",reason:"Reason",expectedSelection:String(repeating:"f",count:64),current:{c});let after=await peer.count();XCTAssertEqual(after,1);state.conceal()
    }
    func testRealMonitorConcealsActualTransportDenial()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c});XCTAssertNotNil(state.result)
        await peer.setDenied(true);try await Task.sleep(for:.seconds(3.4));XCTAssertNil(state.result);XCTAssertNil(state.access);XCTAssertEqual(state.phase,"access");state.conceal()
    }
    func testUnknownStoreAndLateDifferentConnectionDoNotPublish()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await peer.setUnavailable(true);await state.load(peer.concept,source:peer.source,current:{c});XCTAssertNil(state.access);XCTAssertEqual(state.phase,"unavailable")
        await peer.setUnavailable(false);await state.load(peer.concept,source:peer.source,current:{c});state.conceal();XCTAssertNil(state.result)
    }
    func testAccessOnlyActualMonitorConcealsRevokeWithoutAnyPlanOrPOST()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});XCTAssertNotNil(state.access);XCTAssertNil(state.result)
        await peer.setDenied(true);try await Task.sleep(for:.seconds(3.35));XCTAssertNil(state.access);XCTAssertNil(state.result);XCTAssertEqual(state.phase,"access")
        let count=await peer.count();XCTAssertEqual(count,0);state.conceal()
    }
    func testAccessOnlyRealClockExpiryConcealsBeforeFirstPlan()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await peer.expireAccess(after:0.8);await state.load(peer.concept,source:peer.source,current:{c});XCTAssertNotNil(state.access)
        try await Task.sleep(for:.seconds(1.1));XCTAssertNil(state.access);XCTAssertEqual(state.phase,"access");let count=await peer.count();XCTAssertEqual(count,0);state.conceal()
    }
    func testAccessOnlyRecoverableReadFailureMonitorSurvivesAndRestores()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await peer.setUnavailable(true)
        try await Task.sleep(for:.seconds(3.35));XCTAssertNil(state.access);XCTAssertEqual(state.phase,"unavailable")
        await peer.setUnavailable(false);try await Task.sleep(for:.seconds(3.35));XCTAssertNotNil(state.access);XCTAssertEqual(state.phase,"choose");let count=await peer.count();XCTAssertEqual(count,0);state.conceal()
    }
    func testOriginalReasonAndDocumentAreScopedAndPreservedAcrossClientStateReopen()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        state.updateReason("Only this exact original plan");let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path)
        await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c});XCTAssertEqual(state.expandedDocument,path);state.conceal();XCTAssertEqual(state.reason,"")
        let reopened=GenesisState(root:root,transport:peer);await reopened.load(peer.concept,source:peer.source,current:{c});XCTAssertEqual(reopened.reason,"Only this exact original plan");XCTAssertEqual(reopened.expandedDocument,path);reopened.conceal()
    }
    func testDocumentNavigationFocusFollowsActualAuthorizedToggleAndReturnsToExactOpener()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path);let navigation=GenesisDocumentNavigation();var focus:[String?]=[];var anchors:[String]=[]
        await navigation.navigate(path,state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focus.append($0)},reveal:{anchors.append($0)})
        XCTAssertEqual(state.expandedDocument,path);XCTAssertEqual(focus.last!,"genesis-detail-"+path);XCTAssertEqual(anchors.last,"genesis-detail-"+path)
        await navigation.navigate(path,state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focus.append($0)},reveal:{anchors.append($0)})
        XCTAssertEqual(state.expandedDocument,"");XCTAssertEqual(focus.last!,"genesis-document-"+path);XCTAssertEqual(anchors.last,"genesis-document-"+path);XCTAssertFalse(navigation.busy);state.conceal()
    }
    func testFiveLanguagesAndHostedNarrowWideLightDarkRemainSourceEvidence()async throws {
        for (_,values) in GenesisCopy.rows {XCTAssertEqual(values.count,5);XCTAssertTrue(values.allSatisfy{!$0.isEmpty})}
        for language in ["nl","en","de","fr","es"] {XCTAssertNotEqual(GenesisCopy.text("title",language),"title")}
        XCTAssertEqual(GenesisCopy.text("title","unknown"),GenesisCopy.text("title","en"))
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        for language in ["nl","en","de","fr","es"] {for width in [440.0,1100.0] {for scheme in [ColorScheme.light,.dark] {
            let view=GenesisView(state:state,concept:peer.concept,source:peer.source,dirty:false,current:{c},reveal:{_ in}).environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme)
            let host=NSHostingView(rootView:view);host.frame=NSRect(x:0,y:0,width:width,height:1000);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0)
        }}}
        state.conceal()
    }
}
