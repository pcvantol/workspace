import Foundation
import XCTest
@testable import WorkspaceClient

// Actual producer HTTP examples, replayed at the native transport boundary.
// These prove consumer recovery, not installed producer qualification.
final class MissionApprovalRecoveryTests: XCTestCase, @unchecked Sendable {
    let examples=MissionApprovalWireTests()
    var requests:[URLRequest]=[]
    var operationID:String?
    var loseReply=false
    var superseded=false
    var deny=false
    var missingOperation=false
    var alreadyApproved=false
    // Namespace translation is explicit test setup; source decision/effect contents stay unchanged.
    let conversation=String(repeating:"a",count:32)
    func fixture(_ name:String) throws -> Data {
        var raw=try AdvisoryWire.object(examples.fixture(name))
        func package(_ value:[String:Any])->[String:Any] {
            var p=value,s=p["source"] as! [String:Any];s["conversation_id"]=conversation;p["source"]=s;return p
        }
        if let p=raw["package"] as? [String:Any] { let changed=package(p);raw["package"]=changed;raw["package_digest"]=try AdvisoryWire.digest(changed) }
        if let p=raw["frozen_package"] as? [String:Any] { let changed=package(p);raw["frozen_package"]=changed;raw["package_digest"]=try AdvisoryWire.digest(changed) }
        if name=="compound-result" {
            let p=try AdvisoryWire.object(fixture("prepared-complete"));raw["package_digest"]=p["package_digest"]
        }
        if var registration=raw["original_registration"] as? [String:Any],var source=registration["source"] as? [String:Any] {
            source["conversation_id"]=conversation;registration["source"]=source;raw["original_registration"]=registration
        }
        if var items=raw["items"] as? [[String:Any]] {
            for i in items.indices { items[i]["conversation_id"]=conversation }
            raw["items"]=items;raw["snapshot_revision"]=try AdvisoryWire.digest(items)
        }
        return try JSONSerialization.data(withJSONObject:raw)
    }
    func transport(_ access:AdvisoryAccess) throws -> MissionConceptTransport {
        let conversation=access.conversationIDs[0]
        let check=try MissionConceptWire.catalog(fixture("catalog-promoted"),access:access)
        XCTAssertEqual(check.items.count,1)
        StubProtocol.handler = { request in
            self.requests.append(request)
            if self.deny { return (403,Data("{}".utf8)) }
            let path=request.url!.path
            var data:Data
            if path.hasSuffix("/capability") {
                var cap=try MissionConceptWireTests().fixture("capability")
                cap["instance_id"]=access.forgeInstanceID;cap["project_id"]=access.forgeProjectID;cap["repository_id"]=access.repositoryID;cap["conversation_ids"]=[conversation]
                cap["approval_supported"]=true;cap["maximum_missions"]=2;cap["supported_work_kinds"]=["BUILD"]
                cap["supported_operations"]=["REFINE","READ","CANCEL_REQUEST","PREPARE","APPROVE","READ_OPERATION"]
                cap["workspace_reference_resolution_supported"]=true
                var context=cap["context"] as! [String:Any]
                context["instance_id"]=access.forgeInstanceID;context["project_id"]=access.forgeProjectID;context["repository_id"]=access.repositoryID
                cap["context"]=context;cap["context_revision"]=try AdvisoryWire.digest(context)
                data=try JSONSerialization.data(withJSONObject:cap)
            } else if path.hasSuffix("/catalog") {
                var catalog=try AdvisoryWire.object(self.fixture("catalog-promoted"))
                if !self.alreadyApproved && self.operationID==nil {
                    var items=catalog["items"] as! [[String:Any]];items[0]["canonical_history"]=[];items[0]["candidate_id"]=NSNull();items[0]["mission_id"]=NSNull();items[0]["state"]="CONCEPT"
                    catalog["items"]=items;catalog["snapshot_revision"]=try AdvisoryWire.digest(items)
                }
                data=try JSONSerialization.data(withJSONObject:catalog)
            }
            else if path.hasSuffix("/package") { data=try self.fixture("prepared-complete") }
            else if path.hasSuffix("/approve") {
                var bytes=request.httpBody
                if bytes == nil,let stream=request.httpBodyStream {
                    stream.open();defer { stream.close() }
                    var buffer=[UInt8](repeating:0,count:4096),body=Data()
                    while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 { break };body.append(buffer,count:n) };bytes=body
                }
                self.operationID=try AdvisoryWire.object(bytes!)["operation_id"] as? String
                self.missingOperation=false
                var result=try AdvisoryWire.object(self.fixture("compound-result"));result["operation_id"]=self.operationID
                data=try JSONSerialization.data(withJSONObject:result)
                if self.loseReply { throw URLError(.networkConnectionLost) }
            } else if path.contains("/operations/") {
                if self.missingOperation { return (404,Data("{}".utf8)) }
                var result=try AdvisoryWire.object(self.fixture(self.superseded ? "operation-after-refinement":"operation-current"))
                result["operation_id"]=path.components(separatedBy:"/").last!
                data=try JSONSerialization.data(withJSONObject:result)
            } else { return (404,Data("{}".utf8)) }
            return (200,data)
        }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[StubProtocol.self]
        return MissionConceptTransport(http:AdvisoryTransport(configuration:config))
    }
    func connection(_ a:AdvisoryAccess)->AdvisoryConnection {
        .init(endpoint:a.endpoint,workspaceInstanceID:a.workspaceInstanceID,actorID:a.actorID,workspaceProjectID:a.workspaceProjectID,conversationID:a.conversationIDs[0],bearer:"synthetic-root",draftGrant:String(repeating:"D",count:43))
    }
    @MainActor func state(_ store:MissionIntentMemory) throws -> (MissionConceptState,AdvisoryConnection) {
        let (original,_)=try examples.access(),credentials=AdviceMemory()
        let access=AdvisoryAccess(endpoint:original.endpoint,workspaceInstanceID:original.workspaceInstanceID,workspaceProjectID:original.workspaceProjectID,actorID:original.actorID,forgeInstanceID:original.forgeInstanceID,forgeProjectID:original.forgeProjectID,repositoryID:original.repositoryID,conversationIDs:[conversation],token:original.token)
        credentials.access=access
        return (MissionConceptState(credentials:credentials,store:store,transport:try transport(access)),connection(access))
    }
    @MainActor func testExplicitApprovalRemainsWaitingRefreshChecksSupersessionAndRevocation() async throws {
        let store=MissionIntentMemory(),(state,c)=try state(store)
        await state.refresh(c)
        XCTAssertEqual(state.phase,"current", "Routes: \(requests.map { $0.url!.path })")
        let card=try XCTUnwrap(state.presentation(project:"Own").flatMap { $0.cards.first })
        await state.prepare(card,connection:c);XCTAssertTrue(state.canApprove(card))
        await state.approve(card,connection:c)
        XCTAssertEqual(state.phase,"APPROVED_WAITING");XCTAssertNil(store.value)
        XCTAssertFalse(state.canApprove(card))
        await state.prepare(card,connection:c);XCTAssertFalse(state.canApprove(card))
        await state.approve(card,connection:c)
        XCTAssertEqual(requests.filter { $0.httpMethod=="POST" }.count,1)
        await state.refresh(c);XCTAssertEqual(state.phase,"APPROVED_WAITING")
        superseded=true;await state.refresh(c)
        XCTAssertEqual(state.phase,"SUPERSEDED");XCTAssertFalse(try XCTUnwrap(state.approval).sourceFresh)
        XCTAssertEqual(state.presentation(project:"Own")?.cards.first?.status,"SUPERSEDED")
        deny=true;await state.refresh(c);XCTAssertEqual(state.phase,"denied")
        XCTAssertNil(state.approval);XCTAssertNil(state.presentation(project:"No leak"))
        XCTAssertEqual(requests.filter { $0.httpMethod=="POST" }.count,1)
    }
    @MainActor func testLostApprovalResponseRestartReadsOriginalOperationWithoutSecondPost() async throws {
        let store=MissionIntentMemory(),(first,c)=try state(store)
        await first.refresh(c)
        let card=try XCTUnwrap(first.presentation(project:"Own")?.cards.first)
        await first.prepare(card,connection:c);loseReply=true
        await first.approve(card,connection:c)
        let saved=try XCTUnwrap(store.value);XCTAssertEqual(saved.kind,"approve")
        XCTAssertNil(first.approval)
        let (restarted,_)=try state(store)
        await restarted.refresh(c)
        XCTAssertEqual(restarted.phase,"APPROVED_WAITING");XCTAssertNil(store.value)
        XCTAssertEqual(restarted.approval?.operationID,operationID)
        XCTAssertEqual(requests.filter { $0.httpMethod=="POST" }.count,1)
    }
    @MainActor func testMissingOperationRequiresExplicitResumeAndKeepsOriginalPayload() async throws {
        let store=MissionIntentMemory(),(initial,c)=try state(store)
        await initial.refresh(c)
        let card=try XCTUnwrap(initial.presentation(project:"Own")?.cards.first)
        await initial.prepare(card,connection:c)
        let packet=try XCTUnwrap(initial.packet),key=CandidateLocal.scopeKey(c)
        let body=try JSONSerialization.data(withJSONObject:["contract_version":MissionConceptWire.contract,"operation_id":"original-user-confirmation","revision":card.revision,"package_digest":packet.digest!,"confirm":true])
        try store.save(.init(key:key,connectionScope:MissionTransportIntent.scope(c),kind:"approve",refine:nil,approvalBody:body,frozenPackage:nil))
        missingOperation=true
        let (restarted,_)=try state(store)
        await restarted.refresh(c)
        XCTAssertEqual(restarted.phase,"pending");XCTAssertNotNil(store.value)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod=="GET" })
        await restarted.resume(c)
        XCTAssertEqual(operationID,"original-user-confirmation")
        XCTAssertEqual(restarted.phase,"APPROVED_WAITING");XCTAssertNil(store.value)
        XCTAssertEqual(requests.filter { $0.httpMethod=="POST" }.count,1)
        await restarted.resume(c)
        XCTAssertEqual(requests.filter { $0.httpMethod=="POST" }.count,1)
    }
    @MainActor func testPersistenceFailureAndUnpreparedSelectionNeverSendApproval() async throws {
        let store=MissionIntentMemory(),(state,c)=try state(store)
        await state.refresh(c)
        let card=try XCTUnwrap(state.presentation(project:"Own")?.cards.first)
        await state.approve(card,connection:c)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod=="GET" })
        await state.prepare(card,connection:c)
        store.broken=true
        await state.approve(card,connection:c)
        XCTAssertNil(state.approval);XCTAssertNil(state.packet)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod=="GET" })
        store.broken=false;await state.refresh(c)
        XCTAssertEqual(state.phase,"current")
        state.invalidate();XCTAssertNil(state.presentation(project:"Cleared"))
        await state.prepare(card,connection:c);XCTAssertNil(state.packet)
    }

    @MainActor func testScopeInvalidationWhileRecoveryLookupIsMissingNeverRetriesApprovalPost() async throws {
        let store=MissionIntentMemory(),(state,c)=try state(store)
        await state.refresh(c)
        let card=try XCTUnwrap(state.presentation(project:"Own")?.cards.first)
        await state.prepare(card,connection:c)
        let packet=try XCTUnwrap(state.packet)
        let body=try JSONSerialization.data(withJSONObject:["contract_version":MissionConceptWire.contract,"operation_id":"delayed-own-confirmation","revision":card.revision,"package_digest":packet.digest!,"confirm":true])
        let intent=MissionTransportIntent(key:CandidateLocal.scopeKey(c),connectionScope:MissionTransportIntent.scope(c),kind:"approve",refine:nil,approvalBody:body,frozenPackage:nil)
        try store.save(intent);missingOperation=true
        let original=try XCTUnwrap(StubProtocol.handler),entered=expectation(description:"Original lookup blocked"),release=DispatchSemaphore(value:0)
        StubProtocol.handler = { request in
            if request.url!.path.contains("/operations/") { entered.fulfill();XCTAssertEqual(release.wait(timeout:.now()+5),.success) }
            return try original(request)
        }
        let recovery=Task { await state.resume(c) }
        await fulfillment(of:[entered],timeout:3)
        state.invalidate();release.signal();await recovery.value
        XCTAssertEqual(store.value,intent);XCTAssertNil(state.approval)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod=="GET" })
    }

    @MainActor func testCompletedCanonicalHistoryRestoresApprovalFenceAfterRestart() async throws {
        let store=MissionIntentMemory();alreadyApproved=true
        let (first,c)=try state(store)
        await first.refresh(c)
        let card=try XCTUnwrap(first.presentation(project:"Own")?.cards.first)
        // Genuine canonical history is authoritative even with no local pending intent.
        XCTAssertFalse(first.canApprove(card))
        await first.prepare(card,connection:c)
        XCTAssertEqual(first.approval?.state,"COMPLETE")
        let (restarted,_)=try state(store)
        await restarted.refresh(c);await restarted.prepare(card,connection:c)
        XCTAssertEqual(restarted.approval?.state,"COMPLETE");XCTAssertFalse(restarted.canApprove(card))
        let restored = try XCTUnwrap(restarted.presentation(project:"Own")?.cards.first)
        let frozen = try AdvisoryWire.object(try XCTUnwrap(restarted.approval).frozenPackageData)
        let effects = try XCTUnwrap(frozen["consequences"] as? [String:Any])
        let effect = try XCTUnwrap(effects["repository_effect"] as? [String:Any])
        XCTAssertEqual(restored.consequences, [effect["mode"] as? String ?? "", effect["delivery"] as? String ?? ""])
        XCTAssertEqual(restored.remainingDecisions, effects["human_gates"] as? [String])
        await restarted.approve(card,connection:c)
        XCTAssertTrue(requests.allSatisfy { $0.httpMethod=="GET" })
        XCTAssertNil(store.value)
    }

}
