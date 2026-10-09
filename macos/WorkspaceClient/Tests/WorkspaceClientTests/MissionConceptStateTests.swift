import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionIntentMemory: MissionIntentStore, @unchecked Sendable {
    var value: MissionTransportIntent?
    var broken=false
    func load(_ key:String) throws -> MissionTransportIntent? { if broken { throw AdvisoryError.unavailable };return value?.key == key ? value:nil }
    func save(_ intent:MissionTransportIntent) throws { if broken { throw AdvisoryError.unavailable };value=intent }
    func clear(_ key:String) throws { if broken { throw AdvisoryError.unavailable };if value?.key==key { value=nil } }
}
final class MissionConceptStateTests: XCTestCase, @unchecked Sendable {
    let peer=MissionConceptTransportTests()
    @MainActor func testRefreshDisplaysOnlyActualDefinitionsAndReadsDoNotSubmit() async throws {
        let credentials=AdviceMemory();credentials.access=peer.wire.access
        let store=MissionIntentMemory(),state=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        await state.refresh(peer.connection)
        XCTAssertEqual(state.items.count,1);XCTAssertEqual(state.history.count,1)
        let presentation=state.presentation(project:"Own synthetic project")!
        XCTAssertEqual(presentation.cards[0].title,"Invoice portal")
        XCTAssertTrue(presentation.relations.isEmpty)
        XCTAssertNil(presentation.cards[0].consequences)
        XCTAssertEqual(presentation.transcript?.count,2)
        XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        XCTAssertTrue(state.canRefine("Make this smaller",lens:"BUSINESS"))
        XCTAssertFalse(state.canRefine("",lens:"BUSINESS"));XCTAssertFalse(state.canRefine("hello",lens:"UX"))
        peer.deny=true;await state.refresh(peer.connection)
        XCTAssertNil(state.presentation(project:"must not leak"));XCTAssertTrue(state.items.isEmpty)
        XCTAssertFalse(state.canRefine("hello",lens:"BUSINESS"))
        state.invalidate();XCTAssertNil(state.pending)
    }
    @MainActor func testRestartPendingReadsOriginalWithoutAutomaticRegeneration() async throws {
        let credentials=AdviceMemory();credentials.access=peer.wire.access
        let store=MissionIntentMemory(),request=try MissionConceptWire.request(peer.wire.fixture("request"),access:peer.wire.access,conversation:peer.wire.conversation)
        let intent=MissionTransportIntent(key:CandidateLocal.scopeKey(peer.connection),connectionScope:MissionTransportIntent.scope(peer.connection),kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil)
        try store.save(intent)
        let state=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        await state.refresh(peer.connection)
        XCTAssertNil(store.value);XCTAssertNil(state.pending)
        XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        try store.save(intent);await state.resume(peer.connection)
        XCTAssertNil(store.value);XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        await state.refresh(nil);XCTAssertTrue(state.history.isEmpty)
    }
    @MainActor func testExplicitRefinementAndLostResponseRestartKeepSameTurn() async throws {
        let credentials=AdviceMemory();credentials.access=peer.wire.access
        let store=MissionIntentMemory(),state=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        await state.refresh(peer.connection)
        await state.refine("Keep payment execution excluded",lens:"ARCHITECTURE",connection:peer.connection)
        XCTAssertEqual(state.revision,2);XCTAssertNil(state.pending)
        XCTAssertEqual(state.history.first?.request.objective,"Keep payment execution excluded")
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" }.count,1)
        peer.dropSubmit=true
        await state.refine("Require account isolation",lens:"BUSINESS",connection:peer.connection)
        let original=try XCTUnwrap(store.value?.refine)
        XCTAssertEqual(state.phase,"pending");XCTAssertNil(state.capability)
        let restarted=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        await restarted.refresh(peer.connection)
        XCTAssertNil(store.value);XCTAssertEqual(restarted.revision,3)
        XCTAssertEqual(restarted.history.first?.request.turn_id,original.turn_id)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" }.count,2)
    }
    @MainActor func testUnsentPendingRequiresExplicitResumeAndStorageFailureSendsNothing() async throws {
        let credentials=AdviceMemory();credentials.access=peer.wire.access
        let store=MissionIntentMemory(),request=try MissionConceptWire.request(peer.wire.fixture("request"),access:peer.wire.access,conversation:peer.wire.conversation)
        try store.save(.init(key:CandidateLocal.scopeKey(peer.connection),connectionScope:MissionTransportIntent.scope(peer.connection),kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil))
        peer.absentTurn=true
        let state=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        await state.refresh(peer.connection)
        XCTAssertEqual(state.phase,"pending");XCTAssertNotNil(state.pending)
        XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
        await state.resume(peer.connection)
        XCTAssertNil(store.value);XCTAssertEqual(state.history.first?.request.turn_id,request.turn_id)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" }.count,1)
        store.broken=true
        await state.refine("New refinement",lens:"BUSINESS",connection:peer.connection)
        XCTAssertEqual(peer.calls.filter { $0.httpMethod=="POST" }.count,1)
        XCTAssertNil(state.capability)
    }

    @MainActor func testInvalidatedScopeDoesNotRetryMissingRefinementAfterDelayedRead() async throws {
        let credentials=AdviceMemory();credentials.access=peer.wire.access
        let store=MissionIntentMemory(),request=try MissionConceptWire.request(peer.wire.fixture("request"),access:peer.wire.access,conversation:peer.wire.conversation)
        let intent=MissionTransportIntent(key:CandidateLocal.scopeKey(peer.connection),connectionScope:MissionTransportIntent.scope(peer.connection),kind:"refine",refine:request,approvalBody:nil,frozenPackage:nil)
        try store.save(intent);peer.absentTurn=true
        let state=MissionConceptState(credentials:credentials,store:store,transport:peer.transport())
        let original=try XCTUnwrap(StubProtocol.handler),entered=expectation(description:"Original turn read blocked"),release=DispatchSemaphore(value:0)
        StubProtocol.handler = { r in
            if r.url!.path.contains("/turns/") { entered.fulfill();XCTAssertEqual(release.wait(timeout:.now()+5),.success) }
            return try original(r)
        }
        let task=Task { await state.resume(peer.connection) }
        await fulfillment(of:[entered],timeout:3)
        state.invalidate();release.signal();await task.value
        XCTAssertEqual(store.value,intent);XCTAssertTrue(peer.calls.allSatisfy { $0.httpMethod=="GET" })
    }

}
