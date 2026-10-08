import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class CandidateMemory:CandidateCredentials,@unchecked Sendable {
    var access:CandidateAccess?
    var broken=false
    func load() throws -> CandidateAccess? { if broken { throw AdvisoryError.unavailable };return access }
    func save(_ a:CandidateAccess) throws { if broken { throw AdvisoryError.unavailable };access=a }
    func forget() throws { if broken { throw AdvisoryError.unavailable };access=nil }
}
final class CandidateDraftMemory:CandidateLocalStore,@unchecked Sendable {
    var values:[String:CandidateLocal]=[:]
    var broken=false
    func load(_ key:String) throws -> CandidateLocal? { if broken { throw AdvisoryError.unavailable };return values[key] }
    func save(_ v:CandidateLocal) throws { if broken { throw AdvisoryError.unavailable };values[v.key]=v }
}
final class CandidateTests:XCTestCase {
    let access=CandidateAccess(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),workspaceProjectID:"ws-project",actorID:"alice",
        forgeInstanceID:"forge-one",forgeProjectID:"project-one",repositoryID:"repo-one",conversationID:String(repeating:"a",count:32),proposalIDs:["proposal-one","proposal-two"],maximumRegistrations:2,token:String(repeating:"C",count:43))
    var connection:AdvisoryConnection { .init(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,conversationID:access.conversationID,bearer:"synthetic-read-root",draftGrant:String(repeating:"D",count:43)) }
    var calls:[URLRequest]=[]
    var proposals:[[String:Any]]=[]
    var observed:[String:Any]?
    var drop=false
    var dropBefore=false
    var code=200
    var errorCode="SOURCE_STALE"
    var forcePending=false
    func fixture(_ key:String) throws -> [String:Any] {
        let file=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/candidate/wire.json")
        return (try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any])[key] as! [String:Any]
    }
    func data(_ raw:Any) throws -> Data { try JSONSerialization.data(withJSONObject:raw) }
    func body(_ r:URLRequest) throws -> [String:Any] {
        if let d=r.httpBody { return try AdvisoryWire.object(d) }
        let stream=r.httpBodyStream!;stream.open();defer{stream.close()};var d=Data();var b=[UInt8](repeating:0,count:65536)
        while stream.hasBytesAvailable { let n=stream.read(&b,maxLength:b.count);if n<=0 { break };d.append(contentsOf:b.prefix(n)) };return try AdvisoryWire.object(d)
    }
    func transport() -> CandidateTransport {
        StubProtocol.handler={ r in
            self.calls.append(r)
            XCTAssertEqual(r.value(forHTTPHeaderField:"X-Workspace-Candidate-Grant"),self.access.token)
            XCTAssertEqual(r.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),self.connection.draftGrant)
            if self.code != 200 { return (self.code,try self.data(["error":self.errorCode])) }
            let path=r.url!.path;var raw:[String:Any]
            if path.hasSuffix("/access") {
                raw=["contract_version":"workspace-candidate-access/v1","actor_id":"alice","workspace_project_id":"ws-project","instance_id":"forge-one","project_id":"project-one","repository_id":"repo-one","conversation_id":self.access.conversationID,"proposal_ids":self.access.proposalIDs,"maximum_registrations":2]
            } else if path.hasSuffix("/capability") { raw=try self.fixture("capability") }
            else if path.contains("/source/") { raw=["contract_version":CandidateWire.contract,"source":try self.fixture("source"),"read_only":true] }
            else if r.httpMethod=="POST" {
                if self.dropBefore { self.dropBefore=false;throw URLError(.networkConnectionLost) }
                let submitted=try self.body(r)
                if path.hasSuffix("/registrations") {
                    raw=try self.fixture("registration")
                    var receipt=raw["original_receipt"] as! [String:Any];receipt["operation_id"]=submitted["operation_id"];receipt["proposal_revision"]=submitted["proposal_revision"];receipt["proposal_digest"]=submitted["proposal_digest"]
                    receipt["registration_key"]=try AdvisoryWire.digest(["forge-one:alice","project-one","repo-one",self.access.conversationID,"proposal-one",submitted["proposal_revision"]!] as [Any]);raw["original_receipt"]=receipt;self.observed=raw
                } else {
                    var p=try self.fixture("proposal");p["fields"]=submitted["fields"];p["proposal_id"]=submitted["proposal_id"];p["proposal_revision"]=(submitted["expected_revision"] as! Int)+1;p.removeValue(forKey:"proposal_digest");p["proposal_digest"]=try AdvisoryWire.digest(p)
                    if !self.proposals.contains(where:{($0["proposal_revision"] as? Int)==p["proposal_revision"] as? Int && ($0["proposal_id"] as? String)==p["proposal_id"] as? String}) { self.proposals.append(p) }
                    raw=["contract_version":CandidateWire.contract,"proposal":p,"registered":false,"additional_model_calls":0]
                }
                if self.drop { self.drop=false;throw URLError(.networkConnectionLost) }
            } else if path.contains("/registrations/") {
                if self.forcePending { raw=["contract_version":CandidateWire.contract,"state":"PENDING","operation_id":r.url!.lastPathComponent,"read_only":true] }
                else { guard let value=self.observed else { return (404,Data("{}".utf8)) };raw=value }
            } else {
                let revision=Int(URLComponents(url:r.url!,resolvingAgainstBaseURL:false)!.queryItems!.first!.value!)!
                guard let p=self.proposals.first(where:{$0["proposal_revision"] as? Int==revision && $0["proposal_id"] as? String==r.url!.lastPathComponent}) else { return (404,Data("{}".utf8)) }
                raw=try self.fixture("preview");raw["proposal"]=p;raw["latest_revision"]=self.proposals.filter{$0["proposal_id"] as? String==r.url!.lastPathComponent}.count;raw["registration"]=NSNull()
            }
            return (200,try self.data(raw))
        }
        let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[StubProtocol.self];return CandidateTransport(configuration:c)
    }
    func turn() throws -> AdvisoryTurnRecord {
        let a=AdvisoryTests(),raw=try a.fixture("record")
        var t=try AdvisoryWire.turn(raw,access:a.access,conversation:a.connection.conversationID)
        let s=try AdvisoryWire.decode(fixture("source"),as:CandidateSource.self)
        t=AdvisoryTurnRecord(request:AdvisoryRequest(contract_version:AdvisoryWire.contract,turn_id:s.turn_id,instance_id:"forge-one",project_id:"project-one",repository_id:"repo-one",conversation_id:access.conversationID,advisor_kind:s.advisor_kind,objective:"Synthetic source",expected_revision:0,context_revision:s.context_revision,selected_sources:s.selected_sources),request_digest:s.request_digest,session_id:s.session_id,invocation_id:s.invocation_id,context:t.context,provider:t.provider,status:"COMPLETE",lifecycle:t.lifecycle,execution:"CONFIRMED",outcome:AdvisoryOutcome(execution:"CONFIRMED",diagnostic:t.outcome!.diagnostic,usage:t.outcome!.usage,usage_status:"OBSERVED",observed_model:"NOT_REPORTED",observed_effort:"NOT_REPORTED",output:t.outcome!.output,result_digest:s.result_digest,error_code:nil),admitted_at:t.admitted_at,grant_id:t.grant_id,consumption:1)
        return t
    }
    @MainActor func prepared() async throws -> (CandidateState,CandidateMemory,CandidateDraftMemory) {
        let m=CandidateMemory();m.access=access;let store=CandidateDraftMemory(),state=CandidateState(credentials:m,store:store,transport:transport())
        await state.begin(try turn(),connection:connection);await state.chooseProposal("proposal-one")
        let f=try AdvisoryWire.decode(fixture("request")["fields"]!,as:CandidateFields.self)
        for (k,v) in CandidateForm(f).text { state.edit(k,v) }
        return (state,m,store)
    }
    @MainActor func testUserSaveAmendmentCancelExactRegistrationAndRestartOnlyReads() async throws {
        let (s,m,store)=try await prepared();XCTAssertTrue(s.canSave)
        await s.save();XCTAssertEqual(s.preview?.proposal.proposal_revision,1);XCTAssertNil(s.registration)
        s.edit("objective","Explicitly amended assessment");await s.save();XCTAssertEqual(s.preview?.proposal.proposal_revision,2)
        XCTAssertEqual(proposals.count,2);XCTAssertEqual((proposals[0]["fields"] as! [String:Any])["objective"] as? String,"A bounded assessment")
        await s.prepareRegistration();XCTAssertNotNil(s.confirmation);s.cancelConfirmation();XCTAssertNil(observed)
        await s.prepareRegistration();let operation=s.confirmation!.operation_id;await s.register();XCTAssertEqual(s.phase,"candidateRegistered");XCTAssertEqual(s.registration?.original_receipt.operation_id,operation)
        let posts=calls.filter{$0.httpMethod=="POST"}.count
        let reopened=CandidateState(credentials:m,store:store,transport:transport());await reopened.begin(try turn(),connection:connection)
        XCTAssertEqual(reopened.registration?.original_receipt.operation_id,operation);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,posts)
        XCTAssertEqual(reopened.local.form.text["objective"],"Explicitly amended assessment")
        await reopened.chooseRevision(1);reopened.loadSelectedFields();XCTAssertEqual(reopened.local.form.text["objective"],"A bounded assessment")
        reopened.edit("title","Literal café proposal");await reopened.chooseProposal("proposal-two");XCTAssertNil(reopened.preview)
        XCTAssertEqual(reopened.local.form.text["title"],"Literal café proposal")
    }
    @MainActor func testLostSaveAndRegistrationResponsesKeepSameIdentityAndNoAutomaticPosts() async throws {
        let (s,m,store)=try await prepared();drop=true;await s.save();XCTAssertNotNil(s.local.saveIntent);XCTAssertEqual(proposals.count,1)
        var posts=calls.filter{$0.httpMethod=="POST"}.count
        await s.refreshSelection();XCTAssertNil(s.local.saveIntent);XCTAssertEqual(s.local.revision,1);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,posts)
        await s.prepareRegistration();let operation=s.confirmation!.operation_id;drop=true;await s.register();XCTAssertTrue(s.local.registrationPending)
        let reopened=CandidateState(credentials:m,store:store,transport:transport());posts=calls.filter{$0.httpMethod=="POST"}.count
        await reopened.begin(try turn(),connection:connection);XCTAssertFalse(reopened.local.registrationPending);XCTAssertEqual(reopened.registration?.original_receipt.operation_id,operation);XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,posts)
        await reopened.chooseProposal("proposal-two");dropBefore=true;await reopened.save();XCTAssertTrue(reopened.pending)
        await reopened.recover();XCTAssertFalse(reopened.pending)
    }
    @MainActor func testDenyOfflineConflictCapacityClearProtectedPresentationKeepOwnText() async throws {
        let (s,_,store)=try await prepared();await s.save();s.edit("rationale","Own unsent explanation")
        for (status,error,phase) in [(403,"DENIED","candidateDenied"),(409,"SOURCE_STALE","candidateConflict"),(409,"PROPOSAL_CAPACITY_EXHAUSTED","candidateCapacity"),(503,"UNSUPPORTED","candidateUnsupported"),(400,"INVALID_REQUEST","candidateOffline"),(404,"missing","candidateMissing")] {
            code=status;errorCode=error;await s.refreshSelection();XCTAssertEqual(s.phase,phase);XCTAssertNil(s.source);XCTAssertNil(s.preview);XCTAssertNil(s.registration);XCTAssertEqual(s.local.form.text["rationale"],"Own unsent explanation")
        }
        code=200;await s.refreshSelection();s.suspend();XCTAssertNil(s.source);XCTAssertEqual(s.local.form.text["rationale"],"Own unsent explanation")
        s.invalidate();XCTAssertNil(s.local.form.text["rationale"]);await s.begin(try turn(),connection:connection);XCTAssertEqual(s.local.form.text["rationale"],"Own unsent explanation")
        store.broken=true;s.edit("title","Cannot be silently saved");XCTAssertEqual(s.phase,"candidateLocalCapacity")
        store.broken=false;await s.saveGrantSelection(access.token);s.forgetGrant();XCTAssertEqual(s.phase,"candidateReadOnly")
    }
}

extension CandidateTests {
    func testClosedContractScopeSourceFieldsAndReceiptBindings() throws {
        let raw=try fixture("proposal")
        _=try CandidateWire.proposal(raw,access:access,id:"proposal-one",revision:1)
        for (key,value) in [("principal_reference","forge-one:bob" as Any),("proposal_digest","sha256:"+String(repeating:"0",count:64)),("proposal_revision",2),("extra",true)] {
            var d=raw;d[key]=value;XCTAssertThrowsError(try CandidateWire.proposal(d,access:access,id:"proposal-one",revision:1))
        }
        let fields=try AdvisoryWire.decode(fixture("request")["fields"]!,as:CandidateFields.self)
        _=try CandidateForm(fields).fields()
        for key in CandidateForm.scalarKeys where key != "confidence" {
            var f=CandidateForm(fields);f.text[key]="";XCTAssertThrowsError(try f.fields())
        }
        for (key,value) in [("confidence",""),("confidence","101"),("scope",""),("acceptance_criteria","yes"),("dependencies","same\nsame"),("rationale","<script>"),("read_paths","../private"),("read_paths","credentials/token"),("write_paths","src/file.swift"),("delivery","GIT"),("mode","DOCUMENTATION_ONLY")] {
            var f=CandidateForm(fields);f.text[key]=value;XCTAssertThrowsError(try f.fields())
        }
        var f=fields;f.effect_policy=CandidateEffectPolicy(contract_version:"1.0",mode:"DOCUMENTATION_ONLY",delivery:"GIT",read_paths:["docs/"],write_paths:["docs/boundary.md"]);try CandidateWire.fields(f)
        f.effect_policy.write_paths=["docs/"];XCTAssertThrowsError(try CandidateWire.fields(f))
        f.effect_policy.mode="BOUNDED_REPOSITORY_CHANGE";f.effect_policy.write_paths=["src/code.swift"];try CandidateWire.fields(f)
        var bad=try fixture("capability");bad["maximum_registrations"]=true;XCTAssertThrowsError(try CandidateWire.capability(data(bad),access:access))
        for (key,value) in [("instance_id","foreign" as Any),("additional_model_calls",1),("proposal_ids",["other"])] {
            var b=try fixture("capability");b[key]=value;XCTAssertThrowsError(try CandidateWire.capability(data(b),access:access))
        }
        let source=try fixture("source");XCTAssertThrowsError(try CandidateWire.source(data(["contract_version":CandidateWire.contract,"source":source,"read_only":true]),turn:"wrong"))
        _=try CandidateWire.registration(fixture("registration"),access:access,id:"proposal-one")
        for key in ["registration_key","candidate_digest","principal_reference","operation_id","rationale"] {
            var b=try fixture("registration"),r=b["original_receipt"] as! [String:Any];r[key]=key=="rationale" ? "<script>":"bad/value";b["original_receipt"]=r
            XCTAssertThrowsError(try CandidateWire.registration(b,access:access,id:"proposal-one"))
        }
        var b=try fixture("registration"),c=b["current"] as! [String:Any],doc=c["candidate"] as! [String:Any];doc["id"]="foreign";c["candidate"]=doc;c["candidate_digest"]=try AdvisoryWire.digest(doc);b["current"]=c
        XCTAssertThrowsError(try CandidateWire.registration(b,access:access,id:"proposal-one"))
        var p=try fixture("preview");p["registration"]=try fixture("registration");_=try CandidateWire.preview(data(p),access:access,id:"proposal-one",revision:1)
        p["latest_revision"]=0;XCTAssertThrowsError(try CandidateWire.preview(data(p),access:access,id:"proposal-one",revision:1))
        XCTAssertFalse(CandidateWire.safe("password=secret"));XCTAssertFalse(CandidateWire.safePath(".env.private"));XCTAssertFalse(CandidateWire.safePath("docs/name."));XCTAssertFalse(CandidateWire.safePath("/private"))
    }
    func testDurableOwnDraftIntentRoundtripAndPrivateStorageFaults() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("candidate-private-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let store=PrivateCandidateLocalStore(root:root),key=CandidateLocal.scopeKey(connection)
        XCTAssertNil(try store.load(key));var value=CandidateLocal();value.key=key;value.form.text["title"]="Own unsent literal café";value.saveIntent=try AdvisoryWire.decode(fixture("request"),as:CandidateSaveRequest.self);value.registrationIntent=try AdvisoryWire.decode(fixture("registration_request"),as:CandidateRegistrationRequest.self);value.registrationPending=true
        try store.save(value);XCTAssertEqual(try store.load(key),value)
        value.form.text["title"]="A changed own draft";try store.save(value);XCTAssertEqual(try store.load(key),value)
        XCTAssertThrowsError(try store.load("wrong"));value.form.text["objective"]=String(repeating:"x",count:70000);XCTAssertThrowsError(try store.save(value))
        let file=root.appendingPathComponent("candidate-"+key+".json");try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path);XCTAssertThrowsError(try store.load(key));XCTAssertThrowsError(try store.save(value))
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path);try Data("{}".utf8).write(to:file);XCTAssertThrowsError(try store.load(key))
        try FileManager.default.removeItem(at:file);try FileManager.default.createSymbolicLink(at:file,withDestinationURL:root.appendingPathComponent("elsewhere"));XCTAssertThrowsError(try store.load(key));XCTAssertThrowsError(try store.save(value))
        try FileManager.default.removeItem(at:file);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:root.path);XCTAssertThrowsError(try store.load(key))
    }
    @MainActor func testFiveLanguageThemesNarrowFormPreviewConfirmationAndReceiptRendering() async throws {
        let (s,_,_)=try await prepared()
        for language in ["en","nl","de","fr","es"] {
            XCTAssertEqual(Set(CandidateCopy.values[language]!.keys),Set(CandidateCopy.values["en"]!.keys))
            XCTAssertEqual(CandidateCopy.text("unknown",locale:language),"unknown")
            for theme in [ColorScheme.light,.dark] {
                let host=NSHostingView(rootView:CandidateView(state:s).environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,theme))
                host.frame=NSRect(x:0,y:0,width:640,height:1800);host.layoutSubtreeIfNeeded();XCTAssertNotNil(host.bitmapImageRepForCachingDisplay(in:host.bounds))
            }
        }
        await s.save();await s.prepareRegistration()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:900),styleMask:[.titled],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:CandidateView(state:s));window.contentView=host;host.frame=window.contentView!.bounds;host.layoutSubtreeIfNeeded()
        XCTAssertNotNil(s.confirmation);s.cancelConfirmation();await s.prepareRegistration();await s.register();host.layoutSubtreeIfNeeded();XCTAssertNotNil(s.registration)
        s.suspend();host.layoutSubtreeIfNeeded();await s.refreshSelection();host.layoutSubtreeIfNeeded()
        window.orderOut(nil)
    }
    @MainActor func testPendingOriginalRecoveryAndPersistenceFailureStayBounded() async throws {
        let (s,_,store)=try await prepared();dropBefore=true;await s.save();XCTAssertTrue(s.pending)
        var alternate=try turn();alternate=AdvisoryTurnRecord(request:AdvisoryRequest(contract_version:alternate.request.contract_version,turn_id:"other-turn",instance_id:alternate.request.instance_id,project_id:alternate.request.project_id,repository_id:alternate.request.repository_id,conversation_id:alternate.request.conversation_id,advisor_kind:alternate.request.advisor_kind,objective:alternate.request.objective,expected_revision:0,context_revision:alternate.request.context_revision,selected_sources:[]),request_digest:alternate.request_digest,session_id:alternate.session_id,invocation_id:alternate.invocation_id,context:alternate.context,provider:alternate.provider,status:alternate.status,lifecycle:alternate.lifecycle,execution:alternate.execution,outcome:alternate.outcome,admitted_at:alternate.admitted_at,grant_id:alternate.grant_id,consumption:1)
        await s.begin(alternate,connection:connection);XCTAssertEqual(s.phase,"candidatePending");XCTAssertEqual(s.local.turnID,"turn-one")
        await s.recover();XCTAssertFalse(s.pending)
        await s.prepareRegistration();forcePending=true;await s.register();XCTAssertTrue(s.pending);XCTAssertEqual(s.phase,"candidatePending")
        let original=s.local.registrationIntent;await s.recover();XCTAssertEqual(s.local.registrationIntent,original);XCTAssertTrue(s.pending)
        forcePending=false;await s.refreshSelection();XCTAssertFalse(s.pending)
        s.loadSelectedFields();store.broken=true;s.edit("objective","Unavailable persistence");await s.save();XCTAssertEqual(s.phase,"candidateLocalCapacity");XCTAssertFalse(s.canSave);XCTAssertEqual(s.local.form.text["objective"],"Unavailable persistence")
    }
}

extension CandidateTests {
    func testSeparateCandidateCredentialNamespaceWithoutPersonalKeychain() throws {
        let backend=AdviceKeychainBackend(),store=CandidateKeychain(operations:backend.operations)
        XCTAssertNil(try store.load());try store.save(access);try store.save(access);XCTAssertEqual(try store.load(),access)
        try store.forget();XCTAssertNil(try store.load());try store.forget()
        XCTAssertTrue(backend.services.allSatisfy{$0=="com.pcvantol.workspace.native-client.candidate.v1"})
        backend.records["candidate-access"]=Data("bad".utf8);XCTAssertThrowsError(try store.load())
        backend.failure=errSecAuthFailed;XCTAssertThrowsError(try store.load());XCTAssertThrowsError(try store.save(access));XCTAssertThrowsError(try store.forget())
        backend.failure=nil
        let bad=CandidateAccess(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,workspaceProjectID:access.workspaceProjectID,actorID:access.actorID,
            forgeInstanceID:access.forgeInstanceID,forgeProjectID:access.forgeProjectID,repositoryID:access.repositoryID,conversationID:access.conversationID,proposalIDs:[],maximumRegistrations:1,token:access.token)
        XCTAssertThrowsError(try store.save(bad));backend.records["candidate-access"]=try JSONEncoder().encode(bad);XCTAssertThrowsError(try store.load())
    }
    @MainActor func testLateCandidateReadAndGrantProbeCannotCrossSelectionEpoch() async throws {
        let (s,m,_)=try await prepared();let before=calls.filter{$0.httpMethod=="POST"}.count
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        let original=StubProtocol.handler!
        StubProtocol.handler={ r in
            if r.url!.path.hasSuffix("/capability") { entered.signal();self.waitBarrier(release) }
            return try original(r)
        }
        let task=Task { await s.refreshSelection() }
        while !signalled(entered) { await Task.yield() }
        s.invalidate();release.signal();await task.value;XCTAssertNil(s.capability);XCTAssertNil(s.source);XCTAssertNil(s.preview);XCTAssertFalse(s.hasGrant)
        XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,before)
        StubProtocol.handler={ r in
            entered.signal();self.waitBarrier(release);return try original(r)
        }
        let probe=Task { await s.saveGrant(self.access.token,connection:self.connection) }
        while !signalled(entered) { await Task.yield() }
        s.invalidate();m.access=nil;release.signal();await probe.value;XCTAssertNil(m.access);XCTAssertEqual(s.phase,"candidateReadOnly")
    }
    private func signalled(_ semaphore:DispatchSemaphore) -> Bool { semaphore.wait(timeout:.now()) == .success }
    private func waitBarrier(_ semaphore:DispatchSemaphore) { _=semaphore.wait(timeout:.now()+3) }
}

extension CandidateTests {
    @MainActor func testObservedDenialStopsExplicitRecoveryBeforeAnyPost() async throws {
        let (s,_,_)=try await prepared();dropBefore=true;await s.save();XCTAssertTrue(s.pending)
        let before=calls.filter{$0.httpMethod=="POST"}.count;code=403;await s.recover()
        XCTAssertEqual(s.phase,"candidateDenied");XCTAssertTrue(s.pending);XCTAssertNil(s.source)
        XCTAssertEqual(calls.filter{$0.httpMethod=="POST"}.count,before)
        XCTAssertEqual(s.local.saveIntent?.proposal_id,"proposal-one")
    }
}
