import Foundation
import CryptoKit

enum ConceptBaselineError:Error {case sourceRejected}

struct ConceptBaselineCommand: Codable, Equatable, Sendable {
    let operation_id:String
    let expected_revision:Int
    let description:String?
    enum CodingKeys:String,CodingKey {case operation_id,expected_revision,description}
    func encode(to encoder:any Encoder) throws {
        var container=encoder.container(keyedBy:CodingKeys.self)
        try container.encode(operation_id,forKey:.operation_id)
        try container.encode(expected_revision,forKey:.expected_revision)
        if let description {try container.encode(description,forKey:.description)}
        else {try container.encodeNil(forKey:.description)}
    }
}
struct ConceptBaselineAccess: Decodable, Sendable {
    let contract_version:String; let actor_id:String; let context_id:String; let concept_id:String
    let binding_id:String; let producer_source:String; let source_revision:Int
    let document_language:String; let can_prepare:Bool; let expires_at:String
}
struct ConceptBaselineHistory: Decodable, Sendable {
    struct Entry: Decodable, Identifiable, Sendable {let operation_id:String;let source_revision:Int;var id:String{operation_id}}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String
    let binding_id:String;let producer_source:String;let operations:[Entry]
}
struct ConceptBaselineResult: Decodable, Sendable {
    struct Product:Decodable,Sendable {let name:String;let purpose:String;let users:String;let non_goals:String;let constraints:String;let open_questions:[String]}
    struct Artifact:Decodable,Identifiable,Sendable {let path:String;let mode:Int;let sha256:String;let content:String;var id:String{path}}
    struct Documents:Decodable,Sendable {let state:String;let original_contract_version:String;let summary:String;let artifacts:[Artifact];let observations:String;let repository_quality:String}
    struct Proposal:Decodable,Sendable {
        let contract_version:String;let instance_id:String;let principal_id:String;let audience:String;let dossier_id:String
        let operation_id:String;let plan_id:String;let proposal_kind:String;let request_digest:String;let record_digest:String
        let result:Documents;let read_only_result:Bool;let approval:String;let registration:String
    }
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let operation_id:String
    let source_revision:Int;let current_revision:Int;let source_digest:String;let producer_source:String;let binding_id:String
    let unknown_fields:[String];let source_product:Product;let proposal:Proposal;let status:String
    func validate(_ connection:ConceptConnection,concept:ProjectConcept,operation:String,access:ConceptBaselineAccess) throws {
        guard contract_version=="workspace-concept-baseline/1",actor_id==concept.actor_id,context_id==connection.access.projectID,
              concept_id==concept.id,operation_id==operation,binding_id==access.binding_id,producer_source==access.producer_source,
              source_revision>0,current_revision>=source_revision,status=="PROPOSAL_PROJECT_NOT_CONFIGURED",
              proposal.contract_version=="forge-project-proposal-http/v1",proposal.operation_id==operation,
              proposal.proposal_kind=="pb-render/1.0",proposal.read_only_result,proposal.approval=="NOT_PERFORMED",proposal.registration=="NOT_PERFORMED",
              proposal.result.state=="PROPOSED_NOT_APPROVED",proposal.result.original_contract_version=="pb-render/1.0",
              proposal.result.observations=="SUPPLIED_UNVERIFIED",proposal.result.repository_quality=="NOT_ASSESSED",
              proposal.result.artifacts.count<=64,!proposal.result.artifacts.isEmpty,
              Set(proposal.result.artifacts.map(\.path)).count==proposal.result.artifacts.count,
              source_product.open_questions.count<=32,unknown_fields.allSatisfy({["purpose","users","non_goals","constraints"].contains($0)}) else {throw ConceptError.invalid}
        for artifact in proposal.result.artifacts {
            let data=Data(artifact.content.utf8)
            guard !artifact.path.hasPrefix("/"),!artifact.path.contains("\\"),
                  !artifact.path.split(separator:"/",omittingEmptySubsequences:false).contains(where:{$0.isEmpty || $0==".." || $0=="." || $0==".git"}),
                  artifact.mode==420,data.count<=131072,
                  SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==artifact.sha256 else {throw ConceptError.invalid}
        }
    }
}
protocol ConceptBaselineServing:Sendable {
    func access(_ connection:ConceptConnection,concept:String) async throws -> ConceptBaselineAccess
    func history(_ connection:ConceptConnection,concept:String) async throws -> ConceptBaselineHistory
    func prepare(_ connection:ConceptConnection,concept:String,command:ConceptBaselineCommand) async throws -> ConceptBaselineResult
    func read(_ connection:ConceptConnection,concept:String,operation:String) async throws -> ConceptBaselineResult
}
struct ConceptBaselineTransport:ConceptBaselineServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=65;configuration.timeoutIntervalForResource=75
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request<T:Decodable>(_ type:T.Type,_ connection:ConceptConnection,concept:String,action:String,body:Data?=nil) async throws -> T {
        guard concept.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else {throw ConceptError.invalid}
        let url=try ServerEndpoint(connection.access.endpoint).route("/v1/concept-baselines/"+concept+"/"+action)
        var request=URLRequest(url:url);request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(connection.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(connection.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        if body != nil {request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url else {throw ConceptError.invalid}
        switch http.statusCode {
        case 200:break
        case 401,403:throw ConceptError.denied
        case 404:
            let code=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            guard code=="BASELINE_NOT_FOUND" || code=="PROPOSAL_NOT_FOUND" else {throw ConceptError.unavailable}
            throw ConceptError.notFound
        case 409:
            let code=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            if code=="BASELINE_CONFLICT" {throw ConceptBaselineError.sourceRejected}
            if code=="PROPOSAL_IDEMPOTENCY_CONFLICT" {throw ConceptError.conflict}
            throw ConceptError.denied
        case 400:throw ConceptError.invalid
        default:throw ConceptError.unavailable
        }
        guard data.count<=1150000,http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json")==true else {throw ConceptError.invalid}
        guard let value=try? JSONDecoder().decode(T.self,from:data) else {throw ConceptError.invalid}
        return value
    }
    func access(_ connection:ConceptConnection,concept:String) async throws -> ConceptBaselineAccess {try await request(ConceptBaselineAccess.self,connection,concept:concept,action:"access")}
    func history(_ connection:ConceptConnection,concept:String) async throws -> ConceptBaselineHistory {try await request(ConceptBaselineHistory.self,connection,concept:concept,action:"operations")}
    func prepare(_ connection:ConceptConnection,concept:String,command:ConceptBaselineCommand) async throws -> ConceptBaselineResult {try await request(ConceptBaselineResult.self,connection,concept:concept,action:"prepare",body:JSONEncoder().encode(command))}
    func read(_ connection:ConceptConnection,concept:String,operation:String) async throws -> ConceptBaselineResult {
        guard operation.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else {throw ConceptError.invalid}
        return try await request(ConceptBaselineResult.self,connection,concept:concept,action:"operations/"+operation)
    }
}
