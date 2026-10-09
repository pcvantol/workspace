import Foundation
import CryptoKit
import Darwin

struct CandidateForm: Codable, Equatable, Sendable {
    var text:[String:String]=[:]
    static let scalarKeys=["title","objective","business_value","engineering_value","architectural_value","rationale","confidence"]
    static let listKeys=["scope","exclusions","acceptance_criteria","architecture_constraints","dependencies","read_paths","write_paths"]
    func lines(_ key:String) -> [String] {
        (text[key] ?? "").components(separatedBy:.newlines).map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
    }
    func fields() throws -> CandidateFields {
        guard let confidence=Int(text["confidence"] ?? "") else { throw AdvisoryError.invalid }
        let f=CandidateFields(title:text["title"] ?? "",objective:text["objective"] ?? "",business_value:text["business_value"] ?? "",
            engineering_value:text["engineering_value"] ?? "",architectural_value:text["architectural_value"] ?? "",rationale:text["rationale"] ?? "",confidence:confidence,
            scope:lines("scope"),exclusions:lines("exclusions"),acceptance_criteria:lines("acceptance_criteria"),architecture_constraints:lines("architecture_constraints"),dependencies:lines("dependencies"),
            effect_policy:CandidateEffectPolicy(contract_version:"1.0",mode:text["mode"] ?? "",delivery:text["delivery"] ?? "",read_paths:lines("read_paths"),write_paths:lines("write_paths")))
        try CandidateWire.fields(f);return f
    }
    init() {}
    init(_ fields:CandidateFields) {
        text=["title":fields.title,"objective":fields.objective,"business_value":fields.business_value,"engineering_value":fields.engineering_value,
              "architectural_value":fields.architectural_value,"rationale":fields.rationale,"confidence":String(fields.confidence),"mode":fields.effect_policy.mode,"delivery":fields.effect_policy.delivery,
              "scope":fields.scope.joined(separator:"\n"),"exclusions":fields.exclusions.joined(separator:"\n"),"acceptance_criteria":fields.acceptance_criteria.joined(separator:"\n"),
              "architecture_constraints":fields.architecture_constraints.joined(separator:"\n"),"dependencies":fields.dependencies.joined(separator:"\n"),
              "read_paths":fields.effect_policy.read_paths.joined(separator:"\n"),"write_paths":fields.effect_policy.write_paths.joined(separator:"\n")]
    }
}
struct CandidateLocal: Codable, Equatable, Sendable {
    var form=CandidateForm()
    var turnID:String?
    var proposalID:String?
    var revision:Int=0
    var saveIntent:CandidateSaveRequest?
    var registrationIntent:CandidateRegistrationRequest?
    var registrationPending=false
    var key:String=""
    static func scopeKey(_ c:AdvisoryConnection) -> String {
        SHA256.hash(data:Data([c.endpoint,c.workspaceInstanceID,c.workspaceProjectID,c.actorID,c.conversationID].joined(separator:"\u{0}").utf8)).map{String(format:"%02x",$0)}.joined()
    }
}
protocol CandidateLocalStore:Sendable {
    func load(_ key:String) throws -> CandidateLocal?
    func save(_ value:CandidateLocal) throws
}
struct PrivateCandidateLocalStore:CandidateLocalStore {
    let root:URL
    let synchronizeDirectory:@Sendable(Int32)->Int32
    init(root:URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/CandidateDrafts"),synchronizeDirectory:@escaping @Sendable(Int32)->Int32 = { fsync($0) }) { self.root=root;self.synchronizeDirectory=synchronizeDirectory }
    private var records: PrivateLocalRecordStore {
        PrivateLocalRecordStore(root:root,namespace:"candidate",synchronizeDirectory:synchronizeDirectory)
    }
    func load(_ key:String) throws -> CandidateLocal? {
        guard let data=try records.load(key) else { return nil }
        let v=try JSONDecoder().decode(CandidateLocal.self,from:data)
        guard v.key==key else { throw AdvisoryError.invalid }
        if let r=v.saveIntent { _=try CandidateWire.data(r,kind:"proposal_request") }
        if let r=v.registrationIntent { _=try CandidateWire.data(r,kind:"registration_request") }
        return v
    }
    func save(_ value:CandidateLocal) throws {
        try records.save(JSONEncoder().encode(value),key:value.key)
    }
}
