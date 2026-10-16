import SwiftUI

struct ConceptAdoptionPanel:View {
    @ObservedObject var state:ConceptAdoptionState
    let concept:ProjectConcept
    let dirty:Bool
    let current:@MainActor () async throws->ConceptConnection
    var reveal:(String)->Void={_ in}
    @Environment(\.locale) private var locale
    @State private var requested=Set(["docs/product/VISION.md","docs/architecture/ARCHITECTURE.md","docs/roadmap/ROADMAP.md"])
    @State private var vision=""
    @State private var confirmed=false
    @FocusState private var focus:String?
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ConceptAdoptionCopy.text(key,language)}
    private var selected:ConceptAdoptionSources.Source? {state.sources.first{$0.id==state.source}}
    private func cardAnchor(_ operation:String,_ document:String)->String {"adoption-entry-"+state.source+"-"+operation+"-"+document}
    private func revealFocus(_ target:String) {
        if let result=state.result,let entry=result.document?.entries.first(where:{"adoption-detail-"+$0.id==target}) {reveal(cardAnchor(result.operation_id,entry.id))}
        else {reveal(target)}
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Divider();Text(text("title")).font(.title2.bold())
            Text(text("notice")).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Text(text("unknown")).font(.caption).foregroundStyle(.secondary)
            ProposalCompareControl(title:text("refresh"),focused:focus=="concept-adoption-refresh") {Task {await state.load(concept,current:current)}}.disabled(state.busy).focused($focus,equals:"concept-adoption-refresh").id("concept-adoption-refresh").accessibilityIdentifier("concept-adoption-refresh")
            if state.phase=="empty" {Text(text("empty")).fixedSize(horizontal:false,vertical:true)}
            Picker(text("source"),selection:Binding(get:{state.source},set:{value in vision="";confirmed=false;state.expandedDocument="";Task {await state.select(value,concept:concept,current:current)}})) {
                Text(text("choose")).tag("")
                ForEach(state.sources) {source in Text(verbatim:source.label).tag(source.id)}
            }.disabled(state.busy || state.sources.isEmpty).focused($focus,equals:"adoption-source").id("adoption-source").accessibilityIdentifier("adoption-source")
            if let selected {
                Text(text("setup")).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(zip(["vision","architecture","roadmap"],["docs/product/VISION.md","docs/architecture/ARCHITECTURE.md","docs/roadmap/ROADMAP.md"])),id:\.1) {key,path in
                    Toggle(text(key),isOn:Binding(get:{requested.contains(path)},set:{value in if value {requested.insert(path)} else {requested.remove(path);if key=="vision" {vision=""}};confirmed=false})).disabled(state.busy || state.pending != nil).accessibilityIdentifier("adoption-request-"+key)
                }
                if requested.contains("docs/product/VISION.md") {
                    Picker(text("reference"),selection:$vision) {Text(text("referenceNone")).tag("");ForEach(selected.source_options,id:\.self) {Text(verbatim:$0).tag($0)}}.disabled(state.busy || state.pending != nil).accessibilityIdentifier("adoption-vision-reference")
                    Toggle(text("confirm"),isOn:$confirmed).disabled(vision.isEmpty || state.busy || state.pending != nil).accessibilityIdentifier("adoption-confirm-vision")
                }
                if let pending=state.pending {
                    if state.phase=="sourceRejected" {
                        ProposalCompareControl(title:text("newAfterRejected"),focused:focus=="adoption-retire-rejected") {Task {await state.retireRejected(concept:concept,current:current)}}.disabled(state.busy).focused($focus,equals:"adoption-retire-rejected").id("adoption-retire-rejected").accessibilityIdentifier("adoption-retire-rejected")
                    }
                    Text(text(state.phase=="sourceRejected" ? "sourceRejected":state.phase=="capacity" ? "capacity":"pending")).fixedSize(horizontal:false,vertical:true)
                    if state.phase != "sourceRejected" {
                    ProposalCompareControl(title:text("resume"),focused:focus=="adoption-resume") {Task {await state.open(pending.command.operation_id,concept:concept,current:current)}}.disabled(state.busy).focused($focus,equals:"adoption-resume").id("adoption-resume").accessibilityIdentifier("adoption-resume")
                    }
                } else {
                    ProposalCompareControl(title:text("prepare"),focused:focus=="adoption-prepare") {Task {await state.prepare(concept,paths:requested.sorted(),vision:confirmed ? vision:nil,current:current)}}
                        .focused($focus,equals:"adoption-prepare").id("adoption-prepare").disabled(dirty || state.busy || state.access?.can_prepare != true || requested.isEmpty || (!vision.isEmpty && !confirmed)).accessibilityIdentifier("adoption-prepare")
                }
            }
            if dirty {Text(text("dirty"))}
            else if state.access != nil && state.access?.can_prepare != true {Text(text("noPrepare"))}
            else if requested.isEmpty {Text(text("noDocuments"))}
            else if !vision.isEmpty && !confirmed {Text(text("confirmMapping"))}
            if state.busy {ProgressView()}
            if ["access","unavailable","conflict","invalid","notFound","pending","capacity"].contains(state.phase) && !(state.phase=="capacity" && state.pending != nil) {Text(text(state.phase)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("adoption-status")}
            ForEach(state.history) {entry in
                ProposalCompareControl(title:text("open")+" "+String((state.history.firstIndex(where:{$0.id==entry.id}) ?? 0)+1)+" · "+String(entry.source_revision),focused:focus=="adoption-open-"+entry.id) {Task {await state.open(entry.operation_id,concept:concept,current:current)}}.disabled(state.busy).focused($focus,equals:"adoption-open-"+entry.id).id("adoption-open-"+entry.id).accessibilityIdentifier("adoption-open-"+entry.id)
            }
            if let result=state.result,let document=result.document {documents(document,result:result)}
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .task(id:concept) {await state.load(concept,current:current)}
        .onDisappear {state.conceal()}
        .onChange(of:focus) {_,value in if let value {revealFocus(value)}}
        .onChange(of:vision) {_,_ in confirmed=false}
        .onChange(of:state.source) {_,_ in vision="";confirmed=false;state.expandedDocument=""}
        .onChange(of:concept) {_,_ in vision="";confirmed=false;state.expandedDocument="";requested=Set(["docs/product/VISION.md","docs/architecture/ARCHITECTURE.md","docs/roadmap/ROADMAP.md"])}
    }
    private func documents(_ doc:ConceptAdoptionResult.Document,result:ConceptAdoptionResult)->some View {
        VStack(alignment:.leading,spacing:10) {
            LabeledContent(text("sourceRevision"),value:String(result.source_revision)).accessibilityIdentifier("adoption-source-revision")
            if result.source_revision != result.current_revision {
                LabeledContent(text("currentRevision"),value:String(result.current_revision))
                Text(text("historicalConcept")).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text(text("historical")).font(.callout).foregroundStyle(.secondary)
            Text(verbatim:doc.source_observation.observed_at).font(.caption)
            ForEach(["KEEP","LINK_EXISTING","PROPOSE_ADDITION","PROPOSE_CHANGE","CONFLICT","INSUFFICIENT_INFORMATION"].filter{op in doc.entries.contains{$0.operation==op}},id:\.self) {op in
                // One layout root per category preserves nested scroll-target identity.
                VStack(alignment:.leading,spacing:10) {
                Text(text(op)).font(.headline)
                ForEach(doc.entries.filter{$0.operation==op}) {entry in
                VStack(alignment:.leading,spacing:8) {
                    ProposalCompareControl(title:entry.artifact_path,focused:focus=="adoption-document-"+entry.id) {Task {await state.chooseDocument(entry.id,concept:concept,current:current)}}
                        .focused($focus,equals:"adoption-document-"+entry.id).id("adoption-document-"+entry.id).accessibilityIdentifier("adoption-document-"+entry.id)
                    if ["INSUFFICIENT_INFORMATION","CONFLICT"].contains(entry.operation) {Text(ConceptAdoptionCopy.reason(entry.reason,language)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}
                    if state.expandedDocument==entry.id {
                        VStack(alignment:.leading,spacing:8) {
                            ProposalCompareControl(title:text("close"),focused:focus=="adoption-detail-"+entry.id) {Task {await state.chooseDocument(entry.id,concept:concept,current:current)};focus="adoption-document-"+entry.id}
                                .focused($focus,equals:"adoption-detail-"+entry.id).id("adoption-detail-"+entry.id).accessibilityIdentifier("adoption-detail-"+entry.id)
                                .onKeyPress(keys:[.escape]) {press in guard press.modifiers.isEmpty else{return .ignored};Task {await state.chooseDocument(entry.id,concept:concept,current:current)};focus="adoption-document-"+entry.id;return .handled}
                            if let original=entry.mapping_source.content ?? entry.before.content {bounded(original,label:text("before"),anchor:result.operation_id+entry.id+"-before")}
                            if let proposed=entry.after.content {bounded(proposed,label:text("after"),anchor:result.operation_id+entry.id+"-after")}
                            if !entry.diff.isEmpty {DisclosureGroup(text("details")) {bounded(entry.diff,label:text("details"),anchor:result.operation_id+entry.id+"-diff")}}
                            DisclosureGroup(text("details")) {Text(verbatim:entry.reason);ForEach(entry.decisions,id:\.self) {Text(verbatim:$0)}}
                        }.task(id:entry.id) {
                                let operation=result.operation_id,source=state.source,target="adoption-detail-"+entry.id
                                await Task.yield()
                                guard !Task.isCancelled,state.source==source,state.expandedDocument==entry.id,state.result?.operation_id==operation else{return}
                                focus=target
                                // Re-reveal after layout even when restored focus already has this identity.
                                await Task.yield()
                                guard !Task.isCancelled,focus==target,state.source==source,state.expandedDocument==entry.id,state.result?.operation_id==operation else{return}
                                revealFocus(target)
                            }
                    }
                }.padding(12).frame(minWidth:0,maxWidth:.infinity,alignment:.leading).background(.quaternary.opacity(0.25),in:RoundedRectangle(cornerRadius:12)).id(cardAnchor(result.operation_id,entry.id))
            }
                }
            }
            DisclosureGroup(text("details")) {
                Text(verbatim:result.proposal.plan_id);Text(verbatim:result.proposal.request_digest);Text(verbatim:result.source_digest);Text(verbatim:doc.source_observation.snapshot_digest)
                Text(verbatim:doc.source_observation.selection.joined(separator:"\n"));Text(verbatim:doc.source_observation.exclusions.joined(separator:"\n"))
                ForEach(doc.decisions,id:\.self) {Text(verbatim:$0)}
            }.font(.caption).textSelection(.enabled)
        }
    }
    private func bounded(_ value:String,label:String,anchor:String)->some View {ProposalCompareOriginalView(value:nil,side:label,language:language,reveal:reveal,documentPath:"adoption-"+anchor,content:value)}
}
