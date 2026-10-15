import Foundation
import CryptoKit

enum ConceptChatError:Error {case inputRejected, ownOriginalNotCaptured}

indirect enum ConceptChatValue:Codable,Equatable,Sendable {
    case text(String),list([String]),null
    init(from decoder:any Decoder) throws {
        let c=try decoder.singleValueContainer()
        if c.decodeNil(){self = .null}
        else if let text=try? c.decode(String.self){self = .text(text)}
        else {self = .list(try c.decode([String].self))}
    }
    func encode(to encoder:any Encoder) throws {
        var c=encoder.singleValueContainer()
        switch self {case .text(let v):try c.encode(v);case .list(let v):try c.encode(v);case .null:try c.encodeNil()}
    }
    var display:String {switch self {case .text(let v):v;case .list(let v):v.joined(separator:"\n");case .null:""}}
}
struct ConceptChatCommand:Codable,Equatable,Sendable {
    let operation_id:String;let turn_id:String;let expected_concept_revision:Int;let role:String;let language:String;let message:String
}
struct ConceptChatAdopt:Codable,Equatable,Sendable {
    let operation_id:String;let expected_revision:Int;let result_reference:String;let displayed_change_digest:String
}
struct ConceptChatCapability:Decodable,Sendable {
    struct Provider:Decodable,Sendable {
        let provider_id:String;let model:String;let profile:String?;let policy_digest:String;let transfer_policy_digest:String
        let receiver:String;let tools:Bool;let data_transfer:[String];let input_token_bound:Int;let output_token_bound:Int;let context_token_bound:Int;let timeout_seconds:Int
    }
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String
    let source_revision:Int;let can_advise:Bool;let expires_at:String;let maximum_turns:Int;let maximum_tokens:Int;let maximum_seconds:Int
    let provider:Provider;let transfer_authorized:Bool
    func validate(_ c:ConceptConnection,_ concept:ProjectConcept) throws {
        guard contract_version=="workspace-concept-chat/1",actor_id==concept.actor_id,context_id==c.access.projectID,concept_id==concept.id,
              !binding_id.isEmpty,producer_source.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil,
              source_revision==concept.revision,WorksetReleaseWire.date(expires_at).map({$0>Date()})==true,
              (1...8).contains(maximum_turns),(1...384000).contains(maximum_tokens),(1...960).contains(maximum_seconds),
              provider.receiver=="INSTANCE_CONFIGURED_EXTERNAL_SESSION",!provider.tools,
              provider.transfer_policy_digest.range(of:"^sha256:[0-9a-f]{64}$",options:.regularExpression) != nil else {throw ConceptError.invalid}
    }
}
struct ConceptChatBriefing:Decodable,Sendable {
    struct Snapshot:Decodable,Sendable {
        let id:String;let actor_id:String;let context_id:String;let title:String;let notes:String;let revision:Int;let state:String
        func matches(_ concept:ProjectConcept)->Bool {id==concept.id && actor_id==concept.actor_id && context_id==concept.context_id && title==concept.title && notes==concept.notes && revision==concept.revision && state==concept.state}
    }
    let briefing_version:String;let concept:Snapshot;let fields:[String:ConceptChatValue];let source_digest:String;let lifecycle:String
}
struct ConceptChatWireTurn:Decodable,Sendable {
    struct Briefing:Decodable,Sendable {let concept_id:String;let revision:Int}
    struct Request:Decodable,Sendable {let operation_id:String;let turn_id:String;let advisor_kind:String;let message:String;let language:String;let briefing:Briefing}
    struct Output:Decodable,Sendable {let answer:String;let questions:[String];let assumptions:[String];let applied:Bool}
    struct Outcome:Decodable,Sendable {let output:Output?;let result_digest:String?;let execution:String}
    let request:Request;let request_digest:String;let status:String;let revision:Int;let outcome:Outcome?
    func validate(_ concept:ProjectConcept) throws {
        guard request.briefing.concept_id==concept.id,request.briefing.revision>0,request.briefing.revision<=concept.revision,
              request.operation_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,
              request.turn_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,
              ["BUSINESS","ARCHITECTURE"].contains(request.advisor_kind),["en","nl","de","fr","es"].contains(request.language),
              ["PENDING","COMPLETE","FAILED","UNCERTAIN"].contains(status),revision>0,request.message.count<=4000 else {throw ConceptError.invalid}
        if status=="COMPLETE" {guard let outcome,let output=outcome.output,outcome.execution=="CONFIRMED",!output.applied,output.answer.count<=2000,output.questions.count<=6,output.assumptions.count<=6 else{throw ConceptError.invalid}}
    }
    var display:ConceptChatTurn {ConceptChatTurn(id:request.turn_id,role:request.advisor_kind,message:request.message,answer:status=="COMPLETE" ? outcome?.output?.answer ?? "":"",sourceRevision:request.briefing.revision,questions:status=="COMPLETE" ? outcome?.output?.questions ?? []:[],assumptions:status=="COMPLETE" ? outcome?.output?.assumptions ?? []:[],status:status)}
}
struct ConceptChatWireProposal:Decodable,Sendable {
    struct Change:Codable,Sendable {let field:String;let before:ConceptChatValue;let after:ConceptChatValue;let reason:String}
    let source_digest:String;let changes:[Change];let displayed_change_digest:String;let result_reference:String;let adoptable:Bool
    func validate() throws {
        let data=try JSONEncoder().encode(changes),object=try JSONSerialization.jsonObject(with:data)
        let digest=SHA256.hash(data:try CanonicalJSON.data(object,ascii:false)).map{String(format:"%02x",$0)}.joined()
        guard digest==displayed_change_digest,changes.count<=6,!changes.isEmpty,Set(changes.map(\.field)).count==changes.count,
              changes.allSatisfy({["name","purpose","users","non_goals","constraints","open_questions"].contains($0.field)}) else {throw ConceptError.invalid}
    }
}
struct ConceptChatReply:Decodable,Sendable {
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String
    let operation_id:String;let source_revision:Int;let turn:ConceptChatWireTurn;let proposal:ConceptChatWireProposal?
    func validate(_ c:ConceptConnection,_ concept:ProjectConcept,_ cap:ConceptChatCapability,_ operation:String) throws {
        guard contract_version=="workspace-concept-chat/1",actor_id==concept.actor_id,context_id==c.access.projectID,concept_id==concept.id,
              binding_id==cap.binding_id,producer_source==cap.producer_source,operation_id==operation,turn.request.operation_id==operation,
              source_revision==turn.request.briefing.revision else {throw ConceptError.invalid}
        try turn.validate(concept);try proposal?.validate()
        if let proposal {guard turn.status=="COMPLETE",proposal.result_reference==operation else{throw ConceptError.invalid}}
    }
}
struct ConceptChatHistory:Decodable,Sendable {
    struct History:Decodable,Sendable {let turns:[ConceptChatWireTurn];let revision:Int;let read_only:Bool}
    struct LocalOperation:Decodable,Sendable {let operation_id:String;let command:ConceptChatCommand;let state:String}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String;let history:History
    let local_operations:[LocalOperation]
    func validate(_ c:ConceptConnection,_ concept:ProjectConcept,_ cap:ConceptChatCapability) throws {
        guard contract_version=="workspace-concept-chat/1",actor_id==concept.actor_id,context_id==c.access.projectID,concept_id==concept.id,binding_id==cap.binding_id,producer_source==cap.producer_source,
              history.read_only,history.revision==history.turns.count,history.turns.count<=cap.maximum_turns,
              Set(history.turns.map({$0.request.turn_id})).count==history.turns.count else{throw ConceptError.invalid}
        for turn in history.turns {try turn.validate(concept)}
        guard local_operations.count<=256,Set(local_operations.map(\.operation_id)).count==local_operations.count else{throw ConceptError.invalid}
        for operation in local_operations {
            guard operation.operation_id==operation.command.operation_id,operation.operation_id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,
                  ["PRODUCER_NOT_OBSERVED","PENDING","COMPLETE","FAILED","UNCERTAIN"].contains(operation.state),operation.command.expected_concept_revision>0,
                  operation.command.expected_concept_revision<=concept.revision else{throw ConceptError.invalid}
        }
    }
}
protocol ConceptChatServing:Sendable {
    func access(_ c:ConceptConnection,concept:String) async throws -> ConceptChatCapability
    func briefing(_ c:ConceptConnection,concept:String) async throws -> ConceptChatBriefing
    func history(_ c:ConceptConnection,concept:String) async throws -> ConceptChatHistory
    func send(_ c:ConceptConnection,concept:String,command:ConceptChatCommand) async throws -> ConceptChatReply
    func read(_ c:ConceptConnection,concept:String,operation:String) async throws -> ConceptChatReply
    func adopt(_ c:ConceptConnection,concept:String,command:ConceptChatAdopt) async throws -> ConceptChatBriefing
}
struct ConceptChatTransport:ConceptChatServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=65;configuration.timeoutIntervalForResource=75
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request<T:Decodable>(_ type:T.Type,_ c:ConceptConnection,concept:String,action:String,body:Data?=nil) async throws -> T {
        guard concept.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else{throw ConceptError.invalid}
        let url=try ServerEndpoint(c.access.endpoint).route("/v1/concept-chats/"+concept+"/"+action)
        var r=URLRequest(url:url);r.httpMethod=body==nil ? "GET":"POST";r.httpBody=body
        r.setValue("Bearer "+c.bearer,forHTTPHeaderField:"Authorization");r.setValue(c.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance");r.setValue(c.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        if body != nil {r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:r)
        guard let http=response as? HTTPURLResponse,http.url==url else{throw ConceptError.invalid}
        switch http.statusCode {case 200:break;case 401,403:throw ConceptError.denied;case 404:
            let code=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            if code=="CHAT_NOT_FOUND" {throw ConceptChatError.ownOriginalNotCaptured}
            guard code=="CONCEPT_TURN_NOT_FOUND" else{throw ConceptError.unavailable}
            throw ConceptError.notFound;case 409:throw ConceptError.conflict;case 400:
            let code=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            guard code=="CHAT_INVALID_OR_UNAVAILABLE" else{throw ConceptError.unavailable}
            throw ConceptChatError.inputRejected;default:throw ConceptError.unavailable}
        guard data.count<=1150000,http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json")==true,
              let result=try? JSONDecoder().decode(T.self,from:data) else{throw ConceptError.invalid}
        return result
    }
    func access(_ c:ConceptConnection,concept:String) async throws -> ConceptChatCapability {try await request(ConceptChatCapability.self,c,concept:concept,action:"access")}
    func briefing(_ c:ConceptConnection,concept:String) async throws -> ConceptChatBriefing {try await request(ConceptChatBriefing.self,c,concept:concept,action:"briefing")}
    func history(_ c:ConceptConnection,concept:String) async throws -> ConceptChatHistory {try await request(ConceptChatHistory.self,c,concept:concept,action:"history")}
    func send(_ c:ConceptConnection,concept:String,command:ConceptChatCommand) async throws -> ConceptChatReply {try await request(ConceptChatReply.self,c,concept:concept,action:"turns",body:JSONEncoder().encode(command))}
    func read(_ c:ConceptConnection,concept:String,operation:String) async throws -> ConceptChatReply {
        guard operation.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else{throw ConceptError.invalid}
        return try await request(ConceptChatReply.self,c,concept:concept,action:"operations/"+operation)
    }
    func adopt(_ c:ConceptConnection,concept:String,command:ConceptChatAdopt) async throws -> ConceptChatBriefing {try await request(ConceptChatBriefing.self,c,concept:concept,action:"adopt",body:JSONEncoder().encode(command))}
}
