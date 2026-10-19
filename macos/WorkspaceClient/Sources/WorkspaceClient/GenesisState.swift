import Foundation
import CryptoKit

struct GenesisPending:Codable,Sendable {
    let kind:String;let operation:String;let source:String;let actor:String;let context:String;let concept:String;let body:Data
    var completed=false
}
@MainActor final class GenesisState:ObservableObject {
    @Published private(set) var access:GenesisAccess?
    @Published private(set) var result:GenesisEnvelope?
    @Published private(set) var pending:GenesisPending?
    @Published private(set) var busy=false
    @Published private(set) var phase="choose"
    @Published private(set) var reason=""
    @Published private(set) var expandedDocument=""
    private var presentationKey:String?
    struct Presentation:Codable {
        let actor:String;let context:String;let concept:String;let source:String;let planDigest:String
        var document:String;var reason:String
    }
    private let transport:any GenesisServing
    let records:PrivateLocalRecordStore
    private(set) var generation=0
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    private var planOperation:String?
    init(root:URL,transport:any GenesisServing=GenesisTransport()) {self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"genesis-bootstrap")}
    func conceal() {monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;generation+=1;access=nil;result=nil;pending=nil;busy=false;planOperation=nil;presentationKey=nil;reason="";expandedDocument="";phase="choose"}
    private func key(_ connection:ConceptConnection,_ concept:ProjectConcept,_ source:ConceptBaselineResult)->String {
        SHA256.hash(data:Data((connection.key+"\n"+concept.actor_id+"\n"+concept.id+"\n"+source.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private func witnessKey(_ key:String)->String {SHA256.hash(data:Data(("allocation\n"+key).utf8)).map{String(format:"%02x",$0)}.joined()}
    private func complete(_ value:GenesisPending,key:String) throws {
        var done=value;done.completed=true
        try records.saveBounded(JSONEncoder().encode(done),key:key)
    }
    private func capture(_ value:GenesisPending,key:String) throws {
        if let existing=try records.load(key) {
            let old=try JSONDecoder().decode(GenesisPending.self,from:existing)
            guard old.operation==value.operation || old.completed else {throw ConceptError.conflict}
            if old.operation != value.operation {
                let archive=SHA256.hash(data:Data((key+"/"+old.operation).utf8)).map{String(format:"%02x",$0)}.joined()
                try records.saveBounded(existing,key:archive)
            }
        }
        try records.saveBounded(Data(key.utf8),key:witnessKey(key))
        try records.saveBounded(JSONEncoder().encode(value),key:key)
    }
    private func checked(_ ticket:Int,_ connection:ConceptConnection,current:@escaping @MainActor () async throws -> ConceptConnection) async throws {
        guard ticket==generation,try await current()==connection else {throw ConceptError.denied}
        guard ticket==generation else {throw ConceptError.denied}
        if let expiry=result?.expires_at ?? access?.expires_at,WorksetReleaseWire.date(expiry).map({$0>Date()}) != true {throw ConceptError.denied}
    }
    private func failure(_ error:Error,ticket:Int) {
        guard ticket==generation else {return}
        result=nil;access=nil;expandedDocument="";reason=""
        switch error {
        case ConceptError.denied:conceal();phase="access"
        case ConceptError.conflict:phase="conflict"
        case ConceptError.notFound:phase="notObserved"
        case ConceptError.invalid,is DecodingError:phase="invalid"
        default:phase="unavailable"
        }
    }
    private func install(_ value:GenesisEnvelope,_ connection:ConceptConnection,_ concept:ProjectConcept,_ source:ConceptBaselineResult) throws {
        try value.validate(connection,concept:concept,source:source)
        restorePresentation(value,connection:connection,concept:concept,source:source)
        result=value;phase="loaded";planOperation=value.plan_operation_id
        armExpiry(value.expires_at)
    }
    private func armExpiry(_ text:String) {
        expiry?.cancel()
        guard let until=WorksetReleaseWire.date(text) else {return}
        let ticket=generation
        expiry=Task { [weak self] in
            try? await Task.sleep(for:.seconds(max(0,until.timeIntervalSinceNow)))
            guard !Task.isCancelled,let self,ticket==self.generation else {return}
            self.conceal();self.phase="access"
        }
    }
    private func restorePresentation(_ value:GenesisEnvelope,connection:ConceptConnection,concept:ProjectConcept,source:ConceptBaselineResult) {
        let k=SHA256.hash(data:Data(("presentation\n"+key(connection,concept,source)+"\n"+value.result.plan.plan_digest).utf8)).map{String(format:"%02x",$0)}.joined()
        guard k != presentationKey else {return}
        presentationKey=k;reason="";expandedDocument=""
        guard let data=try? records.load(k),let saved=try? JSONDecoder().decode(Presentation.self,from:data),
              saved.actor==concept.actor_id,saved.context==concept.context_id,saved.concept==concept.id,saved.source==source.operation_id,saved.planDigest==value.result.plan.plan_digest,saved.reason.unicodeScalars.count<=2000,
              saved.document.isEmpty || value.result.plan.documents.files.contains(where:{$0.path==saved.document}) else {return}
        reason=saved.reason;expandedDocument=saved.document
    }
    private func savePresentation() throws {
        guard let k=presentationKey,let result else {return}
        let record=Presentation(actor:result.actor_id,context:result.context_id,concept:result.concept_id,source:result.source_operation_id,planDigest:result.result.plan.plan_digest,document:expandedDocument,reason:reason)
        try records.saveBounded(JSONEncoder().encode(record),key:k)
    }
    func updateReason(_ text:String) {
        guard result != nil,text.unicodeScalars.count<=2000 else {return}
        reason=text
        do {try savePresentation()} catch {failure(error,ticket:generation)}
    }
    func chooseDocument(_ path:String,concept:ProjectConcept,source:ConceptBaselineResult,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let original=result,original.result.plan.documents.files.contains(where:{$0.path==path}) else {return}
        let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current()
            let value=try await transport.result(c,concept:concept.id,action:original.kind=="DECISION" ? "operations":"decision-access",operation:original.operation_id,body:nil)
            try await checked(ticket,c,current:current)
            guard result?.operation_id==original.operation_id,value.operation_id==original.operation_id,value.result.plan.plan_digest==original.result.plan.plan_digest else {throw ConceptError.conflict}
            try install(value,c,concept,source)
            expandedDocument=expandedDocument==path ? "":path
            try savePresentation()
        } catch {failure(error,ticket:ticket)}
    }

    func load(_ concept:ProjectConcept,source:ConceptBaselineResult,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        conceal();let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();let value=try await transport.access(c,concept:concept.id,source:source.operation_id)
            try await checked(ticket,c,current:current);try value.validate(c,concept:concept,source:source);access=value;armExpiry(value.expires_at)
            let localKey=key(c,concept,source);let data=try records.load(localKey);let witness=try records.load(witnessKey(localKey))
            if witness != nil && data==nil {throw ConceptError.unavailable}
            if let data {
                guard witness==Data(localKey.utf8) else {throw ConceptError.unavailable}
                let prior=try JSONDecoder().decode(GenesisPending.self,from:data)
                guard prior.source==source.operation_id,prior.actor==concept.actor_id,prior.context==concept.context_id,prior.concept==concept.id,["PLAN","DECISION"].contains(prior.kind),prior.operation.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else {throw ConceptError.invalid}
                pending=prior.completed ? nil:prior
                let original=try await transport.result(c,concept:concept.id,action:"operations",operation:prior.operation,body:nil)
                try await checked(ticket,c,current:current);try install(original,c,concept,source);try complete(prior,key:localKey);pending=nil
                planOperation=prior.kind=="PLAN" ? prior.operation:value.plans.first(where:{$0.plan_id==original.result.plan.plan_id})?.operation_id
            } else if let latest=value.latest {
                planOperation=latest.operation_id
                let active=try await transport.result(c,concept:concept.id,action:"decision-access",operation:latest.operation_id,body:nil)
                try await checked(ticket,c,current:current);try install(active,c,concept,source)
            } else {phase="choose"}
            startMonitor(concept,source:source,connection:c,ticket:ticket,current:current)
        } catch {failure(error,ticket:ticket)}
    }
    private func startMonitor(_ concept:ProjectConcept,source:ConceptBaselineResult,connection:ConceptConnection,ticket:Int,current:@escaping @MainActor () async throws -> ConceptConnection) {
        monitor?.cancel()
        var reference=result.map{($0.kind,$0.operation_id)}
        monitor=Task { [weak self] in
            while !Task.isCancelled {
                do {try await Task.sleep(for:.seconds(3))} catch {return}
                guard let self,ticket==self.generation else {return}
                if self.busy {continue}
                if let currentResult=self.result {reference=(currentResult.kind,currentResult.operation_id)}
                guard let original=reference else {
                    do {
                        let cap=try await self.transport.access(connection,concept:concept.id,source:source.operation_id)
                        try await self.checked(ticket,connection,current:current);try cap.validate(connection,concept:concept,source:source)
                        guard !self.busy,self.result==nil else {continue}
                        self.access=cap;self.phase="choose";self.armExpiry(cap.expires_at)
                    } catch {self.failure(error,ticket:ticket)}
                    continue
                }
                do {
                    let action=original.0=="DECISION" ? "operations":"decision-access"
                    let operation=original.0=="DECISION" ? original.1:(self.planOperation ?? original.1)
                    let value=try await self.transport.result(connection,concept:concept.id,action:action,operation:operation,body:nil)
                    try await self.checked(ticket,connection,current:current)
                    guard !self.busy,self.result==nil || self.result?.operation_id==original.1 else {continue}
                    try self.install(value,connection,concept,source)
                } catch {
                    if case ConceptError.denied=error {self.failure(error,ticket:ticket);return}
                    self.failure(error,ticket:ticket)
                }
            }
        }
    }
    private func send(_ value:GenesisPending,_ concept:ProjectConcept,_ source:ConceptBaselineResult,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy else {return};let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();try await checked(ticket,c,current:current)
            guard value.actor==concept.actor_id,value.context==concept.context_id,value.concept==concept.id,value.source==source.operation_id else {throw ConceptError.denied}
            // Persist exact original command before any POST. Reads/restarts never
            // allocate another ID or repeat a dispatch automatically.
            try capture(value,key:key(c,concept,source));pending=value
            let reply=try await transport.result(c,concept:concept.id,action:value.kind=="PLAN" ? "plans":"decisions",operation:nil,body:value.body)
            try await checked(ticket,c,current:current);try install(reply,c,concept,source)
            guard reply.operation_id==value.operation else {throw ConceptError.invalid}
            try complete(value,key:key(c,concept,source));pending=nil
            if value.kind=="PLAN" {
                planOperation=value.operation
                let active=try await transport.result(c,concept:concept.id,action:"decision-access",operation:value.operation,body:nil)
                try await checked(ticket,c,current:current);try install(active,c,concept,source)
            }
            startMonitor(concept,source:source,connection:c,ticket:ticket,current:current)
        } catch {failure(error,ticket:ticket)}
    }
    func prepare(_ concept:ProjectConcept,source:ConceptBaselineResult,target:String,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard pending==nil,let access,access.can_plan,access.targets.contains(where:{$0.id==target}) else {return}
        let command=GenesisPlanCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),source_operation_id:source.operation_id,expected_concept_revision:concept.revision,selection_digest:access.selection_digest,target_id:target)
        do {
            let p=GenesisPending(kind:"PLAN",operation:command.operation_id,source:source.operation_id,actor:concept.actor_id,context:concept.context_id,concept:concept.id,body:try JSONEncoder().encode(command))
            await send(p,concept,source,current:current)
        } catch {failure(error,ticket:generation)}
    }
    func decide(_ concept:ProjectConcept,source:ConceptBaselineResult,decision:String,reason:String,expectedSelection:String,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard pending==nil,let result,result.can_decide==true,result.selection_digest==expectedSelection,let planOperation,
              decision != "APPROVE_EFFECT" || result.can_approve==true,
              ["APPROVE_EFFECT","REQUEST_CHANGES"].contains(decision),!reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,reason.unicodeScalars.count<=2000 else {return}
        let command=GenesisEffectCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),source_operation_id:source.operation_id,expected_concept_revision:concept.revision,selection_digest:expectedSelection,plan_operation_id:planOperation,decision:decision,reason:reason)
        do {
            let p=GenesisPending(kind:"DECISION",operation:command.operation_id,source:source.operation_id,actor:concept.actor_id,context:concept.context_id,concept:concept.id,body:try JSONEncoder().encode(command))
            await send(p,concept,source,current:current)
        } catch {failure(error,ticket:generation)}
    }
    func resume(_ concept:ProjectConcept,source:ConceptBaselineResult,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard let pending else {return}
        await send(pending,concept,source,current:current)
    }
    func open(_ operation:String,concept:ProjectConcept,source:ConceptBaselineResult,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,pending==nil else {return};let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();let value=try await transport.result(c,concept:concept.id,action:"decision-access",operation:operation,body:nil)
            try await checked(ticket,c,current:current);try install(value,c,concept,source);planOperation=operation
        } catch {failure(error,ticket:ticket)}
    }
}
