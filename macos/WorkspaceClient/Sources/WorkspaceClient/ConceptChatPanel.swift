import SwiftUI

struct ConceptChatPanel:View {
    @ObservedObject var state:ConceptChatState
    let concept:ProjectConcept
    let dirty:Bool
    let current:@MainActor () async throws -> ConceptConnection
    let adopted:@MainActor () async -> Void
    @Environment(\.locale) private var locale
    private var language:String {let value=locale.language.languageCode?.identifier ?? "en";return ConceptChatCopy.languages.contains(value) ? value:"en"}
    private func text(_ key:String)->String {ConceptChatCopy.text(key,language)}
    private var access:ConceptChatAccess? {
        guard let cap=state.access else{return nil}
        let model=cap.provider.model=="SESSION_CONFIGURED_NOT_REPORTED" ? text("notKnown"):cap.provider.model
        let profile=[model,cap.provider.profile].compactMap{$0}.joined(separator:" · ")
        let limits=String(cap.maximum_turns)+" "+text("turnsLimit")+" · "+String(cap.maximum_tokens)+" "+text("tokensLimit")+" · "+String(cap.maximum_seconds)+" "+text("secondsLimit")
        return ConceptChatAccess(profile:profile,recipient:text("externalSession"),limits:limits,maySubmit:cap.can_advise,dataCategories:cap.provider.data_transfer)
    }
    private var proposal:ConceptChatProposal? {
        guard let reply=state.reply,let value=reply.proposal else{return nil}
        return ConceptChatProposal(reference:value.result_reference,sourceRevision:reply.source_revision,changes:value.changes.map{ConceptChatChange(field:$0.field,before:$0.before.display,after:$0.after.display,reason:$0.reason)})
    }
    var body:some View {
            ConceptChatView(concept:concept,dirty:dirty,access:access,briefingFields:state.briefing,turns:state.turns.map(\.display),proposal:proposal,supplement:AnyView(controls),submissionHeld:state.pending != nil,busy:state.busy,
                onSend:{role,message in Task {await state.send(role:role,message:message,language:language,concept:concept,current:current)}},
                onAccept:state.reply?.proposal?.adoptable==true && state.pending==nil ? {_ in Task {await state.adopt(concept,current:current)}}:nil)
        .task(id:concept) {await state.load(concept,current:current)}
        .onChange(of:state.phase) {_,value in if value=="adopted" {Task {await adopted()}}}
        .onDisappear {state.conceal()}
    }
    private var controls:some View {
        VStack(alignment:.leading,spacing:12) {
            if state.busy {ProgressView()}
            if state.pending != nil {
                Text(text("pending")).foregroundStyle(.secondary)
                Button(text("resume")) {Task {await state.resume(concept,current:current)}}.disabled(state.busy || dirty).accessibilityIdentifier("concept-chat-resume")
            }
            if state.phase=="inputRejected",state.pending?.command != nil {
                Button(text("retireRejected")) {Task {await state.retireRejected(concept,current:current)}}.disabled(state.busy || dirty).accessibilityIdentifier("concept-chat-retire-rejected")
            }
            if state.reply?.proposal?.adoptable==false {Text(text("editRequired")).foregroundStyle(.secondary)}
            if ["unavailable","invalid","inputRejected","conflict","capacity"].contains(state.phase) {Text(text(state.phase)).foregroundStyle(.secondary).accessibilityIdentifier("concept-chat-status")}
            Button(text("refresh")) {Task {await state.load(concept,current:current)}}.disabled(state.busy).accessibilityIdentifier("concept-chat-refresh")
            ForEach(Array(state.turns.enumerated()),id:\.element.request.turn_id) {index,turn in
                Button(text("reopen")+" · "+(turn.request.advisor_kind=="BUSINESS" ? "Business":"Architect")+" "+String(index+1)+" · "+String(turn.request.message.prefix(50))) {Task {await state.open(turn.request.operation_id,concept:concept,current:current)}}
                    .disabled(state.busy).accessibilityIdentifier("concept-chat-reopen-"+turn.request.operation_id)
            }
        }
    }
}
