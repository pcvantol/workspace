import Foundation
import AppKit
import SwiftUI
import Security
import XCTest
@testable import WorkspaceClient

private final class MissionCredentialBackend:@unchecked Sendable {
    let lock=NSLock()
    var values:[String:Data]=[:]
    func key(_ query:CFDictionary)->String {
        let q=query as NSDictionary
        return (q[kSecAttrService] as! String)+":"+(q[kSecAttrAccount] as! String)
    }
    var operations:DraftKeychainOperations {
        .init(copy:{ q in self.lock.withLock { self.values[self.key(q)].map { (errSecSuccess,$0) } ?? (errSecItemNotFound,nil) } },
              update:{ q,v in self.lock.withLock { let k=self.key(q);guard self.values[k] != nil else { return errSecItemNotFound };self.values[k]=(v as NSDictionary)[kSecValueData] as? Data;return errSecSuccess } },
              add:{ q in self.lock.withLock { self.values[self.key(q)]=(q as NSDictionary)[kSecValueData] as? Data;return errSecSuccess } },
              delete:{ q in self.lock.withLock { self.values[self.key(q)]=nil;return errSecSuccess } })
    }
}
final class MissionCredentialNamespaceTests:XCTestCase {
    func testGenericProducerSlotsNeverRelaxOrOverwriteLegacyAdviceCredentials() throws {
        let original=MissionConceptWireTests().access
        let source=AdvisoryAccess(endpoint:original.endpoint,workspaceInstanceID:original.workspaceInstanceID,workspaceProjectID:original.workspaceProjectID,actorID:original.actorID,forgeInstanceID:original.forgeInstanceID,forgeProjectID:original.forgeProjectID,repositoryID:original.repositoryID,conversationIDs:["producer-slot-a"],token:original.token)
        XCTAssertFalse(source.valid);XCTAssertTrue(source.validForMission)
        let backend=MissionCredentialBackend(),advice=AdvisoryKeychain(operations:backend.operations),mission=AdvisoryKeychain(operations:backend.operations,mission:true)
        XCTAssertThrowsError(try advice.saveAccess(source))
        try advice.saveAccess(original);try mission.saveAccess(source)
        XCTAssertEqual(try advice.loadAccess(),original);XCTAssertEqual(try mission.loadAccess(),source)
        XCTAssertThrowsError(try mission.loadIntent());XCTAssertThrowsError(try mission.forgetIntent())
        try mission.forgetAccess();XCTAssertNil(try mission.loadAccess());XCTAssertEqual(try advice.loadAccess(),original)
    }
    @MainActor func testOwnReferencesAndProducerConnectionsRemainProjectActorAndInstanceBound() async throws {
        let peer=MissionConceptTransportTests(),credentials=AdviceMemory();credentials.access=peer.wire.access
        let state=MissionConceptState(credentials:credentials,store:MissionIntentMemory(),transport:peer.transport())
        let own=AdvisoryConnection(endpoint:peer.connection.endpoint,workspaceInstanceID:peer.connection.workspaceInstanceID,actorID:peer.connection.actorID,workspaceProjectID:peer.connection.workspaceProjectID,conversationID:String(repeating:"b",count:32),bearer:peer.connection.bearer,draftGrant:peer.connection.draftGrant)
        let source=await state.resolveWorkspace(own)
        XCTAssertEqual(source?.conversationID,peer.wire.conversation)
        XCTAssertEqual(peer.calls.count,1);XCTAssertEqual(peer.calls[0].url?.path,"/v1/mission-concepts/resolve")
        let foreign=AdvisoryConnection(endpoint:own.endpoint,workspaceInstanceID:own.workspaceInstanceID,actorID:"bob",workspaceProjectID:own.workspaceProjectID,conversationID:own.conversationID,bearer:own.bearer,draftGrant:own.draftGrant)
        XCTAssertNil(state.producerConnection(foreign));let denied=await state.resolveWorkspace(foreign);XCTAssertNil(denied)
        XCTAssertEqual(peer.calls.count,1)
    }
    @MainActor func testOneTimeOwnerAccessSaveReadsOnlyAndFailureDoesNotCreatePermissions() async throws {
        let peer=MissionConceptTransportTests(),credentials=AdviceMemory()
        let state=MissionConceptState(credentials:credentials,store:MissionIntentMemory(),transport:peer.transport())
        let own=AdvisoryConnection(endpoint:peer.connection.endpoint,workspaceInstanceID:peer.connection.workspaceInstanceID,actorID:peer.connection.actorID,workspaceProjectID:peer.connection.workspaceProjectID,conversationID:"",bearer:peer.connection.bearer,draftGrant:peer.connection.draftGrant)
        await state.saveGrant("invalid",workspace:own);XCTAssertTrue(peer.calls.isEmpty)
        await state.saveGrant(peer.wire.access.token,workspace:own)
        XCTAssertEqual(credentials.access,peer.wire.access);XCTAssertNotNil(state.capability)
        XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        credentials.broken=true
        await state.saveGrant(peer.wire.access.token,workspace:own)
        XCTAssertNil(state.capability);XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        let client=ClientState(keychain:MissionRootCredentialsForSetup(),transport:ServerTransport()),conversations=ConversationState(missionConcepts:state)
        for language in ["en","nl","de","fr","es"] {
            let host=NSHostingView(rootView:MissionSetupView(client:client,conversations:conversations,state:state).environment(\.locale,Locale(identifier:language)))
            host.frame=NSRect(x:0,y:0,width:490,height:300);host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.height,0)
        }
        XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
    }

}

private struct MissionRootCredentialsForSetup:CredentialStore {
    func binding() throws -> ServerBinding? { nil }
    func token() throws -> String? { nil }
    func save(binding:ServerBinding,token:String) throws {}
    func forget() throws {}
}
