import Foundation
import Combine

@MainActor final class ActivityState: ObservableObject {
    @Published private(set) var access: ActivityAccess?
    @Published private(set) var pages: [ActivityPage] = []
    @Published private(set) var selected = ""
    @Published private(set) var detail: ActivityEvent?
    @Published private(set) var status = "choose"
    @Published private(set) var busy = false
    @Published private(set) var historical = false
    @Published private(set) var journal = ActivityJournal()
    private let transport: any ActivityServing
    private let credentials: any ActivityCredentials
    private let store: ActivityLocalStore
    private var epoch = UUID()
    private var monitor: Task<Void,Never>?
    private var expiry: Task<Void,Never>?
    private var connection: AdvisoryConnection?
    init(transport:any ActivityServing=ActivityTransport(),credentials:any ActivityCredentials=ActivityKeychain(),store:ActivityLocalStore=ActivityLocalStore()) {
        self.transport=transport;self.credentials=credentials;self.store=store
    }
    var events: [ActivityEvent] { pages.flatMap(\.events) }
    var complete: Bool { pages.last?.hasMore == false && !pages.isEmpty && !historical }
    var newIDs: Set<String> { journal.comparisonKnown && complete ? Set(events.map(\.id)).subtracting(journal.lastViewedIDs) : [] }
    private func key(_ access: ActivityAccess, _ connection: AdvisoryConnection) -> String { access.key(selected,draft:connection.draftGrant) }
    private func live(_ ticket:UUID,_ access:ActivityAccess) -> Bool {
        ticket==epoch && self.access==access && (WorksetReleaseWire.date(access.expires_at).map {$0>Date()} ?? false)
    }
    func invalidate() {
        epoch=UUID();monitor?.cancel();expiry?.cancel();monitor=nil;expiry=nil
        access=nil;pages=[];detail=nil;selected="";connection=nil;journal = .init();busy=false;historical=false;status="denied"
    }
    private func failure(_ error:Error,_ ticket:UUID) {
        guard ticket==epoch else { return }
        if let access,!live(ticket,access) { invalidate();return }
        if case AdvisoryError.denied=error { invalidate();return }
        historical = !pages.isEmpty;detail=nil
        if case AdvisoryError.state(let code)=error { status=code=="RESYNC_REQUIRED" ? "resync":code=="UNSUPPORTED" ? "unsupported":code=="ACTIVITY_HISTORY_PARTIAL_CAPACITY" ? "capacity":code=="ACTIVITY_HISTORY_SOURCE_INVALID" || code=="ACTIVITY_INVALID_RESPONSE" ? "invalid":"unavailable" }
        else { status="unavailable" }
    }
    func connect(_ connection:AdvisoryConnection?, token:String?=nil) async {
        invalidate();guard let connection else { return }
        let ticket=epoch;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            guard let saved=try credentials.load(),saved.matches(connection) || token != nil else {
                if let token { try await pair(token,connection,ticket);return };status="grant";return
            }
            let checked=try await transport.probe(connection,token:token ?? saved.token)
            guard ticket==epoch else { return }
            guard token != nil || checked==saved else { throw AdvisoryError.denied }
            try credentials.save(checked);accept(checked,connection)
        } catch { failure(error,ticket) }
    }
    func reauthorize(_ own:AdvisoryConnection?) async {
        guard let own,let access,access.matches(own),connection==own else { await connect(own);return }
        let ticket=epoch
        do {
            let checked=try await transport.probe(own,token:access.token)
            guard live(ticket,access) else { return };guard checked==access else { throw AdvisoryError.denied }
        } catch { failure(error,ticket) }
    }
    private func pair(_ token:String,_ connection:AdvisoryConnection,_ ticket:UUID) async throws {
        let checked=try await transport.probe(connection,token:token)
        guard ticket==epoch else { return };try credentials.save(checked);accept(checked,connection)
    }
    private func accept(_ access:ActivityAccess,_ connection:AdvisoryConnection) {
        guard (WorksetReleaseWire.date(access.expires_at).map {$0>Date()} ?? false) else { invalidate();return }
        self.access=access;self.connection=connection;status="choose"
        let ticket=epoch
        expiry=Task { [weak self] in
            while !Task.isCancelled {
                guard let self,self.live(ticket,access) else { self?.invalidate();return }
                try? await Task.sleep(for:.milliseconds(250))
            }
        }
        monitor=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(5));guard !Task.isCancelled,let self,self.live(ticket,access) else { return }
                do {
                    let fresh=try await self.transport.probe(connection,token:access.token)
                    guard self.live(ticket,access) else { return };guard fresh==access else { throw AdvisoryError.denied }
                } catch { self.failure(error,ticket) }
            }
        }
    }
    func choose(_ workset:String) async {
        guard !busy,let access,let connection,access.worksets.contains(where:{$0.workset_id==workset}) else { return }
        selected=workset;detail=nil;pages=[];historical=false;journal = .init()
        let ticket=epoch;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            let fresh=try await transport.probe(connection,token:access.token)
            guard live(ticket,access) else { return };guard fresh==access else { throw AdvisoryError.denied }
            let key=key(access,connection),loaded=try store.load(key)
            var display=loaded
            if display.pageKeys.isEmpty { display.pageKeys=display.historicalKeys }
            let cached=try store.pages(display,key).map { try ActivityWire.page($0,access:access,workset:workset) }
            try checkSeries(cached)
            guard live(ticket,access),selected==workset else { if ticket==epoch { invalidate() };return }
            journal=loaded;pages=cached;historical = !cached.isEmpty
        } catch { failure(error,ticket);return }
        busy=false
        // Incomplete progress resumes its original producer cursor. A completed view starts a fresh observation.
        await fetch(restart:journal.complete || journal.pageKeys.isEmpty)
    }
    private func checkSeries(_ values:[ActivityPage]) throws {
        guard values.count<=8,Set(values.flatMap(\.events).map(\.id)).count==values.flatMap(\.events).count,
            values.dropLast().allSatisfy(\.hasMore),Set(values.map(\.watermark)).count<=1 else { throw AdvisoryError.state("RESYNC_REQUIRED") }
    }
    func fetch(restart:Bool=false) async {
        guard !busy,let access,let connection,!selected.isEmpty else { return }
        let ticket=epoch,workset=selected;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            let fresh=try await transport.probe(connection,token:access.token)
            guard live(ticket,access) else { return };guard fresh==access else { throw AdvisoryError.denied }
            var comparisonWatermark:String?
            if restart,journal.comparisonKnown,let original=journal.previousCursor {
                let confirmed=try await transport.page(connection,access:access,workset:workset,cursor:original)
                guard live(ticket,access),selected==workset else { return }
                comparisonWatermark=confirmed.watermark
            }
            let response=try await transport.page(connection,access:access,workset:workset,cursor:restart ? nil:journal.cursor)
            guard live(ticket,access),selected==workset else { return }
            if let comparisonWatermark,comparisonWatermark != response.watermark { throw AdvisoryError.state("RESYNC_REQUIRED") }
            let combined=restart ? [response]:pages+[response];try checkSeries(combined)
            guard combined.flatMap(\.events).count<=128 else { throw AdvisoryError.invalid }
            var updated=journal
            if restart { updated.pageKeys=[] }
            let pageKey=ActivityWire.hash(Data((key(access,connection)+"/"+String(combined.count)+"/"+response.watermark).utf8))
            updated.pageKeys.append(pageKey);updated.cursor=response.cursor;updated.complete = !response.hasMore
            try store.commit(updated,key(access,connection),page:response.data,pageKey:pageKey)
            guard live(ticket,access),selected==workset else { if ticket==epoch { invalidate() };return }
            journal=updated;pages=combined;historical=false;status=response.hasMore ? "more":"ready"
        } catch {
            guard ticket==epoch else { return }
            guard live(ticket,access),selected==workset else { invalidate();return }
            if case AdvisoryError.state("RESYNC_REQUIRED")=error {
                var updated=journal;if !updated.pageKeys.isEmpty { updated.historicalKeys=updated.pageKeys };updated.cursor=nil;updated.pageKeys=[];updated.complete=false;updated.comparisonKnown=false
                do {
                    try store.save(updated,key(access,connection))
                    guard live(ticket,access),selected==workset else { if ticket==epoch { invalidate() };return }
                    journal=updated
                } catch { failure(error,ticket);return }
            }
            failure(error,ticket)
        }
    }
    // Explicit foreground action only after every retained page has actually been displayed.
    func rememberDisplayed(visible:Bool) async {
        guard visible,!busy,complete,let access,let connection else { return }
        let ticket=epoch;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            let fresh=try await transport.probe(connection,token:access.token)
            guard live(ticket,access) else { return };guard fresh==access else { throw AdvisoryError.denied }
            var value=journal;value.lastViewedIDs=events.map(\.id);value.previousCursor=journal.cursor;value.comparisonKnown=true
            try store.save(value,key(access,connection))
            guard live(ticket,access) else { if ticket==epoch { invalidate() };return }
            journal=value;status="remembered"
        } catch { failure(error,ticket) }
    }
    func open(_ id:String) async {
        guard !busy,let access,let connection,events.contains(where:{$0.id==id}) else { return }
        let ticket=epoch,workset=selected;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            let response=try await transport.detail(connection,access:access,workset:workset,id:id)
            guard live(ticket,access),workset==selected else { return };detail=response
        } catch { failure(error,ticket) }
    }
    func forget() { invalidate();do { try credentials.forget() } catch { status="unavailable" } }
}
