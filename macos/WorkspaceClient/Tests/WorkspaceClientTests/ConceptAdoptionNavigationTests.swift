import XCTest
@testable import WorkspaceClient

// Source-only lifecycle scheduling; native Space/focus acceptance remains a real GUI gate.
@MainActor private final class AdoptionNavigationGate {
    let connection:ConceptConnection
    var waiting:CheckedContinuation<ConceptConnection,Error>?
    var calls=0
    init(_ connection:ConceptConnection) {self.connection=connection}
    func current() async throws->ConceptConnection {
        calls+=1
        if calls==1 {return try await withCheckedThrowingContinuation {waiting=$0}}
        return connection
    }
    func release(denied:Bool=false) {
        let held=waiting;waiting=nil
        if denied {held?.resume(throwing:ConceptError.denied)} else {held?.resume(returning:connection)}
    }
}
final class ConceptAdoptionNavigationTests:XCTestCase {
    let path="docs/product/VISION.md"
    @MainActor private func seeded(_ root:URL) async throws->(ConceptAdoptionState,AdoptionFixture,ProjectConcept,ConceptConnection) {
        let c=ConceptAdoptionContractTests(),concept=c.concept,active=c.connection
        let fixture=AdoptionFixture(concept),state=ConceptAdoptionState(transport:fixture,root:root)
        state.source=fixture.source;state.access=try await fixture.access(active,concept:concept.id,source:fixture.source);state.result=try c.scoped()
        return(state,fixture,concept,active)
    }
    @MainActor private func held(_ gate:AdoptionNavigationGate) async {
        for _ in 0..<1000 {if gate.waiting != nil {return};await Task.yield()}
        XCTFail("The actual current-connection boundary must be held")
    }
    @MainActor func testSerializedActionWaitsForAuthorizationThenFocusesActualDetailAndOpener() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept,active)=try await seeded(root);defer{state.conceal()}
        let navigation=ConceptAdoptionDocumentNavigation(),gate=AdoptionNavigationGate(active),operation=try XCTUnwrap(state.result?.operation_id)
        var focused:[String?]=[],revealed:[String]=[]
        let task=Task {await navigation.navigate(path,operation:operation,state:state,concept:concept,current:{try await gate.current()},focus:{focused.append($0)},reveal:{revealed.append($0)})}
        await held(gate);XCTAssertTrue(navigation.busy);XCTAssertTrue(focused.isEmpty);XCTAssertTrue(revealed.isEmpty)
        await navigation.navigate(path,operation:operation,state:state,concept:concept,current:{XCTFail("Duplicate action must be serialized");return active},focus:{_ in XCTFail()},reveal:{_ in XCTFail()})
        XCTAssertEqual(gate.calls,1);gate.release();await task.value
        XCTAssertEqual(state.expandedDocument,path);XCTAssertEqual(focused,[nil,"adoption-detail-"+path]);XCTAssertEqual(revealed,["adoption-detail-"+path]);XCTAssertFalse(navigation.busy)
        await navigation.navigate(path,operation:operation,state:state,concept:concept,current:{active},focus:{focused.append($0)},reveal:{revealed.append($0)})
        XCTAssertEqual(state.expandedDocument,"");XCTAssertEqual(focused.suffix(2),[nil,"adoption-document-"+path]);XCTAssertEqual(revealed.last,"adoption-document-"+path)
        XCTAssertEqual(try state.nav(active,concept)?.operation,operation);XCTAssertEqual(try state.nav(active,concept)?.document,"");XCTAssertTrue(fixture.posts.isEmpty)
    }
    @MainActor func testOldCompletionCannotClearNewBusyOrFocusAfterConcealAndReselection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept,active)=try await seeded(root);defer{state.conceal()}
        let navigation=ConceptAdoptionDocumentNavigation(),oldGate=AdoptionNavigationGate(active),newGate=AdoptionNavigationGate(active),packet=try XCTUnwrap(state.result)
        var focused:[String?]=[]
        let old=Task {await navigation.navigate(path,operation:packet.operation_id,state:state,concept:concept,current:{try await oldGate.current()},focus:{focused.append($0)},reveal:{_ in XCTFail("Stale reveal")})}
        await held(oldGate);state.conceal();navigation.invalidate()
        state.source=fixture.source;state.access=try await fixture.access(active,concept:concept.id,source:fixture.source);state.result=packet
        let next=Task {await navigation.navigate(path,operation:packet.operation_id,state:state,concept:concept,current:{try await newGate.current()},focus:{focused.append($0)},reveal:{_ in})}
        await held(newGate);oldGate.release();await old.value
        XCTAssertTrue(navigation.busy);XCTAssertTrue(focused.isEmpty);XCTAssertEqual(state.expandedDocument,"")
        newGate.release();await next.value
        XCTAssertFalse(navigation.busy);XCTAssertEqual(focused,[nil,"adoption-detail-"+path]);XCTAssertTrue(fixture.posts.isEmpty)
    }
    @MainActor func testDeniedNavigationNeverFocusesOrRevealsConcealedData() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,_,concept,active)=try await seeded(root);defer{state.conceal()}
        let navigation=ConceptAdoptionDocumentNavigation(),gate=AdoptionNavigationGate(active),operation=try XCTUnwrap(state.result?.operation_id)
        let task=Task {await navigation.navigate(path,operation:operation,state:state,concept:concept,current:{try await gate.current()},focus:{_ in XCTFail("Denied focus")},reveal:{_ in XCTFail("Denied reveal")})}
        await held(gate);gate.release(denied:true);await task.value
        XCTAssertNil(state.result);XCTAssertNil(state.access);XCTAssertFalse(navigation.busy)
        await navigation.navigate(path,operation:operation,state:state,concept:concept,current:{active},focus:{_ in XCTFail()},reveal:{_ in XCTFail()})
    }
    @MainActor func testSameGenerationReplacementOriginalCannotReceiveOldNavigation() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let(state,fixture,concept,active)=try await seeded(root);defer{state.conceal()}
        let navigation=ConceptAdoptionDocumentNavigation(),gate=AdoptionNavigationGate(active),original=try XCTUnwrap(state.result?.operation_id)
        let task=Task {await navigation.navigate(path,operation:original,state:state,concept:concept,current:{try await gate.current()},focus:{_ in XCTFail("Old original focus")},reveal:{_ in XCTFail("Old original reveal")})}
        await held(gate);state.result=fixture.packet(String(repeating:"f",count:32));gate.release();await task.value
        XCTAssertEqual(state.expandedDocument,"");XCTAssertNil(try state.nav(active,concept));XCTAssertEqual(state.result?.operation_id,String(repeating:"f",count:32));XCTAssertFalse(navigation.busy);XCTAssertTrue(fixture.posts.isEmpty)
    }
}
