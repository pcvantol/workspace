import SwiftUI
import AppKit

struct ProposalCompareView:View {
    @ObservedObject var state:ProposalCompareState
    let concept:ProjectConcept
    let current:@MainActor () async throws->ConceptConnection
    var discuss:()->Void={}
    var returnFocusRequest=0
    var reveal:(String)->Void={_ in}
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
            ProposalCompareControl(title:text("refresh"),focused:returnFocused == .refresh) {Task {await state.load(concept,current:current)}}.disabled(state.busy).focused($returnFocused,equals:.refresh).accessibilityIdentifier("proposal-compare-refresh").id("proposal-compare-refresh")
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
                            ProposalCompareDocumentView(document:document,language:language,reveal:reveal,scrollIdentity:"proposal-compare-anchor-"+model.before.operation_id+model.after.operation_id+document.path)
                                .id("proposal-compare-anchor-"+model.before.operation_id+model.after.operation_id+document.path)
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
                ProposalCompareControl(title:text("discuss"),focused:returnFocused == .discuss,action:discuss).focused($returnFocused,equals:.discuss).accessibilityIdentifier("proposal-compare-discuss").id("proposal-compare-discuss")
            }
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .onChange(of:returnFocused) {_,target in if let target {reveal(target == .refresh ? "proposal-compare-refresh":"proposal-compare-discuss")} }
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

// One bounded native pager keeps its focused control and the new page visible.
struct ProposalComparePager:View {
    @Binding var page:Int
    let count:Int
    let label:String
    let language:String
    let anchor:String
    var reveal:(String)->Void={_ in}
    private enum Direction {case previous,next}
    @FocusState private var focused:Direction?
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    var body:some View {
        HStack {
            ProposalCompareControl(title:text("previous"),focused:focused == .previous) {page-=1}
                .focused($focused,equals:.previous)
                .accessibilityLabel([text("previous"),label].joined(separator:" · "))
                .accessibilityIdentifier(anchor+"-previous").disabled(page==0)
            Text(text("page")+" "+String(page+1)+" / "+String(count))
            ProposalCompareControl(title:text("next"),focused:focused == .next) {page+=1}
                .focused($focused,equals:.next)
                .accessibilityLabel([text("next"),label].joined(separator:" · "))
                .accessibilityIdentifier(anchor+"-next").disabled(page+1>=count)
        }
        .onChange(of:focused) {_,value in if value != nil {reveal(anchor)}}
        .onChange(of:page) {_,_ in reveal(anchor)}
    }
}

struct ProposalCompareDocumentView:View {
    let document:ProposalCompareModel.Document
    let language:String
    var reveal:(String)->Void={_ in}
    var scrollIdentity=""
    @State var expanded=false
    @State var difference:ProposalCompareModel.Difference?
    @State var page=0
    @State var invisible=false
    @FocusState private var openerFocused:Bool
    private var anchor:String {scrollIdentity.isEmpty ? "proposal-compare-anchor-"+document.path:scrollIdentity}
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            ProposalCompareControl(title:text(document.status)+" · "+document.path,systemImage:expanded ? "chevron.down":"chevron.right",focused:openerFocused) {expanded.toggle()}
                .focused($openerFocused)
                .accessibilityLabel(text(document.status)+" · "+document.path)
                .accessibilityIdentifier("proposal-compare-document-"+document.path)
            if expanded {
                Toggle(text("invisible"),isOn:$invisible)
                if let difference {
                    if !difference.complete {Text(text("bounded")).font(.caption)}
                    if difference.rows.isEmpty,document.status=="changed" {Text(text("metadataOnly"))}
                    let pages=max(1,(difference.rows.count+119)/120)
                    ProposalComparePager(page:$page,count:pages,label:document.path,language:language,anchor:anchor,reveal:reveal)
                    ForEach(Array(difference.rows.dropFirst(page*120).prefix(120))) {line in
                        Text(verbatim:line.sign+" "+(invisible ? ProposalCompareModel.visible(line.text):line.text)).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
                    }
                } else {ProgressView()}
                DisclosureGroup(text("full")) {
                    VStack(alignment:.leading) {
                        ProposalCompareOriginalView(value:document.before,side:text("before"),language:language,reveal:reveal,documentPath:document.path)
                        ProposalCompareOriginalView(value:document.after,side:text("after"),language:language,reveal:reveal,documentPath:document.path)
                    }
                }.accessibilityIdentifier("proposal-compare-originals-"+document.path)
                DisclosureGroup(text("details")) {
                    Text(verbatim:document.path).textSelection(.enabled)
                    ForEach([document.before,document.after].indices,id:\.self) {index in
                        if let value=[document.before,document.after][index] {Text(verbatim:String(value.mode)+" · "+String(value.content.utf8.count)+" bytes · "+value.sha256).font(.caption.monospaced()).textSelection(.enabled)}
                    }
                }.accessibilityIdentifier("proposal-compare-document-details-"+document.path)
            }
        }.padding(.leading,8)
        .onChange(of:openerFocused) {_,value in if value {reveal(anchor)}}
        .onChange(of:expanded) {_,_ in reveal(anchor)}
        .onExitCommand {if expanded {expanded=false;openerFocused=true}}
        .task {let result=await Task.detached(priority:.utility) {ProposalCompareModel.difference(document)}.value;if !Task.isCancelled {difference=result}}
    }
}
struct ProposalCompareOriginalView:View {
    let value:ConceptBaselineResult.Artifact?
    let side:String
    let language:String
    var reveal:(String)->Void={_ in}
    var documentPath=""
    @State var page=0
    private var anchor:String {"proposal-compare-original-anchor-"+side+"-"+(documentPath.isEmpty ? value?.path ?? "missing":documentPath)}
    private func text(_ key:String)->String {ProposalCompareCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading) {
            Text(side).font(.subheadline.bold())
            if let value {
                let pages=ProposalCompareModel.pages(value.content)
                ProposalComparePager(page:$page,count:pages.count,label:side+" · "+value.path,language:language,anchor:anchor,reveal:reveal)
                Text(verbatim:pages[min(page,pages.count-1)]).font(.system(.caption,design:.monospaced)).textSelection(.enabled).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
            } else {Text(text("absent")).foregroundStyle(.secondary)}
        }.id(anchor)
    }
}

// Exactly one keyboard focus owner; the AppKit anchor reveals that same control.
struct ProposalCompareControl:View {
    let title:String
    var systemImage:String?=nil
    var focused=false
    let action:()->Void
    @Environment(\.isEnabled) private var enabled
    private func activate()->KeyPress.Result {guard enabled else{return .ignored};action();return .handled}
    var body:some View {
        Group {if let systemImage {Label(title,systemImage:systemImage)} else {Text(title)}}
            .multilineTextAlignment(.leading).padding(.vertical,3).padding(.horizontal,7)
            .background(.quaternary,in:RoundedRectangle(cornerRadius:5)).opacity(enabled ? 1:0.45)
            .overlay(RoundedRectangle(cornerRadius:5).stroke(focused ? Color.accentColor:Color.clear,lineWidth:2))
            .contentShape(Rectangle()).focusable(enabled,interactions:.edit)
            .onTapGesture {if enabled {action()}}
            .onKeyPress(keys:[.space,.return]) {press in guard press.modifiers.isEmpty else{return .ignored};return activate()}
            .accessibilityElement(children:.ignore).accessibilityLabel(title)
            .accessibilityAddTraits(.isButton).accessibilityAction {if enabled {action()}}
            .background(ProposalCompareFocusViewport(focused:focused).allowsHitTesting(false))
    }
}
struct ProposalCompareFocusViewport:NSViewRepresentable {
    var focused:Bool
    func makeNSView(context:Context)->ProposalCompareViewportAnchor {ProposalCompareViewportAnchor()}
    func updateNSView(_ view:ProposalCompareViewportAnchor,context:Context) {view.reveal(focused)}
    static func dismantleNSView(_ view:ProposalCompareViewportAnchor,coordinator:()) {view.reveal(false)}
}
final class ProposalCompareViewportAnchor:NSView {
    private var currentFocus=false
    private var generation=0
    func reveal(_ focused:Bool) {
        currentFocus=focused;generation+=1;let ticket=generation
        guard focused else{return}
        DispatchQueue.main.async {[weak self] in
            guard let self,self.window != nil,self.currentFocus,self.generation==ticket else{return}
            self.scrollToVisible(self.bounds)
        }
    }
}
