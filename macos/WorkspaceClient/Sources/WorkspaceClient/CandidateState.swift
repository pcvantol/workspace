import Foundation
import Combine

@MainActor final class CandidateState:ObservableObject {
    @Published private(set) var local=CandidateLocal()
    @Published private(set) var source:CandidateSource?
    @Published private(set) var preview:CandidatePreview?
    @Published private(set) var registration:CandidateRegistration?
    @Published private(set) var capability:CandidateCapability?
    @Published private(set) var phase="candidateReadOnly"
    @Published private(set) var busy=false
    @Published private(set) var hasGrant=false
    @Published private(set) var localDurable=true
    @Published private(set) var confirmation:CandidateRegistrationRequest?
    @Published var open=false
    private var connection:AdvisoryConnection?
    private var epoch=0
    private let credentials:any CandidateCredentials
    private let store:any CandidateLocalStore
    private let transport:CandidateTransport
    init(credentials:any CandidateCredentials=CandidateKeychain(),store:any CandidateLocalStore=PrivateCandidateLocalStore(),transport:CandidateTransport=CandidateTransport()) {
        self.credentials=credentials;self.store=store;self.transport=transport
    }
    var pending:Bool { local.saveIntent != nil || local.registrationPending }
    func invalidate() {
        epoch &+= 1;connection=nil;local=CandidateLocal();localDurable=true;clear();open=false;busy=false;hasGrant=false;phase="candidateReadOnly"
    }
    func suspend() { epoch &+= 1;clear();busy=false;hasGrant=false;phase="candidateOffline" }
    private func clear() { source=nil;preview=nil;registration=nil;capability=nil;confirmation=nil }
    private func access(_ c:AdvisoryConnection) throws -> CandidateAccess {
        guard let a=try credentials.load(),a.matches(c) else { throw AdvisoryError.denied };return a
    }
    private func admit(_ c:AdvisoryConnection?) throws -> AdvisoryConnection {
        guard let c else { invalidate();throw AdvisoryError.denied }
        if connection != c {
            invalidate();connection=c
            local=try store.load(CandidateLocal.scopeKey(c)) ?? CandidateLocal();local.key=CandidateLocal.scopeKey(c)
        }
        return c
    }
    private func persist(_ value:CandidateLocal) throws { try store.save(value);local=value;localDurable=true }
    func edit(_ key:String,_ text:String) {
        guard connection != nil,!busy else { return }
        var v=local;v.form.text[key]=text;confirmation=nil
        do { try persist(v) } catch { local=v;localDurable=false;phase="candidateLocalCapacity" }
    }
    func chooseProposal(_ id:String) async {
        guard !busy,!pending,capability?.proposal_ids.contains(id)==true else { return }
        var v=local;v.proposalID=id;v.revision=0;v.registrationIntent=nil;confirmation=nil;preview=nil;registration=nil
        do { try persist(v);await refresh(connection) } catch { fail(error) }
    }
    func chooseRevision(_ revision:Int) async {
        guard !busy,!pending,(1...8).contains(revision),let c=connection,let id=local.proposalID else { return }
        let e=epoch;busy=true;defer{if epoch==e { busy=false }}
        do {
            let a=try access(c),p=try await transport.preview(a,c,id:id,revision:revision)
            guard e==epoch else { return }
            var v=local;v.revision=revision;try persist(v);preview=p;registration=p.registration;confirmation=nil;phase="candidateSaved"
        } catch { if epoch==e { fail(error) } }
    }
    func begin(_ turn:AdvisoryTurnRecord,connection new:AdvisoryConnection?) async {
        guard turn.status=="COMPLETE",turn.execution=="CONFIRMED",turn.outcome?.output != nil else { return }
        var admittedEpoch=epoch
        do {
            let c=try admit(new);guard !busy else { return };admittedEpoch=epoch
            if let current=local.turnID,current != turn.request.turn_id,pending { phase="candidatePending";open=true;return }
            if local.turnID != turn.request.turn_id {
                var v=local;v.turnID=turn.request.turn_id;v.proposalID=nil;v.revision=0;v.registrationIntent=nil;try persist(v)
            }
            open=true;await refresh(c)
            guard admittedEpoch==epoch else { return }
            if let s=source {
                guard s.matches(turn) else { throw AdvisoryError.invalid }
            }
        } catch { if admittedEpoch==epoch { fail(error) } }
    }
    func saveGrant(_ token:String,connection new:AdvisoryConnection?) async {
        var admittedEpoch=epoch
        do {
            let c=try admit(new);guard !busy else { return };admittedEpoch=epoch;busy=true
            defer{if epoch==admittedEpoch { busy=false }}
            let a=try await transport.probe(c,token:token)
            guard epoch==admittedEpoch else { return };try credentials.save(a);hasGrant=true
        } catch { if epoch==admittedEpoch { fail(error) } }
        guard epoch==admittedEpoch else { return }
        await refresh(new)
    }
    func forgetGrant() {
        guard !busy else { return }
        do { try credentials.forget();suspend();phase="candidateReadOnly" } catch { fail(error) }
    }
    private func fail(_ error:Error) {
        clear()
        switch error {
        case AdvisoryError.denied:hasGrant=false;phase="candidateDenied"
        case AdvisoryError.invalid:phase="candidateInvalid"
        case AdvisoryError.missing:phase=pending ? "candidateUncertain":"candidateMissing"
        case AdvisoryError.state(let code):
            if code.contains("CAPACITY") || code.contains("BUDGET") || code.contains("KEY_LIMIT") { phase="candidateCapacity" }
            else if code.contains("PENDING") { phase="candidatePending" }
            else if code.contains("STALE") || code.contains("CONFLICT") { phase="candidateConflict" }
            else if code.contains("UNSUPPORTED") { phase="candidateUnsupported" }
            else { phase=pending ? "candidateUncertain":"candidateOffline" }
        default:phase=pending ? "candidateUncertain":"candidateOffline"
        }
    }
    private func observe(_ value:CandidateRegistration) throws {
        var v=local;v.registrationPending=false;try persist(v);registration=value
        phase="candidateRegistered"
    }
    func refresh(_ new:AdvisoryConnection?) async {
        let c:AdvisoryConnection
        do { c=try admit(new) } catch { fail(error);return }
        guard !busy else { return };let e=epoch;busy=true;defer{if e==epoch { busy=false }}
        do {
            guard try credentials.load() != nil else { hasGrant=false;clear();phase="candidateReadOnly";return }
            let a=try access(c);let cap=try await transport.capability(a,c)
            guard e==epoch else { return };capability=cap;hasGrant=true
            if let t=local.turnID {
                let s=try await transport.source(a,c,turn:t)
                guard e==epoch else { return };source=s
            }
            if let r=local.saveIntent {
                do {
                    let p=try await transport.preview(a,c,id:r.proposal_id,revision:r.expected_revision+1)
                    guard e==epoch else { return }
                    guard CandidateWire.matches(p.proposal,r) else { throw AdvisoryError.state("PROPOSAL_CONFLICT") }
                    var v=local;v.revision=p.proposal.proposal_revision;v.saveIntent=nil;try persist(v);preview=p;phase="candidateSaved"
                } catch AdvisoryError.missing { phase="candidateUncertain" }
            } else if let id=local.proposalID {
                do {
                    let p=try await transport.preview(a,c,id:id,revision:max(1,local.revision))
                    guard e==epoch else { return }
                    var v=local;if v.revision==0 { v.revision=p.proposal.proposal_revision };try persist(v);preview=p;registration=p.registration;phase="candidateSaved"
                } catch AdvisoryError.missing { preview=nil;registration=nil;phase="candidateEditing" }
            } else { phase="candidateEditing" }
            if let r=local.registrationIntent {
                do {
                    let value=try await transport.operation(a,c,body:r)
                    guard e==epoch else { return }
                    if let value { try observe(value) } else { phase="candidatePending" }
                } catch AdvisoryError.missing { phase=local.registrationPending ? "candidateUncertain":phase }
            }
        } catch { if e==epoch { fail(error) } }
    }
    var canSave:Bool {
        !busy && !pending && localDurable && hasGrant && source != nil && local.proposalID != nil && (try? local.form.fields()) != nil && local.revision<8
    }
    func save() async {
        guard canSave,let c=connection,let s=source,let id=local.proposalID else { return }
        let e=epoch;busy=true;defer{if e==epoch { busy=false }}
        do {
            let a=try access(c),fresh=try await transport.source(a,c,turn:s.turn_id)
            guard e==epoch else { return };guard fresh==s else { throw AdvisoryError.state("SOURCE_STALE") }
            let r=CandidateSaveRequest(contract_version:CandidateWire.contract,instance_id:a.forgeInstanceID,project_id:a.forgeProjectID,repository_id:a.repositoryID,
                conversation_id:c.conversationID,proposal_id:id,turn_id:s.turn_id,expected_revision:local.revision,expected_conversation_revision:s.conversation_revision,
                context_revision:s.context_revision,fields:try local.form.fields())
            var v=local;v.saveIntent=r;try persist(v);phase="candidateSaving"
            let saved=try await transport.save(a,c,body:r)
            guard e==epoch else { return }
            let p=try await transport.preview(a,c,id:id,revision:saved.proposal_revision)
            guard e==epoch else { return };guard p.proposal==saved else { throw AdvisoryError.invalid }
            v=local;v.revision=saved.proposal_revision;v.saveIntent=nil;try persist(v);preview=p;registration=p.registration;phase="candidateSaved"
        } catch { if e==epoch { fail(error) } }
    }
    func prepareRegistration() async {
        guard !busy,!pending,let c=connection,let p=preview else { return }
        let e=epoch;busy=true;defer{if e==epoch { busy=false }}
        do {
            let a=try access(c),current=try await transport.preview(a,c,id:p.proposal.proposal_id,revision:p.proposal.proposal_revision)
            guard e==epoch else { return }
            let fresh=try await transport.source(a,c,turn:p.proposal.source.turn_id)
            guard e==epoch else { return }
            guard current.proposal==p.proposal,current.latest_revision==p.proposal.proposal_revision,fresh==p.proposal.source else { throw AdvisoryError.state("PROPOSAL_STALE") }
            preview=current
            confirmation=p.proposal.registrationRequest(operationID:"candidate-"+UUID().uuidString.lowercased())
        } catch { if e==epoch { fail(error) } }
    }
    func saveGrantSelection(_ token:String) async { await saveGrant(token,connection:connection) }
    func refreshSelection() async { await refresh(connection) }
    func loadSelectedFields() {
        guard !busy,!pending,let p=preview else { return }
        var v=local;v.form=CandidateForm(p.proposal.fields)
        do { try persist(v);confirmation=nil } catch { phase="candidateLocalCapacity" }
    }
    func cancelConfirmation() { confirmation=nil }
    func register() async {
        guard !busy,!pending,let r=confirmation,let c=connection else { return }
        confirmation=nil;let e=epoch;busy=true;defer{if e==epoch { busy=false }}
        do {
            let a=try access(c),p=try await transport.preview(a,c,id:r.proposal_id,revision:r.proposal_revision)
            guard e==epoch else { return }
            let s=try await transport.source(a,c,turn:p.proposal.source.turn_id)
            guard e==epoch else { return }
            guard p.proposal.proposal_digest==r.proposal_digest,p.latest_revision==r.proposal_revision,s.context_revision==r.context_revision,s.conversation_revision==r.expected_conversation_revision else { throw AdvisoryError.state("PROPOSAL_STALE") }
            var v=local;v.registrationIntent=r;v.registrationPending=true;try persist(v);phase="candidateRegistering"
            _=try await transport.register(a,c,body:r)
            guard e==epoch else { return }
            guard let actual=try await transport.operation(a,c,body:r) else { throw AdvisoryError.state("PENDING") }
            guard e==epoch else { return };try observe(actual)
        } catch { if e==epoch { fail(error) } }
    }
    func recover() async {
        guard !busy,pending,let c=connection else { return }
        await refresh(c)
        guard !busy,pending else { return };let e=epoch;busy=true;defer{if e==epoch { busy=false }}
        do {
            let a=try access(c)
            if let r=local.saveIntent {
                let s=try await transport.source(a,c,turn:r.turn_id)
                guard e==epoch else { return }
                guard s.context_revision==r.context_revision,s.conversation_revision==r.expected_conversation_revision else { throw AdvisoryError.state("SOURCE_STALE") }
                _=try await transport.save(a,c,body:r)
            } else if local.registrationPending,let r=local.registrationIntent {
                _=try await transport.register(a,c,body:r)
            }
            guard e==epoch else { return };busy=false;await refresh(c)
        } catch { if e==epoch { fail(error) } }
    }
}
