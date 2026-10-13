import SwiftUI

struct WorksetOrderView: View {
    @ObservedObject var state:OrderState
    @ObservedObject var client:ClientState
    let grants:any DraftGrantStore
    var onApplied:(@MainActor (OrderAccess,String) async -> Void)? = nil
    @Environment(\.locale) private var locale
    @State private var token=""
    @State private var reason=""
    @FocusState private var reasonFocused:Bool
    private var language:String { locale.language.languageCode?.identifier ?? "en" }
    private func text(_ key:String) -> String { OrderCopy.text(key,language) }
    private func connection() async -> AdvisoryConnection? {
        guard client.phase=="CONNECTED",!client.authorizationLost,
            let access=try? await Task.detached { try grants.load() }.value,
            access.endpoint==client.savedEndpoint,access.instanceID==client.savedInstance,
            let bearer=try? await client.draftReadToken() else { return nil }
        guard let observed=try? await ConversationTransport().list(endpoint:ServerEndpoint(access.endpoint),readToken:bearer,access:access),
            client.phase=="CONNECTED",!client.authorizationLost,
            access.endpoint==client.savedEndpoint,access.instanceID==client.savedInstance,
            (try? await Task.detached { try grants.load() }.value)==access else { return nil }
        return AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.instanceID,actorID:observed.actor_id,workspaceProjectID:access.projectID,conversationID:"",bearer:bearer,draftGrant:access.token)
    }
    private func orderTitles(_ order:[String]) -> String { order.compactMap { id in state.current?.members.first(where:{$0.id==id})?.title }.joined(separator:" → ") }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text(text("title")).font(.largeTitle.bold()).minimumScaleFactor(0.75)
                HStack {
                    Button(text("refresh")) { Task { if state.access==nil { await state.connect(await connection()) } else { await state.refresh() } } }.disabled(state.busy)
                    if state.access != nil { Button(text("forget")) { state.forget() } }
                    if state.busy { ProgressView().controlSize(.small) }
                }
                Text(text(state.status)).foregroundStyle(.secondary).accessibilityIdentifier("order.status")
                if state.status=="rejected",let cause=state.rejectionCode {Text(text(cause)).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true)}
                if state.access==nil {
                    SecureField(text("grant"),text:$token)
                    Button(text("pair")) { let value=token;token="";Task { await state.connect(await connection(),token:value) } }.disabled(token.isEmpty || state.busy)
                }
                if let access=state.access {
                    Picker(text("choose"),selection:Binding(get:{state.selected},set:{value in reason="";Task { await state.choose(value) }})) {
                        Text(text("choose")).tag("")
                        ForEach(Array(access.binding.worksets.enumerated()),id:\.element.workset_id) { index,subject in Text((state.selected==subject.workset_id ? state.current?.members.first?.title : nil) ?? (text("choose")+" "+String(index+1))).tag(subject.workset_id) }
                    }.disabled(state.busy).accessibilityIdentifier("order.workset")
                    if let current=state.current {
                        Text(text("current")).font(.headline)
                        Text(current.members.map(\.title).joined(separator:" → ")).fixedSize(horizontal:false,vertical:true)
                        Text(text("proposed")).font(.headline)
                        ForEach(Array(state.proposed.enumerated()),id:\.element) { index,id in
                            if let member=current.members.first(where:{$0.id==id}) {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(String(index+1)+". "+member.title).font(.headline)
                                    Text(text(index<current.fixed ? "fixed":"moveable")).font(.caption).foregroundStyle(.secondary)
                                    if !member.dependencies.isEmpty {
                                        Text(text("dependencies")+": "+member.dependencies.compactMap { dependency in current.members.first(where:{$0.id==dependency})?.title }.joined(separator:" · ")).font(.caption)
                                    }
                                    HStack {
                                        Button(text("up")) { state.move(id,-1) }.disabled(index<=current.fixed || state.busy || state.intent != nil).accessibilityLabel(text("up")+": "+member.title)
                                        Button(text("down")) { state.move(id,1) }.disabled(index<current.fixed || index==state.proposed.count-1 || state.busy || state.intent != nil).accessibilityLabel(text("down")+": "+member.title)
                                    }
                                }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(.quaternary,in:RoundedRectangle(cornerRadius:10))
                            }
                        }
                        Button(text("preview")) { Task { await state.showPreview() } }.disabled(state.busy || state.intent != nil || state.proposed==current.order).accessibilityIdentifier("order.preview")
                    }
                    if let preview=state.preview {
                        GroupBox(text("preview")) {
                            VStack(alignment:.leading,spacing:10) {
                                Text(text("consequences")).fixedSize(horizontal:false,vertical:true)
                                Text(text("consequencesRoles")).font(.caption).fixedSize(horizontal:false,vertical:true)
                                ForEach(preview.blockers,id:\.self) { Text(text($0)).foregroundStyle(.orange) }
                                TextField(text("reason"),text:$reason).textFieldStyle(.roundedBorder).focused($reasonFocused)
                                Button(text("confirm")) { let value=reason;Task { await state.confirm(reason:value) } }.disabled(state.busy || !preview.supported || !preview.blockers.isEmpty || reason.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("order.confirm")
                                Button(text("cancel")) { reason="";state.cancel() }.disabled(state.busy)
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    if let result=state.result,let raw=try? OrderWire.object(result),let original=raw["original_request"] as? [String:Any],let package=original["package"] as? [String:Any] {
                        GroupBox(text("original")) {
                            VStack(alignment:.leading,spacing:8) {
                                Text(orderTitles(package["current_order"] as? [String] ?? []))
                                Text(text(raw["state"] as? String=="APPLIED" ? "appliedOrder":"proposed")+": "+orderTitles(package["proposed_order"] as? [String] ?? []))
                                let decisions=raw["canonical_decisions_observed"] as? [String:String] ?? [:]
                                Text(text(decisions["business"] == nil ? "businessPending":"businessRecorded"))
                                Text(text(decisions["architecture"] == nil ? "architecturePending":"architectureRecorded"))
                                Text(text(raw["state"] as? String=="APPLIED" ? "applied":"pendingExplanation"))
                            }.frame(maxWidth:.infinity,alignment:.leading)
                        }
                    }
                    if state.status=="applied" || state.status=="rejected" { Button(text("newProposal")) { reason="";state.newProposal() }.disabled(state.busy || state.current==nil) }
                    if state.intent != nil {
                        Button(text("recover")) { Task { await state.recover(replay:false) } }.disabled(state.busy)
                        if state.status != "applied" && state.status != "rejected" { Button(text("replay")) { Task { await state.recover(replay:true) } }.disabled(state.busy) }
                    }
                    DisclosureGroup(text("technical")) {
                        Text("Forge 2.15.0 · "+access.binding.scope.instance_id).font(.caption).textSelection(.enabled)
                        if let intent=state.intent { Text(intent.operation).font(.caption).textSelection(.enabled) }
                        if let result=state.result { Text(String(data:result,encoding:.utf8) ?? "").font(.caption).textSelection(.enabled) }
                    }
                }
            }.padding().frame(maxWidth:.infinity,alignment:.leading)
        }
        .task { state.authority={ await connection() };state.onApplied=onApplied;await state.connect(await connection()) }
        .onChange(of:state.preview?.digest) { _,digest in reason="";reasonFocused=digest != nil }
        .onChange(of:client.phase) { _,phase in
            if phase=="CONNECTED" { Task { await state.connect(await connection()) } }
        }
        .onDisappear { state.invalidate() }
    }
}
