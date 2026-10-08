import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WorkspaceClient

extension AdvisoryTests {
    func inspectorFixtures() throws -> (AdvisoryTurnRecord,AdvisoryCapability) {
        var r=try fixture("record"),cap=try fixture("capability")
        let source:[String:Any]=["source_id":"selected-doc","version":"sha256:"+String(repeating:"b",count:64)]
        let reference="advisory-source:selected-doc:sha256:"+String(repeating:"b",count:64)
        var context=r["context"] as! [String:Any];context["selected_sources"]=[source];context["included_sources"]=["PROJECT_BINDING","selected-doc"];context["evidence_references"]=["project:one",reference]
        var request=r["request"] as! [String:Any];request["selected_sources"]=[source];request["context_revision"]=try AdvisoryWire.digest(context)
        r["context"]=context;r["request"]=request;r["request_digest"]=try AdvisoryWire.digest(request)
        var outcome=r["outcome"] as! [String:Any],output=outcome["output"] as! [String:Any]
        output["request_digest"]=r["request_digest"];output["evidence_references"]=["project:one",reference]
        output["alternatives"]=["First alternative.","First alternative.","Second alternative."];output["questions"]=["A separate question?"];output["suggestions"]=["A separate recommendation."]
        outcome["output"]=output;outcome["result_digest"]=try AdvisoryWire.digest(output);r["outcome"]=outcome
        cap["available_sources"]=[["source_id":"selected-doc","version":source["version"]!,"state":"ACTIVE","repository":"owner/repository","revision":String(repeating:"a",count:40),"path":"docs/advice.md","content_digest":"sha256:"+String(repeating:"c",count:64)]]
        inspectorFixtureOverride=["record":r,"capability":cap]
        return (try AdvisoryWire.turn(r,access:access,conversation:connection.conversationID),try AdvisoryWire.capability(JSONSerialization.data(withJSONObject:cap),access:access))
    }
    func changedCap(_ cap:AdvisoryCapability,_ mutate:(inout [String:Any])->Void) throws -> AdvisoryCapability {
        var raw=try AdvisoryWire.object(JSONEncoder().encode(cap));mutate(&raw);return try AdvisoryWire.decode(raw,as:AdvisoryCapability.self)
    }
    func testInspectorExactVersionJoinsAndCategoryOrder() throws {
        let (turn,cap)=try inspectorFixtures(),reference=turn.context.evidence_references[1]
        XCTAssertEqual(AdvisoryAnswerCategory.summary.items(turn),[turn.outcome!.output!.summary])
        XCTAssertEqual(AdvisoryAnswerCategory.alternatives.items(turn),["First alternative.","First alternative.","Second alternative."])
        XCTAssertEqual(AdvisoryAnswerCategory.questions.items(turn),["A separate question?"])
        XCTAssertEqual(AdvisoryAnswerCategory.suggestions.items(turn),["A separate recommendation."])
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:cap),.metadata(cap.available_sources[0]))
        XCTAssertEqual(AdvisoryInspector.source("project:one",turn:turn,capability:cap),.unavailable("sourceUnlinked"))
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:nil),.unavailable("sourceUnavailable"))
        let foreign=try changedCap(cap){$0["instance_id"]="foreign"}
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:foreign),.unavailable("sourceUnavailable"))
        let absent=try changedCap(cap){$0["available_sources"]=[]}
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:absent),.unavailable("sourceVersionMissing"))
        let changed=try changedCap(cap){raw in var m=(raw["available_sources"] as! [[String:Any]])[0];m["version"]="sha256:"+String(repeating:"d",count:64);raw["available_sources"]=[m]}
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:changed),.unavailable("sourceVersionMissing"))
        let duplicate=try changedCap(cap){raw in let m=(raw["available_sources"] as! [[String:Any]])[0];raw["available_sources"]=[m,m]}
        XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:duplicate),.unavailable("sourceAmbiguous"))
        for (key,value) in [("path","/private/owner/secret"),("path","../secret"),("path","~/.private"),("path","file:secret"),("path","docs\\secret"),("repository","https://private"),("state","REVOKED"),("revision","wrong"),("content_digest","wrong")] {
            let unsafe=try changedCap(cap){raw in var m=(raw["available_sources"] as! [[String:Any]])[0];m[key]=value;raw["available_sources"]=[m]}
            XCTAssertEqual(AdvisoryInspector.source(reference,turn:turn,capability:unsafe),.unavailable("sourceUnverifiable"))
        }
    }
    @MainActor func testInspectorReadOnlySelectionCursorAndFailClosedPresentation() async throws {
        let (frozen,_)=try inspectorFixtures();records=[inspectorFixtureOverride!["record"]!]
        for n in 1...4 {
            var r=records[0],request=r["request"] as! [String:Any];request["turn_id"]="turn-\(n)";request["expected_revision"]=0
            r["request"]=request;r["request_digest"]=try AdvisoryWire.digest(request)
            var o=r["outcome"] as! [String:Any],output=o["output"] as! [String:Any];output["request_digest"]=r["request_digest"];o["output"]=output;o["result_digest"]=try AdvisoryWire.digest(output);r["outcome"]=o;records.append(r)
        }
        let memory=AdviceMemory();memory.access=access;let state=AdvisoryState(credentials:memory,transport:transport())
        state.inspect("absent");XCTAssertNil(state.inspectedTurn)
        await state.refresh(connection);state.inspect("turn-one");XCTAssertEqual(state.inspectedTurn,frozen)
        state.inspectCategory(.questions);XCTAssertEqual(state.inspectorCategory,.questions)
        state.inspectReference("invalid");XCTAssertNil(state.inspectedReference)
        state.inspectReference(frozen.context.evidence_references[1]);XCTAssertNotNil(state.inspectedReference)
        state.inspectorBack();XCTAssertNil(state.inspectedReference);XCTAssertNotNil(state.inspectedTurn)
        await state.more(connection);state.inspect("turn-4");let selected=state.inspectedTurn
        await state.refresh(connection);XCTAssertEqual(state.inspectedTurn,selected);XCTAssertEqual(state.history.count,5)
        state.suspend(transient:true);XCTAssertTrue(state.inspectorOpen);XCTAssertNil(state.inspectedTurn);XCTAssertNil(state.capability)
        await state.refresh(connection);XCTAssertEqual(state.inspectedTurn,selected);XCTAssertEqual(state.history.count,5)
        XCTAssertEqual(Set(state.history.map{$0.request.turn_id}).count,5)
        XCTAssertFalse(calls.contains{$0.httpMethod=="POST"})
        code=403;await state.refresh(connection);XCTAssertNil(state.inspectedTurnID);XCTAssertNil(state.inspectedReference);XCTAssertTrue(state.history.isEmpty)
        state.inspectCategory(.summary);state.inspectReference("invalid");state.inspectorBack();XCTAssertNil(state.inspectedTurn)
    }
    @MainActor func testInspectorFiveLanguageThemesEmptyAndSourceStatesRender() async throws {
        let (_,cap)=try inspectorFixtures();records=[inspectorFixtureOverride!["record"]!]
        let memory=AdviceMemory();memory.access=access;let state=AdvisoryState(credentials:memory,transport:transport());await state.refresh(connection);state.inspect("turn-one")
        NSApplication.shared.setActivationPolicy(.prohibited)
        func render(_ language:String,_ theme:ColorScheme) {
            let host=NSHostingView(rootView:AdvisoryInspectorView(state:state).environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,theme))
            host.frame=NSRect(x:0,y:0,width:640,height:620);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0)
        }
        for language in ["en","nl","de","fr","es"] {
            for key in ["title","summary","alternatives","questions","suggestions","frozen","selected","included","missing","limitations","sourceVersionMissing","sourceAmbiguous","sourceUnlinked","sourceUnverifiable","unknown","requestedModel","observedModel"] { XCTAssertNotEqual(AdvisoryInspectorCopy.text(key,language:language),key) }
            for theme in [ColorScheme.light,.dark] {
                for category in AdvisoryAnswerCategory.allCases { state.inspectCategory(category);render(language,theme) }
                state.inspectReference(state.inspectedTurn!.context.evidence_references[1]);render(language,theme)
                state.inspectorBack();state.inspectReference("project:one");render(language,theme);state.inspectorBack()
            }
        }
        var raw=inspectorFixtureOverride!["record"]!;var o=raw["outcome"] as! [String:Any];var output=o["output"] as! [String:Any];output["alternatives"]=[];output["questions"]=[];output["suggestions"]=[];o["output"]=output;o["result_digest"]=try AdvisoryWire.digest(output);raw["outcome"]=o;records=[raw]
        await state.refresh(connection);state.inspectCategory(.alternatives);render("en",.light)
        var current=try AdvisoryWire.object(JSONEncoder().encode(cap));current["available_sources"]=[];inspectorFixtureOverride!["capability"]=current
        await state.refresh(connection);state.inspectReference(state.inspectedTurn!.context.evidence_references[1]);render("en",.dark)
        code=503;await state.refresh(connection);render("en",.light);XCTAssertNil(state.inspectedTurnID)
    }
}

private struct InspectorNoDraftGrant:DraftGrantStore {
    func load() throws -> DraftAccess? { nil }
    func save(_ access:DraftAccess) throws { throw AdvisoryError.denied }
    func forget() throws {}
}
private final class InspectorReadBarrier:@unchecked Sendable {
    let entered=DispatchSemaphore(value:0)
    let release=DispatchSemaphore(value:0)
    func arrived() -> Bool { entered.wait(timeout:.now()) == .success }
}
extension AdvisoryTests {
    @MainActor func testInspectorLateReadScopeChangePreservesOnlyDraftAndPendingIntent() async throws {
        let (turn,_)=try inspectorFixtures();records=[inspectorFixtureOverride!["record"]!]
        let memory=AdviceMemory();memory.access=access;let state=AdvisoryState(credentials:memory,transport:transport())
        await state.refresh(connection);state.inspect(turn.request.turn_id);state.inspectReference(turn.context.evidence_references[1])
        let local=FileManager.default.temporaryDirectory.appendingPathComponent("inspector-draft-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:local) }
        let draft=ConversationState(grants:InspectorNoDraftGrant(),localDrafts:PrivateLocalDraftCache(root:local),advisory:state);draft.draft="Synthetic unsent local edit."
        var raw=try AdvisoryWire.object(JSONEncoder().encode(turn.request));raw["turn_id"]="unresolved-synthetic-intent"
        let request=try AdvisoryWire.decode(raw,as:AdvisoryRequest.self)
        memory.intent=AdvisoryIntent(fingerprint:access.fingerprint,endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,workspaceProjectID:access.workspaceProjectID,actorID:access.actorID,request:request,cancel:nil)
        let intent=memory.intent,barrier=InspectorReadBarrier(),original=StubProtocol.handler!
        StubProtocol.handler={ request in
            if request.url!.path.hasSuffix("/capability") { barrier.entered.signal();_ = barrier.release.wait(timeout:.now()+4) }
            return try original(request)
        }
        // No pending HTTP read here: first delay the capability before changing scope.
        memory.intent=nil
        let originalConnection=connection
        let old=Task { await state.refresh(originalConnection) }
        var reached=false
        for _ in 0..<100 {
            if barrier.arrived() { reached=true;break }
            try await Task.sleep(for:.milliseconds(5))
        }
        XCTAssertTrue(reached);memory.intent=intent
        state.invalidate()
        let other=AdvisoryConnection(endpoint:connection.endpoint,workspaceInstanceID:connection.workspaceInstanceID,actorID:"bob",workspaceProjectID:"other-project",conversationID:String(repeating:"b",count:32),bearer:connection.bearer,draftGrant:connection.draftGrant)
        await state.refresh(other);barrier.release.signal();await old.value
        XCTAssertNil(state.inspectedTurn);XCTAssertNil(state.inspectedTurnID);XCTAssertNil(state.inspectedReference)
        XCTAssertNil(state.capability);XCTAssertTrue(state.history.isEmpty)
        XCTAssertEqual(memory.intent,intent);XCTAssertEqual(draft.draft,"Synthetic unsent local edit.")
        XCTAssertFalse(calls.contains{$0.httpMethod=="POST"})
        state.suspend();XCTAssertNil(state.inspectedTurnID);XCTAssertEqual(memory.intent,intent)
    }
}
