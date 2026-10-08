import Foundation

struct AdvisoryUsage: Codable, Equatable, Sendable { let input_tokens: Int; let output_tokens: Int }
struct AdvisoryScope: Codable, Equatable, Sendable { let instance_id: String; let project_id: String; let repository_id: String }

struct AdvisorySource: Codable, Equatable, Sendable {
    let source_id: String
    let version: String
}

struct AdvisorySourceMetadata: Codable, Equatable, Sendable {
    let source_id: String
    let state: String
    let repository: String
    let revision: String
    let path: String
    let content_digest: String
    let version: String
}

struct AdvisoryRequest: Codable, Equatable, Sendable {
    let contract_version: String
    let turn_id: String
    let instance_id: String
    let project_id: String
    let repository_id: String
    let conversation_id: String
    let advisor_kind: String
    let objective: String
    let expected_revision: Int
    let context_revision: String
    let selected_sources: [AdvisorySource]
}

struct AdvisoryProvider: Codable, Equatable, Sendable {
    let provider_id: String
    let requested_model: String?
    let requested_profile: String?
    let requested_effort: String
    let policy_digest: String
    let generation_digest: String
    let configuration_revision: Int
    let input_token_bound: Int
    let context_token_bound: Int
    let output_token_bound: Int
}

struct AdvisoryDiagnostic: Codable, Equatable, Sendable {
    let classification: String
    let process_started: Bool
    let exception_type: String?
    let errno: Int?
    let timed_out: Bool
    let elapsed_milliseconds: Int?
    let returncode: Int?
    let error_category: String?
    let terminal_events: [String]
}

struct AdvisoryOutput: Codable, Equatable, Sendable {
    let contract_version: String
    let request_digest: String
    let advisor_kind: String
    let summary: String
    let alternatives: [String]
    let questions: [String]
    let suggestions: [String]
    let evidence_references: [String]
    let applied: Bool
}

struct AdvisoryOutcome: Codable, Equatable, Sendable {
    let execution: String
    let diagnostic: AdvisoryDiagnostic
    let usage: AdvisoryUsage?
    let usage_status: String
    let observed_model: String
    let observed_effort: String
    let output: AdvisoryOutput?
    let result_digest: String?
    let error_code: String?
}

struct AdvisoryContext: Codable, Equatable, Sendable {
    let instance_id: String
    let project_id: String
    let repository_id: String
    let dataset_generation: Int
    let included_sources: [String]
    let selected_sources: [AdvisorySource]
    let missing_sources: [String]
    let freshness: String
    let evidence_references: [String]
    let limitations: [String]
}

struct AdvisoryTurnRecord: Codable, Equatable, Sendable {
    let request: AdvisoryRequest
    let request_digest: String
    let session_id: String
    let invocation_id: String
    let context: AdvisoryContext
    let provider: AdvisoryProvider
    let status: String
    let lifecycle: [String]
    let execution: String
    let outcome: AdvisoryOutcome?
    let admitted_at: String
    let grant_id: String
    let consumption: Int
}

struct AdvisoryCapability: Codable, Equatable, Sendable {
    let contract_version: String
    let supported_modes: [String]
    let unsupported: [String]
    let project_id: String
    let repository_id: String
    let instance_id: String
    let conversation_ids: [String]
    let context: AdvisoryContext
    let context_revision: String
    let maximum_turns: Int
    let available_sources: [AdvisorySourceMetadata]
    let max_concurrent_invocations_per_instance: Int
    let cancel_request_supported: Bool
    let provider_stop_supported: Bool
    let retained_principal_consumed_turns: Int
    let live_model_quality: String
    let unknown_usage: String
    let read_only: Bool
}

struct AdvisoryHistory: Codable, Equatable, Sendable {
    let contract_version: String
    let conversation_id: String
    let scope: AdvisoryScope
    let revision: Int
    let turns: [AdvisoryTurnRecord]
    let next_cursor: Int?
    let consumed_turns: Int
    let maximum_turns: Int
    let retention: String
    let read_only: Bool
}

struct AdvisoryCancelRequest: Codable, Equatable, Sendable {
    let contract_version: String
    let expected_revision: Int
    let request_digest: String
}

struct AdvisoryObservation: Sendable {
    let turn: AdvisoryTurnRecord
    let currentRevision: Int
}


extension AdvisoryTurnRecord {
    var hasValidatedAdvice: Bool { status=="COMPLETE" && outcome?.output != nil }
}
