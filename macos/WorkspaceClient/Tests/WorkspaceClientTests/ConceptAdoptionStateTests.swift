import XCTest
@testable import WorkspaceClient

// Source-only protocol doubles; real installed qualified chain is separately required.
final class AdoptionFixture:ConceptAdoptionServing,@unchecked Sendable {
    let concept:ProjectConcept;let source=String(repeating:"e",count:32)
    var posts:[ConceptAdoptionCommand]=[];var created:[String:ConceptAdoptionResult]=[:]
    var reject=false
    var lose=false;var holdRead=false;var holdHistory=false
    var readWait:CheckedContinuation<ConceptAdoptionResult,Error>?
    var historyWait:CheckedContinuation<ConceptAdoptionHistory,Error>?
    init(_ concept:ProjectConcept){self.concept=concept}
    func sources(_ c:ConceptConnection,concept:String) async throws->ConceptAdoptionSources {.init(contract_version:"workspace-concept-adoption/1",actor_id:self.concept.actor_id,context_id:c.access.projectID,concept_id:concept,sources:[.init(id:source,label:"Source-only owner label",source_options:["docs/RICHTING.md"],setup_metadata_not_observed:true,can_prepare:true,expires_at:"2099-01-01T00:00:00Z")])}
    func access(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionAccess {.init(contract_version:"workspace-concept-adoption/1",actor_id:self.concept.actor_id,context_id:c.access.projectID,concept_id:concept,binding_id:source,producer_source:ConceptAdoptionResult.pin,source_revision:self.concept.revision,can_prepare:true,expires_at:"2099-01-01T00:00:00Z")}
    func history(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionHistory {if holdHistory{return try await withCheckedThrowingContinuation{historyWait=$0}};return .init(operations:[])}
    func packet(_ op:String,digest:String=String(repeating:"a",count:64))->ConceptAdoptionResult {.init(contract_version:"workspace-concept-adoption/1",actor_id:concept.actor_id,context_id:concept.context_id,concept_id:concept.id,binding_id:source,producer_source:ConceptAdoptionResult.pin,operation_id:op,source_revision:1,current_revision:concept.revision,source_digest:String(repeating:"d",count:64),proposal:.init(contract_version:"forge-ep-inspection-adoption-preview/v1",instance_id:"forge",principal_id:"actor",audience:"workspace",dossier_id:"dossier",pairing_id:"pairing",operation_id:op,plan_id:"original",request_digest:digest,state:"PREPARING",result:nil,proposal_kind:"ep-inspection-adoption-preview/1.0",original_intent:true,approval:"NOT_PERFORMED",registration:"NOT_PERFORMED"),document:nil)}
    func prepare(_ c:ConceptConnection,concept:String,source:String,command:ConceptAdoptionCommand) async throws->ConceptAdoptionResult {posts.append(command);if reject{throw ConceptAdoptionError.sourceRejected};let value=packet(command.operation_id);created[command.operation_id]=value;if lose{throw ConceptError.unavailable};return value}
    func read(_ c:ConceptConnection,concept:String,source:String,operation:String) async throws->ConceptAdoptionResult {if holdRead{return try await withCheckedThrowingContinuation{readWait=$0}};guard let value=created[operation] else{throw ConceptError.notFound};return value}
}
final class ConceptAdoptionStateTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"context",token:String(repeating:"c",count:43)),bearer:"source-only")
    @MainActor private func configured(_ root:URL) async->(ConceptAdoptionState,AdoptionFixture,ProjectConcept) {
        let concept=ConceptBaselineTests().concept();let fixture=AdoptionFixture(concept);let state=ConceptAdoptionState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});await state.select(fixture.source,concept:concept,current:{active});return(state,fixture,concept)
    }
    @MainActor func testLostCommittedResponseRecoversOnlyOriginalAfterStateRestart() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection;fixture.lose=true
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:"docs/RICHTING.md",current:{active});let original=try XCTUnwrap(state.pending);state.conceal()
        let restarted=ConceptAdoptionState(transport:fixture,root:root);await restarted.load(concept,current:{active});await restarted.select(fixture.source,concept:concept,current:{active})
        XCTAssertEqual(fixture.posts.count,1);XCTAssertEqual(restarted.result?.operation_id,original.command.operation_id);XCTAssertEqual(restarted.phase,"pending");restarted.conceal()
    }
    @MainActor func testSourceOptionsValidatedBeforeDurablePendingCapture() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection
        for(paths,vision) in [(["docs/product/VISION.md"],"docs/OTHER.md"),(["docs/roadmap/ROADMAP.md"],"docs/RICHTING.md")] {await state.prepare(concept,paths:paths,vision:vision,current:{active});XCTAssertNil(state.pending)}
        XCTAssertTrue(fixture.posts.isEmpty);XCTAssertNil(try state.records.load(state.key(active,concept,fixture.source)));state.conceal()
    }
    @MainActor func testDelayedHistoryCannotReturnAfterConcealAndSameSourceReselection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection;fixture.holdHistory=true
        let old=Task{await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})}
        for _ in 0..<100 where fixture.historyWait==nil {await Task.yield()};let waiting=try XCTUnwrap(fixture.historyWait);state.conceal();fixture.holdHistory=false
        await state.load(concept,current:{active});await state.select(fixture.source,concept:concept,current:{active});let raw=try state.records.load(state.key(active,concept,fixture.source))
        waiting.resume(returning:.init(operations:[.init(operation_id:String(repeating:"f",count:32),source_revision:1)]));await old.value
        XCTAssertTrue(state.history.isEmpty);XCTAssertEqual(try state.records.load(state.key(active,concept,fixture.source)),raw);state.conceal()
    }
    @MainActor func testDelayedReadCannotRewriteJournalAfterSameSourceReselection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection;await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active});let op=try XCTUnwrap(state.pending?.command.operation_id);fixture.holdRead=true
        let old=Task{await state.open(op,concept:concept,current:{active})};for _ in 0..<100 where fixture.readWait==nil {await Task.yield()};let waiting=try XCTUnwrap(fixture.readWait);state.conceal();fixture.holdRead=false
        await state.load(concept,current:{active});await state.select(fixture.source,concept:concept,current:{active});let raw=try state.records.load(state.key(active,concept,fixture.source))
        waiting.resume(returning:fixture.packet(op,digest:String(repeating:"b",count:64)));await old.value
        XCTAssertEqual(try state.records.load(state.key(active,concept,fixture.source)),raw);XCTAssertEqual(state.result?.proposal.request_digest,String(repeating:"a",count:64));state.conceal()
    }
    @MainActor func testDefinitivePreCaptureRejectionSurvivesRestartAndRequiresExplicitRetirement() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection;fixture.reject=true
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
        let rejected=try XCTUnwrap(state.pending);XCTAssertEqual(state.phase,"sourceRejected");XCTAssertTrue(fixture.created.isEmpty);state.conceal()
        let restarted=ConceptAdoptionState(transport:fixture,root:root);await restarted.load(concept,current:{active})
        XCTAssertEqual(restarted.phase,"sourceRejected");XCTAssertEqual(restarted.pending?.command,rejected.command)
        await restarted.retireRejected(concept:concept,current:{active});XCTAssertNil(restarted.pending)
        let archive=ConceptAdoptionResult.hash(Data((rejected.key+"\n"+rejected.command.operation_id).utf8));XCTAssertNotNil(try restarted.records.load(archive))
        fixture.reject=false;await restarted.prepare(concept,paths:["docs/architecture/ARCHITECTURE.md"],vision:nil,current:{active})
        XCTAssertEqual(fixture.posts.count,2);XCTAssertNotEqual(restarted.pending?.command.operation_id,rejected.command.operation_id);restarted.conceal()
    }
    @MainActor func testUncertainOriginal404CannotRetireOrMakeSecondRequest() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection;fixture.lose=true
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
        let pending=try XCTUnwrap(state.pending);fixture.created=[:]
        await state.open(pending.command.operation_id,concept:concept,current:{active});XCTAssertEqual(state.phase,"notFound")
        await state.retireRejected(concept:concept,current:{active})
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
        XCTAssertEqual(state.pending?.command,pending.command);XCTAssertEqual(fixture.posts.count,1);state.conceal()
    }
    @MainActor func testMonitorCompletesOriginalJournalWithoutAnotherPrepare() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept)=await configured(root);let active=connection
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
        let pending=try XCTUnwrap(state.pending);var observed=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/inspection-adoption-observed.json"))) as! [String:Any]
        observed["actor_id"]=concept.actor_id;observed["context_id"]=concept.context_id;observed["concept_id"]=concept.id;observed["binding_id"]=fixture.source;observed["operation_id"]=pending.command.operation_id;observed["source_revision"]=1;observed["current_revision"]=1
        var proposal=observed["proposal"] as! [String:Any];proposal["operation_id"]=pending.command.operation_id;proposal["request_digest"]=String(repeating:"a",count:64);observed["proposal"]=proposal
        fixture.created[pending.command.operation_id]=try JSONDecoder().decode(ConceptAdoptionResult.self,from:JSONSerialization.data(withJSONObject:observed))
        try await state.refreshOriginal(active,concept:concept,selected:fixture.source,cap:XCTUnwrap(state.access),ticket:state.generation,current:{active})
        XCTAssertNil(state.pending);XCTAssertEqual(state.phase,"prepared");XCTAssertEqual(fixture.posts.count,1)
        let persisted=try JSONDecoder().decode(ConceptAdoptionState.Journal.self,from:XCTUnwrap(state.records.load(pending.key)));XCTAssertTrue(persisted.complete)
        state.conceal()
    }

}
