import Foundation

enum AdvisoryAnswerCategory:String,CaseIterable,Identifiable {
    case summary,alternatives,questions,suggestions
    var id:String { rawValue }
    func items(_ turn:AdvisoryTurnRecord) -> [String] {
        guard turn.hasValidatedAdvice,let output=turn.outcome?.output else { return [] }
        switch self {
        case .summary:return [output.summary]
        case .alternatives:return output.alternatives
        case .questions:return output.questions
        case .suggestions:return output.suggestions
        }
    }
}

enum AdvisorySourceInspection:Equatable {
    case metadata(AdvisorySourceMetadata)
    case unavailable(String)
}

enum AdvisoryInspector {
    static func source(_ reference:String,turn:AdvisoryTurnRecord,capability:AdvisoryCapability?) -> AdvisorySourceInspection {
        guard let cap=capability,cap.instance_id==turn.request.instance_id,
              cap.project_id==turn.request.project_id,cap.repository_id==turn.request.repository_id,
              cap.conversation_ids.contains(turn.request.conversation_id) else { return .unavailable("sourceUnavailable") }
        guard turn.context.evidence_references.contains(reference),
              let selected=turn.request.selected_sources.first(where:{reference=="advisory-source:\($0.source_id):\($0.version)"}),
              turn.context.selected_sources.contains(selected),turn.context.included_sources.contains(selected.source_id) else { return .unavailable("sourceUnlinked") }
        let candidates=cap.available_sources.filter{$0.source_id==selected.source_id && $0.version==selected.version}
        guard !candidates.isEmpty else { return .unavailable("sourceVersionMissing") }
        guard candidates.count==1 else { return .unavailable("sourceAmbiguous") }
        let metadata=candidates[0]
        let components=metadata.path.split(separator:"/",omittingEmptySubsequences:false)
        guard metadata.state=="ACTIVE",AdvisoryWire.safe(metadata.source_id),AdvisoryWire.safe(metadata.path),
              metadata.repository.range(of:"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$",options:.regularExpression) != nil,
              metadata.revision.range(of:"^[0-9a-f]{40}$",options:.regularExpression) != nil,
              metadata.content_digest.range(of:"^sha256:[0-9a-f]{64}$",options:.regularExpression) != nil,
              !metadata.path.hasPrefix("~"),!metadata.path.contains(":"),!metadata.path.contains("\\"),
              !components.contains(where:{$0.isEmpty || $0==".." || $0=="."}) else { return .unavailable("sourceUnverifiable") }
        return .metadata(metadata)
    }
}
