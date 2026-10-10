import Foundation
import Combine

@MainActor final class AdvisoryState: ObservableObject {
    @Published private(set) var capability: AdvisoryCapability?
    @Published private(set) var history: [AdvisoryTurnRecord] = []
    @Published private(set) var latest: AdvisoryObservation?
    @Published private(set) var pending: AdvisoryIntent?
    @Published private(set) var phase="adviceReadOnly"
    @Published private(set) var busy=false
    @Published private(set) var hasGrant=false
    @Published private(set) var revision=0
    @Published private(set) var nextCursor:Int?
    @Published private(set) var selectedSources:[AdvisorySource]=[]
    @Published private(set) var inspectorOpen=false
    private var inspectorNeedsTail=false
    @Published private(set) var inspectedTurnID:String?
    @Published private(set) var inspectedReference:String?
    @Published private(set) var inspectorCategory:AdvisoryAnswerCategory = .summary
    var inspectedTurn:AdvisoryTurnRecord? {
        guard hasGrant,capability != nil,let id=inspectedTurnID else { return nil }
        return history.first{$0.request.turn_id==id} ?? (latest?.turn.request.turn_id==id ? latest?.turn:nil)
    }
    func inspect(_ id:String) {
        guard !busy,hasGrant,capability != nil,history.contains(where:{$0.request.turn_id==id}) || latest?.turn.request.turn_id==id else { return }
        inspectorOpen=true;inspectorNeedsTail=history.count>4;inspectedTurnID=id;inspectedReference=nil;inspectorCategory = .summary
    }
    func inspectCategory(_ category:AdvisoryAnswerCategory) {
        guard inspectedTurn != nil else { return };inspectorCategory=category;inspectedReference=nil
    }
    func inspectReference(_ reference:String) {
        guard inspectedTurn?.context.evidence_references.contains(reference)==true else { return };inspectedReference=reference
    }
    func inspectorBack() {
        if inspectedReference != nil { inspectedReference=nil } else { closeInspector() }
    }
    func closeInspector() { inspectorOpen=false;inspectorNeedsTail=false;inspectedTurnID=nil;inspectedReference=nil;inspectorCategory = .summary }
    private let credentials:any AdvisoryCredentials
    private let transport:AdvisoryTransport
    private var connection:AdvisoryConnection?
    private var generation=0
    init(credentials:any AdvisoryCredentials = AdvisoryKeychain(), transport:AdvisoryTransport = AdvisoryTransport()) {
        self.credentials=credentials;self.transport=transport
    }
    private func clearPresentation(preserveInspection:Bool=false) { if !preserveInspection { closeInspector() };capability=nil;history=[];latest=nil;nextCursor=nil;revision=0 }
    func invalidate() {
        generation &+= 1;connection=nil;clearPresentation();selectedSources=[];busy=false;hasGrant=false;phase="adviceReadOnly"
        pending=try? credentials.loadIntent()
    }
    func suspend(transient:Bool=false) {
        generation &+= 1;clearPresentation(preserveInspection:transient);busy=false;hasGrant=false;phase="adviceOffline"
    }
    private func admit(_ new:AdvisoryConnection?) -> Bool {
        guard let new else { invalidate();return false }
        if connection != new { invalidate();connection=new }
        return true
    }
    private func access(_ c:AdvisoryConnection) throws -> AdvisoryAccess {
        guard let a=try credentials.loadAccess(),a.valid,a.endpoint==c.endpoint,a.workspaceInstanceID==c.workspaceInstanceID,
              a.workspaceProjectID==c.workspaceProjectID,a.actorID==c.actorID,a.conversationIDs.contains(c.conversationID) else { throw AdvisoryError.denied }
        return a
    }
    var pendingForSelection: Bool {
        guard let p=pending,let c=connection else { return false }
        return p.actorID==c.actorID && p.workspaceProjectID==c.workspaceProjectID && p.request.conversation_id==c.conversationID && p.workspaceInstanceID==c.workspaceInstanceID && p.endpoint==c.endpoint
    }
    func canSend(text:String,mode:String) -> Bool {
        guard let cap=capability,hasGrant,!busy,pending==nil,let c=connection,
              cap.conversation_ids.contains(c.conversationID),cap.supported_modes.contains(mode),
              cap.retained_principal_consumed_turns<cap.maximum_turns,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              text.unicodeScalars.count<=1000 else { return false }
        return true
    }
    private func setFailurePhase(_ code: String) {
        switch code {
        case "CONVERSATION_BUSY":phase="adviceBusy"
        case "TURN_BUDGET_EXHAUSTED","TRANSCRIPT_CAPACITY_EXHAUSTED","CONVERSATION_CAPACITY_EXHAUSTED":phase="adviceBudget"
        case "INVOCATION_UNRESOLVED":phase="adviceUncertain"
        case "CONVERSATION_OR_CONTEXT_STALE","CONTEXT_STALE","TURN_PAYLOAD_CONFLICT","CANCEL_PRECONDITION_CHANGED","ADVISORY_CONFLICT":phase="adviceStale"
        case "ADVISOR_UNSUPPORTED":phase="adviceUnsupported"
        case "ADVISORY_NOT_FOUND":phase=pending==nil ? "adviceUnsupported":"adviceUncertain"
        case "INVALID_REQUEST","ADVISORY_REQUEST_INVALID":phase="adviceInvalid"
        default:phase="adviceOffline"
        }
    }

    private func fail(_ error:Error) {
        clearPresentation()
        switch error {
        case AdvisoryError.denied:hasGrant=false;phase="adviceDenied"
        case AdvisoryError.missing:phase=pending==nil ? "adviceUnsupported":"adviceUncertain"
        case AdvisoryError.invalid:phase="adviceInvalid"
        case AdvisoryError.state(let code): setFailurePhase(code)
        default:phase=pending==nil ? "adviceOffline":"adviceUncertain"
        }
    }
    private func accept(_ value:AdvisoryObservation, intent:AdvisoryIntent) throws {
        latest=value;revision=value.currentRevision
        if value.turn.execution=="MAY_HAVE_HAPPENED" {
            phase=value.turn.status=="CANCEL_REQUESTED" ? "adviceCancelIntent":"adviceUncertain"
        } else {
            phase=value.turn.status=="COMPLETE" ? "adviceComplete":"adviceFailed"
            if pending==intent { try credentials.forgetIntent();pending=nil }
        }
    }
    private func refreshHistory(_ a: AdvisoryAccess, _ c: AdvisoryConnection, preservePage: Bool) async throws -> (AdvisoryHistory?, [AdvisoryTurnRecord], Int?) {
        var page:AdvisoryHistory?
        do { page=try await transport.history(a,c) }
        catch AdvisoryError.missing {
            // Pinned Forge does not allocate a transcript until first send.
            // Absence is not an empty canonical transcript or an auto send.
            guard pending==nil,revision==0,latest==nil else { throw AdvisoryError.missing }
        }
        var turns=page?.turns ?? [];var cursor=page?.next_cursor
        if preservePage,let next=cursor,let first=page {
            let tail=try await transport.history(a,c,cursor:next)
            guard tail.revision==first.revision,turns.count+tail.turns.count<=8,
                  Set((turns+tail.turns).map{$0.request.turn_id}).count==turns.count+tail.turns.count else { throw AdvisoryError.state("CONVERSATION_OR_CONTEXT_STALE") }
            turns+=tail.turns;cursor=tail.next_cursor
        }
        return (page, turns, cursor)
    }

    private func recoverPendingTurn(_ a: AdvisoryAccess, _ c: AdvisoryConnection, epoch: Int) async throws -> Bool {
        if let p=pending,p.matches(a,connection:c) {
            let value=try await transport.turn(a,c,request:p.request)
            guard epoch==generation else { return false };try accept(value,intent:p)
        }
        return true
    }

    private func updateHistoryPhase(_ page: AdvisoryHistory?) {
        if inspectedTurnID != nil && inspectedTurn==nil { closeInspector() }
        if pending==nil { phase=page==nil ? "adviceNew":latest?.turn.status=="COMPLETE" ? "adviceComplete":"adviceCurrent" }
        else if !pendingForSelection { phase="adviceOtherPending" }
    }

    func refresh(_ new:AdvisoryConnection?) async {
        guard admit(new),!busy,let c=new else { return }
        let epoch=generation;let preservePage=inspectedTurnID != nil && (history.count>4 || inspectorNeedsTail)
        busy=true;defer { if epoch==generation { busy=false } }
        do {
            pending=try credentials.loadIntent()
            guard try credentials.loadAccess() != nil else { clearPresentation();hasGrant=false;phase="adviceReadOnly";return }
            let a=try access(c);hasGrant=true
            guard try await recoverPendingTurn(a, c, epoch: epoch) else { return }
            let cap=try await transport.capability(a,c,sources:selectedSources)
            guard epoch==generation else { return }
            let (page, turns, cursor) = try await refreshHistory(a, c, preservePage: preservePage)
            guard epoch==generation else { return }
            capability=cap;history=turns;revision=page?.revision ?? 0;nextCursor=cursor
            updateHistoryPhase(page)
        } catch { if epoch==generation { fail(error) } }
    }
    func saveGrant(_ token:String,connection c:AdvisoryConnection?) async {
        guard admit(c),!busy,let c else { return }
        let epoch=generation;busy=true
        do {
            guard try credentials.loadIntent()==nil else { throw AdvisoryError.state("INVOCATION_UNRESOLVED") }
            let a=try await transport.probe(connection:c,token:token)
            guard epoch==generation else { return };try credentials.saveAccess(a);hasGrant=true;busy=false
            await refresh(c)
        } catch { if epoch==generation { busy=false;fail(error) } }
    }
    func forgetGrant() {
        guard !busy else { return }
        do {
            guard try credentials.loadIntent()==nil else { throw AdvisoryError.state("INVOCATION_UNRESOLVED") }
            try credentials.forgetAccess();invalidate()
        } catch { fail(error) }
    }
    func select(_ source:AdvisorySource,include:Bool,connection c:AdvisoryConnection?) async {
        guard !busy,pending==nil,capability?.available_sources.contains(where:{$0.source_id==source.source_id && $0.version==source.version})==true else { return }
        if include {
            guard selectedSources.count<2,!selectedSources.contains(source) else { return };selectedSources.append(source)
        } else { selectedSources.removeAll{$0==source} }
        await refresh(c)
    }
    func more(_ c:AdvisoryConnection?) async {
        guard let c,c==connection,!busy,let cursor=nextCursor else { return }
        let epoch=generation;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c);let page=try await transport.history(a,c,cursor:cursor)
            guard epoch==generation else { return }
            guard page.revision==revision,history.count+page.turns.count<=8,Set((history+page.turns).map{$0.request.turn_id}).count==history.count+page.turns.count else { throw AdvisoryError.state("CONVERSATION_OR_CONTEXT_STALE") }
            history+=page.turns;nextCursor=page.next_cursor
        } catch { if epoch==generation { fail(error) } }
    }
    func send(text:String,mode:String,connection c:AdvisoryConnection?) async {
        guard let c,c==connection,canSend(text:text,mode:mode),let cap=capability else { return }
        let epoch=generation;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c)
            let r=AdvisoryRequest(contract_version:AdvisoryWire.contract,turn_id:UUID().uuidString,instance_id:a.forgeInstanceID,
                project_id:a.forgeProjectID,repository_id:a.repositoryID,conversation_id:c.conversationID,advisor_kind:mode,
                objective:text,expected_revision:revision,context_revision:cap.context_revision,selected_sources:selectedSources)
            _=try r.data()
            let intent=AdvisoryIntent(fingerprint:a.fingerprint,endpoint:a.endpoint,workspaceInstanceID:a.workspaceInstanceID,
                workspaceProjectID:a.workspaceProjectID,actorID:a.actorID,request:r,cancel:nil)
            try credentials.saveIntent(intent);pending=intent;phase="adviceSending"
            _=try await transport.submit(a,c,body:r)
            guard epoch==generation else { return }
            let value=try await transport.turn(a,c,request:r)
            guard epoch==generation else { return };try accept(value,intent:intent)
            busy=false;await refresh(c)
        } catch { if epoch==generation { fail(error) } }
    }
    private func validateRecoveryContext(_ a: AdvisoryAccess, _ c: AdvisoryConnection, intent p: AdvisoryIntent) async throws {
            let cap=try await transport.capability(a,c,sources:p.request.selected_sources)
            var currentRevision:Int
            do { currentRevision=try await transport.history(a,c).revision }
            catch AdvisoryError.missing {
                guard p.request.expected_revision==0 else { throw AdvisoryError.missing };currentRevision=0
            }
            guard cap.context_revision==p.request.context_revision,currentRevision==p.request.expected_revision else { throw AdvisoryError.state("CONVERSATION_OR_CONTEXT_STALE") }
    }

    func resume(_ c:AdvisoryConnection?) async {
        guard let c,c==connection,!busy,let p=pending else { return }
        let epoch=generation;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c);guard p.matches(a,connection:c) else { throw AdvisoryError.denied }
            var value:AdvisoryObservation?
            do { value=try await transport.turn(a,c,request:p.request) }
            catch AdvisoryError.missing {
                try await validateRecoveryContext(a, c, intent: p)
            }
            guard epoch==generation else { return }
            if let cancel=p.cancel {
                if value?.turn.status != "CANCEL_REQUESTED" { _=try await transport.cancel(a,c,request:p.request,cancel:cancel) }
            } else if value==nil || value?.turn.execution=="MAY_HAVE_HAPPENED" {
                _=try await transport.submit(a,c,body:p.request)
            }
            guard epoch==generation else { return }
            let read=try await transport.turn(a,c,request:p.request)
            guard epoch==generation else { return };try accept(read,intent:p)
        } catch { if epoch==generation { fail(error) } }
    }
    func cancel(_ c:AdvisoryConnection?) async {
        guard let c,c==connection,let p=pending,pendingForSelection,p.cancel==nil else { return }
        generation &+= 1;let epoch=generation;busy=true;defer { if epoch==generation { busy=false } }
        do {
            let a=try access(c);guard p.matches(a,connection:c) else { throw AdvisoryError.denied }
            let value=try await transport.turn(a,c,request:p.request)
            guard epoch==generation else { return }
            let cancel=AdvisoryCancelRequest(contract_version:AdvisoryWire.contract,expected_revision:value.currentRevision,request_digest:p.request.digest)
            var frozen=p;frozen.cancel=cancel;try credentials.saveIntent(frozen);pending=frozen;phase="adviceCancelIntent"
            _=try await transport.cancel(a,c,request:p.request,cancel:cancel)
            guard epoch==generation else { return }
            let read=try await transport.turn(a,c,request:p.request)
            guard epoch==generation else { return };try accept(read,intent:frozen)
        } catch { if epoch==generation { fail(error) } }
    }
}
