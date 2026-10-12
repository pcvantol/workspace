import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

private final class ConceptFixture: ConceptServing, @unchecked Sendable {
    var items:[ProjectConcept] = []
    var commands:[ConceptCommand] = []
    var fail:ConceptError?
    var loseReply = false
    var hold:CheckedContinuation<[ProjectConceptSummary],Error>?
    var held = false
    let context = "own-context"
    func list(_ connection:ConceptConnection) async throws -> [ProjectConceptSummary] {
        if let fail {throw fail};if held {return try await withCheckedThrowingContinuation {hold=$0}};return items.map(\.summary)
    }
    func get(_ connection:ConceptConnection,id:String) async throws -> ProjectConcept {
        if let fail {throw fail};guard let item=items.first(where:{$0.id==id}) else {throw ConceptError.notFound};return item
    }
    func save(_ connection:ConceptConnection,id:String?,command:ConceptCommand) async throws -> ProjectConcept {
        commands.append(command);if let fail {throw fail}
        if commands.count>1,commands.dropLast().contains(command),let item=items.first {return item}
        if let id,items.first(where:{$0.id==id})?.revision != command.expected_revision {throw ConceptError.conflict}
        let item=ProjectConcept(id:id ?? String(repeating:"a",count:32),actor_id:"alice",context_id:context,title:command.title,notes:command.notes,revision:command.expected_revision+1,created_at:"2026-10-12T00:00:00Z",updated_at:"2026-10-12T01:00:00Z",state:"CONCEPT_NOT_CONFIGURED")
        items.removeAll {$0.id==item.id};items.append(item)
        if loseReply {throw ConceptError.unavailable};return item
    }
}
final class ProjectConceptTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"own-context",token:String(repeating:"c",count:43)),bearer:"synthetic-own-bearer")
    func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @MainActor func testRealStateCreateEditAndDurableLostReplyRecovery() async throws {
        let root=temporary();defer {try? FileManager.default.removeItem(at:root)}
        let fixture=ConceptFixture();let state=ProjectConceptState(transport:fixture,root:root);let binding=connection
        await state.refresh(current:{binding});XCTAssertEqual(state.phase,"empty")
        state.new(defaultTitle:"Een idee");state.notes="日本語\nFrançais 🌱"
        fixture.loseReply=true;await state.save(current:{binding})
        XCTAssertEqual(state.phase,"offline");XCTAssertNotNil(state.pending)
        let original=fixture.commands[0]
        let restart=ProjectConceptState(transport:fixture,root:root)
        await restart.refresh(current:{binding});XCTAssertEqual(restart.phase,"retry");XCTAssertEqual(restart.notes,state.notes)
        fixture.loseReply=false;await restart.save(current:{binding})
        XCTAssertEqual(restart.phase,"saved");XCTAssertEqual(fixture.commands,[original,original]);XCTAssertEqual(fixture.items.count,1)
        let id=try XCTUnwrap(restart.selected?.id)
        restart.notes="Verder uitwerken";await restart.save(current:{binding})
        XCTAssertEqual(restart.selected?.id,id);XCTAssertEqual(restart.selected?.revision,2)
        XCTAssertEqual(fixture.commands.last?.expected_revision,1)
        restart.cancelReads();await restart.open(id,current:{binding});XCTAssertEqual(restart.notes,"Verder uitwerken")
        restart.invalidate();XCTAssertTrue(restart.items.isEmpty);XCTAssertEqual(restart.notes,"")
    }
    @MainActor func testConflictDirtySwitchDenialAndLateReads() async throws {
        let root=temporary();defer {try? FileManager.default.removeItem(at:root)}
        let fixture=ConceptFixture(),binding=connection;let state=ProjectConceptState(transport:fixture,root:root)
        await state.refresh(current:{binding});state.new(defaultTitle:"Idea");await state.save(current:{binding})
        let id=try XCTUnwrap(state.selected?.id)
        state.notes="Unsaved";state.new(defaultTitle:"Must not replace");XCTAssertEqual(state.notes,"Unsaved")
        await state.open(id,current:{binding});XCTAssertEqual(state.phase,"unsaved")
        fixture.fail = .conflict;await state.save(current:{binding});XCTAssertEqual(state.phase,"conflict");XCTAssertEqual(state.notes,"Unsaved");XCTAssertNil(state.pending)
        fixture.fail=nil;await state.open(id,discard:true,current:{binding});XCTAssertEqual(state.notes,"")
        fixture.fail = .denied;await state.refresh(current:{binding});XCTAssertEqual(state.phase,"denied");XCTAssertTrue(state.items.isEmpty)
        fixture.fail=nil;fixture.held=true
        let task=Task {await state.refresh(current:{binding})}
        for _ in 0..<100 where fixture.hold==nil {await Task.yield()}
        state.invalidate();fixture.hold?.resume(returning:fixture.items.map(\.summary));await task.value
        XCTAssertNil(state.selected);XCTAssertTrue(state.items.isEmpty);XCTAssertFalse(state.busy)
    }
    @MainActor func testImmediateDirtyStatusTransientDisconnectRetentionAndKnownDenial() async throws {
        let root=temporary();defer {try? FileManager.default.removeItem(at:root)}
        let fixture=ConceptFixture(),binding=connection;let state=ProjectConceptState(transport:fixture,root:root)
        await state.refresh(current:{binding});state.new(defaultTitle:"Initial");state.notes="Never saved"
        state.clientPhaseChanged("CONNECTING")
        XCTAssertEqual(state.notes,"Never saved");XCTAssertEqual(state.displayPhase,"offline");XCTAssertTrue(state.items.isEmpty)
        await state.refresh(current:{binding});XCTAssertEqual(state.displayPhase,"unsaved");XCTAssertEqual(state.notes,"Never saved")
        await state.save(current:{binding});XCTAssertEqual(state.displayPhase,"saved")
        state.title="Changed title";XCTAssertEqual(state.displayPhase,"unsaved")
        state.title=state.selected!.title;XCTAssertEqual(state.displayPhase,"saved")
        state.notes="Unsent edit";XCTAssertEqual(state.displayPhase,"unsaved")
        state.clientPhaseChanged("UNAVAILABLE");XCTAssertEqual(state.notes,"Unsent edit")
        await state.refresh(current:{binding});XCTAssertEqual(state.displayPhase,"unsaved");XCTAssertEqual(state.notes,"Unsent edit")
        state.clientPhaseChanged("UNAUTHORIZED");XCTAssertEqual(state.notes,"");XCTAssertNil(state.selected);XCTAssertEqual(state.phase,"denied")
        state.clientPhaseChanged("CONNECTED");XCTAssertEqual(state.phase,"denied")
    }
    @MainActor func testBoundedInputCurrentPairingAndPrivateStorageFailures() async throws {
        let root=temporary();defer {try? FileManager.default.removeItem(at:root)}
        let fixture=ConceptFixture(),binding=connection;let state=ProjectConceptState(transport:fixture,root:root)
        await state.save(current:{binding});XCTAssertEqual(fixture.commands.count,0)
        await state.refresh(current:{binding})
        for (title,notes) in [("", ""),(String(repeating:"x",count:121),""),("Good",String(repeating:"x",count:10001)),("Good","\u{0000}")] {
            state.title=title;state.notes=notes;await state.save(current:{binding});XCTAssertEqual(state.phase,"invalid");XCTAssertNil(state.pending)
        }
        state.title="Good";state.notes="No loss"
        await state.save(current:{throw ConceptError.denied});XCTAssertEqual(state.phase,"denied");XCTAssertEqual(fixture.commands.count,0)
        await state.refresh(current:{binding});let changed=ConceptConnection(access:binding.access,bearer:"changed")
        await state.refresh(current:{changed});XCTAssertEqual(state.phase,"connect")
        let file=temporary();try Data("block".utf8).write(to:file);defer{try? FileManager.default.removeItem(at:file)}
        let bad=ProjectConceptState(transport:fixture,root:file)
        await bad.refresh(current:{binding});XCTAssertEqual(bad.phase,"offline")
        XCTAssertFalse(ProjectConcept.validText("\u{0001}"));XCTAssertTrue(ProjectConcept.validText("🌱\n\t"))
    }
    @MainActor func testFiveLocalesSourceViewAndRecordValidation() async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)}
        let fixture=ConceptFixture(),binding=connection;let state=ProjectConceptState(transport:fixture,root:root)
        let client=ClientState(keychain:ConceptMemoryServer());let grants=ConceptMemoryGrant()
        for language in ["en","nl","de","fr","es"] {
            for key in ProjectConceptCopy.values.keys {XCTAssertNotEqual(ProjectConceptCopy.text(key,language:language),key)}
            let view=NSHostingView(rootView:ProjectConceptView(state:state,client:client,grants:grants).environment(\.locale,Locale(identifier:language)))
            view.frame=NSRect(x:0,y:0,width:560,height:780);view.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(ProjectConceptCopy.text("unknown",language:"nl"),"unknown")
        XCTAssertEqual(ProjectConceptCopy.text("nav",language:"zz"),"Project concepts")
        await state.refresh(current:{binding});state.new(defaultTitle:"Idea");await state.save(current:{binding})
        let item=try XCTUnwrap(state.selected);try item.validate("own-context")
        XCTAssertThrowsError(try item.validate("wrong"))
        let view=NSHostingView(rootView:ProjectConceptView(state:state,client:client,grants:grants));view.frame=NSRect(x:0,y:0,width:560,height:780);view.layoutSubtreeIfNeeded()
        state.notes="conflict";fixture.fail = .conflict;await state.save(current:{binding});view.layoutSubtreeIfNeeded()
        XCTAssertEqual(state.phase,"conflict")
    }
}
private struct ConceptMemoryGrant:DraftGrantStore {
    func load() throws -> DraftAccess? {nil}
    func save(_ access:DraftAccess) throws {}
    func forget() throws {}
}
private final class ConceptHTTPProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var code=200
    nonisolated(unsafe) static var value:[String:Any]=[:]
    nonisolated(unsafe) static var last:URLRequest?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){Self.last=request;let r=HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!;client?.urlProtocol(self,didReceive:r,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:Self.value));client?.urlProtocolDidFinishLoading(self)}
    override func stopLoading(){}
}
extension ProjectConceptTests {
    func testHTTPProjectionHeaderRevisionErrorsAndInvalidIdentities() async throws {
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[ConceptHTTPProtocol.self]
        let transport=ProjectConceptTransport(configuration:configuration)
        let item:[String:Any]=["id":String(repeating:"a",count:32),"actor_id":"alice","context_id":"own-context","title":"Idea","notes":"🌱","revision":1,"created_at":"2026-10-12T00:00:00Z","updated_at":"2026-10-12T00:00:00Z","state":"CONCEPT_NOT_CONFIGURED"]
        var summary=item;summary.removeValue(forKey:"notes")
        ConceptHTTPProtocol.code=200;ConceptHTTPProtocol.value=["actor_id":"alice","context_id":"own-context","concepts":[summary]]
        let rows=try await transport.list(connection);XCTAssertEqual(rows.count,1)
        XCTAssertEqual(ConceptHTTPProtocol.last?.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),connection.access.token)
        ConceptHTTPProtocol.value=item
        let record=try await transport.get(connection,id:String(repeating:"a",count:32));XCTAssertEqual(record.title,"Idea")
        let command=ConceptCommand(title:"Idea",notes:"🌱",operation_id:String(repeating:"b",count:32),expected_revision:0)
        ConceptHTTPProtocol.code=201;_=try await transport.save(connection,id:nil,command:command)
        ConceptHTTPProtocol.code=200;_=try await transport.save(connection,id:record.id,command:command)
        XCTAssertEqual(ConceptHTTPProtocol.last?.httpMethod,"PATCH")
        for code in [400,401,403,404,409,503] {
            ConceptHTTPProtocol.code=code
            do{_=try await transport.list(connection);XCTFail("Error accepted")}catch{}
        }
        for id in ["bad/path","unknown"] {
            do{_=try await transport.get(connection,id:id);XCTFail("Invalid ID accepted")}catch{}
            do{_=try await transport.save(connection,id:id,command:command);XCTFail("Invalid ID accepted")}catch{}
        }
        ConceptHTTPProtocol.code=200;ConceptHTTPProtocol.value=["context_id":"wrong","actor_id":"alice","concepts":[]]
        do{_=try await transport.list(connection);XCTFail("Wrong context accepted")}catch{}
        ConceptHTTPProtocol.value=["invalid":true]
        do{_=try await transport.list(connection);XCTFail("Malformed accepted")}catch{}
    }
}

private struct ConceptMemoryServer:CredentialStore {
    func binding() throws -> ServerBinding? {nil}
    func token() throws -> String? {nil}
    func save(binding:ServerBinding,token:String) throws {}
    func forget() throws {}
}
