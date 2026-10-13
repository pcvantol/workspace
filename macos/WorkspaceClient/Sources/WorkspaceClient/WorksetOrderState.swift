import Foundation
import Combine

@MainActor final class OrderState: ObservableObject {
    @Published private(set) var access:OrderAccess?
    @Published private(set) var current:OrderCurrent?
    @Published private(set) var preview:OrderPreview?
    @Published private(set) var result:Data?
    @Published private(set) var intent:OrderIntent?
    @Published private(set) var selected=""
    @Published private(set) var proposed:[String]=[]
    @Published private(set) var busy=false
    @Published private(set) var status="grant"
    @Published private(set) var rejectionCode:String?
    let credentials:any OrderCredentials
    let store:OrderIntentStore
    let transport:any OrderServing
    private var connection:AdvisoryConnection?
    private var epoch=UUID()
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    var authority:(@MainActor () async -> AdvisoryConnection?)?
    var onApplied:(@MainActor (OrderAccess,String) async -> Void)?
    init(credentials:any OrderCredentials=OrderKeychain(),store:OrderIntentStore=OrderIntentStore(),transport:any OrderServing=OrderTransport()) {
        self.credentials=credentials;self.store=store;self.transport=transport
    }
    func invalidate() {
        epoch=UUID();monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;access=nil;connection=nil;current=nil;preview=nil;result=nil;intent=nil;selected="";proposed=[];busy=false;status="grant";rejectionCode=nil
    }
    func forget() { invalidate();do { try credentials.forget() } catch { status="invalid" } }
    private func live(_ ticket:UUID,_ access:OrderAccess) -> Bool {
        ticket==epoch && self.access==access && (WorksetReleaseWire.date(access.binding.expires_at).map{$0>Date()} ?? false)
    }
    private func failure(_ error:Error,_ ticket:UUID) {
        guard ticket==epoch else { return }
        if case AdvisoryError.denied=error { invalidate();status="denied" }
        else if case AdvisoryError.state(let code)=error { preview=nil;status=code }
        else if case AdvisoryError.invalid=error { preview=nil;status="invalid" }
        else { preview=nil;current=nil;result=nil;proposed=[];status="unavailable" }
    }
    private func authorize(_ ticket:UUID,_ access:OrderAccess) async throws {
        guard let currentOwn=await authority?(),live(ticket,access),currentOwn==connection,access.binding.matches(currentOwn),
            (try credentials.load())==access else { throw AdvisoryError.denied }
        let checked=try await transport.probe(currentOwn,token:access.binding.token)
        guard let after=await authority?(),live(ticket,access),checked==access,after==currentOwn,connection==after,(try credentials.load())==access else { throw AdvisoryError.denied }
    }
    func newProposal() {
        guard !busy,(status=="applied" && result != nil) || status=="rejected" else { return }
        intent=nil;preview=nil;rejectionCode=nil;proposed=current?.order ?? [];status="current"
    }
    func connect(_ own:AdvisoryConnection?,token:String?=nil) async {
        invalidate();guard let own else { return };let ticket=epoch;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            let saved=try credentials.load()
            guard let token=token ?? saved?.binding.token else { return }
            let access=try await transport.probe(own,token:token)
            guard ticket==epoch,access.binding.matches(own) else { return }
            try credentials.save(access);self.access=access;connection=own;status="choose"
            expiry=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(250))
                    guard !Task.isCancelled,let self,self.epoch==ticket,self.access==access else { return }
                    guard self.live(ticket,access) else { self.invalidate();self.status="denied";return }
                }
            }
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(3));guard !Task.isCancelled,let self,self.live(ticket,access) else { return }
                    do {
                        try await self.authorize(ticket,access)
                        if !self.busy,let shown=self.preview,!self.selected.isEmpty {
                            let key=self.selected
                            let fresh=try await self.transport.read(own,access:access,workset:key)
                            try await self.authorize(ticket,access)
                            guard self.live(ticket,access),self.selected==key,self.preview?.data==shown.data,!self.busy else { continue }
                            if fresh.revision != shown.current.revision || fresh.digest != shown.current.digest || fresh.fixed != shown.current.fixed || fresh.order != shown.current.order || fresh.worksetRevision != shown.current.worksetRevision {
                                self.preview=nil;self.current=fresh;self.proposed=fresh.order;self.status="ORDER_PREVIEW_STALE"
                            }
                        }
                    }
                    catch { self.failure(error,ticket);return }
                }
            }
        } catch { failure(error,ticket) }
    }
    func choose(_ value:String) async {
        guard !busy,let access,access.binding.worksets.contains(where:{$0.workset_id==value}) else { return }
        selected=value;current=nil;preview=nil;result=nil;proposed=[];intent=nil;rejectionCode=nil
        do {
            intent=try store.load(access.key(value,draft:connection!.draftGrant))
            if let intent,let cause=try store.rejectionCode(intent) { status="rejected";rejectionCode=cause }
        } catch { status="invalid";return }
        await refresh()
        if let intent,(try? store.isRejected(intent))==true { status="rejected" }
        else if intent != nil { await recover(replay:false) }
    }
    func refresh() async {
        guard !busy,let access,let connection,!selected.isEmpty else { return }
        let ticket=epoch,key=selected,shown=preview;busy=true;defer { if ticket==epoch { busy=false } }
        do {
            try await authorize(ticket,access)
            let value=try await transport.read(connection,access:access,workset:key)
            try await authorize(ticket,access)
            guard live(ticket,access),selected==key else { return }
            current=value
            if let shown {
                let changed=shown.current.revision != value.revision || shown.current.worksetRevision != value.worksetRevision || shown.current.digest != value.digest || shown.current.fixed != value.fixed
                if changed { preview=nil;proposed=value.order;status="ORDER_PREVIEW_STALE" }
            } else {
                proposed=value.order
                if let intent,let cause=try store.rejectionCode(intent) {status="rejected";rejectionCode=cause}
                else if let result,let original=try? OrderWire.object(result),let phase=original["state"] as? String {status=phase=="APPLIED" ? "applied":"pending"}
                else {status="current"}
            }
        } catch { failure(error,ticket) }
    }
    func move(_ id:String,_ delta:Int) {
        guard !busy,intent==nil,let current,let from=proposed.firstIndex(of:id),from>=current.fixed else { return }
        let to=from+delta;guard to>=current.fixed,to<proposed.count else { return }
        var value=proposed;value.swapAt(from,to)
        let members=Dictionary(uniqueKeysWithValues:current.members.map{($0.id,$0)})
        guard value.enumerated().allSatisfy({ index,id in members[id]!.dependencies.allSatisfy{value.firstIndex(of:$0).map{$0<index} ?? false} }) else { status="HARD_DEPENDENCY_ORDER_CONFLICT";return }
        proposed=value;preview=nil;result=nil;status="changed"
    }
    func showPreview() async {
        guard !busy,intent==nil,let access,let connection,let current,proposed != current.order else { return }
        let ticket=epoch,key=selected,order=proposed;busy=true;preview=nil;defer { if ticket==epoch { busy=false } }
        do {
            try await authorize(ticket,access)
            let value=try await transport.preview(connection,access:access,workset:key,proposed:order)
            try await authorize(ticket,access)
            guard live(ticket,access),selected==key,proposed==order else { return }
            preview=value;self.current=value.current;status=value.supported ? "preview":"readonly"
        } catch { failure(error,ticket) }
    }
    func cancel() { guard !busy,intent==nil else { return };preview=nil;proposed=current?.order ?? [];status="current" }
    func confirm(reason:String) async {
        guard !busy,intent==nil,let preview,preview.supported,preview.blockers.isEmpty,let access,let connection,!reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        do {
            let ticket=epoch
            try await authorize(ticket,access)
            guard self.preview?.data==preview.data,self.intent==nil,!busy else { return }
            let operation="order-"+UUID().uuidString.lowercased()
            let command=try OrderWire.command(preview,operation:operation,workset:selected,reason:reason)
            let intent=OrderIntent(scopeKey:access.key(selected,draft:connection.draftGrant),operation:operation,workset:selected,request:command)
            try store.save(intent);self.intent=intent;self.preview=nil
        } catch { status="invalid";return }
        await recover(replay:true)
    }
    func recover(replay:Bool) async {
        guard !busy,let access,let connection,let intent,intent.scopeKey==access.key(selected,draft:connection.draftGrant) else { return }
        let ticket=epoch;busy=true;defer { if ticket==epoch { busy=false } }
        var attempted=false
        do {
            if try store.isRejected(intent) { status="rejected";return }
            try await authorize(ticket,access)
            var data:Data
            do { data=try await transport.operation(connection,access:access,intent:intent,confirm:false) }
            catch AdvisoryError.state("ORDER_OPERATION_UNKNOWN") {
                guard replay else { status="uncertain";return }
                try await authorize(ticket,access)
                attempted=true
                data=try await transport.operation(connection,access:access,intent:intent,confirm:true)
            }
            if replay,try OrderWire.object(data)["state"] as? String=="PENDING" {
                try await authorize(ticket,access)
                try await authorize(ticket,access)
                attempted=true
                data=try await transport.operation(connection,access:access,intent:intent,confirm:true)
            }
            try await authorize(ticket,access)
            guard live(ticket,access),self.intent==intent else { return }
            let raw=try OrderWire.object(data);result=data
            current=try OrderWire.current(JSONSerialization.data(withJSONObject:raw["current"]!),access,selected);proposed=current!.order
            status=raw["state"] as? String=="APPLIED" ? "applied":"pending"
            if status=="applied" { await onApplied?(access,selected) }
        } catch {
            if attempted,case AdvisoryError.state(let code)=error,
                ["ORDER_PREVIEW_STALE","ORDER_UNCHANGED","CLAIMED_PREFIX_CHANGED","HARD_DEPENDENCY_ORDER_CONFLICT","ORDER_ALLOWANCE_EXHAUSTED","FUTURE_RELEASE_NOT_ELIGIBLE","ORDER_EFFECT_PREFIX_OR_EVIDENCE_CHANGED","CURRENT_SUBJECT_OR_AUTHORITY_UNAVAILABLE","ANOTHER_ORDER_INTENT_PENDING","ORDER_EFFECT_REVISION_CONFLICT","ORDER_MEMBERSHIP_CHANGED"].contains(code) {
                do {
                    try await authorize(ticket,access)
                    let original=try await transport.operation(connection,access:access,intent:intent,confirm:false)
                    try await authorize(ticket,access)
                    guard live(ticket,access),self.intent==intent else { return }
                    result=original;let raw=try OrderWire.object(original)
                    current=try OrderWire.current(JSONSerialization.data(withJSONObject:raw["current"]!),access,selected)
                    status=raw["state"] as? String=="APPLIED" ? "applied":"pending"
                    if status=="applied" { await onApplied?(access,selected) }
                    return
                } catch AdvisoryError.state("ORDER_OPERATION_UNKNOWN") {
                    do {
                        try await authorize(ticket,access)
                        guard live(ticket,access),self.intent==intent else { return }
                        try store.markRejected(intent,code:code);preview=nil;current=nil;proposed=[];status="rejected";rejectionCode=code
                        do {
                            let fresh=try await transport.read(connection,access:access,workset:selected)
                            try await authorize(ticket,access)
                            guard live(ticket,access),self.intent==intent else { return }
                            current=fresh;proposed=fresh.order
                        } catch { failure(error,ticket) }
                    } catch { failure(error,ticket) }
                    return
                } catch { failure(error,ticket);return }
            }
            failure(error,ticket)
        }
    }
}
