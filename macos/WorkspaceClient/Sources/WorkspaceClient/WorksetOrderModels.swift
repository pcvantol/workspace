import Foundation

struct OrderAccess: Codable, Equatable, Sendable {
    let binding: ActivityAccess
    let permissions: [String]
    let maximumAmendments: Int
    var valid: Bool { binding.valid && (permissions == ["READ"] || permissions == ["READ","REORDER"]) && (1...16).contains(maximumAmendments) }
    func key(_ workset:String, draft:String) -> String { binding.key(workset,draft:draft) }
}
struct OrderMember: Codable, Equatable, Sendable, Identifiable {
    let candidate_id:String
    let title:String
    let position:Int
    let remaining_position:Int?
    let dependencies:[String]
    let claimed:Bool
    var id:String { candidate_id }
}
struct OrderCurrent: Sendable {
    let data:Data
    let members:[OrderMember]
    let order:[String]
    let fixed:Int
    let revision:Int
    let worksetRevision:Int
    let digest:String
}
struct OrderPreview: Sendable {
    let data:Data
    let package:Data
    let digest:String
    let proposed:[String]
    let current:OrderCurrent
    let supported:Bool
    let blockers:[String]
}
struct OrderIntent: Codable, Equatable, Sendable {
    let scopeKey:String
    let operation:String
    let workset:String
    let request:Data
}
enum OrderWire {
    static let contract="forge-workset-order/v1"
    static func object(_ data:Data) throws -> [String:Any] {
        guard data.count<=1_000_000,let raw=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AdvisoryError.invalid };return raw
    }
    static func validate(_ raw:Any,_ kind:String) throws {
        let defs=try WorksetOrderSchema.definitions()
        guard let schema=defs[kind] as? [String:Any] else { throw AdvisoryError.invalid }
        try AdvisoryWire.check(raw,schema,definitions:defs)
    }
    static func scope(_ raw:[String:Any],_ access:OrderAccess) throws {
        guard raw["instance_id"] as? String == access.binding.scope.instance_id,
              raw["project_id"] as? String == access.binding.scope.project_id,
              raw["repository_id"] as? String == access.binding.scope.repository_id else { throw AdvisoryError.denied }
    }
    static func current(_ data:Data,_ access:OrderAccess,_ workset:String) throws -> OrderCurrent {
        let raw=try object(data);try validate(raw,"current")
        guard let projection=raw["current"] as? [String:Any],let scoped=projection["scope"] as? [String:Any],
            raw["workset_id"] as? String == workset,scoped["workset_id"] as? String == workset,
            scoped["principal_id"] as? String == access.binding.actorID,
            projection["instance_id"] as? String == access.binding.scope.instance_id,
            projection["installation_id"] as? String == access.binding.installation_id,
            ["forge-workspace-worklist/v1","forge-workspace-worklist/v2"].contains(projection["contract_version"] as? String ?? ""),
            access.binding.worksets.contains(where:{$0.workset_id==workset && $0.definition_digest==projection["membership_revision"] as? String}),
            let order=raw["current_order"] as? [String],let fixed=raw["fixed_prefix"] as? Int,
            let revision=raw["order_revision"] as? Int,let digest=raw["order_digest"] as? String,
            fixed<=order.count else { throw AdvisoryError.denied }
        if projection["contract_version"] as? String == "forge-workspace-worklist/v2" {
            guard order == projection["effective_order"] as? [String],revision == projection["order_revision"] as? Int,digest == projection["order_digest"] as? String else { throw AdvisoryError.invalid }
        } else {
            guard revision==0,let items=projection["items"] as? [[String:Any]],items.sorted(by:{ ($0["committed_order"] as? Int ?? -1)<($1["committed_order"] as? Int ?? -1) }).compactMap({$0["candidate_id"] as? String})==order else { throw AdvisoryError.invalid }
        }
        let members=try AdvisoryWire.decode(raw["members"] as Any,as:[OrderMember].self)
        guard members.map(\.id)==order,Set(order).count==order.count else { throw AdvisoryError.invalid }
        return OrderCurrent(data:data,members:members,order:order,fixed:fixed,revision:revision,worksetRevision:projection["workset_revision"] as? Int ?? 0,digest:digest)
    }
    static func preview(_ data:Data,_ access:OrderAccess,_ workset:String,_ proposed:[String]) throws -> OrderPreview {
        let raw=try object(data);try validate(raw,"preview")
        guard let package=raw["package"] as? [String:Any],let currentRaw=raw["current"],
            let digest=raw["package_digest"] as? String,package["proposed_order"] as? [String]==proposed,
            package["workset_id"] as? String==workset else { throw AdvisoryError.invalid }
        try scope(package,access)
        let current=try current(JSONSerialization.data(withJSONObject:currentRaw),access,workset)
        guard package["current_order"] as? [String]==current.order,package["fixed_prefix"] as? Int==current.fixed,
            Set(proposed)==Set(current.order),Array(proposed.prefix(current.fixed))==Array(current.order.prefix(current.fixed)) else { throw AdvisoryError.invalid }
        return OrderPreview(data:data,package:try JSONSerialization.data(withJSONObject:package),digest:digest,proposed:proposed,current:current,supported:raw["reorder_supported"] as? Bool==true,blockers:raw["blocking_reasons"] as? [String] ?? [])
    }
    static func command(_ preview:OrderPreview,operation:String,workset:String,reason:String) throws -> Data {
        let package=try object(preview.package)
        let raw:[String:Any]=["contract_version":contract,"operation_id":operation,"instance_id":package["instance_id"]!,"project_id":package["project_id"]!,"repository_id":package["repository_id"]!,"workset_id":workset,"package_digest":preview.digest,"package":package,"reason":reason,"confirm":true]
        try validate(raw,"request");return try JSONSerialization.data(withJSONObject:raw)
    }
}
