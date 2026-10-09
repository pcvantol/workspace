import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

private final class MissionRootCredentials:CredentialStore,@unchecked Sendable {
    let access:AdvisoryAccess
    private let lock=NSLock()
    private var tokenPause:(() -> Void)?
    func pauseNextToken(_ pause:@escaping () -> Void) { lock.withLock { tokenPause=pause } }
    init(_ access:AdvisoryAccess) { self.access=access }
    func binding() throws -> ServerBinding? { .init(endpoint:access.endpoint,instanceID:access.workspaceInstanceID) }
    func token() throws -> String? {
        let pause=lock.withLock { let value=tokenPause;tokenPause=nil;return value };pause?()
        return "synthetic-root"
    }
    func save(binding:ServerBinding,token:String) throws {}
    func forget() throws {}
}
private final class MissionDraftCredentials:DraftGrantStore,@unchecked Sendable {
    let value:DraftAccess
    init(_ value:DraftAccess) { self.value=value }
    func load() throws -> DraftAccess? { value }
    func save(_ access:DraftAccess) throws {}
    func forget() throws {}
}
private struct MissionNoLocalDrafts:LocalDraftStore {
    func load(scopeHash:String) throws -> LocalDraftSnapshot? { nil }
    func save(_ snapshot:LocalDraftSnapshot) throws {}
    func remove(scopeHash:String) throws {}
}
final class LiveMissionWorkspaceTests:XCTestCase {
    @MainActor func testConnectedSelectionPreparationRefinementAndScopeLossThroughExistingRoot() async throws {
        let peer=MissionApprovalRecoveryTests(),store=MissionIntentMemory(),(mission,c)=try peer.state(store)
        let (original,_)=try peer.examples.access()
        let access=AdvisoryAccess(endpoint:original.endpoint,workspaceInstanceID:original.workspaceInstanceID,workspaceProjectID:original.workspaceProjectID,actorID:original.actorID,forgeInstanceID:original.forgeInstanceID,forgeProjectID:original.forgeProjectID,repositoryID:original.repositoryID,conversationIDs:[peer.conversation],token:original.token)
        let conceptHandler=try XCTUnwrap(StubProtocol.handler)
        var ownCalls:[String]=[]
        let conversation:[String:Any] = ["id":peer.conversation,"actor_id":access.actorID,"project_id":access.workspaceProjectID,"title":"Client portal","focus":"Invoices","mode":"BUSINESS","draft":"","revision":1,"created_at":"2026-10-09T06:00:00Z","updated_at":"2026-10-09T06:00:00Z","history":[],"history_availability":"UNQUALIFIED_FORGE","state":"DRAFT_ONLY"]
        StubProtocol.handler = { request in
            let path=request.url!.path
            if path.hasPrefix("/v1/mission-concepts/") { return try conceptHandler(request) }
            ownCalls.append(path)
            let raw:[String:Any]
            switch path {
            case "/v1/identity":raw=["instance_id":access.workspaceInstanceID]
            case "/v1/status":raw=["instance_id":access.workspaceInstanceID,"version":"2.8.12","state":"READY","project_source":"AVAILABLE"]
            case "/v1/projects":raw=["state":"AVAILABLE","projects":[["id":access.workspaceProjectID,"name":"Own project"]],"source":"LOCAL","observed_at":"2026-10-09T06:00:00Z","partial":false,"stale":false]
            case "/v1/conversations":raw=["actor_id":access.actorID,"project_id":access.workspaceProjectID,"conversations":[conversation],"history_availability":"UNQUALIFIED_FORGE"]
            default:return (503,Data("{}".utf8))
            }
            return (200,try JSONSerialization.data(withJSONObject:raw))
        }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[StubProtocol.self]
        let rootCredentials=MissionRootCredentials(access)
        let client=ClientState(keychain:rootCredentials,transport:ServerTransport(configuration:config))
        for _ in 0..<100 where client.phase != "CONNECTED" { try await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(client.phase,"CONNECTED")
        let conversations=ConversationState(grants:MissionDraftCredentials(.init(endpoint:access.endpoint,instanceID:access.workspaceInstanceID,projectID:access.workspaceProjectID,token:c.draftGrant)),localDrafts:MissionNoLocalDrafts(),transport:ConversationTransport(configuration:config),missionConcepts:mission)
        let view=LiveMissionWorkspaceView(client:client,conversations:conversations)
        await view.refresh()
        XCTAssertEqual(conversations.selectedID,peer.conversation)
        let observed=await view.connection();XCTAssertEqual(observed,c.replacingBearer("synthetic-root"))
        let card=try XCTUnwrap(mission.presentation(project:"Own project")?.cards.first)
        await view.prepare(card);XCTAssertTrue(mission.canApprove(card))
        XCTAssertEqual(conversations.missionSelection.conversationID,peer.conversation)
        conversations.missionSelection.conversationID="foreign"
        let refused=await view.connection();XCTAssertNil(refused)
        conversations.missionSelection.conversationID=peer.conversation
        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:"nl")))
        host.frame=NSRect(x:0,y:0,width:1280,height:720);host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height,0)
        XCTAssertTrue(peer.requests.allSatisfy { $0.httpMethod=="GET" })
        // An unsupported perspective never reaches a provider.
        await view.refine("Do not invent UX permission",lens:"UX",card:card)
        XCTAssertTrue(peer.requests.allSatisfy { $0.httpMethod=="GET" })
        XCTAssertTrue(ownCalls.contains("/v1/conversations"))
        await view.refine("A focused context is required before generation",lens:"BUSINESS",card:card)
        XCTAssertNil(mission.capability)
        XCTAssertTrue(peer.requests.allSatisfy { $0.httpMethod=="GET" })
        client.forget();await view.refresh()
        XCTAssertNil(conversations.missionSelection.conversationID)
        XCTAssertNil(mission.presentation(project:"No leak"));let cleared=await view.connection();XCTAssertNil(cleared)
    }
    @MainActor func testEmptyNormalScreenNaturalSendCreatesOwnDraftThenResolvesAndGeneratesOnce() async throws {
        let peer=MissionConceptTransportTests(),access=peer.wire.access,credentials=AdviceMemory();credentials.access=access
        let mission=MissionConceptState(credentials:credentials,store:MissionIntentMemory(),transport:peer.transport())
        let sourceHandler=try XCTUnwrap(StubProtocol.handler)
        var ownRows:[[String:Any]]=[],ownCreates:[[String:Any]]=[]
        var twoCards=false
        let otherProducer="producer-second"
        func body(_ request:URLRequest) throws -> [String:Any] {
            if let data=request.httpBody { return try AdvisoryWire.object(data) }
            let stream=try XCTUnwrap(request.httpBodyStream);stream.open();defer { stream.close() }
            var buffer=[UInt8](repeating:0,count:4096),data=Data()
            while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 { break };data.append(buffer,count:n) }
            return try AdvisoryWire.object(data)
        }
        StubProtocol.handler = { request in
            let path=request.url!.path
            if path.hasPrefix("/v1/mission-concepts/") {
                if path.hasSuffix("/capability") {
                    var cap=try peer.wire.fixture("capability");cap["workspace_reference_resolution_supported"]=true
                    if twoCards { cap["conversation_ids"]=[peer.wire.conversation,otherProducer] }
                    return (200,try JSONSerialization.data(withJSONObject:cap))
                }
                if twoCards && path.hasSuffix("/catalog") {
                    let (_,bytes)=try sourceHandler(request)
                    var catalog=try AdvisoryWire.object(bytes),items=catalog["items"] as! [[String:Any]]
                    var second=items[0];second["conversation_id"]=otherProducer;second["object_id"]="concept-"+String(repeating:"b",count:32)
                    items.append(second);catalog["items"]=items;catalog["snapshot_revision"]=try AdvisoryWire.digest(items)
                    return (200,try JSONSerialization.data(withJSONObject:catalog))
                }
                if path=="/v1/mission-concepts/"+otherProducer { return (404,Data("{}".utf8)) }
                if path=="/v1/mission-concepts/"+otherProducer+"/context" {
                    let cap=try peer.wire.fixture("capability")
                    return (200,try JSONSerialization.data(withJSONObject:["contract_version":MissionConceptWire.contract,"conversation_id":otherProducer,"context":cap["context"]!,"context_revision":cap["context_revision"]!,"read_only":true,"additional_model_calls":0]))
                }
                if path.hasSuffix("/package"),let record=peer.recorded {
                    // Synthetic unprepared packet follows this test's changing turn/catalog.
                    var item=(try peer.wire.fixture("catalog")["items"] as! [[String:Any]])[0]
                    if path.contains(otherProducer) { item["object_id"]="concept-"+String(repeating:"b",count:32) }
                    let request=record["request"] as! [String:Any]
                    let packet:[String:Any]=["contract_version":MissionConceptWire.contract,"object_id":item["object_id"]!,"revision":(request["expected_revision"] as! Int)+1,"definition":item["definition"]!,"package":NSNull(),"questions":["Fixture planning remains unavailable."],"approval_supported":false,"read_only":true,"additional_model_calls":0]
                    return (200,try JSONSerialization.data(withJSONObject:packet))
                }
                if peer.recorded==nil && path.hasSuffix("/catalog") {
                    var catalog=try peer.wire.fixture("catalog");catalog["items"]=[];catalog["snapshot_revision"]=try AdvisoryWire.digest([])
                    return (200,try JSONSerialization.data(withJSONObject:catalog))
                }
                if peer.recorded==nil && path=="/v1/mission-concepts/"+peer.wire.conversation { return (404,Data("{}".utf8)) }
                return try sourceHandler(request)
            }
            let raw:[String:Any]
            switch path {
            case "/v1/identity":raw=["instance_id":access.workspaceInstanceID]
            case "/v1/status":raw=["instance_id":access.workspaceInstanceID,"version":"2.8.12","state":"READY","project_source":"AVAILABLE"]
            case "/v1/projects":raw=["state":"AVAILABLE","projects":[["id":access.workspaceProjectID,"name":"Own project"]],"source":"LOCAL","observed_at":"2026-10-09T06:00:00Z","partial":false,"stale":false]
            case "/v1/conversations":
                if request.httpMethod=="POST" {
                    let submitted=try body(request);ownCreates.append(submitted)
                    let row:[String:Any]=["id":String(repeating:"b",count:32),"actor_id":access.actorID,"project_id":access.workspaceProjectID,"title":submitted["title"]!,"focus":submitted["focus"]!,"mode":submitted["mode"]!,"draft":submitted["draft"]!,"revision":1,"created_at":"2026-10-09T06:00:00Z","updated_at":"2026-10-09T06:00:00Z","history":[],"history_availability":"UNQUALIFIED_FORGE","state":"DRAFT_ONLY"]
                    ownRows=[row];return (201,try JSONSerialization.data(withJSONObject:row))
                }
                raw=["actor_id":access.actorID,"project_id":access.workspaceProjectID,"conversations":ownRows,"history_availability":"UNQUALIFIED_FORGE"]
            default:return (503,Data("{}".utf8))
            }
            return (200,try JSONSerialization.data(withJSONObject:raw))
        }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[StubProtocol.self]
        let rootCredentials=MissionRootCredentials(access)
        let client=ClientState(keychain:rootCredentials,transport:ServerTransport(configuration:config))
        for _ in 0..<100 where client.phase != "CONNECTED" { try await Task.sleep(for:.milliseconds(10)) }
        let conversations=ConversationState(grants:MissionDraftCredentials(.init(endpoint:access.endpoint,instanceID:access.workspaceInstanceID,projectID:access.workspaceProjectID,token:String(repeating:"D",count:43))),localDrafts:MissionNoLocalDrafts(),transport:ConversationTransport(configuration:config),missionConcepts:mission)
        let view=LiveMissionWorkspaceView(client:client,conversations:conversations)
        await view.refresh()
        XCTAssertTrue(conversations.conversations.isEmpty);XCTAssertTrue(mission.items.isEmpty)
        XCTAssertEqual(conversations.observedActorID,"alice")
        view.beginNewMission()
        XCTAssertTrue(conversations.missionSelection.newDraft);XCTAssertTrue(ownCreates.isEmpty)
        let goal="I want clients to see their invoices, without executing payments."
        await view.refine(goal,lens:"BUSINESS",card:nil)
        XCTAssertEqual(ownCreates.count,1);XCTAssertEqual(ownCreates.first?["draft"] as? String,goal)
        XCTAssertEqual(conversations.selectedID,String(repeating:"b",count:32))
        XCTAssertEqual(conversations.missionSelection.conversationID,peer.wire.conversation)
        XCTAssertEqual(mission.history.first?.request.objective,goal)
        XCTAssertEqual(mission.history.first?.request.conversation_id,peer.wire.conversation)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/resolve") }.count,1)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/turns") }.count,1)
        XCTAssertFalse(conversations.missionSelection.newDraft)
        await view.refresh()
        XCTAssertEqual(ownCreates.count,1)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/turns") }.count,1)
        let setup=MissionSetupView(client:client,conversations:conversations,state:mission)
        await setup.save(access.token)
        let card=try XCTUnwrap(mission.presentation(project:"Own")?.cards.first)
        twoCards=true
        credentials.access=AdvisoryAccess(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,workspaceProjectID:access.workspaceProjectID,actorID:access.actorID,forgeInstanceID:access.forgeInstanceID,forgeProjectID:access.forgeProjectID,repositoryID:access.repositoryID,conversationIDs:[peer.wire.conversation,otherProducer],token:access.token)
        await view.refresh()
        let secondCard=try XCTUnwrap(mission.presentation(project:"Own")?.cards.first(where: { $0.id=="concept-"+String(repeating:"b",count:32) }))
        let liveHandler=try XCTUnwrap(StubProtocol.handler)
        let refreshEntered=expectation(description:"Refinement refresh is delayed"),releaseRefresh=DispatchSemaphore(value:0)
        var delayRefresh=true
        StubProtocol.handler = { request in
            if delayRefresh && request.url!.path.hasSuffix("/capability") {
                delayRefresh=false;refreshEntered.fulfill();XCTAssertEqual(releaseRefresh.wait(timeout:.now()+5),.success)
            }
            return try liveHandler(request)
        }
        let delayedRefinement=Task { await view.refine("This message belongs to the original selection",lens:"BUSINESS",card:card) }
        await fulfillment(of:[refreshEntered],timeout:3)
        // Actual A→B selection while A refresh is delayed must send to neither subject.
        let selectOther=Task { await view.prepare(secondCard) }
        for _ in 0..<100 where conversations.missionSelection.conversationID != otherProducer { await Task.yield() }
        XCTAssertEqual(conversations.missionSelection.conversationID,otherProducer)
        releaseRefresh.signal();await selectOther.value;await delayedRefinement.value
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/turns") }.count,1)
        StubProtocol.handler=liveHandler
        await view.prepare(card)
        let tokenEntered=expectation(description:"Earlier credential lookup is delayed"),releaseToken=DispatchSemaphore(value:0)
        rootCredentials.pauseNextToken { tokenEntered.fulfill();XCTAssertEqual(releaseToken.wait(timeout:.now()+5),.success) }
        let earlyRefinement=Task { await view.refine("Original A intent must not overwrite B",lens:"BUSINESS",card:card) }
        await fulfillment(of:[tokenEntered],timeout:3)
        let earlySelection=Task { await view.prepare(secondCard) }
        for _ in 0..<100 where conversations.missionSelection.conversationID != otherProducer { await Task.yield() }
        XCTAssertEqual(conversations.missionSelection.conversationID,otherProducer)
        releaseToken.signal();await earlyRefinement.value;await earlySelection.value
        XCTAssertEqual(conversations.missionSelection.conversationID,otherProducer)
        XCTAssertEqual(mission.packet?.objectID,secondCard.id)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/turns") }.count,1)
        twoCards=false;credentials.access=access
        await view.prepare(card)
        peer.dropSubmit=true
        await view.refine("Keep the account isolation criterion",lens:"ARCHITECTURE",card:nil)
        XCTAssertEqual(ownCreates.count,1)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/resolve") }.count,1)
        XCTAssertNotNil(mission.pending)
        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:"nl")))
        host.frame=NSRect(x:0,y:0,width:1280,height:720);host.layoutSubtreeIfNeeded()
        await view.resume()
        XCTAssertNil(mission.pending)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" && $0.url!.path.hasSuffix("/turns") }.count,2)
    }

}
private extension AdvisoryConnection {
    func replacingBearer(_ token:String)->AdvisoryConnection {
        .init(endpoint:endpoint,workspaceInstanceID:workspaceInstanceID,actorID:actorID,workspaceProjectID:workspaceProjectID,conversationID:conversationID,bearer:token,draftGrant:draftGrant)
    }
}
