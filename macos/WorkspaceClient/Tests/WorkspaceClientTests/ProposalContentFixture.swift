import Foundation
@testable import WorkspaceClient

// Synthetic contract fixture; actual producer and packaged GUI are separate.
@MainActor final class ContentFixture:ProposalContentServing {
    let source:ConceptBaselineResult
    var history:[[String:Any]]=[]
    var posts:[ProposalContentCommand]=[]
    var lost=false
    var ownMissing=false
    var loseBeforeCapture=false
    var currentRevision=3
    var failure:Error?
    var binding="content-pair"
    var roles=["ARCHITECTURE","BUSINESS"]
    var permissions=["DECIDE","READ"]
    var expires="2099-01-01T00:00:00Z"
    var rejected:[String]=[]
    var pending:[[String:Any]]=[]
    var stale=false
    var wait=false
    var waiting:CheckedContinuation<ProposalContentResult,Error>?
    init()throws {source=try CompareFixture.result(CompareFixture.first)}
    var human:[String:Any] {["operator_id":"synthetic-human","operator_binding_version":1,"installation_id":"fixture-install"]}
    var subject:[String:Any] {["plan_id":source.proposal.plan_id,"proposal_principal_id":source.proposal.principal_id,"proposal_kind":"pb-render/1.0","input_digest":String(repeating:"a",count:64),"result_digest":String(repeating:"b",count:64),"record_digest":source.proposal.record_digest,"manifest_digest":String(repeating:"d",count:64),"baseline":"portable-docs/1.0.0","profile_id":"CONTENT_BASELINE_ONLY/1.0","source_references":[["reference":"declared","owner":"USER_DECLARED","digest":String(repeating:"e",count:64)]],"concept_revision":NSNull()]}
    func object(original:String?=nil)->[String:Any] {
        var latest:[String:String]=[:]
        for record in history {let r=record["request"] as! [String:Any];latest[r["role"] as! String]=r["decision"] as? String}
        let state=latest.values.contains("REQUEST_CHANGES") ? "CHANGES_REQUESTED":(["BUSINESS","ARCHITECTURE"].allSatisfy{latest[$0]=="APPROVE_CONTENT"} ? "CONTENT_APPROVED":"DECISION_NEEDED")
        let decision:[String:Any]=["contract_version":"forge-project-proposal-content-decision/v1","instance_id":source.proposal.instance_id,"principal_id":"synthetic-human","audience":source.proposal.audience,"dossier_id":source.proposal.dossier_id,"plan_id":source.proposal.plan_id,"subject":subject,"decision_revision":history.count,"state":state,"required_roles":["BUSINESS","ARCHITECTURE"],"open_points":source.source_product.open_questions,"history":history,"original_decision":history.first(where:{($0["request"] as! [String:Any])["operation_id"] as? String==original}) as Any? ?? NSNull(),"meaning":"CONTENT_BASELINE_ONLY","effects_authorized":false,"execution_readiness":"NOT_ASSESSED","concept_revision_qualification":"NOT_STRUCTURALLY_PROVIDED_BY_R52","original_proposal_state":"PROPOSED_NOT_APPROVED"]
        return ["contract_version":"workspace-proposal-content-decision/1","actor_id":"alice","context_id":"context","concept_id":CompareFixture.concept.id,"binding_id":binding,"producer_source":source.producer_source,"source_operation_id":source.operation_id,"source_revision":1,"current_revision":currentRevision,"selection_digest":String(repeating:String(history.count),count:64),"permissions":permissions,"roles":roles,"expires_at":expires,"human_binding":human,"pending_operations":pending,"rejected_operations":rejected,"decision":decision]
    }
    func decode(_ object:[String:Any])throws->ProposalContentResult {try JSONDecoder().decode(ProposalContentResult.self,from:JSONSerialization.data(withJSONObject:object))}
    func result(original:String?=nil)throws->ProposalContentResult {try decode(object(original:original))}
    func proposal(_ connection:ConceptConnection,concept:String,source:String)async throws->ProposalContentResult {
        if wait {wait=false;return try await withCheckedThrowingContinuation{waiting=$0}}
        if let failure {throw failure};return try result()
    }
    func original(_ connection:ConceptConnection,concept:String,operation:String)async throws->ProposalContentResult {
        if let failure {throw failure}
        guard history.contains(where:{($0["request"] as! [String:Any])["operation_id"] as? String==operation}) else {if ownMissing {throw ProposalContentError.ownIntentNotFound};throw ConceptError.notFound}
        return try result(original:operation)
    }
    func decide(_ connection:ConceptConnection,concept:String,command:ProposalContentCommand)async throws->ProposalContentResult {
        if let failure {throw failure}
        if loseBeforeCapture {throw ConceptError.unavailable}
        if stale {rejected.append(command.operation_id);throw ConceptError.conflict}
        posts.append(command);pending.removeAll{($0["operation_id"] as? String)==command.operation_id}
        let request:[String:Any]=["contract_version":"forge-project-proposal-content-decision/v1","instance_id":self.source.proposal.instance_id,"dossier_id":self.source.proposal.dossier_id,"operation_id":command.operation_id,"plan_id":self.source.proposal.plan_id,"subject":subject,"profile_id":"CONTENT_BASELINE_ONLY/1.0","role":command.role,"decision":command.decision,"expected_decision_revision":history.count,"previous_decision_id":history.last?["decision_id"] ?? NSNull(),"reason":command.reason,"acknowledged_open_points":command.acknowledged_open_points]
        history.append(["decision_id":"decision-"+String(history.count),"request":request,"request_digest":String(repeating:"f",count:64),"principal_id":"synthetic-human","audience":self.source.proposal.audience,"human_binding":human,"grant_id":"finite-human-grant","occurred_at":"2026-10-15T14:00:00Z","revision":history.count+1,"integrity":String(repeating:"e",count:64)])
        if lost {lost=false;throw ConceptError.unavailable}
        return try result(original:command.operation_id)
    }
}
