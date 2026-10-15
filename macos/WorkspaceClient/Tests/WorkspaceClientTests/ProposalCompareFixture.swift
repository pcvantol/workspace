import Foundation
import CryptoKit
@testable import WorkspaceClient

// Synthetic schema fixtures, never installed producer evidence.
enum CompareFixture {
    static let first=String(repeating:"1",count:32),second=String(repeating:"2",count:32),third=String(repeating:"3",count:32)
    static let renderer="a7a16db4d735d9411ff3a3c7997d8aff82be2d4b6f2059aa56bf250b7e104536"
    static var concept:ProjectConcept {.init(id:String(repeating:"a",count:32),actor_id:"alice",context_id:"context",title:"Current source",notes:"Later notes; never insert in history",revision:3,created_at:"2026-10-15T00:00:00Z",updated_at:"2026-10-15T00:00:00Z",state:"CONCEPT_NOT_CONFIGURED",lifecycle:"ACTIVE")}
    static var connection:ConceptConnection {.init(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"context",token:String(repeating:"c",count:43)),bearer:"own-source-fixture")}
    static func artifact(_ path:String,_ text:String,mode:Int=420)->ConceptBaselineResult.Artifact {.init(path:path,mode:mode,sha256:SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined(),content:text)}
    static func object(_ operation:String,revision:Int=1,documents:[String:String]=["README.md":"old\n"],questions:[String]=["Who is this for?"],profile:String="portable-docs/1.0.0")->[String:Any] {
        var files=documents
        files["engineering/bootstrap-manifest.json"]=String(data:try! JSONSerialization.data(withJSONObject:["contract_version":"pb-render/1.0","renderer_version":"1.0.0","baseline":profile,"renderer_source_digest":renderer],options:.sortedKeys),encoding:.utf8)!
        let artifacts=files.sorted{$0.key<$1.key}.map {p,v in ["path":p,"mode":420,"sha256":artifact(p,v).sha256,"content":v] as [String:Any]}
        return ["contract_version":"workspace-concept-baseline/1","actor_id":"alice","context_id":"context","concept_id":concept.id,"operation_id":operation,"source_revision":revision,"current_revision":3,"source_digest":String(repeating:"a",count:64),"producer_source":String(repeating:"9",count:40),"binding_id":"fixture-pair","unknown_fields":["users","non_goals"],"source_product":["name":"Original \(revision)","purpose":"Original purpose \(revision)","users":"Not supplied in this project concept.","non_goals":"Not supplied in this project concept.","constraints":"Keep data private","open_questions":questions],"status":"PROPOSAL_PROJECT_NOT_CONFIGURED","proposal":["contract_version":"forge-project-proposal-http/v1","instance_id":"forge-fixture","principal_id":"alice","audience":"workspace","dossier_id":"fixture-dossier","operation_id":operation,"plan_id":"proposal-"+operation,"proposal_kind":"pb-render/1.0","request_digest":String(repeating:"b",count:64),"record_digest":String(repeating:"c",count:64),"read_only_result":true,"approval":"NOT_PERFORMED","registration":"NOT_PERFORMED","result":["state":"PROPOSED_NOT_APPROVED","original_contract_version":"pb-render/1.0","summary":"Source-only synthetic schema fixture","artifacts":artifacts,"observations":"SUPPLIED_UNVERIFIED","repository_quality":"NOT_ASSESSED"]]]
    }
    static func decode(_ object:[String:Any])throws->ConceptBaselineResult {try JSONDecoder().decode(ConceptBaselineResult.self,from:JSONSerialization.data(withJSONObject:object))}
    static func result(_ id:String,revision:Int=1,documents:[String:String]=["README.md":"old\n"],questions:[String]=["Who is this for?"],profile:String="portable-docs/1.0.0")throws->ConceptBaselineResult {try decode(object(id,revision:revision,documents:documents,questions:questions,profile:profile))}
}
@MainActor final class ComparePeer:ConceptBaselineServing {
    var results:[String:ConceptBaselineResult]=[:]
    var ids=[CompareFixture.first,CompareFixture.second]
    var revoked=false,binding="fixture-pair",sourceRevision=3,expiry="2099-01-01T00:00:00Z"
    var reads:[String]=[],posts=0,accesses=0
    var failure:Error?
    var blockNextRead=false
    var waitingRead:CheckedContinuation<ConceptBaselineResult,Error>?
    var blockAccessAt:Int?
    var waitingAccess:CheckedContinuation<ConceptBaselineAccess,Error>?
    init()throws {results[ids[0]]=try CompareFixture.result(ids[0]);results[ids[1]]=try CompareFixture.result(ids[1],revision:2,documents:["README.md":"new\n"])}
    func capability()->ConceptBaselineAccess {.init(contract_version:"workspace-concept-baseline/1",actor_id:"alice",context_id:"context",concept_id:CompareFixture.concept.id,binding_id:binding,producer_source:String(repeating:"9",count:40),source_revision:sourceRevision,document_language:"en",can_prepare:false,expires_at:expiry)}
    func access(_ connection:ConceptConnection,concept:String) async throws->ConceptBaselineAccess {
        accesses+=1
        if let failure {throw failure}
        if revoked {throw ConceptError.denied}
        if accesses==blockAccessAt {return try await withCheckedThrowingContinuation{waitingAccess=$0}}
        return capability()
    }
    func history(_ connection:ConceptConnection,concept:String)async throws->ConceptBaselineHistory {.init(contract_version:"workspace-concept-baseline/1",actor_id:"alice",context_id:"context",concept_id:concept,binding_id:binding,producer_source:String(repeating:"9",count:40),operations:ids.enumerated().map{.init(operation_id:$0.element,source_revision:results[$0.element]?.source_revision ?? 3)})}
    func read(_ connection:ConceptConnection,concept:String,operation:String)async throws->ConceptBaselineResult {
        reads.append(operation)
        if blockNextRead {blockNextRead=false;return try await withCheckedThrowingContinuation{waitingRead=$0}}
        if let failure {throw failure}
        if revoked {throw ConceptError.denied}
        guard let value=results[operation] else {throw ConceptError.notFound};return value
    }
    func prepare(_ connection:ConceptConnection,concept:String,command:ConceptBaselineCommand)async throws->ConceptBaselineResult {posts+=1;throw ConceptError.invalid}
}
