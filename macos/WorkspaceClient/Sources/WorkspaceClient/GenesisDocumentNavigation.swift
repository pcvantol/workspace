import Foundation

// Same selection-bound presentation sequence as the qualified plan108 navigation:
// authorize/toggle, re-enable native controls, yield, clear focus, yield, focus/reveal.
@MainActor final class GenesisDocumentNavigation:ObservableObject {
    @Published private(set) var busy=false
    private var ticket=0
    func invalidate() {ticket+=1;busy=false}
    func navigate(_ path:String,state:GenesisState,concept:ProjectConcept,source:ConceptBaselineResult,current:@escaping @MainActor () async throws->ConceptConnection,focus:@MainActor (String?)->Void,reveal:@MainActor (String)->Void) async {
        guard !busy,!state.busy,let original=state.result else {return}
        ticket+=1;let request=ticket,generation=state.generation,digest=original.result.plan.plan_digest,operation=original.operation_id
        func valid()->Bool {
            guard request==ticket,generation==state.generation,!state.busy,let value=state.result,value.operation_id==operation,value.result.plan.plan_digest==digest,
                  value.actor_id==concept.actor_id,value.context_id==concept.context_id,value.concept_id==concept.id,value.source_operation_id==source.operation_id,
                  WorksetReleaseWire.date(value.expires_at).map({$0>Date()})==true else {return false}
            return true
        }
        guard valid() else {return}
        busy=true;defer {if ticket==request {busy=false}}
        await state.chooseDocument(path,concept:concept,source:source,current:current)
        guard valid(),state.expandedDocument.isEmpty || state.expandedDocument==path else {return}
        let expanded=state.expandedDocument,target=(expanded.isEmpty ? "genesis-document-":"genesis-detail-")+path
        busy=false;await Task.yield();guard valid(),state.expandedDocument==expanded else {return}
        focus(nil);await Task.yield();guard valid(),state.expandedDocument==expanded else {return}
        focus(target);reveal(target)
    }
}
