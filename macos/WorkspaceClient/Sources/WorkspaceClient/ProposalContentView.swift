import SwiftUI

struct ProposalContentView:View {
    @ObservedObject var state:ProposalContentState
    let concept:ProjectConcept
    let source:ConceptBaselineResult
    let dirty:Bool
    let current:@MainActor () async throws -> ConceptConnection
    let discuss:()->Void
    let returnFocusRequest:Int
    let reveal:()->Void
    @Environment(\.locale) private var locale
    @State private var role=""
    @State private var choice=""
    @State private var reason=""
    @State private var acknowledged=false
    private enum Target:Hashable {case inspect,review,recover,discuss}
    @FocusState private var focused:Target?
    @State private var confirmationIdentity:String?
    @State private var dismissedSubject:String?
    @State private var dismissedGeneration:Int?
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {ProposalContentCopy.text(key,language)}
    private var selectedIdentity:String {source.operation_id+"/"+source.proposal.record_digest+"/"+String(concept.revision)}
    private var canReview:Bool {!dirty && !state.busy && state.pending==nil && state.result?.permissions.contains("DECIDE")==true && state.result?.roles.contains(role)==true && !choice.isEmpty && !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count<=2000 && (acknowledged || source.source_product.open_questions.isEmpty) && concept.lifecycle != "ARCHIVED"}
    private func resetForm() {role="";choice="";reason="";acknowledged=false;state.cancelConfirmation()}
    private var sourceSummary:some View {ProposalContentSourceView(source:source,currentRevision:concept.revision,language:language)}
    private func restoreFocus() {
        guard let subject=dismissedSubject,subject==selectedIdentity,dismissedGeneration==state.focusGeneration,!state.busy else{return}
        dismissedSubject=nil;dismissedGeneration=nil;reveal();focused=state.pending != nil ? .recover:state.result != nil ? .review:.inspect
    }
    private func invalidateFocus() {confirmationIdentity=nil;dismissedSubject=nil;dismissedGeneration=nil;focused=nil;state.conceal()}
    private var questions:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(text("questions")).font(.subheadline.bold())
            ForEach(Array(source.source_product.open_questions.enumerated()),id:\.offset) {_,point in Text(verbatim:point).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Divider();Text(text("title")).font(.title2.bold()).accessibilityIdentifier("proposal-content-title")
            sourceSummary
            Text(text("scope")).foregroundStyle(.secondary)
            ProposalCompareControl(title:text(state.result==nil ? "inspect":"refresh"),focused:focused == .inspect) {resetForm();Task {await state.load(source,concept:concept,current:current)}}.focused($focused,equals:.inspect)
                .disabled(state.busy).accessibilityIdentifier("proposal-content-inspect")
            if state.busy {ProgressView()}
            if ["access","conflict","unavailable","invalid","unsupported","capacity"].contains(state.phase) {Text(text(state.phase)).foregroundStyle(.secondary).accessibilityIdentifier("proposal-content-status")}
            if let value=state.result {
                Text(text(value.decision.state)).font(.headline).accessibilityIdentifier("proposal-content-result")
                ForEach(["BUSINESS","ARCHITECTURE"],id:\.self) {role in
                    let latest=value.decision.history.last(where:{$0.request.role==role})
                    VStack(alignment:.leading,spacing:4) {Text(text(role)).font(.subheadline.bold());Text(text("lastRecorded")).font(.caption).foregroundStyle(.secondary);Text(text(latest.map{$0.request.decision=="APPROVE_CONTENT" ? "approvedRecorded":"changesRecorded"} ?? "noDecision"))}
                }
                questions
                if dirty {Text(text("saveFirst")).foregroundStyle(.secondary)}
                if concept.lifecycle=="ARCHIVED" {Text(text("restoreFirst")).foregroundStyle(.secondary)}
                if !value.permissions.contains("DECIDE") {Text(text("readOnly")).foregroundStyle(.secondary)}
                else if state.pending==nil {
                    Picker(text("role"),selection:$role) {Text(text("chooseRole")).tag("");ForEach(value.roles,id:\.self) {Text(text($0)).tag($0)}}.accessibilityIdentifier("proposal-content-role")
                    Picker(text("choice"),selection:$choice) {Text(text("chooseDecision")).tag("");Text(text("APPROVE_CONTENT")).tag("APPROVE_CONTENT");Text(text("REQUEST_CHANGES")).tag("REQUEST_CHANGES")}.accessibilityIdentifier("proposal-content-choice")
                    TextField(text("reason"),text:$reason,axis:.vertical).lineLimit(3...6).textFieldStyle(.roundedBorder).accessibilityIdentifier("proposal-content-reason")
                    Text(text("reasonLimit")+" · "+String(reason.unicodeScalars.count)+"/2000").font(.caption).foregroundStyle(.secondary)
                    if !value.decision.open_points.isEmpty {Toggle(text("acknowledge"),isOn:$acknowledged).accessibilityIdentifier("proposal-content-acknowledge")}
                    ProposalCompareControl(title:text("review"),focused:focused == .review) {confirmationIdentity=selectedIdentity;state.stage(role:role,choice:choice,reason:reason,acknowledged:acknowledged,concept:concept)}
                        .disabled(!canReview).focused($focused,equals:.review).accessibilityIdentifier("proposal-content-review")
                }
                DisclosureGroup(text("history")) {
                    VStack(alignment:.leading,spacing:12) {
                        ForEach(value.decision.history) {record in
                            VStack(alignment:.leading,spacing:6) {
                                Text(text(record.request.role)+" · "+text(record.request.decision=="APPROVE_CONTENT" ? "approvedRecorded":"changesRecorded")).font(.headline)
                                Text(text("person")+" · "+record.principal_id)
                                Text(verbatim:record.occurred_at).font(.caption)
                                Text(verbatim:record.request.reason).textSelection(.enabled)
                                sourceSummary
                                DisclosureGroup(text("source")) {Text(verbatim:record.request.subject.record_digest).textSelection(.enabled);ForEach(Array(record.request.subject.source_references.enumerated()),id:\.offset) {_,reference in Text(verbatim:reference.reference+" · "+reference.owner+" · "+reference.digest).textSelection(.enabled)}}
                                ForEach(Array(record.request.acknowledged_open_points.enumerated()),id:\.offset) {_,point in Text(verbatim:point).textSelection(.enabled)}
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                }.accessibilityIdentifier("proposal-content-history")
                if value.decision.state=="CHANGES_REQUESTED" {
                    ProposalCompareControl(title:text("discuss"),focused:focused == .discuss,action:discuss).focused($focused,equals:.discuss).accessibilityIdentifier("proposal-content-discuss").id("proposal-content-discuss")
                }
            }
            if state.pending != nil {
                Text(text("pending")).foregroundStyle(.secondary)
                ProposalCompareControl(title:text("recover"),focused:focused == .recover) {Task {await state.recover(source,concept:concept,current:current)}}.focused($focused,equals:.recover).disabled(state.busy || dirty).accessibilityIdentifier("proposal-content-recover")
            }
        }
        .frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .sheet(isPresented:Binding(get:{state.confirmation != nil},set:{if !$0 {state.cancelConfirmation()}}),onDismiss:{let ticket=state.focusGeneration;dismissedSubject=confirmationIdentity;dismissedGeneration=ticket;Task {await Task.yield();guard state.focusGeneration==ticket else{return};restoreFocus()}}) {
            if let command=state.confirmation {
                ProposalContentConfirmation(source:source,currentRevision:concept.revision,command:command,language:language,confirm:{Task {await state.confirm(source,concept:concept,current:current)}},cancel:{state.cancelConfirmation()})
            }
        }
        .onChange(of:selectedIdentity) {_,_ in invalidateFocus();resetForm()}
        .onChange(of:dirty) {_,changed in if changed {invalidateFocus();resetForm()}}
        .onChange(of:state.busy) {_,busy in if !busy {restoreFocus()}}
        .onChange(of:returnFocusRequest) {_,_ in focused = .discuss}
        .onDisappear {invalidateFocus()}
    }
}

struct ProposalContentSourceView:View {
    let source:ConceptBaselineResult
    let currentRevision:Int
    let language:String
    private func text(_ key:String)->String {ProposalContentCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(verbatim:source.source_product.name).font(.headline)
            LabeledContent(text("revision"),value:String(source.source_revision))
            if currentRevision != source.source_revision {
                LabeledContent(text("currentRevision"),value:String(currentRevision));Text(text("historical")).foregroundStyle(.secondary)
            }
            Text(text("source")+" · "+String(source.proposal.record_digest.prefix(12))).font(.caption).foregroundStyle(.secondary)
            Text(verbatim:source.source_product.purpose).textSelection(.enabled)
            DisclosureGroup(text("briefing")) {
                VStack(alignment:.leading,spacing:8) {
                    Text(text("unknown")).foregroundStyle(.secondary)
                    ForEach(["users","non_goals","constraints"],id:\.self) {key in
                        Text(ProposalCompareCopy.text(key,language)).font(.subheadline.bold())
                        Text(verbatim:key=="users" ? source.source_product.users:key=="non_goals" ? source.source_product.non_goals:source.source_product.constraints).textSelection(.enabled)
                    }
                }
            }
        }
    }
}
struct ProposalContentConfirmation:View {
    let source:ConceptBaselineResult
    let currentRevision:Int
    let command:ProposalContentCommand
    let language:String
    let confirm:()->Void
    let cancel:()->Void
    private func text(_ key:String)->String {ProposalContentCopy.text(key,language)}
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            ScrollView {VStack(alignment:.leading,spacing:12) {
                Text(text("title")).font(.title2.bold())
                ProposalContentSourceView(source:source,currentRevision:currentRevision,language:language)
                Text(text(command.role)).font(.headline);Text(text(command.decision)).font(.headline)
                Text(verbatim:command.reason).textSelection(.enabled)
                Text(text("questions")).font(.subheadline.bold())
                ForEach(Array(command.acknowledged_open_points.enumerated()),id:\.offset) {_,point in Text(verbatim:point).textSelection(.enabled)}
                Text(text("acknowledge")).foregroundStyle(.secondary);Text(text("scope")).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity,alignment:.leading)}
            Button(text("confirm"),action:confirm).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).accessibilityIdentifier("proposal-content-confirm")
            Button(text("cancel"),action:cancel).keyboardShortcut(.cancelAction).accessibilityIdentifier("proposal-content-cancel")
        }.padding(24).frame(minWidth:360,idealWidth:580,maxWidth:760,minHeight:320,idealHeight:600,maxHeight:800)
    }
}
