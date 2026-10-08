import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class AdviceMemory: AdvisoryCredentials, @unchecked Sendable {
    var access:AdvisoryAccess?
    var intent:AdvisoryIntent?
    var broken=false
    func loadAccess() throws -> AdvisoryAccess? { if broken { throw AdvisoryError.unavailable };return access }
    func saveAccess(_ a:AdvisoryAccess) throws { if broken { throw AdvisoryError.unavailable };access=a }
    func forgetAccess() throws { access=nil }
    func loadIntent() throws -> AdvisoryIntent? { if broken { throw AdvisoryError.unavailable };return intent }
    func saveIntent(_ p:AdvisoryIntent) throws { if broken { throw AdvisoryError.unavailable };intent=p }
    func forgetIntent() throws { if broken { throw AdvisoryError.unavailable };intent=nil }
}
final class AdvisoryTests:XCTestCase {
    let access=AdvisoryAccess(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),workspaceProjectID:"ws-project",actorID:"alice",forgeInstanceID:"forge-one",forgeProjectID:"project-one",repositoryID:"repo-one",conversationIDs:[String(repeating:"a",count:32)],token:String(repeating:"A",count:43))
    var connection:AdvisoryConnection { .init(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,conversationID:access.conversationIDs[0],bearer:"root-test-read",draftGrant:String(repeating:"D",count:43)) }
    var calls:[URLRequest]=[]
    var records:[[String:Any]]=[]
    var code=200
    var drop=false
    var ambiguous=false
    var errorCode="TURN_BUDGET_EXHAUSTED"
    func fixture(_ key:String) throws -> [String:Any] {
        let path=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/advisory/wire.json")
        let raw=try JSONSerialization.jsonObject(with:Data(contentsOf:path)) as! [String:Any];return raw[key] as! [String:Any]
    }
    func body(_ request:URLRequest) throws -> Data {
        if let body=request.httpBody { return body }
        let stream=request.httpBodyStream!;stream.open();defer{stream.close()}
        var data=Data();var bytes=[UInt8](repeating:0,count:16000)
        while stream.hasBytesAvailable { let n=stream.read(&bytes,maxLength:bytes.count);if n<=0 { break };data.append(contentsOf:bytes.prefix(n)) }
        return data
    }
    func transport() -> AdvisoryTransport {
        StubProtocol.handler={ request in
            self.calls.append(request)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Advisory-Grant"),self.access.token)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),self.connection.draftGrant)
            if self.code != 200 { return (self.code,try JSONSerialization.data(withJSONObject:["error":self.errorCode])) }
            let path=request.url!.path;var raw:[String:Any]
            if path.hasSuffix("/access") {
                raw=["contract_version":"workspace-advisory-access/v1","actor_id":"alice","workspace_project_id":"ws-project","instance_id":"forge-one","project_id":"project-one","repository_id":"repo-one","conversation_ids":self.access.conversationIDs]
            } else if path.hasSuffix("/capability") { raw=try self.fixture("capability") }
            else if request.httpMethod=="POST" {
                if path.hasSuffix("/cancel") {
                    var record=self.records.last!;record["status"]="CANCEL_REQUESTED";record["execution"]="MAY_HAVE_HAPPENED";record["outcome"]=NSNull();self.records[self.records.count-1]=record
                    raw=["contract_version":AdvisoryWire.contract,"original_turn":record,"current_revision":self.records.count,"provider_stopped":false,"cancel_request_recorded":true]
                } else {
                    let submitted=try JSONSerialization.jsonObject(with:self.body(request)) as! [String:Any]
                    var record=try self.fixture("record");record["request"]=submitted;record["request_digest"]=try AdvisoryWire.digest(submitted)
                    var outcome=record["outcome"] as! [String:Any];var output=outcome["output"] as! [String:Any]
                    output["request_digest"]=record["request_digest"];output["advisor_kind"]=submitted["advisor_kind"]
                    outcome["output"]=output;outcome["result_digest"]=try AdvisoryWire.digest(output);record["outcome"]=outcome
                    if self.ambiguous { record["execution"]="MAY_HAVE_HAPPENED";record["status"]="REASONING";record["outcome"]=NSNull() }
                    if !self.records.contains(where:{($0["request"] as! [String:Any])["turn_id"] as? String==submitted["turn_id"] as? String}) { self.records.append(record) }
                    raw=["contract_version":AdvisoryWire.contract,"original_turn":record,"current_revision":self.records.count,"recorded":true]
                }
                if self.drop { throw URLError(.networkConnectionLost) }
            } else if path.contains("/turns/") {
                guard let record=self.records.first(where:{($0["request"] as! [String:Any])["turn_id"] as? String==request.url!.lastPathComponent}) else { return (404,Data("{}".utf8)) }
                raw=["contract_version":AdvisoryWire.contract,"original_turn":record,"current_revision":self.records.count,"read_only":true]
            } else {
                let parts=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems ?? []
                let cursor=Int(parts.first(where:{$0.name=="cursor"})?.value ?? "0")!
                let page=Array(self.records.dropFirst(cursor).prefix(4));let next=cursor+page.count<self.records.count ? cursor+page.count:nil
                raw=["contract_version":AdvisoryWire.contract,"conversation_id":self.connection.conversationID,"scope":["instance_id":"forge-one","project_id":"project-one","repository_id":"repo-one"],"revision":self.records.count,"turns":page,"next_cursor":next as Any? ?? NSNull(),"consumed_turns":self.records.count,"maximum_turns":8,"retention":"PRIVATE_RETAINED_NO_AUTOMATIC_DELETE","read_only":true]
            }
            return (200,try JSONSerialization.data(withJSONObject:raw))
        }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[StubProtocol.self];return AdvisoryTransport(configuration:config)
    }
    func testClosedSchemaUnicodeHashesAndUnsafeProvenance() throws {
        let cap=try fixture("capability"),record=try fixture("record")
        _=try AdvisoryWire.capability(JSONSerialization.data(withJSONObject:cap),access:access)
        let turn=try AdvisoryWire.turn(record,access:access,conversation:connection.conversationID)
        XCTAssertEqual(turn.request.digest,turn.request_digest)
        for (key,value) in [("read_only",1 as Any),("maximum_turns",true),("instance_id","wrong"),("context_revision","wrong"),("extra",1)] {
            var bad=cap;bad[key]=value;XCTAssertThrowsError(try AdvisoryWire.capability(JSONSerialization.data(withJSONObject:bad),access:access))
        }
        var bad=record;var outcome=bad["outcome"] as! [String:Any];var output=outcome["output"] as! [String:Any];output["summary"]="<script>bad</script>";outcome["output"]=output;outcome["result_digest"]=try AdvisoryWire.digest(output);bad["outcome"]=outcome
        XCTAssertThrowsError(try AdvisoryWire.turn(bad,access:access,conversation:connection.conversationID))
        XCTAssertFalse(AdvisoryWire.safe("Bearer private"));XCTAssertFalse(AdvisoryWire.safe("password=private"))
        XCTAssertThrowsError(try AdvisoryWire.validate(["unsupported":true],kind:"request"))
    }
    @MainActor func testBusinessArchitectContinuityLossRestartAndNoAutomaticPost() async throws {
        let memory=AdviceMemory();memory.access=access;let wire=transport();let state=AdvisoryState(credentials:memory,transport:wire)
        await state.refresh(connection);XCTAssertTrue(state.canSend(text:"Synthetic value.",mode:"BUSINESS"));XCTAssertFalse(state.canSend(text:"UX",mode:"UX"))
        drop=true;await state.send(text:"Synthetic value.",mode:"BUSINESS",connection:connection)
        let request=try XCTUnwrap(memory.intent?.request);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,1)
        let reopened=AdvisoryState(credentials:memory,transport:wire);await reopened.refresh(connection)
        XCTAssertNil(memory.intent);XCTAssertEqual(reopened.phase,"adviceComplete");XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,1)
        XCTAssertEqual(reopened.history.first?.request,request)
        drop=false;await reopened.send(text:"Synthetic feasibility.",mode:"ARCHITECTURE",connection:connection)
        XCTAssertEqual(reopened.history.map{$0.request.advisor_kind},["BUSINESS","ARCHITECTURE"])
        for n in 0..<3 { await reopened.send(text:"Synthetic continuation \(n).",mode:"BUSINESS",connection:connection) }
        XCTAssertEqual(reopened.history.count,4);XCTAssertEqual(reopened.nextCursor,4);await reopened.more(connection);XCTAssertEqual(reopened.history.count,5)
        let before=calls.filter{$0.httpMethod=="POST"}.count;await reopened.refresh(connection);await reopened.resume(connection);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,before)
        code=403;await reopened.refresh(connection);XCTAssertTrue(reopened.history.isEmpty);XCTAssertNil(reopened.capability)
    }
    @MainActor func testPersistenceFailureMissingExplicitRecoveryCancellationAndBounds() async throws {
        let memory=AdviceMemory();memory.access=access;let wire=transport();let state=AdvisoryState(credentials:memory,transport:wire)
        await state.refresh(connection);memory.broken=true;await state.send(text:"Synthetic request",mode:"BUSINESS",connection:connection);XCTAssertFalse(calls.contains{$0.httpMethod=="POST"})
        memory.broken=false;await state.refresh(connection);ambiguous=true;await state.send(text:"Synthetic ambiguous",mode:"BUSINESS",connection:connection)
        XCTAssertNotNil(memory.intent);XCTAssertEqual(state.phase,"adviceUncertain")
        await state.cancel(connection);XCTAssertEqual(state.phase,"adviceCancelIntent");XCTAssertNotNil(memory.intent?.cancel)
        let count=calls.filter{$0.httpMethod=="POST"}.count;await state.refresh(connection);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,count)
        state.forgetGrant();XCTAssertEqual(state.phase,"adviceUncertain")
        for (status,error,phase) in [(409,"TURN_BUDGET_EXHAUSTED","adviceBudget"),(409,"CONVERSATION_BUSY","adviceBusy"),(409,"CONTEXT_STALE","adviceStale"),(400,"ADVISOR_UNSUPPORTED","adviceUnsupported"),(503,"UNAVAILABLE","adviceOffline"),(404,"MISSING","adviceUncertain")] {
            code=status;errorCode=error;await state.refresh(connection);XCTAssertEqual(state.phase,phase)
        }
        await state.refresh(nil);XCTAssertNil(state.capability)
    }
    @MainActor func testSeparateGrantProbeUnsupportedEmptyAndFiveLanguageNarrowRendering() async throws {
        let memory=AdviceMemory();let state=AdvisoryState(credentials:memory,transport:transport())
        await state.refresh(connection);XCTAssertEqual(state.phase,"adviceReadOnly")
        await state.saveGrant(access.token,connection:connection);XCTAssertTrue(state.hasGrant)
        let drafts=ConversationState(advisory:state);drafts.draft="Synthetic local text";drafts.title="Synthetic conversation"
        NSApplication.shared.setActivationPolicy(.prohibited)
        for language in ["en","nl","de","fr","es"] {
            XCTAssertNotEqual(AdvisoryCopy.text("send",language:language),"send")
            for theme in [ColorScheme.light,.dark] {
                let host=NSHostingView(rootView:AdvisoryView(state:state,drafts:drafts,connection:{self.connection}).environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,theme))
                host.frame=NSRect(x:0,y:0,width:440,height:1500);host.layoutSubtreeIfNeeded()
            }
        }
        await state.send(text:"Synthetic displayed advice",mode:"BUSINESS",connection:connection)
        func renderCurrent() {
            let host=NSHostingView(rootView:AdvisoryView(state:state,drafts:drafts,connection:{self.connection}));host.frame=NSRect(x:0,y:0,width:640,height:2200);host.layoutSubtreeIfNeeded()
        }
        renderCurrent();drafts.mode="UX";renderCurrent()
        ambiguous=true;await state.send(text:"Synthetic unresolved",mode:"ARCHITECTURE",connection:connection);renderCurrent()
        await state.cancel(connection);renderCurrent()
        code=403;await state.refresh(connection);renderCurrent()
        code=200;state.invalidate();await state.refresh(nil);renderCurrent()
        memory.intent=nil;await state.refresh(connection)
        state.suspend();XCTAssertNil(state.capability);await state.refresh(connection)
        state.forgetGrant();XCTAssertFalse(state.hasGrant)
        XCTAssertEqual(AdvisoryCopy.text("send",language:"unknown"),AdvisoryCopy.text("send",language:"en"))
    }
}
