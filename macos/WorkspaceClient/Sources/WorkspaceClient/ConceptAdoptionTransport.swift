import Foundation
import CryptoKit

enum ConceptAdoptionError:Error {case sourceRejected}

struct ConceptAdoptionCommand:Codable,Equatable,Sendable {
    struct Mapping:Codable,Equatable,Sendable {let artifact_path:String;let source_path:String;let choice:String}
    let operation_id:String;let expected_revision:Int;let requested_artifacts:[String];let mappings:[Mapping]
}
struct ConceptAdoptionSources:Decodable,Sendable {
    struct Source:Decodable,Identifiable,Sendable {let id:String;let label:String;let source_options:[String];let setup_metadata_not_observed:Bool;let can_prepare:Bool;let expires_at:String}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let sources:[Source]
}
struct ConceptAdoptionAccess:Decodable,Sendable {
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String;let source_revision:Int;let can_prepare:Bool;let expires_at:String
}
struct ConceptAdoptionHistory:Decodable,Sendable {
    struct Entry:Decodable,Identifiable,Sendable {let operation_id:String;let source_revision:Int;var id:String{operation_id}}
    let operations:[Entry]
}
struct ConceptAdoptionResult:Decodable,Sendable {
    struct Content:Decodable,Sendable {let status:String?;let sha256:String?;let content:String?;let mode:Int?}
    struct Entry:Decodable,Identifiable,Sendable {let artifact_path:String;let source_path:String;let operation:String;let reason:String;let before:Content;let after:Content;let mapping_source:Content;let diff:String;let decisions:[String];let mapping_only:Bool;var id:String{artifact_path}}
    struct Observation:Decodable,Sendable {let producer_revision:String;let instance_id:String;let host_id:String;let operation_id:String;let observed_at:String;let snapshot_digest:String;let selection:[String];let exclusions:[String];let freshness:String;let completeness:String}
    struct Document:Decodable,Sendable {let contract_version:String;let state:String;let proposal_digest:String;let input_digest:String;let repository_quality:String;let identity_registration:String;let entries:[Entry];let decisions:[String];let source_observation:Observation}
    struct Artifact:Decodable,Sendable {let path:String;let mode:Int;let content:String;let sha256:String}
    struct Packet:Decodable,Sendable {let state:String;let input_digest:String;let summary:String;let artifacts:[Artifact];let result_digest:String;let observations:String;let repository_quality:String;let source_binding:Observation;let approval:String;let registration:String}
    struct Proposal:Decodable,Sendable {let contract_version:String;let instance_id:String;let principal_id:String;let audience:String;let dossier_id:String;let pairing_id:String;let operation_id:String;let plan_id:String;let request_digest:String;let state:String;let result:Packet?;let proposal_kind:String;let original_intent:Bool;let approval:String;let registration:String}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String;let operation_id:String;let source_revision:Int;let current_revision:Int;let source_digest:String;let proposal:Proposal;let document:Document?
    static let pin="cd483fd9b17a96d0deac0f0264ab6fc32c75e778"
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    func validate(_ c:ConceptConnection,concept:ProjectConcept,source:String,operation:String) throws {
        guard contract_version=="workspace-concept-adoption/1",actor_id==concept.actor_id,context_id==c.access.projectID,concept_id==concept.id,binding_id==source,producer_source==Self.pin,operation_id==operation,source_revision>0,current_revision>=source_revision,
              proposal.operation_id==operation,proposal.contract_version=="forge-ep-inspection-adoption-preview/v1",proposal.proposal_kind=="ep-inspection-adoption-preview/1.0",proposal.original_intent,proposal.approval=="NOT_PERFORMED",proposal.registration=="NOT_PERFORMED" else{throw ConceptError.invalid}
        if proposal.state=="PREPARING" {guard proposal.result==nil,document==nil else{throw ConceptError.invalid};return}
        guard proposal.state=="PREPARED",let packet=proposal.result,let doc=document,packet.state=="PROPOSED_NOT_APPROVED",packet.observations=="AUTHENTICATED_EP_HISTORICAL_WITHIN_SELECTION",packet.repository_quality=="NOT_ASSESSED",packet.approval=="NOT_PERFORMED",packet.registration=="NOT_PERFORMED",doc.state==packet.state,doc.repository_quality=="NOT_ASSESSED",doc.identity_registration=="NOT_PERFORMED",doc.entries.count<=20,Set(doc.entries.map(\.id)).count==doc.entries.count,packet.artifacts.count==2,Set(packet.artifacts.map(\.path))==Set(["README.md","proposal.json"]) else{throw ConceptError.invalid}
        guard doc.source_observation.producer_revision=="f3b56303b561a7193965f4aa41fd8da744a8c1c2",doc.source_observation.snapshot_digest==packet.source_binding.snapshot_digest,doc.source_observation.freshness=="AS_OF_OBSERVATION_NOT_CONTINUOUS",doc.source_observation.completeness=="COMPLETE_WITHIN_SELECTION",WorksetReleaseWire.date(doc.source_observation.observed_at) != nil else{throw ConceptError.invalid}
        for a in packet.artifacts {guard a.mode==420,a.content.utf8.count<=131072,Self.hash(Data(a.content.utf8))==a.sha256 else{throw ConceptError.invalid}}
        for e in doc.entries {
            guard ["KEEP","LINK_EXISTING","PROPOSE_ADDITION","PROPOSE_CHANGE","CONFLICT","INSUFFICIENT_INFORMATION"].contains(e.operation),!e.artifact_path.hasPrefix("/"),!e.artifact_path.contains(".."),e.diff.utf8.count<=262144 else{throw ConceptError.invalid}
            for content in [e.before,e.mapping_source,e.after] {if let text=content.content {guard let digest=content.sha256,Self.hash(Data(text.utf8))==digest else{throw ConceptError.invalid}}}
        }
    }
}
protocol ConceptAdoptionServing:Sendable {
    func sources(_ c:ConceptConnection,concept:String) async throws->ConceptAdoptionSources
    func access(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionAccess
    func history(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionHistory
    func prepare(_ c:ConceptConnection,concept:String,source:String,command:ConceptAdoptionCommand) async throws->ConceptAdoptionResult
    func read(_ c:ConceptConnection,concept:String,source:String,operation:String) async throws->ConceptAdoptionResult
}
struct ConceptAdoptionTransport:ConceptAdoptionServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil;configuration.timeoutIntervalForRequest=65;configuration.timeoutIntervalForResource=75;session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)}
    func request<T:Decodable>(_ type:T.Type,_ c:ConceptConnection,concept:String,action:String,body:Data?=nil) async throws->T {
        guard concept.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil,action.range(of:"^(sources|[0-9a-f]{32}/(access|prepare|operations|operations/[0-9a-f]{32}))$",options:.regularExpression) != nil else{throw ConceptError.invalid}
        let url=try ServerEndpoint(c.access.endpoint).route("/v1/concept-adoptions/"+concept+"/"+action);var req=URLRequest(url:url);req.httpMethod=body==nil ? "GET":"POST";req.httpBody=body
        req.setValue("Bearer "+c.bearer,forHTTPHeaderField:"Authorization");req.setValue(c.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance");req.setValue(c.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant");if body != nil {req.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:req);guard let http=response as? HTTPURLResponse,http.url==url,data.count<=1150000,http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json")==true else{throw ConceptError.invalid}
        switch http.statusCode {case 200:break;case 401,403:throw ConceptError.denied;case 409:
            if action.hasSuffix("/prepare"),let error=try? JSONDecoder().decode([String:String].self,from:data),error==["error":"ADOPTION_SOURCE_REJECTED_BEFORE_CAPTURE"] {throw ConceptAdoptionError.sourceRejected}
            throw ConceptError.conflict;case 404:throw ConceptError.notFound;case 400:throw ConceptError.invalid;default:throw ConceptError.unavailable}
        return try JSONDecoder().decode(T.self,from:data)
    }
    func sources(_ c:ConceptConnection,concept:String) async throws->ConceptAdoptionSources {try await request(ConceptAdoptionSources.self,c,concept:concept,action:"sources")}
    func access(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionAccess {try await request(ConceptAdoptionAccess.self,c,concept:concept,action:source+"/access")}
    func history(_ c:ConceptConnection,concept:String,source:String) async throws->ConceptAdoptionHistory {try await request(ConceptAdoptionHistory.self,c,concept:concept,action:source+"/operations")}
    func prepare(_ c:ConceptConnection,concept:String,source:String,command:ConceptAdoptionCommand) async throws->ConceptAdoptionResult {try await request(ConceptAdoptionResult.self,c,concept:concept,action:source+"/prepare",body:JSONEncoder().encode(command))}
    func read(_ c:ConceptConnection,concept:String,source:String,operation:String) async throws->ConceptAdoptionResult {try await request(ConceptAdoptionResult.self,c,concept:concept,action:source+"/operations/"+operation)}
}
