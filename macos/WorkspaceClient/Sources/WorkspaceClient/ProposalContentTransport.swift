import Foundation

struct ProposalContentCommand:Codable,Equatable,Sendable {
    let operation_id:String
    let source_operation_id:String
    let expected_concept_revision:Int
    let selection_digest:String
    let role:String
    let decision:String
    let reason:String
    let acknowledged_open_points:[String]
}
struct ProposalContentHuman:Codable,Equatable,Sendable {
    let operator_id:String;let operator_binding_version:Int;let installation_id:String
}
struct ProposalContentSubject:Codable,Equatable,Sendable {
    struct Reference:Codable,Equatable,Sendable {let reference:String;let owner:String;let digest:String}
    let plan_id:String;let proposal_principal_id:String;let proposal_kind:String
    let input_digest:String;let result_digest:String;let record_digest:String;let manifest_digest:String
    let baseline:String;let profile_id:String;let source_references:[Reference];let concept_revision:Int?
}
struct ProposalContentRequest:Decodable,Equatable,Sendable {
    let contract_version:String;let instance_id:String;let dossier_id:String;let operation_id:String;let plan_id:String
    let subject:ProposalContentSubject;let profile_id:String;let role:String;let decision:String
    let expected_decision_revision:Int;let previous_decision_id:String?;let reason:String;let acknowledged_open_points:[String]
}
struct ProposalContentRecord:Decodable,Equatable,Identifiable,Sendable {
    let decision_id:String;let request:ProposalContentRequest;let request_digest:String
    let principal_id:String;let audience:String;let human_binding:ProposalContentHuman;let grant_id:String
    let occurred_at:String;let revision:Int;let integrity:String
    var id:String {decision_id}
}
struct ProposalContentResult:Decodable,Sendable {
    struct Decision:Decodable,Sendable {
        let contract_version:String;let instance_id:String;let principal_id:String;let audience:String;let dossier_id:String
        let plan_id:String;let subject:ProposalContentSubject;let decision_revision:Int;let state:String;let required_roles:[String]
        let open_points:[String];let history:[ProposalContentRecord];let original_decision:ProposalContentRecord?
        let meaning:String;let effects_authorized:Bool;let execution_readiness:String
        let concept_revision_qualification:String;let original_proposal_state:String
    }
    struct Pending:Decodable,Sendable {let operation_id:String;let command:ProposalContentCommand}
    let contract_version:String;let actor_id:String;let context_id:String;let concept_id:String;let binding_id:String;let producer_source:String
    let source_operation_id:String;let source_revision:Int;let current_revision:Int;let selection_digest:String
    let permissions:[String];let roles:[String];let expires_at:String;let human_binding:ProposalContentHuman
    let pending_operations:[Pending];let rejected_operations:[String];let decision:Decision
    func validate(_ connection:ConceptConnection,concept:ProjectConcept,source:ConceptBaselineResult,original:ProposalContentCommand?=nil) throws {
        let value=decision;let subject=value.subject
        func hex(_ text:String)->Bool {text.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil}
        guard contract_version=="workspace-proposal-content-decision/1",actor_id==concept.actor_id,context_id==concept.context_id,context_id==connection.access.projectID,concept_id==concept.id,
              source_operation_id==source.operation_id,source_revision==source.source_revision,current_revision==concept.revision,
              producer_source==source.producer_source,hex(selection_digest),!binding_id.isEmpty,
              WorksetReleaseWire.date(expires_at).map({$0>Date()})==true,
              permissions==["READ"] || permissions==["DECIDE","READ"],roles==Array(Set(roles)).sorted(),roles.allSatisfy({["BUSINESS","ARCHITECTURE"].contains($0)}),roles.isEmpty == !permissions.contains("DECIDE"),
              human_binding.operator_id==value.principal_id,human_binding.operator_binding_version>0,!human_binding.installation_id.isEmpty,
              value.contract_version=="forge-project-proposal-content-decision/v1",value.instance_id==source.proposal.instance_id,value.dossier_id==source.proposal.dossier_id,value.audience==source.proposal.audience,
              value.plan_id==source.proposal.plan_id,subject.plan_id==value.plan_id,subject.proposal_principal_id==source.proposal.principal_id,subject.proposal_kind=="pb-render/1.0",
              subject.record_digest==source.proposal.record_digest,[subject.input_digest,subject.result_digest,subject.record_digest,subject.manifest_digest].allSatisfy(hex),subject.baseline=="portable-docs/1.0.0",subject.profile_id=="CONTENT_BASELINE_ONLY/1.0",subject.concept_revision==nil,
              !subject.source_references.isEmpty,subject.source_references.count<=32,subject.source_references.allSatisfy({hex($0.digest)}),
              value.open_points==source.source_product.open_questions,value.required_roles==["BUSINESS","ARCHITECTURE"],value.history.count<=8,value.decision_revision==value.history.count,Set(value.history.map(\.id)).count==value.history.count,
              ["DECISION_NEEDED","CHANGES_REQUESTED","CONTENT_APPROVED"].contains(value.state),value.meaning=="CONTENT_BASELINE_ONLY",!value.effects_authorized,value.execution_readiness=="NOT_ASSESSED",value.concept_revision_qualification=="NOT_STRUCTURALLY_PROVIDED_BY_R52",value.original_proposal_state=="PROPOSED_NOT_APPROVED",pending_operations.count<=256 else {throw ConceptError.invalid}
        var previous:String?
        for (index,record) in value.history.enumerated() {
            let request=record.request
            guard record.revision==index+1,request.contract_version==value.contract_version,request.instance_id==value.instance_id,request.dossier_id==value.dossier_id,request.subject==subject,request.plan_id==value.plan_id,request.profile_id==subject.profile_id,
                  request.expected_decision_revision==index,request.previous_decision_id==previous,value.required_roles.contains(request.role),["APPROVE_CONTENT","REQUEST_CHANGES"].contains(request.decision),
                  !request.reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,request.reason.unicodeScalars.count<=2000,
                  request.decision != "APPROVE_CONTENT" || request.acknowledged_open_points==value.open_points,request.acknowledged_open_points.allSatisfy({value.open_points.contains($0)}),
                  record.principal_id==record.human_binding.operator_id,record.audience==value.audience,record.human_binding.operator_binding_version>0,WorksetReleaseWire.date(record.occurred_at) != nil,hex(record.request_digest),hex(record.integrity) else {throw ConceptError.invalid}
            previous=record.decision_id
        }
        if let original {
            guard let record=value.original_decision,value.history.contains(record),record.principal_id==value.principal_id,record.human_binding==human_binding,record.request.operation_id==original.operation_id,
                  record.request.role==original.role,record.request.decision==original.decision,record.request.reason==original.reason,record.request.acknowledged_open_points==original.acknowledged_open_points else {throw ConceptError.invalid}
        } else if value.original_decision != nil {throw ConceptError.invalid}
    }
}
enum ProposalContentError:Error {case unsupportedProfile;case capacity}
protocol ProposalContentServing:Sendable {
    func proposal(_ connection:ConceptConnection,concept:String,source:String) async throws -> ProposalContentResult
    func decide(_ connection:ConceptConnection,concept:String,command:ProposalContentCommand) async throws -> ProposalContentResult
    func original(_ connection:ConceptConnection,concept:String,operation:String) async throws -> ProposalContentResult
}
struct ProposalContentTransport:ProposalContentServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.timeoutIntervalForRequest=65;configuration.timeoutIntervalForResource=75
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request(_ connection:ConceptConnection,concept:String,action:String,identity:String?,body:Data?=nil) async throws -> ProposalContentResult {
        guard ([concept]+(identity.map{[$0]} ?? [])).allSatisfy({$0.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil}) else {throw ConceptError.invalid}
        let url=try ServerEndpoint(connection.access.endpoint).route("/v1/proposal-content/"+concept+"/"+action+(identity.map{"/"+$0} ?? ""))
        var request=URLRequest(url:url);request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization");request.setValue(connection.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance");request.setValue(connection.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        if body != nil {request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url else {throw ConceptError.invalid}
        if http.statusCode==401 || http.statusCode==403 {throw ConceptError.denied}
        guard data.count<=1150000,http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json")==true else {throw ConceptError.invalid}
        if http.statusCode != 200 {
            let code=(try? JSONSerialization.jsonObject(with:data) as? [String:String])?["error"]
            if http.statusCode==404 && (code=="CONTENT_NOT_FOUND" || code=="CONTENT_OWN_NOT_FOUND") {throw ConceptError.notFound}
            if code=="CONTENT_PROFILE_UNSUPPORTED" {throw ProposalContentError.unsupportedProfile}
            if code=="CONTENT_DECISION_CAPACITY" || code=="CONTENT_STORAGE_CAPACITY" {throw ProposalContentError.capacity}
            if http.statusCode==409 {throw ConceptError.conflict}
            throw ConceptError.unavailable
        }
        return try JSONDecoder().decode(ProposalContentResult.self,from:data)
    }
    func proposal(_ connection:ConceptConnection,concept:String,source:String) async throws -> ProposalContentResult {try await request(connection,concept:concept,action:"proposals",identity:source)}
    func decide(_ connection:ConceptConnection,concept:String,command:ProposalContentCommand) async throws -> ProposalContentResult {try await request(connection,concept:concept,action:"decisions",identity:nil,body:JSONEncoder().encode(command))}
    func original(_ connection:ConceptConnection,concept:String,operation:String) async throws -> ProposalContentResult {try await request(connection,concept:concept,action:"operations",identity:operation)}
}
