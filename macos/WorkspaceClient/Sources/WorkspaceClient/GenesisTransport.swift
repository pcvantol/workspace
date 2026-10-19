import Foundation
import CryptoKit

struct GenesisPlanCommand:Codable,Equatable,Sendable {
    let operation_id:String;let source_operation_id:String;let expected_concept_revision:Int
    let selection_digest:String;let target_id:String
}
struct GenesisEffectCommand:Codable,Equatable,Sendable {
    let operation_id:String;let source_operation_id:String;let expected_concept_revision:Int
    let selection_digest:String;let plan_operation_id:String;let decision:String;let reason:String
}
struct GenesisTarget:Decodable,Identifiable,Sendable {let id:String;let label:String}
struct GenesisPlan:Decodable,Sendable {
    struct Target:Decodable,Sendable {let ep_instance_id:String;let placement_ref:String;let target_ref:String;let required_before:String;let absence_evidence:String;let placement_semantics:String}
    struct File:Decodable,Identifiable,Sendable {let path:String;let mode:Int;let sha256:String;let content:String;let bytes:Int;let expected_before:String;var id:String{path}}
    struct Documents:Decodable,Sendable {
        struct Identity:Decodable,Sendable {let project_id:String;let repository_id:String;let authority_repository_id:String}
        let files:[File];let bundle_digest:String;let manifest_digest:String;let baseline:String;let identity:Identity
    }
    let contract_version:String;let profile_id:String;let effect_purpose:String;let plan_id:String;let plan_digest:String;let plan_revision:Int
    let operation_id:String;let request_digest:String;let source_subject:ProposalContentSubject
    let content_revision:Int;let original_content_decisions:[Content];let state:String;let identity_state:String;let reservation:String
    let target:Target;let effects:[String];let expires_at:String;let open_questions:[String];let blocking_open_points:[String];let documents:Documents
    let execution_authorized:Bool;let target_write:String;let ep_admission:String;let ep_credential:String;let project_readiness:String;let mission:String
    struct Content:Decodable,Identifiable,Sendable {let decision_id:String;let role:String;let decision:String;let revision:Int;var id:String{decision_id}}
}
struct GenesisDecision:Decodable,Identifiable,Sendable {
    let decision_id:String;let decision_revision:Int;let principal_id:String;let grant_id:String;let human_binding:ProposalContentHuman
    let operation_id:String;let plan_id:String;let plan_digest:String;let purpose:String;let decision:String;let reason:String
    let occurred_at:String;let request_digest:String;let decision_digest:String
    var id:String{decision_id}
}
struct GenesisEnvelope:Decodable,Sendable {
    struct Result:Decodable,Sendable {
        let contract_version:String;let plan:GenesisPlan;let effect_decision_revision:Int;let effect_history:[GenesisDecision]
        let original_decision:GenesisDecision?;let effect_decision_eligible:Bool;let inapplicability_reasons:[String]
        let effect_decision_currently_applicable:Bool;let state:String;let execution_authorized:Bool;let target_write:String;let ep_credential:String
    }
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String
    let producer_source:String;let expires_at:String;let current_revision:Int;let source_revision:Int;let source_operation_id:String
    let operation_id:String;let kind:String;let result:Result;let can_decide:Bool?;let selection_digest:String?
    func validate(_ connection:ConceptConnection,concept:ProjectConcept,source:ConceptBaselineResult) throws {
        let p=result.plan
        guard contract_version=="workspace-genesis-plan-decision/1",actor_id==concept.actor_id,context_id==concept.context_id,context_id==connection.access.projectID,concept_id==concept.id,
              current_revision==concept.revision,source_revision==source.source_revision,source_operation_id==source.operation_id,
              producer_source=="8ee60c8409b2c3801e70cf129f20f1ff1480d03b",WorksetReleaseWire.date(expires_at).map({$0>Date()})==true,
              result.contract_version=="forge-genesis-bootstrap-effect-plan/v1",p.contract_version==result.contract_version,p.profile_id=="CREATE_GENESIS_LOCAL/1.0",p.effect_purpose=="GENESIS_BOOTSTRAP_EFFECT_ONLY/1.0",
              !result.execution_authorized,!p.execution_authorized,result.state=="EP_ADMISSION_REQUIRED",p.state==result.state,p.identity_state=="PROPOSED_NOT_RESERVED",p.reservation=="NOT_REQUESTED",
              p.target.absence_evidence=="NOT_OBSERVED_BY_FORGE",p.target.required_before=="ABSENT",p.target.placement_semantics=="EP_OWNER_ALLOWED_DIRECT_CHILD_NEW_TARGET",
              p.target_write=="NOT_PERFORMED",result.target_write==p.target_write,p.ep_credential=="NOT_ISSUED",result.ep_credential==p.ep_credential,p.ep_admission=="NOT_REQUESTED",p.project_readiness=="NOT_ASSESSED",p.mission=="NOT_REQUESTED",
              p.source_subject.plan_id==source.proposal.plan_id,p.source_subject.record_digest==source.proposal.record_digest,p.source_subject.proposal_principal_id==source.proposal.principal_id,
              p.documents.files.count==37,source.proposal.result.artifacts.count==37,Set(p.documents.files.map(\.path)).count==37,
              p.documents.baseline=="portable-docs/1.0.0",p.effects==GenesisCopy.effects,
              result.effect_decision_revision==result.effect_history.count,result.effect_history.count<=8,Set(result.effect_history.map(\.id)).count==result.effect_history.count,
              result.effect_decision_eligible==result.inapplicability_reasons.isEmpty else {throw ConceptError.invalid}
        for (file,original) in zip(p.documents.files,source.proposal.result.artifacts) {
            guard file.path==original.path,file.mode==420,file.mode==original.mode,file.sha256==original.sha256,file.content==original.content,file.bytes==file.content.utf8.count,file.expected_before=="ABSENT",
                  SHA256.hash(data:Data(file.content.utf8)).map({String(format:"%02x",$0)}).joined()==file.sha256 else {throw ConceptError.invalid}
        }
        for (index,d) in result.effect_history.enumerated() {
            guard d.decision_revision==index+1,d.plan_id==p.plan_id,d.plan_digest==p.plan_digest,d.purpose==p.effect_purpose,d.principal_id==d.human_binding.operator_id,
                  ["APPROVE_EFFECT","REQUEST_CHANGES"].contains(d.decision),WorksetReleaseWire.date(d.occurred_at) != nil else {throw ConceptError.invalid}
        }
        if result.effect_decision_currently_applicable {
            guard result.effect_decision_eligible,result.effect_history.last?.decision=="APPROVE_EFFECT" else {throw ConceptError.invalid}
        }
        if let original=result.original_decision {guard result.effect_history.contains(where:{$0.decision_id==original.decision_id}) else {throw ConceptError.invalid}}
    }
}
struct GenesisAccess:Decodable,Sendable {
    struct PlanEntry:Decodable,Identifiable,Sendable {let operation_id:String;let plan_id:String;let plan_revision:Int;var id:String{operation_id}}
    struct Content:Decodable,Sendable {let state:String}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let producer_source:String;let expires_at:String
    let current_revision:Int;let source_revision:Int;let source_operation_id:String;let selection_digest:String
    let targets:[GenesisTarget];let can_plan:Bool;let pending_plan_operations:[String];let plans:[PlanEntry];let latest:GenesisEnvelope?;let content:Content
    func validate(_ connection:ConceptConnection,concept:ProjectConcept,source:ConceptBaselineResult) throws {
        guard contract_version=="workspace-genesis-plan-decision/1",actor_id==concept.actor_id,context_id==concept.context_id,context_id==connection.access.projectID,concept_id==concept.id,current_revision==concept.revision,
              source_operation_id==source.operation_id,source_revision==source.source_revision,producer_source=="8ee60c8409b2c3801e70cf129f20f1ff1480d03b",WorksetReleaseWire.date(expires_at).map({$0>Date()})==true,
              selection_digest.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,targets.count<=8,Set(targets.map(\.id)).count==targets.count,plans.count<=8,pending_plan_operations.count<=256 else {throw ConceptError.invalid}
        if let latest {try latest.validate(connection,concept:concept,source:source)}
    }
}
protocol GenesisServing:Sendable {
    func access(_ connection:ConceptConnection,concept:String,source:String) async throws -> GenesisAccess
    func result(_ connection:ConceptConnection,concept:String,action:String,operation:String?,body:Data?) async throws -> GenesisEnvelope
}
struct GenesisTransport:GenesisServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=60;configuration.timeoutIntervalForResource=65
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request(_ connection:ConceptConnection,concept:String,action:String,operation:String?,body:Data?) async throws -> Data {
        guard ([concept]+(operation.map{[$0]} ?? [])).allSatisfy({$0.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil}),["access","operations","decision-access","plans","decisions"].contains(action) else {throw ConceptError.invalid}
        let url=try ServerEndpoint(connection.access.endpoint).route("/v1/concept-genesis/"+concept+"/"+action+(operation.map{"/"+$0} ?? ""))
        var request=URLRequest(url:url);request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization");request.setValue(connection.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance");request.setValue(connection.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        if body != nil {request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url else {throw ConceptError.invalid}
        if [401,403].contains(http.statusCode) {throw ConceptError.denied}
        guard data.count<=1150000,http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json")==true else {throw ConceptError.invalid}
        if http.statusCode==404 {throw ConceptError.notFound}
        if http.statusCode==409 {throw ConceptError.conflict}
        guard http.statusCode==200 else {throw ConceptError.unavailable}
        return data
    }
    func access(_ connection:ConceptConnection,concept:String,source:String) async throws -> GenesisAccess {
        try JSONDecoder().decode(GenesisAccess.self,from:await request(connection,concept:concept,action:"access",operation:source,body:nil))
    }
    func result(_ connection:ConceptConnection,concept:String,action:String,operation:String?,body:Data?=nil) async throws -> GenesisEnvelope {
        try JSONDecoder().decode(GenesisEnvelope.self,from:await request(connection,concept:concept,action:action,operation:operation,body:body))
    }
}
