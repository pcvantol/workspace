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
        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:"nl")))
        host.frame=NSRect(x:0,y:0,width:1280,height:720);host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height,0)
        XCTAssertTrue(peer.requests.allSatisfy { $0.httpMethod=="GET" })
        // An unsupported perspective never reaches a provider.
        await view.refine("Do not invent UX permission",lens:"UX",card:card)
        XCTAssertTrue(peer.requests.allSatisfy { $0.httpMethod=="GET" })
        XCTAssertTrue(ownCalls.contains("/v1/conversations"))
        client.forget();await view.refresh()
        XCTAssertNil(mission.presentation(project:"No leak"));let cleared=await view.connection();XCTAssertNil(cleared)
    }
}
private extension AdvisoryConnection {
    func replacingBearer(_ token:String)->AdvisoryConnection {
        .init(endpoint:endpoint,workspaceInstanceID:workspaceInstanceID,actorID:actorID,workspaceProjectID:workspaceProjectID,conversationID:conversationID,bearer:token,draftGrant:draftGrant)
    }
}
