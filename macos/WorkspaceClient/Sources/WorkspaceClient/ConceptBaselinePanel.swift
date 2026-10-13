import SwiftUI

struct ConceptBaselinePanel:View {
    @ObservedObject var state:ConceptBaselineState
    let concept:ProjectConcept
    let dirty:Bool
    let current:@MainActor () async throws -> ConceptConnection
    @State private var questionsExpanded=true
    @State private var documentsExpanded=true
    @Environment(\.locale) private var locale
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ConceptBaselineCopy.text(key,language)}
    private func group(_ path:String)->String {
        if path=="README.md" || path.hasPrefix("docs/product/") {return "productDocs"}
        if path.hasPrefix("docs/architecture/") {return "architectureDocs"}
        if path.hasPrefix("docs/roadmap/") {return "roadmapDocs"}
        if path=="AGENTS.md" || path=="BOOTSTRAP.md" || path.hasPrefix("docs/engineering/") {return "workingDocs"}
        return "otherDocs"
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            if let pending=state.pending {
                Text(text("original")).font(.headline)
                LabeledContent(text("revision"),value:String(pending.command.expected_revision))
                Text(verbatim:pending.source.title)
                DisclosureGroup(text("source")) {Text(verbatim:pending.source.originalNotes).textSelection(.enabled)}
                if let purpose=pending.command.description {Text(verbatim:purpose).textSelection(.enabled)}
                if state.phase=="sourceRejected" {
                    Button(text("newAfterRejected")) {Task {await state.retireRejected(concept:concept,current:current)}}
                        .disabled(state.busy).accessibilityIdentifier("concept-baseline-new-after-rejection")
                }
                Button(text("resume")) {Task {await state.prepare(pending.source,concept:concept,current:current)}}
                    .disabled(state.busy || state.access?.can_prepare != true).accessibilityIdentifier("concept-baseline-resume")
                    .keyboardShortcut(.return,modifiers:.command).help(text("resumeShortcut"))
                Text(text("resumeShortcut")).font(.caption).foregroundStyle(.secondary)
            } else {
                ConceptBaselineDraftView(concept:concept,dirty:dirty || state.busy,showAccessRequirement:state.phase=="access" || (state.access != nil && state.access?.can_prepare==false),onPrepare:state.access?.can_prepare==true ? {source in Task {await state.prepare(source,concept:concept,current:current)}}:nil)
            }
            if let access=state.access {
                Text(text(access.can_prepare ? "ready":"readOnly")).font(.subheadline)
                Text(verbatim:"Forge · "+String(access.producer_source.prefix(12))).font(.caption).foregroundStyle(.secondary)
            }
            if state.access==nil && !state.busy {
                if state.phase=="access" {Text(text("access")).foregroundStyle(.secondary)}
                Button(text("refreshAccess")) {Task {await state.load(concept,current:current)}}.accessibilityIdentifier("concept-baseline-refresh")
            }
            if state.busy {ProgressView()}
            if ["capacity","offline","conflict","sourceRejected","invalid","notFound","unavailable"].contains(state.phase) {Text(text(state.phase)).foregroundStyle(.secondary)}
            ForEach(state.history) {entry in
                Button {Task {await state.open(entry.operation_id,concept:concept,current:current)}} label: {
                    Text(text("open")+" · "+text("revision")+" "+String(entry.source_revision))
                }.disabled(state.busy).accessibilityIdentifier("concept-baseline-open-"+entry.operation_id)
            }
            if let result=state.result {
                Text(text("badge")).font(.headline).accessibilityIdentifier("concept-baseline-result")
                Text(text("english")).foregroundStyle(.secondary)
                LabeledContent(text("revision"),value:String(result.source_revision))
                LabeledContent(text("documents"),value:String(result.proposal.result.artifacts.count))
                DisclosureGroup(text("summary")) {
                    Text(verbatim:result.proposal.result.summary).textSelection(.enabled)
                }.accessibilityIdentifier("concept-baseline-summary")
                if result.current_revision != result.source_revision {Text(text("sourceChanged")).foregroundStyle(.secondary)}
                DisclosureGroup(text("source")) {
                    Text(verbatim:result.source_product.name).font(.headline)
                    Text(verbatim:result.source_product.purpose).textSelection(.enabled)
                }
                DisclosureGroup(text("questions"),isExpanded:$questionsExpanded) {
                    VStack(alignment:.leading,spacing:8) {
                        ForEach(Array(result.source_product.open_questions.enumerated()),id:\.offset) {_,question in Text(verbatim:question).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
                    }
                }
                DisclosureGroup(text("documents"),isExpanded:$documentsExpanded) {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(["productDocs","architectureDocs","roadmapDocs","workingDocs","otherDocs"],id:\.self) {key in
                            let documents=result.proposal.result.artifacts.filter{group($0.path)==key}
                            if !documents.isEmpty {
                                Text(text(key)+" · "+String(documents.count)).font(.subheadline.bold())
                                ForEach(documents) {artifact in
                                    DisclosureGroup {Text(verbatim:artifact.content).font(.system(.body,design:.monospaced)).textSelection(.enabled).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)} label:{Text(verbatim:artifact.path).lineLimit(2)}
                                    .accessibilityIdentifier("concept-baseline-document-"+artifact.path)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task(id:concept) {await state.load(concept,current:current)}
        .onDisappear {state.conceal()}
    }
}
