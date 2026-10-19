import SwiftUI

struct GenesisView:View {
    @ObservedObject var state:GenesisState
    let concept:ProjectConcept;let source:ConceptBaselineResult;let dirty:Bool
    let current:@MainActor () async throws -> ConceptConnection
    let reveal:(String)->Void
    @Environment(\.locale) private var locale
    @State private var target=""
    @State private var reason=""
    @State private var document:String?
    @State private var confirmation:Confirmation?
    @FocusState private var focused:Focus?
    private struct Confirmation {let decision:String;let reason:String;let selection:String}
    private enum Focus:Hashable {case document(String),close}
    private var language:String {locale.language.languageCode?.identifier ?? "en"}
    private func text(_ key:String)->String {GenesisCopy.text(key,language)}
    private var identity:String {concept.id+"/"+String(concept.revision)+"/"+source.operation_id}
    private var canDecide:Bool {!dirty && !state.busy && state.pending==nil && state.result?.can_decide==true && !reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && reason.unicodeScalars.count<=2000}
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(text("title")).font(.title3.bold())
            Text(text("boundary")).foregroundStyle(.secondary)
            if let access=state.access {
                Text(text("content")).font(.headline)
                Text(text(access.content.state=="CONTENT_APPROVED" ? "CONTENT_APPROVED":"contentMissing"))
                if access.targets.isEmpty {Text(text("noTargets")).foregroundStyle(.secondary)}
                else {
                    Picker(text("target"),selection:$target) {
                        ForEach(access.targets) {t in Text(verbatim:t.label).tag(t.id)}
                    }.accessibilityIdentifier("genesis-target").disabled(state.busy || state.pending != nil)
                    Button(text("prepare")) {confirmation=nil;Task {await state.prepare(concept,source:source,target:target,current:current)}}
                        .disabled(dirty || state.busy || state.pending != nil || !access.can_plan || access.content.state != "CONTENT_APPROVED" || !access.targets.contains(where:{$0.id==target}))
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
            Button(text("refresh")) {confirmation=nil;Task {await state.load(concept,source:source,current:current)}}.disabled(state.busy).accessibilityIdentifier("genesis-refresh")
            if state.pending != nil {
                Text(text("pending"))
                Button(text("resume")) {Task {await state.resume(concept,source:source,current:current)}}.disabled(state.busy).accessibilityIdentifier("genesis-recover-original")
            }
            if let envelope=state.result {plan(envelope)}
        }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
        .task(id:identity) {target="";document=nil;confirmation=nil;await state.load(concept,source:source,current:current);if target.isEmpty {target=state.access?.targets.first?.id ?? ""}}
        .onChange(of:dirty) {_,changed in if changed {confirmation=nil}}
        .onChange(of:state.result?.selection_digest) {_,_ in confirmation=nil}
        .onChange(of:target) {old,new in if old != new {confirmation=nil}}
        .onDisappear {state.conceal()}
        .confirmationDialog(text("confirm"),isPresented:Binding(get:{confirmation != nil},set:{if !$0 {confirmation=nil}}),titleVisibility:.visible) {
            if let saved=confirmation {
                Button(text(saved.decision=="APPROVE_EFFECT" ? "approve":"request")) {confirmation=nil;Task {await state.decide(concept,source:source,decision:saved.decision,reason:saved.reason,expectedSelection:saved.selection,current:current)}}.accessibilityIdentifier("genesis-confirm-effect")
            }
            Button(text("cancel"),role:.cancel) {confirmation=nil}
        } message:{Text(text("boundary")+"\n"+(confirmation?.reason ?? ""))}
        .onExitCommand {if let path=document {closeDocument(path)}}
    }
    @ViewBuilder private func plan(_ envelope:GenesisEnvelope)->some View {
        let value=envelope.result;let p=value.plan
        Divider()
        Text(text(value.effect_decision_currently_applicable ? "approved":value.effect_history.last?.decision=="REQUEST_CHANGES" ? "changed":value.effect_history.last?.decision=="APPROVE_EFFECT" ? "historical":"notApproved")).font(.headline).accessibilityIdentifier("genesis-plan-state")
        Text(text("scope"));Text(verbatim:source.source_product.purpose).textSelection(.enabled)
        ForEach(p.original_content_decisions) {decision in Text(text(decision.role)+" · "+text(decision.decision=="APPROVE_CONTENT" ? "APPROVE_CONTENT":"request"))}
        ForEach(value.inapplicability_reasons,id:\.self) {Text(text($0)).foregroundStyle(.secondary)}
        if envelope.can_decide != true {Text(text("effectAccess")).foregroundStyle(.secondary)}
        DisclosureGroup(text("steps")) {
            ForEach(Array(p.effects.enumerated()),id:\.offset) {index,_ in Text(String(index+1)+". "+text("step"+String(index))).frame(maxWidth:.infinity,alignment:.leading)}
        }
        DisclosureGroup(text("questions")) {ForEach(Array(p.open_questions.enumerated()),id:\.offset) {_,q in Text(verbatim:q).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}
        Text(text("english")).font(.caption).foregroundStyle(.secondary)
        DisclosureGroup(text("documents")) {
            ForEach(p.documents.files) {file in
                VStack(alignment:.leading,spacing:8) {
                    Button {document=file.path;Task {@MainActor in await Task.yield();focused = .close;reveal("genesis-document-detail")}} label:{Text(verbatim:file.path).lineLimit(3).multilineTextAlignment(.leading)}
                        .focused($focused,equals:.document(file.path)).accessibilityIdentifier("genesis-document-"+file.path)
                    if document==file.path {
                        VStack(alignment:.leading,spacing:8) {
                            Button(text("closeDocument")) {closeDocument(file.path)}.focused($focused,equals:.close).accessibilityIdentifier("genesis-document-close")
                            Text(verbatim:file.content).font(.system(.body,design:.monospaced)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true).frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
                        }.id("genesis-document-detail")
                    }
                }.frame(minWidth:0,maxWidth:.infinity,alignment:.leading)
            }
        }
        TextField(text("reason"),text:$reason,axis:.vertical).lineLimit(2...6).accessibilityIdentifier("genesis-reason").disabled(state.busy || state.pending != nil)
        Button(text("approve")) {confirm("APPROVE_EFFECT")}.disabled(!canDecide || !value.effect_decision_eligible).accessibilityIdentifier("genesis-approve")
        Button(text("request")) {confirm("REQUEST_CHANGES")}.disabled(!canDecide).accessibilityIdentifier("genesis-request-changes")
        DisclosureGroup(text("decisions")) {
            ForEach(value.effect_history) {d in
                VStack(alignment:.leading) {Text(text(d.decision=="APPROVE_EFFECT" ? "approve":"request"));Text(verbatim:d.reason).textSelection(.enabled);Text(verbatim:d.occurred_at).font(.caption)}
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
        confirmation=Confirmation(decision:decision,reason:reason,selection:selection)
    }
    private func closeDocument(_ path:String) {
        document=nil
        Task {@MainActor in await Task.yield();focused = .document(path);reveal("genesis-panel")}
    }
}
