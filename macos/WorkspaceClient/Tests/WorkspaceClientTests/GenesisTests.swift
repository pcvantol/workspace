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
    private var gets=0
    private var heldReplyFailure=false
    private var holdNextReply=false
    private var replyHeld=false
    private var release:CheckedContinuation<Void,Never>?
    private var available=true
    init()throws {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/genesis-source-only.json")
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        source=try JSONDecoder().decode(ConceptBaselineResult.self,from:JSONSerialization.data(withJSONObject:root["source"]!))
        concept=try JSONDecoder().decode(ProjectConcept.self,from:JSONSerialization.data(withJSONObject:root["concept"]!))
        connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:concept.context_id,token:String(repeating:"c",count:43)),bearer:"own-only")
        accessObject=root["access"] as! [String:Any];object=root["result"] as! [String:Any]
    }
    func holdReply() {holdNextReply=true}
    func replyIsHeld()->Bool {replyHeld}
    func releaseReply(failing:Bool=false) {heldReplyFailure=failing;release?.resume();release=nil;replyHeld=false}
    func readCount()->Int {gets}
    func setLost() {lost=true}
    func setDenied(_ value:Bool) {denied=value}
    func setUnavailable(_ value:Bool) {available = !value}
    func expireAccess(after seconds:Double) {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        accessObject["expires_at"]=f.string(from:Date().addingTimeInterval(seconds))
    }
    // Presentation-only source variants: never peer capability or installed proof.
    func presentationVariant(_ variant:String) {
        if variant=="noTargets" {accessObject["targets"]=[];accessObject["can_plan"]=false}
        if variant=="missingArchitecture" {
            var content=accessObject["content"] as! [String:Any];content["state"]="DECISION_NEEDED"
            content["history"]=(content["history"] as! [[String:Any]]).filter{($0["request"] as? [String:Any])?["role"] as? String != "ARCHITECTURE"};accessObject["content"]=content
        }
        if variant=="blocked" {
            var value=object["result"] as! [String:Any];var p=value["plan"] as! [String:Any]
            p["blocking_open_points"]=[(p["open_questions"] as! [String]).first!];value["plan"]=p;value["effect_decision_eligible"]=false;value["inapplicability_reasons"]=["REQUIRED_OPEN_POINTS_UNANSWERED"];object["result"]=value;object["target_current"]=false;object["can_approve"]=false
        }
    }
    func count()->Int {posts}
    func access(_ connection:ConceptConnection,concept:String,source:String) async throws -> GenesisAccess {
        if denied {throw ConceptError.denied};if !available {throw ConceptError.unavailable}
        return try JSONDecoder().decode(GenesisAccess.self,from:JSONSerialization.data(withJSONObject:accessObject))
    }
    func result(_ connection:ConceptConnection,concept:String,action:String,operation:String?,body:Data?) async throws -> GenesisEnvelope {
        if denied {throw ConceptError.denied};if !available {throw ConceptError.unavailable}
        if body==nil {gets+=1}
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
        let frozen=try JSONSerialization.data(withJSONObject:object)
        if holdNextReply {holdNextReply=false;replyHeld=true;await withCheckedContinuation {release=$0};if heldReplyFailure {heldReplyFailure=false;throw ConceptError.unavailable}}
        return try JSONDecoder().decode(GenesisEnvelope.self,from:frozen)
    }
}

@MainActor final class GenesisTests:XCTestCase {
    func root()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func testHeldBackgroundOriginalReadIsSharedWithForegroundDocumentNavigation()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path)
        await peer.holdReply()
        for _ in 0..<450 {if await peer.replyIsHeld() {break};try await Task.sleep(for:.milliseconds(10))}
        let held=await peer.replyIsHeld();XCTAssertTrue(held)
        let before=await peer.readCount()
        let foreground=Task {await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c})}
        for _ in 0..<100 {if state.busy {break};await Task.yield()}
        XCTAssertTrue(state.busy)
        let during=await peer.readCount();XCTAssertEqual(during,before,"The held exact original GET must be shared, not duplicated")
        await peer.releaseReply();await foreground.value
        XCTAssertEqual(state.expandedDocument,path);XCTAssertNotNil(state.result)
        let count=await peer.count();XCTAssertEqual(count,1);state.conceal()
    }
    func testChangedBearerDoesNotJoinOldPollAndLateFailureCannotHideForeground()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let old=peer.connection
        var current=old
        await state.load(peer.concept,source:peer.source,current:{current});await state.prepare(peer.concept,source:peer.source,target:"local",current:{current})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path)
        await peer.holdReply()
        for _ in 0..<450 {if await peer.replyIsHeld() {break};try await Task.sleep(for:.milliseconds(10))}
        let held=await peer.replyIsHeld();XCTAssertTrue(held)
        let before=await peer.readCount()
        current=ConceptConnection(access:old.access,bearer:"different-own-bearer")
        await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{current})
        let after=await peer.readCount();XCTAssertEqual(after,before+1,"A different bearer must make its own authenticated GET")
        XCTAssertEqual(state.expandedDocument,path);let operation=state.result?.operation_id,epoch=state.presentationEpoch
        await peer.releaseReply(failing:true)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertEqual(state.result?.operation_id,operation);XCTAssertEqual(state.expandedDocument,path);XCTAssertEqual(state.presentationEpoch,epoch)
        let count=await peer.count();XCTAssertEqual(count,1);state.conceal()
    }
    func testLateFailedBackgroundPollCannotConcealReloadedOriginal()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        await peer.holdReply()
        for _ in 0..<450 {if await peer.replyIsHeld() {break};try await Task.sleep(for:.milliseconds(10))}
        let held=await peer.replyIsHeld();XCTAssertTrue(held)
        await state.load(peer.concept,source:peer.source,current:{c})
        let operation=try XCTUnwrap(state.result?.operation_id),epoch=state.presentationEpoch
        await peer.releaseReply(failing:true)
        for _ in 0..<30 {await Task.yield()}
        XCTAssertEqual(state.result?.operation_id,operation);XCTAssertEqual(state.presentationEpoch,epoch);XCTAssertEqual(state.phase,"loaded")
        let count=await peer.count();XCTAssertEqual(count,1);state.conceal()
    }
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
    func testActualHeldOriginalReplyCannotPublishIntoNewForeignContext()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)}
        let state=GenesisState(root:root,transport:peer);let a=peer.connection
        let b=ConceptConnection(access:.init(endpoint:a.access.endpoint,instanceID:a.access.instanceID,projectID:"different-context",token:a.access.token),bearer:a.bearer)
        var selected=a
        await state.load(peer.concept,source:peer.source,current:{selected});await peer.holdReply()
        let original=Task {await state.prepare(peer.concept,source:peer.source,target:"local",current:{selected})}
        for _ in 0..<100 {if await peer.replyIsHeld() {break};try await Task.sleep(for:.milliseconds(10))}
        let held=await peer.replyIsHeld();XCTAssertTrue(held,"The original POST reply must actually be suspended before selection changes")
        selected=b
        await state.load(peer.concept,source:peer.source,current:{selected})
        XCTAssertNil(state.result);XCTAssertNil(state.access);XCTAssertEqual(state.phase,"invalid")
        await peer.releaseReply();await original.value
        XCTAssertNil(state.result);XCTAssertNil(state.access);XCTAssertNil(state.pending);XCTAssertEqual(state.phase,"invalid","Late A must not overwrite the new scope state")
        selected=a
        await state.load(peer.concept,source:peer.source,current:{selected})
        XCTAssertNotNil(state.result,"Returning to authorized A must recover its original operation")
        let count=await peer.count();XCTAssertEqual(count,1,"Late reply and scope return cannot create another plan")
        state.conceal()
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
    func testAuthorizedOriginalDocumentSectionAndAnchorRestoreWithoutToggleOrEffect()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let c=peer.connection
        let first=GenesisState(root:root,transport:peer);await first.load(peer.concept,source:peer.source,current:{c});await first.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(first.result?.result.plan.documents.files.first?.path)
        await first.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c});XCTAssertTrue(first.documentsVisible);first.conceal()
        let reopened=GenesisState(root:root,transport:peer);await reopened.load(peer.concept,source:peer.source,current:{c});XCTAssertTrue(reopened.documentsVisible);XCTAssertEqual(reopened.expandedDocument,path)
        let navigation=GenesisDocumentNavigation();var revealed:[String]=[];var focused:[String?]=[]
        await navigation.navigate(path,restoring:true,state:reopened,concept:peer.concept,source:peer.source,current:{c},focus:{focused.append($0)},reveal:{revealed.append($0)})
        XCTAssertEqual(reopened.expandedDocument,path);XCTAssertEqual(revealed,["genesis-detail-"+path]);XCTAssertEqual(focused.last!,"genesis-detail-"+path)
        reopened.setDocumentsVisible(false);reopened.conceal()
        let collapsed=GenesisState(root:root,transport:peer);await collapsed.load(peer.concept,source:peer.source,current:{c});XCTAssertFalse(collapsed.documentsVisible);XCTAssertEqual(collapsed.expandedDocument,path)
        await peer.setDenied(true);revealed=[];focused=[]
        await navigation.navigate(path,restoring:true,state:collapsed,concept:peer.concept,source:peer.source,current:{c},focus:{focused.append($0)},reveal:{revealed.append($0)})
        XCTAssertNil(collapsed.result);XCTAssertTrue(revealed.isEmpty);XCTAssertTrue(focused.isEmpty);let count=await peer.count();XCTAssertEqual(count,1);collapsed.conceal()
    }
    func testRecoverableOriginalReadConcealsThenRestoresScopedReasonAndDocument()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path);state.updateReason("Exact original reason after unavailable read");await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c})
        await peer.setUnavailable(true);try await Task.sleep(for:.seconds(3.35));XCTAssertNil(state.result);XCTAssertEqual(state.reason,"");XCTAssertFalse(state.documentsVisible)
        await peer.setUnavailable(false);try await Task.sleep(for:.seconds(3.35));XCTAssertNotNil(state.result);XCTAssertEqual(state.reason,"Exact original reason after unavailable read");XCTAssertEqual(state.expandedDocument,path);XCTAssertTrue(state.documentsVisible)
        let count=await peer.count();XCTAssertEqual(count,1);state.conceal()
    }
    func testRestorationCoordinatorRevealsOriginalAgainAfterActualMonitorFailureAndRecovery()async throws {
        let peer=try GenesisFixture();let root=root();defer{try? FileManager.default.removeItem(at:root)};let state=GenesisState(root:root,transport:peer);let c=peer.connection
        await state.load(peer.concept,source:peer.source,current:{c});await state.prepare(peer.concept,source:peer.source,target:"local",current:{c})
        let path=try XCTUnwrap(state.result?.result.plan.documents.files.first?.path);await state.chooseDocument(path,concept:peer.concept,source:peer.source,current:{c})
        let nav=GenesisDocumentNavigation();var anchors:[String]=[];var focuses:[String?]=[]
        await nav.restore(state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focuses.append($0)},reveal:{anchors.append($0)})
        await nav.restore(state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focuses.append($0)},reveal:{anchors.append($0)})
        XCTAssertEqual(anchors,["genesis-detail-"+path]);let epoch=state.presentationEpoch
        await peer.setUnavailable(true);try await Task.sleep(for:.seconds(3.35));XCTAssertNil(state.result);XCTAssertGreaterThan(state.presentationEpoch,epoch)
        await nav.restore(state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focuses.append($0)},reveal:{anchors.append($0)})
        XCTAssertEqual(anchors.count,1)
        await peer.setUnavailable(false);try await Task.sleep(for:.seconds(3.35));XCTAssertNotNil(state.result)
        await nav.restore(state:state,concept:peer.concept,source:peer.source,current:{c},focus:{focuses.append($0)},reveal:{anchors.append($0)})
        XCTAssertEqual(anchors,["genesis-detail-"+path,"genesis-detail-"+path]);XCTAssertEqual(focuses.last!,"genesis-detail-"+path);let count=await peer.count();XCTAssertEqual(count,1);state.conceal()
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
