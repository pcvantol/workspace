import Foundation
import Combine
import CryptoKit

@MainActor final class ProposalContentState:ObservableObject {
    struct Journal:Codable {let key:String;let binding_id:String;let producer_source:String;let subject:ProposalContentSubject;let command:ProposalContentCommand;var completed:Bool;var rejected:Bool}
    @Published var result:ProposalContentResult?
    @Published var pending:Journal?
    @Published var confirmation:ProposalContentCommand?
    @Published var busy=false
    @Published var phase="choose"
    let transport:any ProposalContentServing
    let records:PrivateLocalRecordStore
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    private var generation=0
    var focusGeneration:Int {generation}
    init(transport:any ProposalContentServing = ProposalContentTransport(),root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ProposalContentIntents")) {
        self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"proposal-content")
    }
    func conceal() {monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;generation+=1;result=nil;confirmation=nil;pending=nil;busy=false;phase="choose"}
    func cancelConfirmation() {confirmation=nil}
    func key(_ connection:ConceptConnection,_ concept:ProjectConcept,_ source:ConceptBaselineResult)->String {
        SHA256.hash(data:Data((connection.key+"\n"+concept.actor_id+"\n"+concept.id+"\n"+source.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func witnessKey(_ key:String)->String {SHA256.hash(data:Data(("allocation\n"+key).utf8)).map{String(format:"%02x",$0)}.joined()}
    private func checked(_ connection:ConceptConnection,current:@escaping @MainActor () async throws -> ConceptConnection) async throws {
        guard try await current()==connection else {throw ConceptError.denied}
        if let result,WorksetReleaseWire.date(result.expires_at).map({$0>Date()}) != true {throw ConceptError.denied}
    }
    private func failure(_ error:Error) {
        result=nil;confirmation=nil
        switch error {
        case ConceptError.denied:conceal();phase="access"
        case ConceptError.conflict:phase="conflict"
        case ConceptError.invalid,is DecodingError:phase="invalid"
        case ProposalContentError.unsupportedProfile:phase="unsupported"
        case ProposalContentError.capacity,AdvisoryError.state("LOCAL_CAPACITY_EXHAUSTED"):phase="capacity"
        default:phase="unavailable"
        }
    }
    func load(_ source:ConceptBaselineResult,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        conceal();let ticket=generation;busy=true
        defer {if generation==ticket {busy=false}}
        do {
            let connection=try await current()
            let value=try await transport.proposal(connection,concept:concept.id,source:source.operation_id)
            try await checked(connection,current:current);try value.validate(connection,concept:concept,source:source)
            guard ticket==generation else{return}
            let localKey=key(connection,concept,source);let original=try records.load(localKey);let witness=try records.load(witnessKey(localKey))
            guard (original==nil)==(witness==nil),witness==nil || witness==Data(localKey.utf8) else {throw ConceptError.unavailable}
            var journal=try original.map{try JSONDecoder().decode(Journal.self,from:$0)}
            if var saved=journal {
                guard saved.key==localKey,saved.binding_id==value.binding_id,saved.producer_source==value.producer_source,saved.subject==value.decision.subject,saved.command.source_operation_id==source.operation_id else {throw ConceptError.denied}
                if value.rejected_operations.contains(saved.command.operation_id) {saved.rejected=true;try records.saveBounded(JSONEncoder().encode(saved),key:localKey);journal=saved}
                if saved.completed && !value.decision.history.contains(where:{$0.request.operation_id==saved.command.operation_id}) {throw ConceptError.unavailable}
            }
            if let original=value.pending_operations.first {
                guard value.pending_operations.count==1,original.command.operation_id==original.operation_id,original.command.source_operation_id==source.operation_id else {throw ConceptError.unavailable}
                if let saved=journal,saved.command.operation_id != original.operation_id {
                    guard saved.completed || saved.rejected else {throw ConceptError.unavailable}
                    let archive=SHA256.hash(data:Data((localKey+"\n"+saved.command.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
                    try records.saveBounded(JSONEncoder().encode(saved),key:archive);journal=nil
                }
                if let saved=journal {guard saved.command==original.command else {throw ConceptError.invalid}}
                else {
                    journal=Journal(key:localKey,binding_id:value.binding_id,producer_source:value.producer_source,subject:value.decision.subject,command:original.command,completed:false,rejected:false)
                    try records.saveBounded(Data(localKey.utf8),key:witnessKey(localKey));try records.saveBounded(JSONEncoder().encode(journal!),key:localKey)
                }
            }
            result=value;pending=journal.flatMap{($0.completed || $0.rejected) ? nil:$0};phase="ready"
            watch(value,connection:connection,source:source,concept:concept,ticket:ticket,current:current)
        } catch {if ticket==generation {failure(error)}}
    }
    private func watch(_ value:ProposalContentResult,connection:ConceptConnection,source:ConceptBaselineResult,concept:ProjectConcept,ticket:Int,current:@escaping @MainActor () async throws -> ConceptConnection) {
        expiry=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.milliseconds(250))
                guard !Task.isCancelled,let self,self.generation==ticket else{return}
                if WorksetReleaseWire.date(value.expires_at).map({$0>Date()}) != true {self.conceal();self.phase="access";return}
            }
        }
        monitor=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(5))
                guard !Task.isCancelled,let self,self.generation==ticket else{return}
                do {
                    if self.busy {continue}
                    try await self.checked(connection,current:current)
                    let now=try await self.transport.proposal(connection,concept:concept.id,source:source.operation_id)
                    try await self.checked(connection,current:current);try now.validate(connection,concept:concept,source:source)
                    guard self.generation==ticket else{return}
                    guard now.binding_id==value.binding_id,now.human_binding==value.human_binding,now.roles==value.roles,now.permissions==value.permissions,now.expires_at==value.expires_at,now.decision.subject==value.decision.subject else {throw ConceptError.denied}
                    if self.result?.selection_digest != now.selection_digest {self.confirmation=nil}
                    self.result=now
                } catch {if self.generation==ticket {self.failure(error)};return}
            }
        }
    }
    func stage(role:String,choice:String,reason:String,acknowledged:Bool,concept:ProjectConcept) {
        confirmation=nil
        guard !busy,pending==nil,let value=result,value.permissions.contains("DECIDE"),value.roles.contains(role),concept.lifecycle != "ARCHIVED",concept.revision==value.current_revision,
              ["APPROVE_CONTENT","REQUEST_CHANGES"].contains(choice),!reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,reason.unicodeScalars.count<=2000,ProjectConcept.validText(reason),acknowledged || value.decision.open_points.isEmpty,
              WorksetReleaseWire.date(value.expires_at).map({$0>Date()})==true else{return}
        confirmation=ProposalContentCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),source_operation_id:value.source_operation_id,expected_concept_revision:concept.revision,selection_digest:value.selection_digest,role:role,decision:choice,reason:reason,acknowledged_open_points:value.decision.open_points)
    }
    func confirm(_ source:ConceptBaselineResult,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let command=confirmation,let value=result,command.selection_digest==value.selection_digest else{return}
        confirmation=nil;let ticket=generation;busy=true
        defer {if generation==ticket {busy=false}}
        do {
            let connection=try await current();try await checked(connection,current:current)
            let now=try await transport.proposal(connection,concept:concept.id,source:source.operation_id)
            try await checked(connection,current:current);try now.validate(connection,concept:concept,source:source)
            guard ticket==generation else{return}
            guard now.selection_digest==command.selection_digest,now.binding_id==value.binding_id,now.roles.contains(command.role),now.permissions.contains("DECIDE"),now.human_binding==value.human_binding,now.pending_operations.isEmpty else {throw ConceptError.conflict}
            let localKey=key(connection,concept,source)
            if let prior=try records.load(localKey) {
                let previous=try JSONDecoder().decode(Journal.self,from:prior)
                guard previous.completed || previous.rejected else {throw ConceptError.conflict}
                let archive=SHA256.hash(data:Data((localKey+"\n"+previous.command.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
                try records.saveBounded(prior,key:archive)
            }
            let journal=Journal(key:localKey,binding_id:now.binding_id,producer_source:now.producer_source,subject:now.decision.subject,command:command,completed:false,rejected:false)
            try records.saveBounded(Data(localKey.utf8),key:witnessKey(localKey));try records.saveBounded(JSONEncoder().encode(journal),key:localKey);pending=journal
            guard ticket==generation else{return}
            try await send(journal,connection:connection,source:source,concept:concept,current:current,ticket:ticket)
        } catch {if ticket==generation {failure(error)}}
    }
    func recover(_ source:ConceptBaselineResult,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let journal=pending else{return};let ticket=generation;busy=true;confirmation=nil
        defer {if generation==ticket {busy=false}}
        do {
            let connection=try await current();try await checked(connection,current:current)
            guard journal.key==key(connection,concept,source) else {throw ConceptError.denied}
            try await send(journal,connection:connection,source:source,concept:concept,current:current,ticket:ticket)
        } catch {if ticket==generation {failure(error)}}
    }
    private func send(_ journal:Journal,connection:ConceptConnection,source:ConceptBaselineResult,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection,ticket:Int) async throws {
        var value:ProposalContentResult
        do {value=try await transport.original(connection,concept:concept.id,operation:journal.command.operation_id)}
        catch ProposalContentError.ownIntentNotFound {
            // Healthy OWN absence is distinct from an absent producer record.
            // A stale command cannot acquire a later own source revision; own
            // Server must freeze durably before any peer POST, including races.
            if journal.command.expected_concept_revision != concept.revision {
                try await checked(connection,current:current)
                guard ticket==generation else{return}
                var rejected=journal;rejected.rejected=true
                try records.saveBounded(JSONEncoder().encode(rejected),key:journal.key)
                pending=nil;throw ConceptError.conflict
            }
            value=try await retry(journal,connection:connection,concept:concept,current:current,ticket:ticket)
        }
        catch ConceptError.notFound {value=try await retry(journal,connection:connection,concept:concept,current:current,ticket:ticket)}
        try await checked(connection,current:current);try value.validate(connection,concept:concept,source:source,original:journal.command)
        guard ticket==generation else{return}
        guard value.binding_id==journal.binding_id,value.producer_source==journal.producer_source,value.decision.subject==journal.subject else {throw ConceptError.denied}
        var completed=journal;completed.completed=true;try records.saveBounded(JSONEncoder().encode(completed),key:journal.key)
        pending=nil;result=value;phase="ready"
    }
    private func retry(_ journal:Journal,connection:ConceptConnection,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection,ticket:Int) async throws -> ProposalContentResult {
        try await checked(connection,current:current)
        guard ticket==generation else {throw CancellationError()}
        return try await transport.decide(connection,concept:concept.id,command:journal.command)
    }
}
