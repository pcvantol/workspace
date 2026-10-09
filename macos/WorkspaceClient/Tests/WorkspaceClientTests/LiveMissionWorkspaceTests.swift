import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

private final class MissionRootCredentials:CredentialStore,@unchecked Sendable {
    let access:AdvisoryAccess
    init(_ access:AdvisoryAccess) { self.access=access }
    func binding() throws -> ServerBinding? { .init(endpoint:access.endpoint,instanceID:access.workspaceInstanceID) }
    func token() throws -> String? { "synthetic-root" }
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
        let client=ClientState(keychain:MissionRootCredentials(access),transport:ServerTransport(configuration:config))
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
                    return (200,try JSONSerialization.data(withJSONObject:cap))
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
        let client=ClientState(keychain:MissionRootCredentials(access),transport:ServerTransport(configuration:config))
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
        peer.dropSubmit=true
        await view.refine("Keep the account isolation criterion",lens:"ARCHITECTURE",card:card)
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
