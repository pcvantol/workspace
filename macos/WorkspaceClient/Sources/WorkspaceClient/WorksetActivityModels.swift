import Foundation
import CryptoKit

struct ActivitySubject: Codable, Equatable, Sendable {
    let workset_id: String
    let definition_digest: String
}
struct ActivityScope: Codable, Equatable, Sendable {
    let instance_id: String
    let project_id: String
    let repository_id: String
}
struct ActivityAccess: Codable, Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let actorID: String
    let workspaceProjectID: String
    let token: String
    let binding_id: String
    let scope: ActivityScope
    let installation_id: String
    let worksets: [ActivitySubject]
    let expires_at: String
    var valid: Bool {
        (try? ServerEndpoint(endpoint))?.url.absoluteString == endpoint &&
        ActivityWire.matches(workspaceInstanceID,"^[0-9a-f]{32}$") &&
        [actorID,workspaceProjectID,binding_id,scope.instance_id,scope.project_id,scope.repository_id,installation_id].allSatisfy(ActivityWire.identifier) &&
        ActivityWire.matches(token,"^[A-Za-z0-9_-]{43}$") &&
        (1...16).contains(worksets.count) && Set(worksets.map(\.workset_id)).count == worksets.count &&
        worksets.allSatisfy { ActivityWire.identifier($0.workset_id) && ActivityWire.matches($0.definition_digest,"^sha256:[0-9a-f]{64}$") } &&
        WorksetReleaseWire.date(expires_at) != nil
    }
    func matches(_ connection: AdvisoryConnection) -> Bool {
        valid && endpoint == connection.endpoint && workspaceInstanceID == connection.workspaceInstanceID &&
        actorID == connection.actorID && workspaceProjectID == connection.workspaceProjectID
    }
    func key(_ workset: String, draft: String) -> String {
        let parts=[endpoint,workspaceInstanceID,actorID,workspaceProjectID,token,binding_id,scope.instance_id,scope.project_id,scope.repository_id,installation_id,workset,worksets.first(where:{$0.workset_id==workset})?.definition_digest ?? "",draft,ActivityWire.pin]
        return ActivityWire.hash(Data(parts.joined(separator:"\n").utf8))
    }
}
struct ActivityEvent: Sendable, Identifiable {
    let id: String
    let kind: String
    let fact: String
    let subject: String
    let subjectID: String
    let occurredAt: String?
    let summary: String
    let sourceKind: String
    let sourceRecord: String
    let sourceRevision: String
    let sourceDigest: String
    let sourceURL: String
    let details: Data
}
struct ActivityCurrentItem: Decodable, Sendable, Identifiable {
    let candidate_id: String
    let mission_id: String?
    let mission_state_revision: Int?
    let title: String
    let approved: Bool
    let released: Bool
    let active: Bool
    let execution_state: String
    let eligibility: String
    let blocking_reasons: [String]
    let engineering_result: String
    let review_state: String
    let final_acceptance: String
    let completed: Bool
    var id: String { candidate_id }
}
struct ActivityPage: Sendable {
    let data: Data
    let events: [ActivityEvent]
    let cursor: String
    let hasMore: Bool
    let watermark: String
    let current: [ActivityCurrentItem]
    let observedAt: String
    let offered: String
    let limitations: [String]
}
enum ActivityWire {
    static func matches(_ value:String,_ pattern:String) -> Bool {
        guard let range=value.range(of:pattern,options:.regularExpression) else { return false }
        return range.lowerBound==value.startIndex && range.upperBound==value.endIndex
    }
    static func identifier(_ value:String) -> Bool { matches(value,"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$") }
    static let pin="989132660997909e74800ddc8648be11262be8d4"
    static let prefix="/v1/approved-workset-activity/"
    static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    static func object(_ data: Data) throws -> [String:Any] {
        guard data.count<=32768,let value=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AdvisoryError.invalid };return value
    }
    static func validate(_ value: Any, _ kind: String) throws {
        let defs=try WorksetActivitySchema.definitions()
        try AdvisoryWire.check(value,defs[kind] as! [String:Any],definitions:defs)
    }
    static func access(_ data: Data, connection: AdvisoryConnection, token: String, now: Date) throws -> ActivityAccess {
        var raw=try object(data)
        let extra:Set<String>=["consumer_contract","binding_id","actor_id","workspace_project_id","producer_source","producer_version","installation_id"]
        guard raw["consumer_contract"] as? String == "workspace-workset-activity-access/v1",raw["producer_source"] as? String == pin,
              raw["producer_version"] as? String == "2.15.0",raw["actor_id"] as? String == connection.actorID,
              raw["workspace_project_id"] as? String == connection.workspaceProjectID else { throw AdvisoryError.denied }
        let scope=try AdvisoryWire.decode(raw["scope"] as Any,as:ActivityScope.self)
        let access=ActivityAccess(endpoint:connection.endpoint,workspaceInstanceID:connection.workspaceInstanceID,actorID:connection.actorID,
            workspaceProjectID:connection.workspaceProjectID,token:token,binding_id:raw["binding_id"] as? String ?? "",scope:scope,
            installation_id:raw["installation_id"] as? String ?? "",worksets:try AdvisoryWire.decode(raw["worksets"] as Any,as:[ActivitySubject].self),expires_at:raw["expires_at"] as? String ?? "")
        for key in extra { raw.removeValue(forKey:key) };try validate(raw,"capability")
        guard access.valid,raw["supported"] as? Bool == true,let expiry=WorksetReleaseWire.date(access.expires_at),expiry>now else { throw AdvisoryError.denied }
        return access
    }
    static func event(_ raw: [String:Any], workset: String) throws -> ActivityEvent {
        try validate(raw,"event")
        let source=raw["source_reference"] as! [String:Any],subject=raw["subject"] as! [String:Any]
        let id=raw["event_id"] as! String
        guard source["url"] as? String == prefix+workset+"/events/"+id,
              (raw["time_status"] as? String == "UNKNOWN") == (raw["occurred_at"] is NSNull) else { throw AdvisoryError.invalid }
        let time=raw["occurred_at"] as? String
        guard time == nil || WorksetReleaseWire.date(time!) != nil else { throw AdvisoryError.invalid }
        return ActivityEvent(id:id,kind:raw["kind"] as! String,fact:raw["fact"] as! String,subject:subject["label"] as! String,
            subjectID:subject["id"] as! String,occurredAt:time,summary:raw["summary"] as! String,sourceKind:source["kind"] as! String,
            sourceRecord:source["record_id"] as! String,sourceRevision:String(describing:raw["source_revision"]!),sourceDigest:raw["source_digest"] as! String,
            sourceURL:source["url"] as! String,details:try CanonicalJSON.data(raw["details"]!,ascii:false))
    }
    static func page(_ data: Data, access: ActivityAccess, workset: String) throws -> ActivityPage {
        let raw=try object(data);try validate(raw,"page")
        guard raw["workset_id"] as? String == workset,let subject=access.worksets.first(where:{$0.workset_id==workset}) else { throw AdvisoryError.denied }
        let current=raw["current"] as! [String:Any],scope=current["scope"] as! [String:Any]
        guard current["instance_id"] as? String == access.scope.instance_id,current["installation_id"] as? String == access.installation_id,
            scope["principal_id"] as? String == access.actorID,scope["workset_id"] as? String == workset,
            current["membership_revision"] as? String == subject.definition_digest,current["selector_revision"] as? String == subject.definition_digest else { throw AdvisoryError.denied }
        var signed=current;for key in ["snapshot_revision","observed_at","freshness","read_only"] { signed.removeValue(forKey:key) }
        guard current["snapshot_revision"] as? String == "sha256:"+hash(try CanonicalJSON.data(signed,ascii:false)) else { throw AdvisoryError.invalid }
        let events=try (raw["events"] as! [[String:Any]]).map { try event($0,workset:workset) }
        let items=try AdvisoryWire.decode(current["items"] as Any,as:[ActivityCurrentItem].self)
        let cursor=raw["cursor"] as! String,more=raw["has_more"] as! Bool
        guard Set(events.map(\.id)).count==events.count,Set(items.map(\.id)).count==items.count,
            matches(cursor,"^[A-Za-z0-9_.-]{1,32768}$"),!more || !events.isEmpty else { throw AdvisoryError.invalid }
        let coverage=raw["coverage"] as! [String:Any]
        return ActivityPage(data:data,events:events,cursor:cursor,hasMore:more,watermark:raw["source_watermark"] as! String,current:items,
            observedAt:current["observed_at"] as! String,offered:coverage["offered_records"] as! String,limitations:coverage["limitations"] as! [String])
    }
    static func detail(_ data: Data, workset: String, id: String) throws -> ActivityEvent {
        let raw=try object(data);try validate(raw,"detail")
        guard raw["workset_id"] as? String == workset,let value=raw["event"] as? [String:Any],value["event_id"] as? String == id else { throw AdvisoryError.denied }
        return try event(value,workset:workset)
    }
}
