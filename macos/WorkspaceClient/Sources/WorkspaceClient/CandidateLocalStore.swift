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
    init(root:URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/CandidateDrafts")) { self.root=root }
    private func file(_ key:String) throws -> URL {
        guard key.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var info=stat()
        guard lstat(root.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR),info.st_uid==getuid(),info.st_mode & 0o077==0 else { throw AdvisoryError.unavailable }
        return root.appendingPathComponent("candidate-"+key+".json")
    }
    func load(_ key:String) throws -> CandidateLocal? {
        let url=try file(key),fd=Darwin.open(url.path,O_RDONLY|O_NOFOLLOW)
        if fd<0 && errno==ENOENT { return nil }
        guard fd>=0 else { throw AdvisoryError.unavailable }
        let handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true);defer{try? handle.close()}
        var info=stat()
        guard fstat(fd,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),info.st_uid==getuid(),info.st_mode & 0o077==0,info.st_size<=65536 else { throw AdvisoryError.unavailable }
        let data=try handle.read(upToCount:65537) ?? Data()
        guard data.count<=65536 else { throw AdvisoryError.invalid }
        let v=try JSONDecoder().decode(CandidateLocal.self,from:data)
        guard v.key==key else { throw AdvisoryError.invalid }
        if let r=v.saveIntent { _=try CandidateWire.data(r,kind:"proposal_request") }
        if let r=v.registrationIntent { _=try CandidateWire.data(r,kind:"registration_request") }
        return v
    }
    func save(_ value:CandidateLocal) throws {
        let target=try file(value.key),data=try JSONEncoder().encode(value)
        guard data.count<=65536 else { throw AdvisoryError.state("LOCAL_CAPACITY_EXHAUSTED") }
        // Atomic private replacement; never follow an existing file or parent symlink.
        var info=stat()
        if lstat(target.path,&info)==0 {
            guard info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),info.st_uid==getuid(),info.st_mode & 0o077==0 else { throw AdvisoryError.unavailable }
        } else if errno != ENOENT { throw AdvisoryError.unavailable }
        let temporary=root.appendingPathComponent(".candidate-"+UUID().uuidString+".tmp")
        let fd=Darwin.open(temporary.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else { throw AdvisoryError.unavailable }
        let h=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        defer { try? h.close();try? FileManager.default.removeItem(at:temporary) }
        try h.write(contentsOf:data);try h.synchronize()
        guard rename(temporary.path,target.path)==0 else { throw AdvisoryError.unavailable }
    }
}
