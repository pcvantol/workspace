import SwiftUI

struct ProposalCompareView:View {
    @ObservedObject var state:ProposalCompareState
    let concept:ProjectConcept
    let current:@MainActor () async throws->ConceptConnection
    var discuss:()->Void={}
    var returnFocusRequest=0
    private enum ReturnTarget:Hashable {case refresh,discuss}
    @FocusState private var returnFocused:ReturnTarget?
    @State var differencesOnly=true
    @Environment(\.locale) private var locale
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    private func label(_ entry:ConceptBaselineHistory.Entry)->String {text("version")+" "+String((state.history.firstIndex(where:{$0.id==entry.id}) ?? 0)+1)+" · "+text("revision")+" "+String(entry.source_revision)}
    private func picker(_ before:Bool)->some View {
        Picker(text(before ? "before":"after"),selection:Binding(get:{before ? state.choice?.before ?? state.history.first?.id ?? "":state.choice?.after ?? state.history.last?.id ?? ""},set:{id in
            guard let chosen=state.choice else{return}
            let next=ProposalCompareState.Choice(before:before ? id:(id==chosen.before ? chosen.after:chosen.before),after:before ? (id==chosen.after ? chosen.before:chosen.after):id)
            guard next != chosen else{return}
            Task {await state.compare(next,concept:concept,current:current)}
        })) {
            ForEach(state.history) {entry in Text(label(entry)).tag(entry.id)}
        }.pickerStyle(.menu).disabled(state.busy).accessibilityIdentifier(before ? "proposal-compare-before":"proposal-compare-after")
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Divider();Text(text("title")).font(.title2.bold())
            Text(text("preparation")).fixedSize(horizontal:false,vertical:true)
            Text(text("readOnly")).font(.caption).foregroundStyle(.secondary)
            Button(text("refresh")) {Task {await state.load(concept,current:current)}}.disabled(state.busy).focusable(interactions:.edit).onKeyPress(.space) {guard !state.busy else{return .ignored};Task {await state.load(concept,current:current)};return .handled}.focused($returnFocused,equals:.refresh).accessibilityIdentifier("proposal-compare-refresh")
            if state.busy {ProgressView(text("loading"))}
            if !["idle","loading","comparable"].contains(state.phase) {Text(text(state.phase)).accessibilityIdentifier("proposal-compare-status")}
            if state.partialHistory {Text(text("historyPartial")).foregroundStyle(.secondary)}
            if state.history.count>1, state.choice != nil {
                ViewThatFits(in:.horizontal) {HStack {picker(true);picker(false)}.frame(minWidth:620);VStack(alignment:.leading) {picker(true);picker(false)}}
            }
            if let model=state.comparison {
                if concept.revision>max(model.before.source_revision,model.after.source_revision) {
                    Text(text("newer")).foregroundStyle(.secondary)
                    LabeledContent(text("revision"),value:String(concept.revision))
                }
                Text(text("overview")).font(.headline)
                ForEach(model.fields) {field in
                    DisclosureGroup {
                        ViewThatFits(in:.horizontal) {
                            HStack(alignment:.top) {fieldText(field.before,side:"before",unknown:model.before.unknown_fields.contains(field.id));fieldText(field.after,side:"after",unknown:model.after.unknown_fields.contains(field.id))}.frame(minWidth:620)
                            VStack(alignment:.leading) {fieldText(field.before,side:"before",unknown:model.before.unknown_fields.contains(field.id));fieldText(field.after,side:"after",unknown:model.after.unknown_fields.contains(field.id))}
                        }
                    } label: {Label(text(field.id)+" · "+text(field.changed ? "changed":"unchanged"),systemImage:field.changed ? "text.badge.plus":"equal.circle")}
                }
                Text(text("documents")+" · "+String(model.changedDocuments)+" / "+String(model.documents.count)).font(.headline)
                Toggle(text("differencesOnly"),isOn:$differencesOnly).accessibilityIdentifier("proposal-compare-filter")
                Text(text("notDeleted")).font(.caption).foregroundStyle(.secondary)
                ForEach(["productDocs","architectureDocs","roadmapDocs","workingDocs","otherDocs"],id:\.self) {group in
                    let documents=model.documents.filter{$0.group==group && (!differencesOnly || $0.status != "unchanged")}
                    if !documents.isEmpty {
                        Text(text(group)).font(.subheadline.bold())
                        ForEach(documents) {document in
                            ProposalCompareDocumentView(document:document,language:language)
                                .id(model.before.operation_id+model.after.operation_id+document.path)
                        }
                    }
                }
                DisclosureGroup(text("questions")) {
                    ForEach(model.questions) {question in
                        VStack(alignment:.leading) {Text(text(question.status)).font(.caption.bold());Text(verbatim:question.text).textSelection(.enabled)}
                    }
                }.accessibilityIdentifier("proposal-compare-questions")
                DisclosureGroup(text("details")) {
                    Text(verbatim:model.profile).textSelection(.enabled)
                    source(model.before);source(model.after)
                }.accessibilityIdentifier("proposal-compare-source")
                Button(text("discuss"),action:discuss).focusable(interactions:.edit).onKeyPress(.space) {discuss();return .handled}.focused($returnFocused,equals:.discuss).accessibilityIdentifier("proposal-compare-discuss").id("proposal-compare-discuss")
            }
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .onChange(of:returnFocusRequest) {_,_ in returnFocused=state.comparison==nil ? .refresh:.discuss}
        .task(id:concept) {await state.load(concept,current:current)}
        .onDisappear {state.conceal()}
    }
    private func fieldText(_ value:String,side:String,unknown:Bool)->some View {
        VStack(alignment:.leading) {Text(text(side)).font(.caption.bold());Text(verbatim:unknown ? text("unknown"):value).textSelection(.enabled)}.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
    }
    private func source(_ value:ConceptBaselineResult)->some View {
        VStack(alignment:.leading) {
            Text(text("revision")+" "+String(value.source_revision))
            Text(verbatim:value.proposal.plan_id+"\n"+value.operation_id+"\n"+value.producer_source+"\n"+value.source_digest+"\n"+value.proposal.request_digest+"\n"+value.proposal.record_digest).font(.caption.monospaced()).textSelection(.enabled)
            Text(verbatim:value.proposal.result.artifacts.first(where:{$0.path=="engineering/bootstrap-manifest.json"})?.content ?? "").font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}

struct ProposalCompareDocumentView:View {
    let document:ProposalCompareModel.Document
    let language:String
    @State var expanded=false
    @State var difference:ProposalCompareModel.Difference?
    @State var page=0
    @State var invisible=false
    @FocusState private var openerFocused:Bool
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Button {expanded.toggle()} label: {Label(text(document.status)+" · "+document.path,systemImage:expanded ? "chevron.down":"chevron.right").multilineTextAlignment(.leading)}
                .focusable(interactions:.edit).focused($openerFocused).onKeyPress(.space) {expanded.toggle();return .handled}.accessibilityIdentifier("proposal-compare-document-"+document.path)
            if expanded {
                Toggle(text("invisible"),isOn:$invisible)
                if let difference {
                    if !difference.complete {Text(text("bounded")).font(.caption)}
                    if difference.rows.isEmpty,document.status=="changed" {Text(text("metadataOnly"))}
                    let pages=max(1,(difference.rows.count+119)/120)
                    ForEach(Array(difference.rows.dropFirst(page*120).prefix(120))) {line in
                        Text(verbatim:line.sign+" "+(invisible ? ProposalCompareModel.visible(line.text):line.text)).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
                    }
                    HStack {Button(text("previous")) {page-=1}.focusable(interactions:.edit).onKeyPress(.space) {guard page>0 else{return .ignored};page-=1;return .handled}.accessibilityLabel(text("previous")+" · "+document.path).disabled(page==0);Text(text("page")+" "+String(page+1)+" / "+String(pages));Button(text("next")) {page+=1}.focusable(interactions:.edit).onKeyPress(.space) {guard page+1<pages else{return .ignored};page+=1;return .handled}.accessibilityLabel(text("next")+" · "+document.path).disabled(page+1>=pages)}
                } else {ProgressView()}
                DisclosureGroup(text("full")) {
                    VStack(alignment:.leading) {
                        ProposalCompareOriginalView(value:document.before,side:text("before"),language:language)
                        ProposalCompareOriginalView(value:document.after,side:text("after"),language:language)
                    }
                }
                DisclosureGroup(text("details")) {
                    Text(verbatim:document.path).textSelection(.enabled)
                    ForEach([document.before,document.after].indices,id:\.self) {index in
                        if let value=[document.before,document.after][index] {Text(verbatim:String(value.mode)+" · "+String(value.content.utf8.count)+" bytes · "+value.sha256).font(.caption.monospaced()).textSelection(.enabled)}
                    }
                }
            }
        }.padding(.leading,8)
        .onExitCommand {if expanded {expanded=false;openerFocused=true}}
        .task {let result=await Task.detached(priority:.utility) {ProposalCompareModel.difference(document)}.value;if !Task.isCancelled {difference=result}}
    }
}
struct ProposalCompareOriginalView:View {
    let value:ConceptBaselineResult.Artifact?
    let side:String
    let language:String
    @State var page=0
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading) {
            Text(side).font(.subheadline.bold())
            if let value {
                let pages=ProposalCompareModel.pages(value.content)
                Text(verbatim:pages[min(page,pages.count-1)]).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
                let previousLabel=[text("previous"),side,value.path].joined(separator:" · ")
                let nextLabel=[text("next"),side,value.path].joined(separator:" · ")
                let pageLabel=text("page")+" "+String(page+1)+" / "+String(pages.count)
                HStack {
                    Button(text("previous")) {page-=1}
                        .focusable(interactions:.edit).onKeyPress(.space) {guard page>0 else{return .ignored};page-=1;return .handled}
                        .accessibilityLabel(previousLabel).disabled(page==0)
                    Text(pageLabel)
                    Button(text("next")) {page+=1}
                        .focusable(interactions:.edit).onKeyPress(.space) {guard page+1<pages.count else{return .ignored};page+=1;return .handled}
                        .accessibilityLabel(nextLabel).disabled(page+1>=pages.count)
                }
            } else {Text(text("absent")).foregroundStyle(.secondary)}
        }
    }
}
