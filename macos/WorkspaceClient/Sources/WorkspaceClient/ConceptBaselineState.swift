import Foundation
import Combine
import CryptoKit

@MainActor final class ConceptBaselineState:ObservableObject {
    struct Journal:Codable {let key:String;let concept_id:String;let command:ConceptBaselineCommand;let source:ConceptBaselineDraftSource;let binding_id:String;let producer_source:String;var completed:Bool;var retired:Bool?=nil}
    @Published var access:ConceptBaselineAccess?
    @Published var history:[ConceptBaselineHistory.Entry]=[]
    @Published var result:ConceptBaselineResult?
    @Published var pending:Journal?
    @Published var busy=false
    @Published var phase="access"
    let transport:any ConceptBaselineServing
    let records:PrivateLocalRecordStore
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    var generation=0
    init(transport:any ConceptBaselineServing = ConceptBaselineTransport(),root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ConceptBaselineIntents")) {
        self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"concept-baseline")
    }
    func conceal() {monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;generation+=1;access=nil;history=[];result=nil;pending=nil;busy=false;phase="access"}
    func key(_ connection:ConceptConnection,_ concept:ProjectConcept)->String {
        SHA256.hash(data:Data((connection.key+"\n"+concept.actor_id+"\n"+concept.id).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func checked(_ connection:ConceptConnection,_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async throws {
        guard try await current()==connection else {throw ConceptError.denied}
        guard access==nil || WorksetReleaseWire.date(access!.expires_at).map({$0>Date()})==true else {throw ConceptError.denied}
        try concept.validate(connection.access.projectID)
    }
    func load(_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        conceal();let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let connection=try await current();try concept.validate(connection.access.projectID)
            let cap=try await transport.access(connection,concept:concept.id)
            try await checked(connection,concept,current:current)
            guard cap.contract_version=="workspace-concept-baseline/1",cap.actor_id==concept.actor_id,cap.context_id==concept.context_id,cap.concept_id==concept.id,
                  cap.document_language=="en",cap.source_revision==concept.revision,WorksetReleaseWire.date(cap.expires_at).map({$0>Date()})==true,
                  cap.producer_source.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil else {throw ConceptError.invalid}
            let previous=try await transport.history(connection,concept:concept.id)
            try await checked(connection,concept,current:current)
            guard previous.contract_version==cap.contract_version,previous.actor_id==cap.actor_id,previous.context_id==cap.context_id,
                  previous.concept_id==concept.id,previous.binding_id==cap.binding_id,previous.producer_source==cap.producer_source,
                  previous.operations.count<=256,Set(previous.operations.map(\.id)).count==previous.operations.count,
                  previous.operations.allSatisfy({$0.source_revision>0 && $0.operation_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil}) else {throw ConceptError.invalid}
            let localKey=key(connection,concept)
            let journal=try records.load(localKey).map{try JSONDecoder().decode(Journal.self,from:$0)}
            if let journal {guard journal.key==localKey,journal.concept_id==concept.id,journal.binding_id==cap.binding_id,journal.producer_source==cap.producer_source,journal.source.conceptID==concept.id,journal.source.revision==journal.command.expected_revision,journal.command.operation_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else {throw ConceptError.invalid}}
            guard ticket==generation else{return}
            guard WorksetReleaseWire.date(cap.expires_at).map({$0>Date()})==true else{throw ConceptError.denied}
            access=cap;history=previous.operations;pending=(journal?.completed==true || journal?.retired==true) ? nil:journal;phase="ready"
            expiry=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(250))
                    guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    guard WorksetReleaseWire.date(cap.expires_at).map({$0>Date()})==true else {self.conceal();return}
                }
            }
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(3))
                    guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    do {
                        try await self.checked(connection,concept,current:current)
                        let now=try await self.transport.access(connection,concept:concept.id)
                        try await self.checked(connection,concept,current:current)
                        guard self.generation==ticket else{return}
                        guard now.binding_id==cap.binding_id,now.actor_id==cap.actor_id,now.context_id==cap.context_id,now.concept_id==cap.concept_id,now.producer_source==cap.producer_source,now.expires_at==cap.expires_at else {throw ConceptError.denied}
                    } catch {if self.generation==ticket {self.conceal()};return}
                }
            }
        } catch {if ticket==generation {failure(error)}}
    }
    func failure(_ error:Error) {
        result=nil
        switch error {
        case ConceptError.denied:conceal();phase="access"
        case ConceptError.conflict:phase="conflict"
        case ConceptBaselineError.sourceRejected:phase="sourceRejected"
        case ConceptError.invalid, is DecodingError:phase="invalid"
        case ConceptError.notFound:phase="notFound"
        default:phase=pending==nil ? "unavailable":"offline"
        }
    }
    func prepare(_ source:ConceptBaselineDraftSource,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let cap=access,cap.can_prepare,source.conceptID==concept.id,(pending != nil || (concept.lifecycle != "ARCHIVED" && source.revision==concept.revision)) else{return}
        let ticket=generation;busy=true;result=nil
        defer {if ticket==generation {busy=false}}
        do {
            let connection=try await current();try await checked(connection,concept,current:current)
            guard ticket==generation else{return}
            let localKey=key(connection,concept)
            let journal:Journal
            if let pending {guard pending.key==localKey,pending.concept_id==concept.id,pending.source==source else{throw ConceptError.denied};journal=pending}
            else {
                let command=ConceptBaselineCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_revision:source.revision,description:source.chosenPurpose)
                journal=Journal(key:localKey,concept_id:concept.id,command:command,source:source,binding_id:cap.binding_id,producer_source:cap.producer_source,completed:false)
                // Durable original command before any product POST; never replace
                // an uncertain command with another operation or newer source.
                try records.save(JSONEncoder().encode(journal),key:localKey)
                pending=journal
            }
            let value:ConceptBaselineResult
            do {value=try await transport.read(connection,concept:concept.id,operation:journal.command.operation_id)}
            catch ConceptError.notFound {
                try await checked(connection,concept,current:current)
                guard ticket==generation else{return}
                value=try await transport.prepare(connection,concept:concept.id,command:journal.command)
            }
            try await checked(connection,concept,current:current)
            try value.validate(connection,concept:concept,operation:journal.command.operation_id,access:cap)
            guard ticket==generation else{return}
            var completed=journal;completed.completed=true
            try records.save(JSONEncoder().encode(completed),key:localKey)
            result=value;phase="badge";pending=nil
            // Retain original command on disk for recovery after either process
            // restart; history GET remains the authoritative proposal inventory.
            if !history.contains(where:{$0.id==value.operation_id}) {history.append(.init(operation_id:value.operation_id,source_revision:value.source_revision))}
        } catch {if ticket==generation {failure(error)}}
    }
    func retireRejected(concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,phase=="sourceRejected",let journal=pending,let cap=access else{return}
        let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let connection=try await current();try await checked(connection,concept,current:current)
            do {
                let existing=try await transport.read(connection,concept:concept.id,operation:journal.command.operation_id)
                try await checked(connection,concept,current:current)
                try existing.validate(connection,concept:concept,operation:journal.command.operation_id,access:cap)
                guard ticket==generation else{return}
                var completed=journal;completed.completed=true
                try records.save(JSONEncoder().encode(completed),key:journal.key)
                pending=nil;result=existing;phase="badge"
            } catch ConceptError.notFound {
                // Only after a definitive own source rejection plus verified
                // original absence. Unknown/lost/storage/permission errors retain
                // the uncertain original and cannot authorize a fresh request.
                try await checked(connection,concept,current:current)
                guard ticket==generation else{return}
                let archiveKey=SHA256.hash(data:Data((journal.key+"\n"+journal.command.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
                try records.save(JSONEncoder().encode(journal),key:archiveKey)
                var retired=journal;retired.retired=true
                try records.save(JSONEncoder().encode(retired),key:journal.key)
                pending=nil;result=nil;phase="ready"
            }
        } catch {if ticket==generation {failure(error)}}
    }
    func open(_ operation:String,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let cap=access else{return};let ticket=generation;busy=true;result=nil
        defer {if ticket==generation {busy=false}}
        do {
            let connection=try await current();try await checked(connection,concept,current:current)
            guard ticket==generation else{return}
            let value=try await transport.read(connection,concept:concept.id,operation:operation)
            try await checked(connection,concept,current:current);try value.validate(connection,concept:concept,operation:operation,access:cap)
            guard ticket==generation else{return};result=value;phase="badge"
        } catch {if ticket==generation {failure(error)}}
    }
}
