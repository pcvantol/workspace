import Foundation

struct CandidateEffectPolicy: Codable, Equatable, Sendable {
    var contract_version: String
    var mode: String
    var delivery: String
    var read_paths: [String]
    var write_paths: [String]
}

struct CandidateFields: Codable, Equatable, Sendable {
    var title: String
    var objective: String
    var business_value: String
    var engineering_value: String
    var architectural_value: String
    var rationale: String
    var confidence: Int
    var scope: [String]
    var exclusions: [String]
    var acceptance_criteria: [String]
    var architecture_constraints: [String]
    var dependencies: [String]
    var effect_policy: CandidateEffectPolicy
}

struct CandidateSource: Codable, Equatable, Sendable {
    var turn_id: String
    var session_id: String
    var invocation_id: String
    var request_digest: String
    var result_digest: String
    var context_revision: String
    var advisor_kind: String
    var conversation_revision: Int
    var selected_sources: [AdvisorySource]
    var evidence_references: [String]
    var advice_summary: String
}

struct CandidateProposal: Codable, Equatable, Sendable {
    var contract_version: String
    var principal_reference: String
    var instance_id: String
    var project_id: String
    var repository_id: String
    var conversation_id: String
    var proposal_id: String
    var proposal_revision: Int
    var source: CandidateSource
    var fields: CandidateFields
    var field_origins: [String:String]
    var proposal_digest: String
}

struct CandidateDocument: Codable, Equatable, Sendable {
    var id: String
    var recommendation_id: String
    var title: String
    var objective: String
    var scope: [String]
    var acceptance_criteria: [String]
    var architecture_constraints: [String]
    var dependencies: [String]
    var effect_policy: CandidateEffectPolicy
}

struct CandidateReceipt: Codable, Equatable, Sendable {
    var contract_version: String
    var operation_id: String
    var principal_reference: String
    var registration_key: String
    var proposal_digest: String
    var proposal_revision: Int
    var source: CandidateSource
    var candidate: CandidateDocument
    var recommendation_id: String
    var candidate_digest: String
    var recommendation_digest: String
    var registered_at: String
    var status_at_registration: String
    var rationale: String
}

struct CandidateCurrent: Codable, Equatable, Sendable {
    var candidate: CandidateDocument
    var candidate_digest: String
    var recommendation_status: String
    var conversation_revision: Int
    var source_fresh: Bool
    var mission_allocation: Bool
}

struct CandidateRegistration: Codable, Equatable, Sendable {
    var contract_version: String
    var recorded: Bool
    var original_receipt: CandidateReceipt
    var current: CandidateCurrent
}

struct CandidateSaveRequest: Codable, Equatable, Sendable {
    var contract_version: String
    var instance_id: String
    var project_id: String
    var repository_id: String
    var conversation_id: String
    var proposal_id: String
    var turn_id: String
    var expected_revision: Int
    var expected_conversation_revision: Int
    var context_revision: String
    var fields: CandidateFields
}

struct CandidateRegistrationRequest: Codable, Equatable, Sendable {
    var contract_version: String
    var instance_id: String
    var project_id: String
    var repository_id: String
    var conversation_id: String
    var operation_id: String
    var proposal_id: String
    var proposal_revision: Int
    var proposal_digest: String
    var expected_conversation_revision: Int
    var context_revision: String
    var confirm: Bool
}

struct CandidateCapability: Codable, Equatable, Sendable {
    var contract_version: String
    var instance_id: String
    var project_id: String
    var repository_id: String
    var conversation_id: String
    var proposal_ids: [String]
    var maximum_registrations: Int
    var registration_authority: String
    var additional_model_calls: Int
    var maximum_proposals_per_instance: Int
    var maximum_revisions_per_proposal: Int
    var read_only: Bool
}

struct CandidateSourceRead: Codable, Equatable, Sendable {
    var contract_version: String
    var source: CandidateSource
    var read_only: Bool
}

struct CandidateSaved: Codable, Equatable, Sendable {
    var contract_version: String
    var proposal: CandidateProposal
    var registered: Bool
    var additional_model_calls: Int
}

struct CandidatePreview: Codable, Equatable, Sendable {
    var contract_version: String
    var proposal: CandidateProposal
    var latest_revision: Int
    var candidate_preview: CandidateDocument
    var registration: CandidateRegistration?
    var read_only: Bool
}

struct CandidatePending: Codable, Equatable, Sendable {
    var contract_version: String
    var state: String
    var operation_id: String
    var read_only: Bool
}

extension CandidateSource {
    func matches(_ turn:AdvisoryTurnRecord) -> Bool {
        turn_id==turn.request.turn_id && request_digest==turn.request_digest && result_digest==turn.outcome?.result_digest &&
        session_id==turn.session_id && invocation_id==turn.invocation_id && context_revision==turn.request.context_revision &&
        advisor_kind==turn.request.advisor_kind && selected_sources==turn.request.selected_sources
    }
}
extension CandidateProposal {
    func registrationRequest(operationID:String) -> CandidateRegistrationRequest {
        CandidateRegistrationRequest(contract_version:CandidateWire.contract,instance_id:instance_id,project_id:project_id,repository_id:repository_id,
            conversation_id:conversation_id,operation_id:operationID,proposal_id:proposal_id,proposal_revision:proposal_revision,
            proposal_digest:proposal_digest,expected_conversation_revision:source.conversation_revision,context_revision:source.context_revision,confirm:true)
    }
}
