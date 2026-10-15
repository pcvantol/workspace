import Foundation

// A deterministic, byte-exact presentation of already validated original R52 results.
// Linear work only: common whole-line prefix/suffix, then explicit removed/added lines.
enum ProposalCompareError:Error {case incompatible, partial}
struct ProposalCompareModel:Sendable {
    struct Document:Identifiable,Sendable {
        let path:String;let before:ConceptBaselineResult.Artifact?;let after:ConceptBaselineResult.Artifact?
        var id:String {path}
        var status:String {guard let before else{return "added"};guard let after else{return "removed"};return before.mode==after.mode && Data(before.content.utf8)==Data(after.content.utf8) ? "unchanged":"changed"}
        var group:String {
            if path=="README.md" || path.hasPrefix("docs/product/") {return "productDocs"}
            if path.hasPrefix("docs/architecture/") {return "architectureDocs"}
            if path.hasPrefix("docs/roadmap/") {return "roadmapDocs"}
            if ["AGENTS.md","BOOTSTRAP.md"].contains(path) || path.hasPrefix("docs/engineering/") {return "workingDocs"}
            return "otherDocs"
        }
    }
    struct Field:Identifiable,Sendable {let id:String;let before:String;let after:String;var changed:Bool {Data(before.utf8) != Data(after.utf8)}}
    struct Question:Identifiable,Sendable {let text:String;let status:String;let id:Int}
    struct Line:Identifiable,Sendable {let id:Int;let sign:String;let text:String}
    let before:ConceptBaselineResult;let after:ConceptBaselineResult
    let documents:[Document];let fields:[Field];let questions:[Question]
    let profile:String
    var changedDocuments:Int {documents.filter{$0.status != "unchanged"}.count}
    static func profile(_ result:ConceptBaselineResult)throws->String {
        guard let artifact=result.proposal.result.artifacts.first(where:{$0.path=="engineering/bootstrap-manifest.json"}),
              let manifest=try JSONSerialization.jsonObject(with:Data(artifact.content.utf8)) as? [String:Any],
              manifest["contract_version"] as? String=="pb-render/1.0",
              manifest["baseline"] as? String=="portable-docs/1.0.0",
              manifest["renderer_version"] as? String=="1.0.0",
              let renderer=manifest["renderer_source_digest"] as? String,renderer=="a7a16db4d735d9411ff3a3c7997d8aff82be2d4b6f2059aa56bf250b7e104536" else {throw ProposalCompareError.incompatible}
        return "pb-render/1.0 · portable-docs/1.0.0 · 1.0.0 · "+renderer
    }
    static func make(_ before:ConceptBaselineResult,_ after:ConceptBaselineResult)throws->Self {
        guard before.concept_id==after.concept_id,before.actor_id==after.actor_id,before.context_id==after.context_id,
              before.binding_id==after.binding_id,before.producer_source==after.producer_source,
              before.proposal.instance_id==after.proposal.instance_id,before.proposal.dossier_id==after.proposal.dossier_id else {throw ConceptError.denied}
        let profile=try profile(before);guard try Self.profile(after)==profile else {throw ProposalCompareError.incompatible}
        guard Set(before.proposal.result.artifacts.map(\.path)).count==before.proposal.result.artifacts.count,Set(after.proposal.result.artifacts.map(\.path)).count==after.proposal.result.artifacts.count else {throw ConceptError.invalid}
        let old=Dictionary(uniqueKeysWithValues:before.proposal.result.artifacts.map{($0.path,$0)}),new=Dictionary(uniqueKeysWithValues:after.proposal.result.artifacts.map{($0.path,$0)})
        guard old.count<=64,new.count<=64,old.values.allSatisfy({$0.content.utf8.count<=131072}),new.values.allSatisfy({$0.content.utf8.count<=131072}) else {throw ProposalCompareError.partial}
        let documents=Set(old.keys).union(new.keys).sorted().map{Document(path:$0,before:old[$0],after:new[$0])}
        let a=before.source_product,b=after.source_product
        let fields=[Field(id:"name",before:a.name,after:b.name),Field(id:"purpose",before:a.purpose,after:b.purpose),Field(id:"users",before:a.users,after:b.users),Field(id:"non_goals",before:a.non_goals,after:b.non_goals),Field(id:"constraints",before:a.constraints,after:b.constraints)]
        var questions:[Question]=[]
        for q in a.open_questions {questions.append(.init(text:q,status:b.open_questions.contains(where:{Data($0.utf8)==Data(q.utf8)}) ? "present":"omitted",id:questions.count))}
        for q in b.open_questions where !a.open_questions.contains(where:{Data($0.utf8)==Data(q.utf8)}) {questions.append(.init(text:q,status:"newQuestion",id:questions.count))}
        return .init(before:before,after:after,documents:documents,fields:fields,questions:questions,profile:profile)
    }
    static func lines(_ text:String)->[String] {
        let bytes=Array(text.utf8);var result:[String]=[];var start=0
        for i in bytes.indices where bytes[i]==10 {result.append(String(decoding:bytes[start...i],as:UTF8.self));start=i+1}
        if start<bytes.count {result.append(String(decoding:bytes[start...],as:UTF8.self))}
        return result
    }
    struct Difference:Sendable {let rows:[Line];let complete:Bool}
    static func difference(_ document:Document)->Difference {
        let a=lines(document.before?.content ?? ""),b=lines(document.after?.content ?? "");var prefix=0,suffix=0
        while prefix<min(a.count,b.count),Data(a[prefix].utf8)==Data(b[prefix].utf8) {prefix+=1}
        while suffix<min(a.count,b.count)-prefix,Data(a[a.count-1-suffix].utf8)==Data(b[b.count-1-suffix].utf8) {suffix+=1}
        var rows:[Line]=[]
        for line in a[prefix..<(a.count-suffix)].prefix(8192) {rows.append(.init(id:rows.count,sign:"−",text:line))}
        for line in b[prefix..<(b.count-suffix)].prefix(8192-rows.count) {rows.append(.init(id:rows.count,sign:"+",text:line))}
        return .init(rows:rows,complete:rows.count==a.count+b.count-2*prefix-2*suffix)
    }
    static func visible(_ value:String)->String {value.replacingOccurrences(of:" ",with:"·").replacingOccurrences(of:"\t",with:"⇥").replacingOccurrences(of:"\r",with:"␍").replacingOccurrences(of:"\n",with:"␊\n")}
    static func pages(_ value:String)->[String] {
        let units=Array(value.unicodeScalars);guard !units.isEmpty else{return [""]}
        return stride(from:0,to:units.count,by:4096).map{String(String.UnicodeScalarView(units[$0..<min($0+4096,units.count)]))}
    }
}
