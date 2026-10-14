import Foundation
import Combine
import CryptoKit

@MainActor final class ConceptChatState:ObservableObject {
    struct Journal:Codable {
        let key:String;let conceptID:String;let bindingID:String;let producerSource:String
        let command:ConceptChatCommand?;let adoption:ConceptChatAdopt?;var complete:Bool;var retired:Bool?=nil
        var operation:String {command?.operation_id ?? adoption?.operation_id ?? ""}
    }
    @Published var access:ConceptChatCapability?
    @Published var briefing:[String:String]=[:]
    @Published var turns:[ConceptChatWireTurn]=[]
    @Published var reply:ConceptChatReply?
    @Published var pending:Journal?
    @Published var adopting=false
    @Published var busy=false
    @Published var phase="access"
    let transport:any ConceptChatServing
    let records:PrivateLocalRecordStore
    var generation=0
    private var observer:Task<Void,Never>?
    init(transport:any ConceptChatServing=ConceptChatTransport(),root:URL) {
        self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"concept-chat")
    }
    func conceal() {observer?.cancel();observer=nil;generation+=1;access=nil;briefing=[:];turns=[];reply=nil;pending=nil;busy=false;adopting=false;phase="access"}
    func key(_ c:ConceptConnection,_ concept:ProjectConcept)->String {hash(c.key+"\n"+concept.actor_id+"\n"+concept.id)}
    func hash(_ text:String)->String {SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()}
    func check(_ c:ConceptConnection,_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async throws {
        guard try await current()==c else{throw ConceptError.denied}
        try concept.validate(c.access.projectID)
        if let access {guard WorksetReleaseWire.date(access.expires_at).map({$0>Date()})==true else{throw ConceptError.denied}}
    }
    func save(_ journal:Journal) throws {
        let allocation=hash("allocation\n"+journal.key)
        if try records.load(allocation) != nil && records.load(journal.key)==nil {throw ConceptError.unavailable}
        try records.saveBounded(Data(journal.key.utf8),key:allocation)
        try records.saveBounded(JSONEncoder().encode(journal),key:journal.key)
        if journal.complete || journal.retired==true {try records.saveBounded(JSONEncoder().encode(journal),key:hash(journal.key+"\n"+journal.operation))}
    }
    func original(_ c:ConceptConnection,_ concept:ProjectConcept,_ cap:ConceptChatCapability) throws -> Journal? {
        let key=key(c,concept),data=try records.load(key),witness=try records.load(hash("allocation\n"+key))
        if witness != nil {guard witness==Data(key.utf8),data != nil else{throw ConceptError.unavailable}}
        guard let data else{return nil}
        guard witness != nil else{throw ConceptError.unavailable}
        let j=try JSONDecoder().decode(Journal.self,from:data)
        guard j.key==key,j.conceptID==concept.id,j.bindingID==cap.binding_id,j.producerSource==cap.producer_source,
              (j.command==nil) != (j.adoption==nil),j.operation.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else{throw ConceptError.invalid}
        return j
    }
    func load(_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !Task.isCancelled else{return}
        conceal();let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();try await check(c,concept,current:current)
            let source=try await transport.briefing(c,concept:concept.id)
            try await check(c,concept,current:current)
            guard source.briefing_version=="workspace-concept-briefing/1",source.concept.matches(concept) else{throw ConceptError.invalid}
            guard ticket==generation else{return};briefing=source.fields.mapValues(\.display)
            let cap=try await transport.access(c,concept:concept.id);try cap.validate(c,concept)
            let history=try await transport.history(c,concept:concept.id);try history.validate(c,concept,cap)
            try await check(c,concept,current:current)
            guard ticket==generation else{return}
            var journal=try original(c,concept,cap)
            let unresolved=history.local_operations.filter{!["COMPLETE","FAILED"].contains($0.state)}
            guard unresolved.count<=1 else{throw ConceptError.invalid}
            if (journal==nil || journal?.complete==true || journal?.retired==true),let operation=unresolved.first {
                let recovered=Journal(key:key(c,concept),conceptID:concept.id,bindingID:cap.binding_id,producerSource:cap.producer_source,command:operation.command,adoption:nil,complete:false)
                try save(recovered);journal=recovered
            } else if let journal,!journal.complete,let command=journal.command,let operation=unresolved.first {
                guard operation.command==command else{throw ConceptError.conflict}
            }
            guard ticket==generation else{return}
            access=cap;turns=history.history.turns;pending=(journal?.complete==true || journal?.retired==true) ? nil:journal;phase="ready"
            observer=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(2))
                    guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    do {
                        try await self.check(c,concept,current:current)
                        let now=try await self.transport.access(c,concept:concept.id);try now.validate(c,concept)
                        guard now.binding_id==cap.binding_id,now.producer_source==cap.producer_source,now.expires_at==cap.expires_at,
                              now.provider.transfer_policy_digest==cap.provider.transfer_policy_digest,now.can_advise==cap.can_advise else{throw ConceptError.denied}
                    } catch {if self.generation==ticket {self.failure(error,clear:true)};return}
                }
            }
        } catch {if ticket==generation {failure(error,clear:true)}}
    }
    func failure(_ error:Error,clear:Bool=false) {
        var denied=false
        if case ConceptError.denied=error {denied=true}
        if clear || denied {conceal()}
        reply=nil
        switch error {case ConceptChatError.inputRejected:phase="inputRejected";case ConceptError.denied:phase="access";case ConceptError.conflict:phase="conflict";case ConceptError.invalid,is DecodingError:phase="invalid";case AdvisoryError.state("LOCAL_CAPACITY_EXHAUSTED"):phase="capacity";default:phase="unavailable"}
    }
    func send(role:String,message:String,language:String,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,pending==nil,let cap=access,cap.can_advise,concept.lifecycle != "ARCHIVED",ConceptChatCopy.validMessage(message),["BUSINESS","ARCHITECT"].contains(role),ConceptChatCopy.languages.contains(language) else{return}
        let ticket=generation;busy=true
        defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();try await check(c,concept,current:current)
            guard ticket==generation else{return}
            let command=ConceptChatCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),turn_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_concept_revision:concept.revision,role:role,language:language,message:message)
            let journal=Journal(key:key(c,concept),conceptID:concept.id,bindingID:cap.binding_id,producerSource:cap.producer_source,command:command,adoption:nil,complete:false)
            try save(journal);pending=journal
            await perform(journal,c:c,concept:concept,cap:cap,ticket:ticket,current:current)
        } catch {if ticket==generation {failure(error)}}
    }
    func resume(_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let journal=pending,let cap=access else{return}
        let ticket=generation;busy=true;defer {if ticket==generation {busy=false}}
        do {let c=try await current();try await check(c,concept,current:current);await perform(journal,c:c,concept:concept,cap:cap,ticket:ticket,current:current)}
        catch {if ticket==generation {failure(error)}}
    }
    private func perform(_ journal:Journal,c:ConceptConnection,concept:ProjectConcept,cap:ConceptChatCapability,ticket:Int,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        do {
            guard journal.key==key(c,concept),journal.bindingID==cap.binding_id,journal.producerSource==cap.producer_source else{throw ConceptError.denied}
            let now=try await transport.access(c,concept:concept.id);try now.validate(c,concept)
            guard now.binding_id==cap.binding_id,now.provider.transfer_policy_digest==cap.provider.transfer_policy_digest else{throw ConceptError.denied}
            try await check(c,concept,current:current);guard ticket==generation else{return}
            if let command=journal.command {
                let result:ConceptChatReply
                do {result=try await transport.read(c,concept:concept.id,operation:command.operation_id)}
                catch ConceptError.notFound,ConceptChatError.ownOriginalNotCaptured {
                    try await check(c,concept,current:current);guard ticket==generation else{return}
                    guard now.can_advise else{throw ConceptError.denied}
                    result=try await transport.send(c,concept:concept.id,command:command)
                }
                try await check(c,concept,current:current);try result.validate(c,concept,cap,command.operation_id)
                guard ticket==generation else{return}
                reply=result
                if let index=turns.firstIndex(where:{$0.request.operation_id==command.operation_id}) {turns[index]=result.turn}else{turns.append(result.turn)}
                if ["COMPLETE","FAILED"].contains(result.turn.status) {var completed=journal;completed.complete=true;try save(completed);pending=nil}
            } else if let adoption=journal.adoption {
                let result=try await transport.adopt(c,concept:concept.id,command:adoption)
                try await check(c,concept,current:current)
                guard result.concept.id==concept.id,result.concept.actor_id==concept.actor_id,result.concept.context_id==c.access.projectID,result.concept.revision==adoption.expected_revision+1 else{throw ConceptError.invalid}
                guard ticket==generation else{return};var completed=journal;completed.complete=true;try save(completed);pending=nil;reply=nil;phase="adopted"
                return
            }
            phase=pending==nil ? "ready":"pending"
        } catch {if ticket==generation {failure(error)}}
    }
    func adopt(_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,pending==nil,let cap=access,let proposal=reply?.proposal,proposal.adoptable,reply?.source_revision==concept.revision,concept.lifecycle != "ARCHIVED" else{return}
        let ticket=generation;busy=true;adopting=true;defer {if ticket==generation {busy=false;adopting=false}}
        do {
            let c=try await current();try await check(c,concept,current:current)
            guard ticket==generation else{return}
            let command=ConceptChatAdopt(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_revision:concept.revision,result_reference:proposal.result_reference,displayed_change_digest:proposal.displayed_change_digest)
            let journal=Journal(key:key(c,concept),conceptID:concept.id,bindingID:cap.binding_id,producerSource:cap.producer_source,command:nil,adoption:command,complete:false)
            try save(journal);pending=journal
            await perform(journal,c:c,concept:concept,cap:cap,ticket:ticket,current:current)
        } catch {if ticket==generation {failure(error)}}
    }
    func retireRejected(_ concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,phase=="inputRejected",let journal=pending,let command=journal.command,let cap=access else{return}
        let ticket=generation;busy=true;defer {if ticket==generation {busy=false}}
        do {
            let c=try await current();try await check(c,concept,current:current)
            do {
                let result=try await transport.read(c,concept:concept.id,operation:command.operation_id)
                try await check(c,concept,current:current);try result.validate(c,concept,cap,command.operation_id)
                guard ticket==generation else{return};reply=result
                if ["COMPLETE","FAILED"].contains(result.turn.status) {var completed=journal;completed.complete=true;try save(completed);pending=nil;phase="ready"}
                else {phase="pending"}
            } catch ConceptChatError.ownOriginalNotCaptured {
                // No ambiguous failure is absence. Only a typed authenticated
                // own pre-capture absence after explicit rejection retires this ID.
                // A retained Server intent with peer404 is NEVER retired here.
                try await check(c,concept,current:current);guard ticket==generation else{return}
                var retired=journal;retired.retired=true;try save(retired);pending=nil;reply=nil;phase="ready"
            }
        } catch {if ticket==generation {failure(error)}}
    }
    func open(_ operation:String,concept:ProjectConcept,current:@escaping @MainActor () async throws -> ConceptConnection) async {
        guard !busy,let cap=access else{return};let ticket=generation;busy=true;defer{if ticket==generation {busy=false}}
        do {
            let c=try await current();try await check(c,concept,current:current)
            let value=try await transport.read(c,concept:concept.id,operation:operation)
            try await check(c,concept,current:current);try value.validate(c,concept,cap,operation)
            guard ticket==generation else{return};reply=value
        } catch {if ticket==generation {failure(error)}}
    }
}
