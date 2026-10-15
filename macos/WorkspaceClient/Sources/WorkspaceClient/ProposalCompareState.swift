import Foundation
import Combine
import CryptoKit

// Selection IDs only share the existing bounded private baseline store. No proposal cache or write transport.
@MainActor final class ProposalCompareState:ObservableObject {
    struct Choice:Codable,Equatable,Sendable {let before:String;let after:String}
    @Published var history:[ConceptBaselineHistory.Entry]=[]
    @Published var choice:Choice?
    @Published var comparison:ProposalCompareModel?
    @Published var phase="idle"
    @Published var busy=false
    @Published var partialHistory=false
    let transport:any ConceptBaselineServing
    let records:PrivateLocalRecordStore
    private var access:ConceptBaselineAccess?
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    private var generation=0
    init(transport:any ConceptBaselineServing=ConceptBaselineTransport(),root:URL) {self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"concept-baseline")}
    func conceal() {generation+=1;monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;comparison=nil;access=nil;history=[];choice=nil;busy=false;partialHistory=false;phase="idle"}
    func key(_ connection:ConceptConnection,_ concept:ProjectConcept)->String {SHA256.hash(data:Data(("proposal-compare\n"+connection.key+"\n"+concept.actor_id+"\n"+concept.id).utf8)).map{String(format:"%02x",$0)}.joined()}
    private func checked(_ connection:ConceptConnection,_ concept:ProjectConcept,_ cap:ConceptBaselineAccess,current:@escaping @MainActor () async throws->ConceptConnection) async throws {
        guard try await current()==connection,WorksetReleaseWire.date(cap.expires_at).map({$0>Date()})==true else {throw ConceptError.denied}
        guard cap.source_revision==concept.revision else {throw ConceptError.conflict}
        guard cap.contract_version=="workspace-concept-baseline/1",cap.actor_id==concept.actor_id,cap.context_id==concept.context_id,cap.concept_id==concept.id,cap.document_language=="en" else {throw ConceptError.invalid}
    }
    private func fresh(_ connection:ConceptConnection,_ concept:ProjectConcept,_ cap:ConceptBaselineAccess,current:@escaping @MainActor () async throws->ConceptConnection) async throws {
        try await checked(connection,concept,cap,current:current)
        let now=try await transport.access(connection,concept:concept.id)
        try await checked(connection,concept,now,current:current)
        guard now.binding_id==cap.binding_id,now.producer_source==cap.producer_source,now.expires_at==cap.expires_at else {throw ConceptError.denied}
    }
    private func failure(_ error:Error) {
        comparison=nil
        switch error {
        case ConceptError.denied:conceal();phase="denied"
        case ProposalCompareError.incompatible:phase="incompatible"
        case ProposalCompareError.partial:phase="partial"
        case ConceptError.notFound:phase="partial"
        case ConceptError.conflict:phase="sourceChanged"
        case ConceptError.invalid,is DecodingError:phase="invalid"
        default:phase="unavailable"
        }
    }
    func load(_ concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        guard !Task.isCancelled else{return}
        conceal();let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let connection=try await current();try concept.validate(connection.access.projectID)
            let cap=try await transport.access(connection,concept:concept.id);try await checked(connection,concept,cap,current:current)
            let entries=try await transport.history(connection,concept:concept.id);try await checked(connection,concept,cap,current:current)
            guard entries.contract_version==cap.contract_version,entries.actor_id==cap.actor_id,entries.context_id==cap.context_id,entries.concept_id==concept.id,entries.binding_id==cap.binding_id,entries.producer_source==cap.producer_source,entries.operations.count<=256,Set(entries.operations.map(\.id)).count==entries.operations.count,entries.operations.allSatisfy({$0.source_revision>0 && $0.id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil}) else {throw ConceptError.invalid}
            let saved=try records.load(key(connection,concept)).map{try JSONDecoder().decode(Choice.self,from:$0)}
            guard ticket==generation,!Task.isCancelled else{return}
            access=cap;history=entries.operations
            if history.count>1 {choice=saved ?? .init(before:history.first!.id,after:history.last!.id)}
            expiry=Task { [weak self] in
                let remaining=WorksetReleaseWire.date(cap.expires_at)!.timeIntervalSinceNow
                try? await Task.sleep(for:.seconds(max(remaining,0)),tolerance:.zero)
                guard !Task.isCancelled,let self,self.generation==ticket else{return}
                self.conceal();self.phase="denied"
            }
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(3))
                    guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    do {
                        try await self.checked(connection,concept,cap,current:current)
                        let now=try await self.transport.access(connection,concept:concept.id)
                        try await self.checked(connection,concept,now,current:current)
                        guard now.binding_id==cap.binding_id,now.producer_source==cap.producer_source,now.expires_at==cap.expires_at else {throw ConceptError.denied}
                    } catch {if self.generation==ticket {self.conceal();self.failure(error)};return}
                }
            }
            if let saved {busy=false;await compare(saved,concept:concept,current:current);return}
            guard !history.isEmpty else {phase="none";return}
            var complete:[String]=[]
            for entry in history.reversed().prefix(8) {
                do {
                    let result=try await transport.read(connection,concept:concept.id,operation:entry.id)
                    try await checked(connection,concept,cap,current:current);try result.validate(connection,concept:concept,operation:entry.id,access:cap)
                    guard ticket==generation,!Task.isCancelled else{return}
                    complete.append(entry.id);if complete.count==2 {break}
                } catch ConceptError.notFound {guard ticket==generation,!Task.isCancelled else{return};partialHistory=true}
            }
            guard ticket==generation,!Task.isCancelled else{return}
            guard complete.count==2 else {phase=partialHistory ? "partial":"single";return}
            busy=false;await compare(.init(before:complete[1],after:complete[0]),concept:concept,current:current)
        } catch {if ticket==generation {failure(error)}}
    }
    func compare(_ next:Choice,concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        guard !busy,let cap=access else{return}
        comparison=nil;choice=next;let ticket=generation;busy=true;phase="loading"
        defer {if ticket==generation {busy=false}}
        do {
            guard next.before != next.after,history.contains(where:{$0.id==next.before}),history.contains(where:{$0.id==next.after}) else {throw ConceptError.invalid}
            let connection=try await current();try await fresh(connection,concept,cap,current:current)
            guard ticket==generation,choice==next,!Task.isCancelled else{return}
            try records.saveBounded(JSONEncoder().encode(next),key:key(connection,concept))
            let before=try await transport.read(connection,concept:concept.id,operation:next.before)
            try await checked(connection,concept,cap,current:current);try before.validate(connection,concept:concept,operation:next.before,access:cap)
            guard ticket==generation,choice==next else{return}
            let after=try await transport.read(connection,concept:concept.id,operation:next.after)
            try await checked(connection,concept,cap,current:current);try after.validate(connection,concept:concept,operation:next.after,access:cap)
            guard before.current_revision==after.current_revision,before.current_revision==cap.source_revision else {throw ConceptError.conflict}
            let value=try await Task.detached(priority:.utility) {try ProposalCompareModel.make(before,after)}.value
            try await fresh(connection,concept,cap,current:current)
            guard ticket==generation,choice==next,!Task.isCancelled else{return}
            comparison=value;phase=value.changedDocuments==0 ? "identical":"comparable"
        } catch {if ticket==generation {failure(error)}}
    }
}
