import Foundation
import Combine

@MainActor final class ExecutionProgressState:ObservableObject {
    @Published private(set) var overview:ExecutionEnvelope?
    @Published private(set) var detail:ExecutionRecord?
    @Published private(set) var navigation=ExecutionNavigation()
    @Published private(set) var status="choose"
    @Published private(set) var busy=false
    private let transport:any ExecutionServing
    private let records:PrivateLocalRecordStore
    private var query:ExecutionQuery?
    private var current:(@MainActor () async->AdvisoryConnection?)?
    private var generation=0
    private var foreground=false
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    private var request:Task<ExecutionEnvelope,Error>?
    private var expiresAt:Date?
    init(transport:any ExecutionServing=ExecutionProgressTransport(),root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ExecutionNavigation")) {
        self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"execution-progress")
    }
    func hide() {foreground=false;generation+=1;request?.cancel();request=nil;monitor?.cancel();monitor=nil;overview=nil;detail=nil;busy=false}
    func reset() {hide();expiry?.cancel();expiry=nil;query=nil;current=nil;navigation = .init();expiresAt=nil;status="choose"}
    func activate(_ q:ExecutionQuery,current:@escaping @MainActor () async->AdvisoryConnection?) async {
        reset();self.current=current;query=q;foreground=true
        do {
            if let raw=try records.load(q.key) {
                let nav=try JSONDecoder().decode(ExecutionNavigation.self,from:raw)
                guard (nav.mission.isEmpty ? nav.submission==nil && nav.run==nil && nav.group==nil && nav.binding.isEmpty && !nav.expanded:ActivityWire.identifier(nav.mission)),nav.submission.map(ActivityWire.identifier) ?? true,nav.run.map(ActivityWire.identifier) ?? true,nav.group.map({ActivityWire.matches($0,"^[a-f0-9]{64}$")}) ?? true,nav.binding.isEmpty || ActivityWire.identifier(nav.binding) else {throw ExecutionError.invalid}
                navigation=nav
            }
            if navigation.mission.isEmpty {status="choose"}
            else {await refresh()}
            watch()
        } catch {status="invalid"}
    }
    func choose(_ mission:String) async {
        guard let q=query,mission.isEmpty || ActivityWire.identifier(mission) else {return}
        generation+=1;request?.cancel();request=nil;busy=false;overview=nil;detail=nil
        navigation=ExecutionNavigation(mission:mission,submission:nil,binding:"",expanded:false)
        query=ExecutionQuery(connection:q.connection,activity:q.activity,workset:q.workset,mission:mission)
        if mission.isEmpty {expiresAt=nil;status="choose";try? saveNavigation()}
        else {await refresh()}
    }
    private func valid(_ ticket:Int,_ q:ExecutionQuery) async->Bool {
        guard ticket==generation,foreground,let current,let connection=await current() else {return false}
        return ticket==generation && foreground && connection==q.connection && (WorksetReleaseWire.date(q.activity.expires_at).map({$0>Date()}) ?? false)
    }
    func refresh(detailOnly:Bool=false) async {
        guard foreground,!busy,let base=query,!navigation.mission.isEmpty else {return}
        let ticket=generation
        var q=ExecutionQuery(connection:base.connection,activity:base.activity,workset:base.workset,mission:navigation.mission,binding:navigation.binding.isEmpty ? nil:navigation.binding)
        if detailOnly {
            guard let row=overview?.packet.records.first(where:{$0.id==navigation.submission}),let run=row.run_id,run==navigation.run,ActivityWire.hash(Data(row.groupKey.utf8))==navigation.group,let snapshot=overview?.packet.snapshot_id else {return}
            q.run=run;q.expectedSnapshot=snapshot
        }
        busy=true;defer {if ticket==generation {busy=false;request=nil}}
        guard await valid(ticket,q) else {if ticket==generation {deny()};return}
        let transport=self.transport;let job=Task {try await transport.read(q)};request=job
        do {
            let value=try await job.value
            guard await valid(ticket,q) else {if ticket==generation {deny()};return}
            guard WorksetReleaseWire.date(value.expires_at).map({$0>Date()})==true else {deny();return}
            try publish(value,detailOnly:detailOnly)
        } catch {if ticket==generation {failure(error)}}
    }
    private func publish(_ value:ExecutionEnvelope,detailOnly:Bool) throws {
        if detailOnly {
            guard let row=value.packet.records.first,value.packet.records.count==1,
                  row.id==navigation.submission,row.run_id==navigation.run,
                  ActivityWire.hash(Data(row.groupKey.utf8))==navigation.group else {throw ExecutionError.invalid}
        }
        expiresAt=WorksetReleaseWire.date(value.expires_at)
        if detailOnly {detail=value.packet.records.first}
        else {
            overview=value
            let selected=value.packet.records.first(where:{$0.id==navigation.submission})
            let original=selected.flatMap {row in (navigation.run==nil || row.run_id==navigation.run) && ActivityWire.hash(Data(row.groupKey.utf8))==navigation.group ? row:nil}
            detail=navigation.expanded ? original:nil
        }
        navigation.binding=value.binding_id
        let missing=navigation.submission.map {chosen in !value.packet.records.contains(where:{$0.id==chosen && (navigation.run==nil || $0.run_id==navigation.run) && ActivityWire.hash(Data($0.groupKey.utf8))==navigation.group})} ?? false
        status=missing ? "notFound":(value.packet.records.isEmpty ? "empty":"ready")
        try records.saveBounded(JSONEncoder().encode(navigation),key:query!.key,maximumRecords:64,maximumBytes:262144)
    }
    func select(_ submission:String) async {
        guard let row=overview?.packet.records.first(where:{$0.id==submission}) else {return}
        generation+=1;request?.cancel();request=nil;busy=false;detail=nil
        navigation.submission=submission;navigation.run=row.run_id;navigation.group=ActivityWire.hash(Data(row.groupKey.utf8));navigation.expanded=true
        if row.run_id != nil {await refresh(detailOnly:true)}
        else {detail=row;try? saveNavigation()}
    }
    func expanded(_ value:Bool) {navigation.expanded=value;try? saveNavigation()}
    private func saveNavigation() throws {
        guard let query else {return}
        try records.saveBounded(JSONEncoder().encode(navigation),key:query.key,maximumRecords:64,maximumBytes:262144)
    }
    private func deny() {hide();status="denied";navigation = .init()}
    private func failure(_ error:Error) {
        overview=nil;detail=nil
        switch error {
        case ExecutionError.denied:deny()
        case ExecutionError.snapshot:status="snapshot"
        case ExecutionError.unbound:status="unbound"
        case ExecutionError.notFound:status="notFound"
        case ExecutionError.unsupported:status="unsupported"
        case ExecutionError.corrupt:status="corrupt"
        case ExecutionError.invalid:status="invalid"
        default:status="unavailable"
        }
    }
    private func watch() {
        expiry?.cancel();monitor?.cancel()
        expiry=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.milliseconds(250))
                guard !Task.isCancelled,let self else {return}
                let local=self.query.flatMap {WorksetReleaseWire.date($0.activity.expires_at)}
                if [local,self.expiresAt].compactMap({$0}).contains(where:{$0<=Date()}) {self.deny();return}
            }
        }
        monitor=Task { [weak self] in
            var delay=5
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(delay));guard !Task.isCancelled,let self,self.foreground else {return}
                if self.status=="snapshot" || self.status=="notFound" {continue}
                await self.refresh();delay=self.status=="unavailable" ? min(30,delay*2):5
            }
        }
    }
}
