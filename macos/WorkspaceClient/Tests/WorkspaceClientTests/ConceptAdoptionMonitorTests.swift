import XCTest
@testable import WorkspaceClient

// Source-only controlled protocol responses; installed qualification remains separate.
private actor AdoptionMonitorFixture:ConceptAdoptionServing {
    nonisolated let source=String(repeating:"e",count:32)
    let base:AdoptionFixture
    var created:[String:ConceptAdoptionResult]=[:]
    var posts:[ConceptAdoptionCommand]=[]
    var reads:[String]=[]
    var accessCalls=0
    var denied=false
    var held:[Int:(String,CheckedContinuation<ConceptAdoptionResult,Error>)]=[:]
    init(_ concept:ProjectConcept) {base=AdoptionFixture(concept)}
    func sources(_ c:ConceptConnection,concept:String) async throws->ConceptAdoptionSources {try await base.sources(c,concept:concept)}
    func access(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionAccess {
        accessCalls+=1
        if denied {throw ConceptError.denied}
        return try await base.access(c,concept:concept,source:source)
    }
    func history(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionHistory {.init(operations:created.keys.sorted().map{.init(operation_id:$0,source_revision:1)})}
    func prepare(_ c:ConceptConnection,concept:String,source:String,command:ConceptAdoptionCommand) async throws->ConceptAdoptionResult {
        posts.append(command);let packet=base.packet(command.operation_id);created[command.operation_id]=packet;return packet
    }
    func read(_ c:ConceptConnection,concept:String,source:String,operation:String) async throws->ConceptAdoptionResult {
        reads.append(operation);let index=reads.count
        if index>2,let packet=created[operation] {return packet}
        return try await withCheckedThrowingContinuation {held[index]=(operation,$0)}
    }
    func heldCount()->Int {held.count}
    func accessCount()->Int {accessCalls}
    func deny() {denied=true}
    func release(_ index:Int,unavailable:Bool=false) {
        guard let (operation,continuation)=held.removeValue(forKey:index) else{return}
        if unavailable {continuation.resume(throwing:ConceptError.unavailable)}
        else if let packet=created[operation] {continuation.resume(returning:packet)}
        else {continuation.resume(throwing:ConceptError.notFound)}
    }
    func releaseAll() {for index in Array(held.keys) {release(index)}}
    func effects()->(Int,[String]) {(posts.count,reads)}
}

final class ConceptAdoptionMonitorTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"context",token:String(repeating:"c",count:43)),bearer:"source-only")
    @MainActor private func observed(_ predicate:() async->Bool) async throws->Bool {
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        repeat {if await predicate(){return true};try await Task.sleep(for:.milliseconds(20))} while ContinuousClock.now<deadline
        return false
    }
    @MainActor private func overlapThenDeny(unavailable:Bool) async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let concept=ConceptBaselineTests().concept(),active=connection
        let fixture=AdoptionMonitorFixture(concept),state=ConceptAdoptionState(transport:fixture,root:root)
        var opening:Task<Void,Never>?
        do {
            await state.load(concept,current:{active});await state.select(fixture.source,concept:concept,current:{active})
            await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
            let original=try XCTUnwrap(state.pending?.command.operation_id)
            // Wait for the REAL three-second monitor to capture the original response.
            let monitorHeld=try await observed{await fixture.heldCount()==1};XCTAssertTrue(monitorHeld)
            guard monitorHeld else{await fixture.releaseAll();state.conceal();return}
            opening=Task{await state.open(original,concept:concept,current:{active})}
            let openHeld=try await observed{await fixture.heldCount()==2};XCTAssertTrue(openHeld)
            guard openHeld else{await fixture.releaseAll();await opening?.value;state.conceal();return}
            XCTAssertNil(state.result);XCTAssertTrue(state.busy)
            let priorAccess=await fixture.accessCount()
            await fixture.release(1,unavailable:unavailable)
            // A superseded read OR recoverable transport failure must not kill authority polling.
            let stillMonitoring=try await observed{await fixture.accessCount()>priorAccess}
            XCTAssertTrue(stillMonitoring,"Original navigation overlap must retain the actual capability monitor")
            XCTAssertNil(state.result,"The old refresh must not republish while the explicit original read is held")
            await fixture.release(2);await opening?.value
            XCTAssertEqual(state.result?.operation_id,original)
            await fixture.deny()
            let concealed=try await observed{state.result==nil && state.access==nil}
            XCTAssertTrue(concealed,"Real denial after overlap must conceal and invalidate outstanding publication")
            let effects=await fixture.effects();XCTAssertEqual(effects.0,1);XCTAssertTrue(effects.1.allSatisfy{$0==original})
            let raw=try XCTUnwrap(state.records.load(state.key(active,concept,fixture.source)))
            let journal=try JSONDecoder().decode(ConceptAdoptionState.Journal.self,from:raw)
            XCTAssertEqual(journal.command.operation_id,original)
            await fixture.releaseAll();state.conceal();try? FileManager.default.removeItem(at:root)
        } catch {await fixture.releaseAll();await opening?.value;state.conceal();try? FileManager.default.removeItem(at:root);throw error}
    }
    @MainActor func testActualMonitorSurvivesSupersededRefreshAndThenConcealsDenial() async throws {try await overlapThenDeny(unavailable:false)}
    @MainActor func testActualMonitorSurvivesRecoverableRefreshFailureAndThenConcealsDenial() async throws {try await overlapThenDeny(unavailable:true)}
    @MainActor func testActualMonitorDenialFencesOutstandingOriginalOpen() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let concept=ConceptBaselineTests().concept(),active=connection
        let fixture=AdoptionMonitorFixture(concept),state=ConceptAdoptionState(transport:fixture,root:root)
        await state.load(concept,current:{active});await state.select(fixture.source,concept:concept,current:{active})
        await state.prepare(concept,paths:["docs/product/VISION.md"],vision:nil,current:{active})
        let original=try XCTUnwrap(state.pending?.command.operation_id)
        let opening=Task{await state.open(original,concept:concept,current:{active})}
        let held=try await observed{await fixture.heldCount()==1};XCTAssertTrue(held)
        await fixture.deny()
        let concealed=try await observed{state.result==nil && state.access==nil};XCTAssertTrue(concealed)
        await fixture.releaseAll();await opening.value
        XCTAssertNil(state.result);XCTAssertNil(state.access);XCTAssertEqual(state.phase,"access")
        let effects=await fixture.effects();XCTAssertEqual(effects.0,1);XCTAssertTrue(effects.1.allSatisfy{$0==original})
        state.conceal();try? FileManager.default.removeItem(at:root)
    }
}
