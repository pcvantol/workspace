import XCTest
import SwiftUI
@testable import WorkspaceClient

// Source-only typed/HTTP fixtures, never installed Forge or live advice proof.
private final class ChatFixture:ConceptChatServing,@unchecked Sendable {
    var seed:[String:Any]
    var values:[String:[String:Any]]=[:]
    var captured:[String:ConceptChatCommand]=[:]
    var posts=0
    var adoptions=0
    var lose=false
    var sendFailure:Error?
    var fail:ConceptError?
    var readonly=false
    var pendingStatus:String?
    init() throws {seed=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("concept-chat-wire-fixture.json"))) as! [String:Any]}
    func decode<T:Decodable>(_ type:T.Type,_ value:Any) throws -> T {try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:value))}
    var concept:ProjectConcept {try! decode(ProjectConcept.self,seed["concept"]!)}
    func access(_ c:ConceptConnection,concept:String) async throws -> ConceptChatCapability {
        if let fail {throw fail};var cap=seed["access"] as! [String:Any];cap["can_advise"] = !readonly
        return try decode(ConceptChatCapability.self,cap)
    }
    func briefing(_ c:ConceptConnection,concept:String) async throws -> ConceptChatBriefing {if let fail {throw fail};return try decode(ConceptChatBriefing.self,seed["briefing"]!)}
    func history(_ c:ConceptConnection,concept:String) async throws -> ConceptChatHistory {
        if let fail {throw fail}
        var body=seed["history"] as! [String:Any]
        body["history"]=["turns":values.values.map{$0["turn"]!},"revision":values.count,"read_only":true]
        body["local_operations"]=try captured.keys.sorted().map {id -> [String:Any] in
            let command=captured[id]!,raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(command))
            return ["operation_id":id,"command":raw,"state":(values[id]?["turn"] as? [String:Any])?["status"] as? String ?? "PRODUCER_NOT_OBSERVED"]
        }
        return try decode(ConceptChatHistory.self,body)
    }
    func result(_ command:ConceptChatCommand) throws -> ConceptChatReply {
        var body=seed["result"] as! [String:Any],turn=body["turn"] as! [String:Any],r=turn["request"] as! [String:Any]
        r["operation_id"]=command.operation_id;r["turn_id"]=command.turn_id;r["message"]=command.message;r["language"]=command.language;r["advisor_kind"]=command.role=="ARCHITECT" ? "ARCHITECTURE":"BUSINESS"
        turn["request"]=r
        if let pendingStatus {turn["status"]=pendingStatus;turn["outcome"]=NSNull();body["proposal"]=NSNull()}
        else {var proposal=body["proposal"] as! [String:Any];proposal["result_reference"]=command.operation_id;body["proposal"]=proposal}
        body["operation_id"]=command.operation_id;body["turn"]=turn;values[command.operation_id]=body
        return try decode(ConceptChatReply.self,body)
    }
    func send(_ c:ConceptConnection,concept:String,command:ConceptChatCommand) async throws -> ConceptChatReply {
        if let sendFailure {throw sendFailure}
        if let fail {throw fail};captured[command.operation_id]=command
        if let old=values[command.operation_id] {return try decode(ConceptChatReply.self,old)}
        posts+=1;let value=try result(command)
        if lose {throw ConceptError.unavailable};return value
    }
    func read(_ c:ConceptConnection,concept:String,operation:String) async throws -> ConceptChatReply {
        if let fail {throw fail};guard let value=values[operation] else{if captured[operation]==nil {throw ConceptChatError.ownOriginalNotCaptured};throw ConceptError.notFound}
        return try decode(ConceptChatReply.self,value)
    }
    func adopt(_ c:ConceptConnection,concept:String,command:ConceptChatAdopt) async throws -> ConceptChatBriefing {
        if let fail {throw fail};adoptions+=1;return try decode(ConceptChatBriefing.self,seed["adopted"]!)
    }
}
final class ConceptChatRuntimeTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"own-context",token:String(repeating:"c",count:43)),bearer:String(repeating:"d",count:43))
    func root()->URL {FileManager.default.temporaryDirectory.appendingPathComponent("chat-test-"+UUID().uuidString)}
    @MainActor func testReadOnlyLoadLostReplyAndClientStateReopenKeepOneOriginal() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path)
        await state.load(fixture.concept,current:{c});XCTAssertNotNil(state.access);XCTAssertEqual(fixture.posts,0)
        fixture.lose=true
        await state.send(role:"BUSINESS",message:"A real user choice",language:"nl",concept:fixture.concept,current:{c})
        XCTAssertNotNil(state.pending);XCTAssertEqual(fixture.posts,1);let original=try XCTUnwrap(state.pending?.command)
        state.conceal();let restarted=ConceptChatState(transport:fixture,root:path)
        await restarted.load(fixture.concept,current:{c});XCTAssertEqual(restarted.pending?.command,original)
        await restarted.resume(fixture.concept,current:{c});XCTAssertNil(restarted.pending);XCTAssertEqual(restarted.reply?.operation_id,original.operation_id);XCTAssertEqual(fixture.posts,1)
        await restarted.open(original.operation_id,concept:fixture.concept,current:{c});XCTAssertNotNil(restarted.reply?.proposal)
        await restarted.adopt(fixture.concept,current:{c});XCTAssertEqual(restarted.phase,"adopted");XCTAssertEqual(fixture.adoptions,1);XCTAssertEqual(fixture.posts,1)
        restarted.conceal()
    }
    @MainActor func testOlderCompleteJournalCannotMaskServerOnlyOriginal() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path)
        await state.load(fixture.concept,current:{c})
        await state.send(role:"ARCHITECT",message:"First message",language:"de",concept:fixture.concept,current:{c})
        XCTAssertNil(state.pending)
        let another=ConceptChatCommand(operation_id:String(repeating:"e",count:32),turn_id:String(repeating:"f",count:32),expected_concept_revision:1,role:"BUSINESS",language:"nl",message:"Another original, captured but not observed")
        fixture.captured[another.operation_id]=another;state.conceal()
        let reopened=ConceptChatState(transport:fixture,root:path);await reopened.load(fixture.concept,current:{c})
        XCTAssertEqual(reopened.pending?.command,another)
        await reopened.resume(fixture.concept,current:{c});XCTAssertEqual(fixture.posts,2);XCTAssertEqual(reopened.reply?.operation_id,another.operation_id)
        reopened.conceal()
    }
    @MainActor func testLateGenerationChangeDoesNotWriteOldJournalOrRepublishPending() async throws {
        for adoption in [false,true] {
            let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
            let state=ConceptChatState(transport:fixture,root:path);await state.load(fixture.concept,current:{c})
            if adoption {let command=ConceptChatCommand(operation_id:String(repeating:"b",count:32),turn_id:String(repeating:"c",count:32),expected_concept_revision:1,role:"BUSINESS",language:"nl",message:"Approved review");state.reply=try fixture.result(command)}
            var hold:CheckedContinuation<ConceptConnection,Never>?
            var first=true
            let current:@MainActor () async -> ConceptConnection = {if first {first=false;return await withCheckedContinuation{hold=$0}};return c}
            let task=Task {@MainActor in
                if adoption {await state.adopt(fixture.concept,current:current)}
                else {await state.send(role:"BUSINESS",message:"Original",language:"nl",concept:fixture.concept,current:current)}
            }
            for _ in 0..<100 where hold==nil {await Task.yield()}
            XCTAssertNotNil(hold);state.conceal();hold?.resume(returning:c);await task.value
            XCTAssertNil(state.pending);XCTAssertNil(try state.records.load(state.key(c,fixture.concept)));XCTAssertEqual(fixture.posts,0);XCTAssertEqual(fixture.adoptions,0)
        }
    }
    @MainActor func testInitializedLocalRecordLossDoesNotBecomeNewAdvice() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path);await state.load(fixture.concept,current:{c});fixture.lose=true
        await state.send(role:"BUSINESS",message:"Retain me",language:"en",concept:fixture.concept,current:{c})
        let key=state.key(c,fixture.concept);state.conceal();try FileManager.default.removeItem(at:path.appendingPathComponent("concept-chat-"+key+".json"))
        let reopened=ConceptChatState(transport:fixture,root:path);await reopened.load(fixture.concept,current:{c})
        XCTAssertNil(reopened.access);XCTAssertEqual(reopened.phase,"unavailable");XCTAssertEqual(fixture.posts,1);reopened.conceal()
    }
    @MainActor func testPendingReadonlyFailuresAndFiveLanguagePanelControls() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path);await state.load(fixture.concept,current:{c})
        fixture.pendingStatus="UNCERTAIN";await state.send(role:"BUSINESS",message:"An original",language:"fr",concept:fixture.concept,current:{c})
        XCTAssertEqual(state.phase,"pending");XCTAssertNotNil(state.pending)
        for language in ConceptChatCopy.languages {
            for width in [520.0,1100.0] {
                let host=NSHostingView(rootView:ConceptChatPanel(state:state,concept:fixture.concept,dirty:false,current:{c},adopted:{}).environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:width,height:900);host.layoutSubtreeIfNeeded();_=host.fittingSize
            }
        }
        fixture.fail = .denied;await state.resume(fixture.concept,current:{c});XCTAssertNil(state.access);XCTAssertEqual(state.phase,"access")
        for error:Error in [ConceptError.conflict,ConceptError.invalid,ConceptError.unavailable,AdvisoryError.state("LOCAL_CAPACITY_EXHAUSTED")] {state.failure(error)}
        fixture.fail=nil;fixture.readonly=true
        let readonlyPath=root();defer {try? FileManager.default.removeItem(at:readonlyPath)}
        let readonlyState=ConceptChatState(transport:fixture,root:readonlyPath)
        await readonlyState.load(fixture.concept,current:{c});XCTAssertEqual(readonlyState.phase,"ready");XCTAssertFalse(readonlyState.access?.can_advise ?? true);readonlyState.conceal()
        state.conceal()
    }
    @MainActor func testExplicitRejectedOriginalRetirementNeedsAuthenticatedAbsence() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path);await state.load(fixture.concept,current:{c})
        fixture.sendFailure=ConceptChatError.inputRejected
        await state.send(role:"BUSINESS",message:"A rejected message",language:"nl",concept:fixture.concept,current:{c})
        XCTAssertEqual(state.phase,"inputRejected");XCTAssertNotNil(state.pending);XCTAssertEqual(fixture.posts,0)
        fixture.fail = .unavailable;await state.retireRejected(fixture.concept,current:{c});XCTAssertNotNil(state.pending)
        fixture.fail=nil;state.phase="inputRejected";await state.retireRejected(fixture.concept,current:{c});XCTAssertNil(state.pending);XCTAssertEqual(fixture.posts,0)
        state.conceal();let reopened=ConceptChatState(transport:fixture,root:path);await reopened.load(fixture.concept,current:{c});XCTAssertNil(reopened.pending);reopened.conceal()
    }
    @MainActor func testCompleteProposalAndBlockedRecoveryControlsRenderTogetherAtBothWidths() async throws {
        let fixture=try ChatFixture(),path=root(),c=connection;defer {try? FileManager.default.removeItem(at:path)}
        let state=ConceptChatState(transport:fixture,root:path);await state.load(fixture.concept,current:{c})
        await state.send(role:"BUSINESS",message:"An exact source review",language:"es",concept:fixture.concept,current:{c})
        let complete=try XCTUnwrap(state.reply)
        for phase in ["ready","conflict","inputRejected","invalid","capacity","unavailable"] {
            state.phase=phase;state.reply=complete
            if phase=="inputRejected" {state.pending=ConceptChatState.Journal(key:state.key(c,fixture.concept),conceptID:fixture.concept.id,bindingID:complete.binding_id,producerSource:complete.producer_source,command:.init(operation_id:complete.operation_id,turn_id:complete.turn.request.turn_id,expected_concept_revision:1,role:"BUSINESS",language:"es",message:"An exact source review"),adoption:nil,complete:false)}
            for language in ["nl","en","de","fr","es","unsupported"] {
                for width in [520.0,1100.0] {
                    let host=NSHostingView(rootView:ConceptChatPanel(state:state,concept:fixture.concept,dirty:false,current:{c},adopted:{}).environment(\.locale,Locale(identifier:language)))
                    host.frame=NSRect(x:0,y:0,width:width,height:1000);host.layoutSubtreeIfNeeded();_=host.fittingSize
                }
            }
        }
        var blocked=fixture.seed["result"] as! [String:Any],proposal=blocked["proposal"] as! [String:Any]
        proposal["adoptable"]=false;blocked["proposal"]=proposal;state.reply=try fixture.decode(ConceptChatReply.self,blocked)
        let host=NSHostingView(rootView:ConceptChatPanel(state:state,concept:fixture.concept,dirty:false,current:{c},adopted:{}))
        host.frame=NSRect(x:0,y:0,width:1100,height:1000);host.layoutSubtreeIfNeeded();_=host.fittingSize
        state.conceal()
    }
    func testTypedWireBindingDigestAndValueShape() async throws {
        let fixture=try ChatFixture(),c=connection,concept=fixture.concept
        let cap=try await fixture.access(c,concept:concept.id);try cap.validate(c,concept)
        let source=try await fixture.briefing(c,concept:concept.id);XCTAssertTrue(source.concept.matches(concept))
        let cmd=ConceptChatCommand(operation_id:String(repeating:"b",count:32),turn_id:String(repeating:"c",count:32),expected_concept_revision:1,role:"BUSINESS",language:"nl",message:"Original")
        let value=try fixture.result(cmd);try value.validate(c,concept,cap,cmd.operation_id);XCTAssertThrowsError(try value.validate(c,concept,cap,String(repeating:"f",count:32)))
        let history=try await fixture.history(c,concept:concept.id);try history.validate(c,concept,cap)
        for value in [ConceptChatValue.text("日本語"),.list(["Question one","Question two"]),.null] {XCTAssertEqual(try JSONDecoder().decode(ConceptChatValue.self,from:JSONEncoder().encode(value)),value);_=value.display}
        var broken=fixture.seed["result"] as! [String:Any],proposal=broken["proposal"] as! [String:Any]
        proposal["displayed_change_digest"]=String(repeating:"0",count:64);broken["proposal"]=proposal
        XCTAssertThrowsError(try fixture.decode(ConceptChatReply.self,broken).validate(c,concept,cap,cmd.operation_id))
    }
}
