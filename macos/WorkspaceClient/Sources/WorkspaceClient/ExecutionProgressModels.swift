import Foundation
import CoreFoundation

struct ExecutionSelection:Codable,Equatable,Sendable {
    let project_id:String;let authority_repository_id:String
    let repository_ids:[String];let mission_ids:[String];let producer_ids:[String]
}
struct ExecutionStep:Codable,Equatable,Sendable {let phase:String;let state:String}
struct ExecutionTransition:Codable,Equatable,Sendable {let phase:String;let recorded_at:String?;let responsible_role:String;let wait_reason:String}
struct ExecutionPhase:Codable,Equatable,Sendable {
    let available:Bool;let current_phase:String?;let activity:String;let wait_reason:String;let responsible_role:String
    let steps:[ExecutionStep];let history:[ExecutionTransition];let history_completeness:String;let terminal_outcome:String?
}
struct ExecutionQualification:Codable,Equatable,Sendable {let required_validation_state:String;let run_qualification:String}
struct ExecutionResult:Codable,Equatable,Sendable {let technical_outcome:String;let qualification:ExecutionQualification;let forge_mission_acceptance:String}
struct ExecutionLineage:Codable,Equatable,Sendable {let state:String;let retry_parent_run_id:String?;let attempt_submission_id:String?;let root_submission_id:String?;let retry_parent_submission_id:String?}
struct ExecutionProvenance:Codable,Equatable,Sendable {let status:String;let acceptance_submission_id:String?;let acceptance_receipt_id:String?}
struct ExecutionRecord:Codable,Equatable,Sendable,Identifiable {
    let submission_id:String;let project_id:String;let repository_id:String;let producer_id:String;let mission_id:String;let mission_revision:String;let engineering_action_id:String;let correlation_id:String
    let submission_disposition:String;let run_id:String?;let lineage:ExecutionLineage?;let provenance:ExecutionProvenance
    let description:String?;let description_status:String;let progress:ExecutionPhase;let result:ExecutionResult;let source_updated_at:String?
    var id:String {submission_id}
    var groupKey:String {[project_id,producer_id,mission_id,mission_revision,engineering_action_id].joined(separator:"\n")}
}
struct ExecutionGroup:Identifiable,Sendable {let id:String;var records:[ExecutionRecord]}
struct ExecutionPacket:Codable,Equatable,Sendable {
    let contract_version:String;let producer_version:String;let instance_id:String;let purpose:String;let snapshot_id:String
    let observed_at:String;let source_updated_at:String?;let freshness:String;let selection:ExecutionSelection
    let selected_mission_id:String?;let selected_run_id:String?;let completeness:String;let unlinked_legacy_records:Int;let logical_action_count:Int
    let records:[ExecutionRecord];let business_mutations:Int
    var groups:[ExecutionGroup] {
        var result:[ExecutionGroup]=[]
        for row in records {
            if let index=result.firstIndex(where:{$0.id==row.groupKey}) {result[index].records.append(row)}
            else {result.append(ExecutionGroup(id:row.groupKey,records:[row]))}
        }
        return result
    }
}
struct ExecutionEnvelope:Codable,Equatable,Sendable {
    let contract_version:String;let actor_id:String;let context_id:String;let workspace_instance_id:String
    let binding_id:String;let activity_binding_id:String;let forge_instance_id:String;let workset_id:String
    let producer_source:String;let expires_at:String;let packet:ExecutionPacket
}
struct ExecutionNavigation:Codable,Equatable,Sendable {
    var mission="";var submission:String?;var run:String?;var group:String?;var binding="";var expanded=false
}
struct ExecutionQuery:Equatable,Sendable {
    let connection:AdvisoryConnection;let activity:ActivityAccess;let workset:String;let mission:String
    var run:String?=nil;var expectedSnapshot:String?=nil;var binding:String?=nil
    var key:String {activity.key(workset,draft:connection.draftGrant)}
    func validate() throws {
        guard activity.matches(connection),activity.worksets.contains(where:{$0.workset_id==workset}),ActivityWire.identifier(mission),ActivityWire.identifier(workset),WorksetReleaseWire.date(activity.expires_at).map({$0>Date()})==true else {throw ExecutionError.denied}
        if let run {guard ActivityWire.identifier(run),expectedSnapshot != nil,binding != nil else {throw ExecutionError.invalid}}
        if let expectedSnapshot {guard ActivityWire.matches(expectedSnapshot,"^[0-9a-f]{64}$") else {throw ExecutionError.invalid}}
    }
}
enum ExecutionError:Error {case denied,unbound,notFound,snapshot,unsupported,corrupt,unavailable,invalid}
protocol ExecutionServing:Sendable {func read(_ query:ExecutionQuery) async throws->ExecutionEnvelope}
enum ExecutionWire {
    static let source="4607202b805bf39808b02cadb2a9b79196b77d14"
    static func envelope(_ data:Data,_ query:ExecutionQuery)->ExecutionEnvelope? {try? decode(data,query)}
    static func decode(_ data:Data,_ query:ExecutionQuery) throws->ExecutionEnvelope {
        try query.validate()
        guard data.count<=600000,let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(raw.keys)==["contract_version","actor_id","context_id","workspace_instance_id","binding_id","activity_binding_id","forge_instance_id","workset_id","producer_source","expires_at","packet"],let packet=raw["packet"] as? [String:Any],let schema=try ExecutionProgressSchema.document(),let options=schema["oneOf"] as? [[String:Any]],let zero=packet["business_mutations"] as? NSNumber,CFGetTypeID(zero) != CFBooleanGetTypeID(),zero.intValue==0 else {throw ExecutionError.invalid}
        try AdvisoryWire.check(packet,options[0],definitions:[:])
        let result=try JSONDecoder().decode(ExecutionEnvelope.self,from:data)
        guard result.contract_version=="workspace-execution-progress/1",result.actor_id==query.connection.actorID,result.context_id==query.connection.workspaceProjectID,result.workspace_instance_id==query.connection.workspaceInstanceID,result.activity_binding_id==query.activity.binding_id,result.forge_instance_id==query.activity.scope.instance_id,result.workset_id==query.workset,result.producer_source==source,ActivityWire.identifier(result.binding_id),WorksetReleaseWire.date(result.expires_at).map({$0>Date()})==true else {throw ExecutionError.denied}
        if let binding=query.binding {guard binding==result.binding_id else {throw ExecutionError.denied}}
        guard result.packet.producer_version=="2.3.122",result.packet.selected_mission_id==query.mission,result.packet.selected_run_id==query.run,result.packet.selection.mission_ids.contains(query.mission) else {throw ExecutionError.invalid}
        if let snapshot=query.expectedSnapshot {guard snapshot==result.packet.snapshot_id else {throw ExecutionError.snapshot}}
        try records(result.packet,query)
        return result
    }
    private static func records(_ packet:ExecutionPacket,_ query:ExecutionQuery) throws {
        guard packet.completeness==(query.run==nil ? "COMPLETE_WITHIN_KNOWN_SCOPED_SUBMISSIONS":"EXACT_RUN"),query.run==nil || packet.records.count==1,Set(packet.records.map(\.id)).count==packet.records.count else {throw ExecutionError.invalid}
        let runs=packet.records.compactMap(\.run_id)
        guard Set(runs).count==runs.count else {throw ExecutionError.invalid}
        for r in packet.records {
            guard r.project_id==packet.selection.project_id,packet.selection.repository_ids.contains(r.repository_id),packet.selection.producer_ids==[r.producer_id],r.mission_id==query.mission,query.run==nil || r.run_id==query.run,r.result.forge_mission_acceptance=="NOT_OWNED_BY_EP" else {throw ExecutionError.denied}
            guard r.result.qualification.run_qualification != "QUALIFIED" || r.result.technical_outcome=="COMPLETE" else {throw ExecutionError.invalid}
            guard (r.description_status=="AVAILABLE")==((r.description) != nil) else {throw ExecutionError.invalid}
            if let description=r.description {guard !description.contains("/"),!description.contains("\\"),description.unicodeScalars.allSatisfy({$0.value>=32}) else {throw ExecutionError.invalid}}
        }
    }
}
