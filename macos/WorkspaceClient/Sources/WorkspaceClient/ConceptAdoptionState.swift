import Foundation
import Combine

@MainActor final class ConceptAdoptionState:ObservableObject {
    struct Navigation:Codable {let source:String;let operation:String?;let document:String?}
    struct Journal:Codable {let key:String;let concept:String;let source:String;let command:ConceptAdoptionCommand;var complete:Bool;var peerDigest:String?}
    @Published var sources:[ConceptAdoptionSources.Source]=[]
    @Published var source=""
    @Published var expandedDocument=""
    @Published var access:ConceptAdoptionAccess?
    @Published var history:[ConceptAdoptionHistory.Entry]=[]
    @Published var result:ConceptAdoptionResult?
    @Published var pending:Journal?
    @Published var phase="ready"
    @Published var busy=false
    let transport:any ConceptAdoptionServing
    let records:PrivateLocalRecordStore
    var generation=0
    private var monitor:Task<Void,Never>?
    private var expiry:Task<Void,Never>?
    init(transport:any ConceptAdoptionServing = ConceptAdoptionTransport(),root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ConceptAdoptionIntents")) {self.transport=transport;records=PrivateLocalRecordStore(root:root,namespace:"concept-adoption")}
    func conceal() {generation+=1;monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;sources=[];source="";expandedDocument="";access=nil;history=[];result=nil;pending=nil;busy=false;phase="access"}
    func key(_ c:ConceptConnection,_ concept:ProjectConcept,_ source:String)->String {ConceptAdoptionResult.hash(Data((c.key+"\n"+concept.actor_id+"\n"+concept.id+"\n"+source).utf8))}
    func nav(_ c:ConceptConnection,_ concept:ProjectConcept) throws->Navigation? {try records.load(key(c,concept,"navigation")).map{try JSONDecoder().decode(Navigation.self,from:$0)}}
    func saveNav(_ c:ConceptConnection,_ concept:ProjectConcept,source:String,operation:String?,document:String?) throws {try records.saveBounded(JSONEncoder().encode(Navigation(source:source,operation:operation,document:document)),key:key(c,concept,"navigation"))}
    func chooseDocument(_ path:String,concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        let ticket=generation;let selected=source
        do {let c=try await current();try await checked(c,concept,selected,ticket:ticket,current:current);guard let result,result.document?.entries.contains(where:{$0.id==path})==true else{throw ConceptError.invalid};let next=expandedDocument==path ? "":path;try saveNav(c,concept,source:selected,operation:result.operation_id,document:next);expandedDocument=next}
        catch {if ticket==generation {failure(error)}}
    }
    func failure(_ error:Error) {result=nil;switch error {case ConceptError.denied:conceal();phase="access";case ConceptError.conflict:phase="conflict";case ConceptError.notFound:phase="notFound";case ConceptError.invalid,is DecodingError:phase="invalid";default:phase="unavailable"}}
    func checked(_ c:ConceptConnection,_ concept:ProjectConcept,_ selected:String,ticket:Int,current:@escaping @MainActor () async throws->ConceptConnection) async throws {
        guard generation==ticket else{throw CancellationError()}
        let now=try await current()
        guard generation==ticket,now==c,source==selected,access==nil || WorksetReleaseWire.date(access!.expires_at).map({$0>Date()})==true else{throw ConceptError.denied};try concept.validate(c.access.projectID)
    }
    func load(_ concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        conceal();let ticket=generation;busy=true;defer{if ticket==generation {busy=false}}
        do {
            let c=try await current();let value=try await transport.sources(c,concept:concept.id)
            guard try await current()==c,value.contract_version=="workspace-concept-adoption/1",value.actor_id==concept.actor_id,value.context_id==concept.context_id,value.concept_id==concept.id,value.sources.count<=8,Set(value.sources.map(\.id)).count==value.sources.count,value.sources.allSatisfy({$0.setup_metadata_not_observed && $0.source_options.count<=16 && WorksetReleaseWire.date($0.expires_at).map({$0>Date()})==true}) else{throw ConceptError.invalid}
            guard ticket==generation else{return};sources=value.sources;phase=sources.isEmpty ? "empty":"ready"
            if let original=try nav(c,concept) {guard sources.contains(where:{$0.id==original.source}) else{throw ConceptError.denied};await select(original.source,concept:concept,current:current)}
        } catch {if ticket==generation {failure(error)}}
    }
    func select(_ selected:String,concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        generation+=1;monitor?.cancel();monitor=nil;expiry?.cancel();expiry=nil;let ticket=generation;source=selected;expandedDocument="";access=nil;result=nil;pending=nil;history=[];busy=true;defer{if ticket==generation {busy=false}}
        guard sources.contains(where:{$0.id==selected}) else{failure(ConceptError.invalid);return}
        do {
            let c=try await current();let cap=try await transport.access(c,concept:concept.id,source:selected);try await checked(c,concept,selected,ticket:ticket,current:current)
            guard cap.contract_version=="workspace-concept-adoption/1",cap.actor_id==concept.actor_id,cap.context_id==concept.context_id,cap.concept_id==concept.id,cap.binding_id==selected,cap.producer_source==ConceptAdoptionResult.pin,cap.source_revision==concept.revision,WorksetReleaseWire.date(cap.expires_at).map({$0>Date()})==true else{throw ConceptError.invalid}
            let listed=try await transport.history(c,concept:concept.id,source:selected);let local=key(c,concept,selected);let raw=try records.load(local);let witness=try records.load(ConceptAdoptionResult.hash(Data(("allocation\n"+local).utf8)))
            guard raw != nil || witness==nil else{throw ConceptError.unavailable}
            let journal=try raw.map{try JSONDecoder().decode(Journal.self,from:$0)}
            if let journal {guard journal.key==local,journal.concept==concept.id,journal.source==selected else{throw ConceptError.invalid}}
            guard listed.operations.count<=256,Set(listed.operations.map(\.id)).count==listed.operations.count else{throw ConceptError.invalid}
            try await checked(c,concept,selected,ticket:ticket,current:current);guard ticket==generation else{return};access=cap;history=listed.operations;pending=journal?.complete==false ? journal:nil;phase="ready"
            expiry=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(250));guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    if WorksetReleaseWire.date(cap.expires_at).map({$0>Date()}) != true {self.conceal();return}
                }
            }
            monitor=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.seconds(3));guard !Task.isCancelled,let self,self.generation==ticket else{return}
                    do {
                        try await self.checked(c,concept,selected,ticket:ticket,current:current)
                        let now=try await self.transport.access(c,concept:concept.id,source:selected)
                        guard now.binding_id==cap.binding_id,now.expires_at==cap.expires_at else{throw ConceptError.denied}
                        if let operation=self.result?.operation_id {let fresh=try await self.transport.read(c,concept:concept.id,source:selected,operation:operation);try fresh.validate(c,concept:concept,source:selected,operation:operation);try await self.checked(c,concept,selected,ticket:ticket,current:current);guard self.generation==ticket,self.result?.operation_id==operation else{return};self.result=fresh}
                    } catch {if self.generation==ticket {self.failure(error)};return}
                }
            }
            let previous=try nav(c,concept)
            let operation=journal?.complete==false ? journal?.command.operation_id:(previous?.source==selected ? previous?.operation:nil) ?? journal?.command.operation_id
            try saveNav(c,concept,source:selected,operation:operation,document:previous?.source==selected ? previous?.document:nil)
            if let operation {await open(operation,concept:concept,current:current)}
        } catch {if ticket==generation {failure(error)}}
    }
    func prepare(_ concept:ProjectConcept,paths:[String],vision:String?,current:@escaping @MainActor () async throws->ConceptConnection) async {
        guard !busy,pending==nil,let cap=access,cap.can_prepare,!paths.isEmpty else{return}
        let allowed=["docs/product/VISION.md","docs/architecture/ARCHITECTURE.md","docs/roadmap/ROADMAP.md"]
        guard paths.count<=3,Set(paths).count==paths.count,paths.allSatisfy({allowed.contains($0)}),vision==nil || (paths.contains(allowed[0]) && sources.first(where:{$0.id==source})?.source_options.contains(vision!)==true) else{failure(ConceptError.invalid);return}
        let ticket=generation;let selected=source;busy=true;result=nil;defer{if ticket==generation {busy=false}}
        do {
            let c=try await current();try await checked(c,concept,selected,ticket:ticket,current:current)
            let command=ConceptAdoptionCommand(operation_id:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased(),expected_revision:concept.revision,requested_artifacts:paths,mappings:vision.map{[.init(artifact_path:"docs/product/VISION.md",source_path:$0,choice:"LINK_EXISTING")]} ?? [])
            let local=key(c,concept,selected);var journal=Journal(key:local,concept:concept.id,source:selected,command:command,complete:false)
            try records.saveBounded(Data(local.utf8),key:ConceptAdoptionResult.hash(Data(("allocation\n"+local).utf8)));try records.saveBounded(JSONEncoder().encode(journal),key:local);guard ticket==generation else{return};pending=journal
            let value=try await transport.prepare(c,concept:concept.id,source:selected,command:command);try value.validate(c,concept:concept,source:selected,operation:command.operation_id);try await checked(c,concept,selected,ticket:ticket,current:current);guard ticket==generation else{return}
            journal.complete=value.proposal.state=="PREPARED";journal.peerDigest=value.proposal.request_digest;try records.saveBounded(JSONEncoder().encode(journal),key:local);pending=journal.complete ? nil:journal;try saveNav(c,concept,source:selected,operation:command.operation_id,document:nil);result=value;phase=journal.complete ? "prepared":"pending"
            let freshHistory=try await transport.history(c,concept:concept.id,source:selected).operations
            try await checked(c,concept,selected,ticket:ticket,current:current);guard ticket==generation else{return};history=freshHistory
        } catch {if ticket==generation {failure(error)}}
    }
    func open(_ operation:String,concept:ProjectConcept,current:@escaping @MainActor () async throws->ConceptConnection) async {
        let ticket=generation;let selected=source;result=nil;busy=true;defer{if ticket==generation {busy=false}}
        do {
            let c=try await current();try await checked(c,concept,selected,ticket:ticket,current:current);let value=try await transport.read(c,concept:concept.id,source:selected,operation:operation);try value.validate(c,concept:concept,source:selected,operation:operation);try await checked(c,concept,selected,ticket:ticket,current:current)
            let local=key(c,concept,selected)
            if let raw=try records.load(local) {var journal=try JSONDecoder().decode(Journal.self,from:raw);if journal.command.operation_id==operation {guard journal.peerDigest==nil || journal.peerDigest==value.proposal.request_digest else{throw ConceptError.invalid};journal.peerDigest=value.proposal.request_digest;journal.complete=value.proposal.state=="PREPARED";try records.saveBounded(JSONEncoder().encode(journal),key:local);guard ticket==generation else{return};pending=journal.complete ? nil:journal}}
            guard ticket==generation else{return};let prior=try nav(c,concept);let document=prior?.source==selected && prior?.operation==operation ? prior?.document:nil;try saveNav(c,concept,source:selected,operation:operation,document:document);expandedDocument=value.document?.entries.contains(where:{$0.id==document})==true ? document ?? "":"";result=value;phase=value.proposal.state=="PREPARED" ? "prepared":"pending"
        } catch {if ticket==generation {failure(error)}}
    }
}
