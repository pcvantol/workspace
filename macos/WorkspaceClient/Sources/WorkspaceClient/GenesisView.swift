import SwiftUI

struct GenesisView:View {
    @ObservedObject var state:GenesisState
    let concept:ProjectConcept;let source:ConceptBaselineResult;let dirty:Bool
    let current:@MainActor () async throws -> ConceptConnection
    let reveal:@MainActor (String)->Void
    @Environment(\.locale) private var locale
    @State private var target=""
    @State private var confirmation:Confirmation?
    @State private var restoredPresentation=""
    @FocusState private var focused:String?
    @StateObject private var navigation=GenesisDocumentNavigation()
    private struct Confirmation {let decision:String;let reason:String;let selection:String;let targetLabel:String;let revision:Int}
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {GenesisCopy.text(key,language)}
    private var identity:String {concept.id+"/"+String(concept.revision)+"/"+source.operation_id}
    private var canDecide:Bool {!dirty && !state.busy && state.pending==nil && state.result?.can_decide==true && state.phase=="loaded" && !navigation.busy && !state.reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && state.reason.unicodeScalars.count<=2000}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(text("title")).font(.title3.bold())
            Text(text("boundary")).foregroundStyle(.secondary)
            if let access=state.access {
                Text(text("content")).font(.headline)
                if access.content.state=="CONTENT_APPROVED" {Text(text("CONTENT_APPROVED"))}
                else {ForEach(access.content.missingRoles,id:\.self) {role in Text(text(role)+" · "+text("contentRoleMissing"))}}
                if access.targets.isEmpty {Text(text("noTargets")).foregroundStyle(.secondary)}
                else {
                    Picker(text("newTarget"),selection:$target) {
                        ForEach(access.targets) {t in Text(verbatim:t.label).tag(t.id)}
                    }.accessibilityIdentifier("genesis-target").disabled(state.busy || state.pending != nil)
                    ProposalCompareControl(title:text("prepare")) {confirmation=nil;Task {await state.prepare(concept,source:source,target:target,current:current)}}
                        .disabled(dirty || state.busy || state.pending != nil || !access.can_plan || !["choose","loaded"].contains(state.phase) || access.content.state != "CONTENT_APPROVED" || !access.targets.contains(where:{$0.id==target}))
                        .accessibilityIdentifier("genesis-prepare")
                }
                if !access.plans.isEmpty {
                    DisclosureGroup(text("history")) {
                        ForEach(access.plans) {p in Button(text("history")+" · "+String(p.plan_revision)) {confirmation=nil;Task {await state.open(p.operation_id,concept:concept,source:source,current:current)}}.disabled(state.busy || state.pending != nil).accessibilityIdentifier("genesis-open-"+p.operation_id)}
                    }
                }
            }
            if state.busy {ProgressView()}
            if ["access","conflict","unavailable","invalid","notObserved"].contains(state.phase) {Text(text(state.phase)).foregroundStyle(.secondary).accessibilityIdentifier("genesis-state")}
            ProposalCompareControl(title:text("refresh")) {confirmation=nil;Task {await state.load(concept,source:source,current:current)}}.disabled(state.busy).accessibilityIdentifier("genesis-refresh")
            if state.pending != nil {
                Text(text("pending"))
                ProposalCompareControl(title:text("resume")) {Task {await state.resume(concept,source:source,current:current)}}.disabled(state.busy).accessibilityIdentifier("genesis-recover-original")
            }
            if let envelope=state.result {plan(envelope)}
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .task(id:identity) {navigation.invalidate();target="";confirmation=nil;await state.load(concept,source:source,current:current);if target.isEmpty {target=state.access?.targets.first?.id ?? ""}}
        .onChange(of:state.busy) {_,busy in if !busy {Task {await restoreDocument()}}}
        .onChange(of:state.result?.result.plan.plan_digest) {_,_ in Task {await Task.yield();await restoreDocument()}}
        .onChange(of:dirty) {_,changed in if changed {confirmation=nil}}
        .onChange(of:state.result?.selection_digest) {_,_ in confirmation=nil}
        .onChange(of:target) {old,new in if old != new {confirmation=nil}}
        .onDisappear {navigation.invalidate();state.conceal()}
        .confirmationDialog(text("confirm"),isPresented:Binding(get:{confirmation != nil},set:{if !$0 {confirmation=nil}}),titleVisibility:.visible) {
            if let saved=confirmation {
                Button(text(saved.decision=="APPROVE_EFFECT" ? "approve":"request")) {confirmation=nil;Task {await state.decide(concept,source:source,decision:saved.decision,reason:saved.reason,expectedSelection:saved.selection,current:current)}}.accessibilityIdentifier("genesis-confirm-effect")
            }
            Button(text("cancel"),role:.cancel) {confirmation=nil}
        } message:{Text(text("boundary")+"\n"+(confirmation?.targetLabel ?? "")+" · "+text("planRevision")+" "+String(confirmation?.revision ?? 0)+"\n"+(confirmation?.reason ?? ""))}
        .onExitCommand {if !state.expandedDocument.isEmpty {navigateDocument(state.expandedDocument)}}
    }
    @ViewBuilder private func plan(_ envelope:GenesisEnvelope)->some View {
        let value=envelope.result;let p=value.plan
        Divider()
        Text(text(value.effect_decision_currently_applicable && envelope.target_current ? "approved":value.effect_history.last?.decision=="REQUEST_CHANGES" ? "changed":value.effect_history.last?.decision=="APPROVE_EFFECT" ? "historical":"notApproved")).font(.headline).accessibilityIdentifier("genesis-plan-state")
        Text(verbatim:envelope.target_label).font(.headline).accessibilityIdentifier("genesis-frozen-target")
        Text(text("planRevision")+" "+String(p.plan_revision))
        if !envelope.target_current {Text(text("targetChanged")).foregroundStyle(.secondary)}
        Text(text("scope"));Text(verbatim:source.source_product.purpose).textSelection(.enabled)
        ForEach(p.original_content_decisions) {decision in Text(text(decision.role)+" · "+text(decision.decision=="APPROVE_CONTENT" ? "APPROVE_CONTENT":"request"))}
        ForEach(value.inapplicability_reasons,id:\.self) {Text(text($0)).foregroundStyle(.secondary)}
        if envelope.can_decide != true {Text(text("effectAccess")).foregroundStyle(.secondary)}
        DisclosureGroup(text("steps")) {
            ForEach(Array(p.effects.enumerated()),id:\.offset) {index,_ in Text(String(index+1)+". "+text("step"+String(index))).frame(maxWidth:.infinity,alignment:.leading)}
        }
        if !p.blocking_open_points.isEmpty {
            Text(text("requiredQuestions")).font(.headline)
            ForEach(Array(p.blocking_open_points.enumerated()),id:\.offset) {_,point in Text(verbatim:point).textSelection(.enabled)}
        }
        DisclosureGroup(text("questions")) {ForEach(Array(p.open_questions.filter{!p.blocking_open_points.contains($0)}.enumerated()),id:\.offset) {_,q in Text(verbatim:q).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
        Text(text("english")).font(.caption).foregroundStyle(.secondary)
        DisclosureGroup(text("documents"),isExpanded:Binding(get:{state.documentsVisible},set:{state.setDocumentsVisible($0)})) {
            ForEach(p.documents.files) {file in
                VStack(alignment:.leading,spacing:8) {
                    ProposalCompareControl(title:file.path,focused:focused=="genesis-document-"+file.path) {navigateDocument(file.path)}
                        .focused($focused,equals:"genesis-document-"+file.path).disabled(state.busy || navigation.busy).padding(.top,16).id("genesis-document-"+file.path).accessibilityIdentifier("genesis-document-"+file.path)
                    if state.expandedDocument==file.path {
                        VStack(alignment:.leading,spacing:8) {
                            ProposalCompareControl(title:text("closeDocument"),focused:focused=="genesis-detail-"+file.path) {navigateDocument(file.path)}.focused($focused,equals:"genesis-detail-"+file.path).disabled(state.busy || navigation.busy).padding(.top,16).accessibilityIdentifier("genesis-detail-"+file.path)
                            Text(verbatim:file.content).font(.system(.body,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
                        }.id("genesis-detail-"+file.path)
                    }
                }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
            }
        }
        .accessibilityLabel(text("documents")).accessibilityIdentifier("genesis-documents")
        TextField(text("reason"),text:Binding(get:{state.reason},set:{state.updateReason($0)}),axis:.vertical).lineLimit(2...6).accessibilityIdentifier("genesis-reason").disabled(state.busy || state.pending != nil)
        ProposalCompareControl(title:text("approve")) {confirm("APPROVE_EFFECT")}.disabled(!canDecide || envelope.can_approve != true || target != envelope.target_id).accessibilityIdentifier("genesis-approve")
        ProposalCompareControl(title:text("request")) {confirm("REQUEST_CHANGES")}.disabled(!canDecide).accessibilityIdentifier("genesis-request-changes")
        DisclosureGroup(text("decisions")) {
            ForEach(value.effect_history) {d in
                VStack(alignment:.leading) {Text(text(d.decision=="APPROVE_EFFECT" ? "approve":"request"));Text(verbatim:d.reason).textSelection(.enabled);Text(text("decisionRevision")+" "+String(d.decision_revision));Text(verbatim:d.occurred_at).font(.caption);DisclosureGroup(text("source")) {Text(verbatim:d.human_binding.operator_id);Text(verbatim:d.decision_id)}}
            }
        }
        DisclosureGroup(text("source")) {
            Text(verbatim:p.plan_id);Text(verbatim:p.plan_digest);Text(verbatim:p.documents.identity.project_id);Text(verbatim:p.documents.identity.repository_id)
            Text(verbatim:p.target.ep_instance_id+" / "+p.target.placement_ref+" / "+p.target.target_ref)
            Text(verbatim:envelope.producer_source);Text(verbatim:p.expires_at)
        }.font(.caption).textSelection(.enabled)
    }
    private func confirm(_ decision:String) {
        guard canDecide,let selection=state.result?.selection_digest else {return}
        guard let envelope=state.result,decision != "APPROVE_EFFECT" || (envelope.can_approve==true && target==envelope.target_id) else {return}
        confirmation=Confirmation(decision:decision,reason:state.reason,selection:selection,targetLabel:envelope.target_label,revision:envelope.result.plan.plan_revision)
    }
    private func restoreDocument() async {
        guard !state.busy,let envelope=state.result else {return}
        let key=identity+"/"+String(state.generation)+"/"+envelope.result.plan.plan_digest
        guard key != restoredPresentation else {return}
        restoredPresentation=key
        guard state.documentsVisible,!state.expandedDocument.isEmpty else {return}
        let restored=await navigation.navigate(state.expandedDocument,restoring:true,state:state,concept:concept,source:source,current:current,focus:{focused=$0},reveal:reveal)
        if !restored && restoredPresentation==key {restoredPresentation=""}
    }
    private func navigateDocument(_ path:String) {
        Task {await navigation.navigate(path,state:state,concept:concept,source:source,current:current,focus:{focused=$0},reveal:reveal)}
    }
}
