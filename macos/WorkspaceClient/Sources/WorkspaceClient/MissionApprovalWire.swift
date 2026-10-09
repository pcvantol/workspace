import Foundation

struct MissionPreparedPacket: Sendable {
    let data:Data
    let packageData:Data?
    let definition:MissionConceptDefinition
    let revision:Int
    let objectID:String
    let digest:String?
    let questions:[String]
}
struct MissionCompoundReadback: Sendable {
    let data:Data
    let frozenPackageData:Data
    let operationID:String
    let state:String
    let sourceFresh:Bool
    let currentDefinitionState:String
    let missionID:String?
    let readiness:MissionReadiness?
    var presentationState:String {
        sourceFresh && state=="COMPLETE" && currentDefinitionState != "SUPERSEDED" ? readiness?.state ?? currentDefinitionState:currentDefinitionState
    }
}
enum MissionApprovalWire {
    static func frozen(_ raw:Any,access:AdvisoryAccess,conversation:String,expectedDigest:String?=nil) throws -> [String:Any] {
        try MissionConceptWire.validate(raw,kind:"frozen_package")
        let p=raw as! [String:Any],source=p["source"] as! [String:Any],authority=p["authority"] as! [String:Any]
        try AdvisoryWire.scope(source,access:access)
        let actualDigest=try AdvisoryWire.digest(p)
        guard access.conversationIDs.contains(conversation),source["conversation_id"] as? String==conversation,
              authority["principal_reference"] as? String==access.forgeInstanceID+":"+access.actorID,
              expectedDigest == nil || actualDigest==expectedDigest else { throw AdvisoryError.denied }
        let d=try MissionConceptWire.definition(p["definition"]!),bindings=p["dependency_bindings"] as! [[String:Any]]
        guard Set(bindings.map { $0["candidate_id"] as! String }).count==bindings.count,
              Set(bindings.map { $0["candidate_id"] as! String })==Set(d.dependencies),
              bindings.allSatisfy({ d.dependency_reasons[$0["candidate_id"] as! String]==$0["reason"] as? String }) else { throw AdvisoryError.invalid }
        let candidate=p["candidate"] as! [String:Any],preview=p["mission_preview"] as! [String:Any]
        let planning=p["planning"] as! [String:Any],effects=p["consequences"] as! [String:Any]
        guard try AdvisoryWire.digest(candidate)==p["subject_revision"] as? String,
              candidate["title"] as? String==d.title,candidate["objective"] as? String==d.objective,
              Set(candidate["acceptance_criteria"] as! [String])==Set(d.acceptance_criteria),
              Set(candidate["dependencies"] as! [String])==Set(d.dependencies),
              Set(d.exclusions.map { "EXCLUDED: "+$0 }).isSubset(of:Set(candidate["architecture_constraints"] as! [String])),
              Set(d.scope.map { "IN SCOPE: "+$0 }).isSubset(of:Set(candidate["architecture_constraints"] as! [String])),
              (candidate["architecture_constraints"] as! [String]).contains("EXPECTED RESULT: "+d.expected_result),
              d.components.allSatisfy({ name in (candidate["architecture_constraints"] as! [String]).contains(where: { $0.hasPrefix("COMPONENT: "+name+": ") }) }),
              NSDictionary(dictionary:effects["repository_effect"] as! [String:Any]).isEqual(to:candidate["effect_policy"] as! [String:Any]),
              effects["exclusions"] as? [String]==d.exclusions,effects["risks"] as? [String]==d.risks,
              preview["candidate_id"] as? String==candidate["id"] as? String,preview["title"] as? String==d.title,
              preview["business_value"] as? String==d.business_value,
              try AdvisoryWire.digest(preview)==planning["mission_spec_digest"] as? String,
              planning["provenance_revision"] as? String==p["subject_revision"] as? String,
              NSDictionary(dictionary:planning["effect_policy"] as! [String:Any]).isEqual(to:candidate["effect_policy"] as! [String:Any]),
              planning["human_gates"] as? [String]==effects["human_gates"] as? [String] else { throw AdvisoryError.invalid }
        return p
    }
    static func prepared(_ data:Data,access:AdvisoryAccess,conversation:String,revision:Int?=nil,expectedDefinition:MissionConceptDefinition?=nil) throws -> MissionPreparedPacket {
        let raw=try AdvisoryWire.object(data),hasPackage = !(raw["package"] is NSNull)
        try MissionConceptWire.validate(raw,kind:hasPackage ? "prepared_complete":"prepared_incomplete")
        let definition=try MissionConceptWire.definition(raw["definition"]!),actualRevision=raw["revision"] as! Int
        guard revision == nil || revision==actualRevision,expectedDefinition == nil || expectedDefinition==definition else { throw AdvisoryError.invalid }
        var packageData:Data?
        if hasPackage {
            let p=try frozen(raw["package"]!,access:access,conversation:conversation,expectedDigest:raw["package_digest"] as? String)
            let source=p["source"] as! [String:Any]
            guard try MissionConceptWire.definition(p["definition"]!)==definition,
                  source["revision"] as? Int==actualRevision,source["object_id"] as? String==raw["object_id"] as? String else { throw AdvisoryError.invalid }
            packageData=try JSONSerialization.data(withJSONObject:p)
        }
        return .init(data:data,packageData:packageData,definition:definition,revision:actualRevision,objectID:raw["object_id"] as! String,digest:raw["package_digest"] as? String,questions:raw["questions"] as! [String])
    }
    static func compound(_ data:Data,access:AdvisoryAccess,conversation:String,expectedDigest:String?=nil,operation:String?=nil,frozenData:Data?=nil) throws -> MissionCompoundReadback {
        let raw=try AdvisoryWire.object(data),isOperation=raw["frozen_package"] != nil
        try MissionConceptWire.validate(raw,kind:isOperation ? "compound_operation":"compound_result")
        let sourceRaw:Any
        if isOperation { sourceRaw=raw["frozen_package"]! }
        else { guard let frozenData else { throw AdvisoryError.invalid };sourceRaw=try AdvisoryWire.object(frozenData) }
        let package=try frozen(sourceRaw,access:access,conversation:conversation,expectedDigest:raw["package_digest"] as? String)
        guard expectedDigest == nil || raw["package_digest"] as? String==expectedDigest,
              operation == nil || raw["operation_id"] as? String==operation else { throw AdvisoryError.invalid }
        let candidate=package["candidate"] as! [String:Any],authority=package["authority"] as! [String:Any],signer=authority["signer"] as! [String:Any]
        if let original=raw["original_registration"] as? [String:Any] {
            guard NSDictionary(dictionary:original["candidate"] as! [String:Any]).isEqual(to:candidate),
                  NSDictionary(dictionary:original["source"] as! [String:Any]).isEqual(to:package["source"] as! [String:Any]),
                  original["principal_reference"] as? String==authority["principal_reference"] as? String,
                  original["candidate_digest"] as? String == (try AdvisoryWire.digest(candidate)) else { throw AdvisoryError.invalid }
        }
        var decisions:[String]=[]
        for (key,kind) in [("business_decision","BUSINESS"),("architecture_decision","ARCHITECTURE")] {
            guard let decision=raw[key] as? [String:Any] else { continue }
            guard decision["kind"] as? String==kind,decision["candidate_id"] as? String==candidate["id"] as? String,
                  decision["subject_revision"] as? String==package["subject_revision"] as? String,
                  decision["principal_reference"] as? String==authority["principal_reference"] as? String,
                  decision["operator_id"] as? String==signer["operator_id"] as? String,
                  decision["installation_id"] as? String==signer["installation_id"] as? String,
                  decision["operator_binding_version"] as? Int==signer["operator_binding_version"] as? Int,
                  try AdvisoryWire.digest(decision["canonical_decision"]!)==decision["canonical_decision_digest"] as? String,
                  try AdvisoryWire.digest(decision["lifecycle_evidence"]!)==decision["lifecycle_evidence_digest"] as? String else { throw AdvisoryError.invalid }
            let canonical=decision["canonical_decision"] as! [String:Any],evidence=decision["lifecycle_evidence"] as! [String:Any]
            guard canonical["decision_id"] as? String==decision["decision_id"] as? String,
                  canonical["subject_id"] as? String==candidate["id"] as? String,canonical["subject_revision"] as? String==package["subject_revision"] as? String,
                  canonical["capability"] as? String==kind+"_APPROVAL",canonical["decision"] as? String=="approved",
                  canonical["operator_id"] as? String==decision["operator_id"] as? String,canonical["installation_id"] as? String==decision["installation_id"] as? String,
                  (canonical["scope"] as! [String]).sorted()==(candidate["scope"] as! [String]).sorted(),
                  (canonical["gates"] as! [String]).sorted()==((package["planning"] as! [String:Any])["human_gates"] as! [String]).sorted(),
                  evidence["recommendation_id"] as? String==candidate["recommendation_id"] as? String,
                  evidence["kind"] as? String==kind.lowercased()+"_decision",evidence["actor"] as? String=="primary_operator",
                  evidence["rationale"] as? String==decision["rationale"] as? String,evidence["occurred_at"] as? String==decision["admitted_at"] as? String,
                  Set([decision["decision_id"] as! String,candidate["id"] as! String,package["subject_revision"] as! String]).isSubset(of:Set(evidence["references"] as! [String])) else { throw AdvisoryError.invalid }
            if kind=="ARCHITECTURE" {
                let planningDigest=try AdvisoryWire.digest(package["planning"]!)
                guard (canonical["evidence"] as? [String:Any])?["planning_digest"] as? String==planningDigest,
                      (evidence["references"] as! [String]).contains(planningDigest),
                      (evidence["references"] as! [String]).contains((package["planning"] as! [String:Any])["mission_spec_digest"] as! String) else { throw AdvisoryError.invalid }
            }
            decisions.append(decision["decision_id"] as! String)
        }
        let complete = !isOperation || raw["state"] as? String=="COMPLETE"
        guard Set(decisions).count==decisions.count,raw["candidate_id"] as? String==candidate["id"] as? String,
              !complete || (raw["original_registration"] is [String:Any] && decisions.count==2 && raw["mission_id"] is String) else { throw AdvisoryError.invalid }
        let readinessRaw=(isOperation ? raw["current_readiness"]:raw["current"]) as? [String:Any]
        var readiness:MissionReadiness?
        if let r=readinessRaw {
            let bindings=package["dependency_bindings"] as! [[String:Any]],facts=r["dependency_facts"] as! [[String:Any]]
            guard r["subject_revision"] as? String==package["subject_revision"] as? String,
                  Set(facts.map { $0["candidate_id"] as! String }).count==facts.count,
                  Set(facts.map { $0["candidate_id"] as! String })==Set(bindings.map { $0["candidate_id"] as! String }),
                  facts.allSatisfy({ fact in bindings.contains(where: { $0["candidate_id"] as? String==fact["candidate_id"] as? String && $0["subject_revision"] as? String==fact["subject_revision"] as? String }) }) else { throw AdvisoryError.invalid }
            readiness=try AdvisoryWire.decode(r,as:MissionReadiness.self)
        }
        return .init(data:data,frozenPackageData:try JSONSerialization.data(withJSONObject:package),operationID:raw["operation_id"] as! String,
            state:complete ? "COMPLETE":"PENDING",sourceFresh:isOperation ? raw["source_fresh"] as! Bool:true,
            currentDefinitionState:isOperation ? raw["current_definition_state"] as! String:(raw["current"] as! [String:Any])["state"] as! String,missionID:raw["mission_id"] as? String,readiness:readiness)
    }
}

struct MissionReadiness:Codable,Sendable {
    let state:String;let mission_status:String;let blockers:[String]
    let execution_resources:String;let execution_ready:Bool;let subject_revision:String
}
