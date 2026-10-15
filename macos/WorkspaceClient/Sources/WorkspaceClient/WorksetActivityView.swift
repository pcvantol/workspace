import SwiftUI

struct WorksetActivityView: View {
    @ObservedObject var state:ActivityState
    @ObservedObject var client:ClientState
    @ObservedObject var execution:ExecutionProgressState
    init(state:ActivityState,client:ClientState,grants:any DraftGrantStore,execution:ExecutionProgressState=ExecutionProgressState()) {self.state=state;self.client=client;self.grants=grants;self.execution=execution}
    let grants:any DraftGrantStore
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scene
    @State private var token=""
    @State private var visible=false
    private var language:String { locale.language.languageCode?.identifier ?? "en" }
    private func text(_ key:String) -> String { ActivityCopy.text(key,language) }
    private func connection() async -> AdvisoryConnection? {
        guard client.phase=="CONNECTED",!client.authorizationLost,
            let access=try? await Task.detached { try grants.load() }.value,
            access.endpoint==client.savedEndpoint,access.instanceID==client.savedInstance,
            let bearer=try? await client.draftReadToken() else { return nil }
        guard let observed=try? await ConversationTransport().list(endpoint:ServerEndpoint(access.endpoint),readToken:bearer,access:access),
            client.phase=="CONNECTED",!client.authorizationLost,
            access.endpoint==client.savedEndpoint,access.instanceID==client.savedInstance,
            (try? await Task.detached { try grants.load() }.value)==access else { return nil }
        return AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.instanceID,actorID:observed.actor_id,
            workspaceProjectID:access.projectID,conversationID:"",bearer:bearer,draftGrant:access.token)
    }
    @ViewBuilder private var activityActions:some View {
        Button(text("refresh")) { Task { if state.selected.isEmpty { await state.connect(await connection()) } else { await state.fetch(restart:true) } } }.disabled(state.busy)
        if state.access != nil { Button(text("forget")) { state.forget() } }
        if state.busy { ProgressView().controlSize(.small) }
    }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text(text("title")).font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.75)
                ViewThatFits(in:.horizontal) {
                    HStack { activityActions }
                    VStack(alignment:.leading) { activityActions }
                }
                Text(text(state.status)).foregroundStyle(.secondary).accessibilityIdentifier("activity.status")
                if state.access == nil {
                    HStack {
                        SecureField(text("grant"),text:$token)
                        Button(text("pair")) { let value=token;token="";Task { await state.connect(await connection(),token:value) } }.disabled(token.isEmpty || state.busy)
                    }
                }
                if let access=state.access {
                    VStack(alignment:.leading,spacing:6) {
                        Text(text("workset")).font(.caption).foregroundStyle(.secondary)
                        Picker(text("workset"),selection:Binding(get:{state.selected},set:{value in Task { await state.choose(value) }})) {
                            Text(text("choose")).tag("")
                            ForEach(Array(access.worksets.enumerated()),id:\.element.workset_id) { index,subject in
                                Text(text("workset")+" "+String(index+1)).tag(subject.workset_id)
                            }
                        }.labelsHidden().disabled(state.busy).accessibilityLabel(text("workset")).accessibilityIdentifier("activity.workset")
                    }
                    DisclosureGroup {
                        VStack(alignment:.leading,spacing:6) {
                            Text("Forge 2.15.0").font(.caption)
                            Text([access.scope.instance_id,access.scope.project_id,access.scope.repository_id].joined(separator:" · ")).font(.caption).textSelection(.enabled)
                            ForEach(Array(access.worksets.enumerated()),id:\.element.workset_id) { index,subject in
                                VStack(alignment:.leading) {
                                    Text(text("workset")+" "+String(index+1)).font(.caption.bold())
                                    Text(subject.workset_id).font(.caption).textSelection(.enabled)
                                }
                            }
                            DisclosureGroup(text("technical")) { Text(ActivityWire.pin).font(.caption).textSelection(.enabled) }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    } label: {
                        Text(text("sourceContext")).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    }
                }
                if let access=state.access,!state.selected.isEmpty,!state.historical {
                    ExecutionProgressView(state:execution,access:access,workset:state.selected,missions:state.pages.last?.current ?? [],connection:{await connection()})
                }
                if !state.pages.isEmpty {
                    if let page=state.pages.last {
                        VStack(alignment:.leading,spacing:5) {
                            Text(text("coverage")).font(.headline)
                            Text(text(page.offered)).font(.caption)
                            Text(text("partial")).font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(page.limitations.enumerated()),id:\.offset) { _,limit in
                                Text(ActivityCopy.limitation(limit,language)).font(.caption).foregroundStyle(.secondary)
                            }
                            DisclosureGroup(text("technical")) {
                                Text(([page.offered]+page.limitations).joined(separator:"\n")).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                    if state.historical { Text(text("historical")).foregroundStyle(.orange) }
                    else {
                        GroupBox(text("current")) {
                            VStack(alignment:.leading,spacing:8) {
                                ForEach(state.pages.last?.current ?? []) { item in
                                    VStack(alignment:.leading) {
                                        Text(item.title).font(.headline)
                                        Text(text("execution")+": "+ActivityCopy.state(item.execution_state,language)).font(.subheadline)
                                        if !item.blocking_reasons.isEmpty {
                                            Text(text("blocked")).foregroundStyle(.orange)
                                            ForEach(item.blocking_reasons,id:\.self) { reason in Text(MissionWorkspaceCopy.blocker(reason,language:language)).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        ForEach([(text("approved"),item.approved),(text("released"),item.released),(text("active"),item.active),(text("completed"),item.completed)],id:\.0) { label,value in
                                            Text(label+": "+text(value ? "yes":"no")).font(.caption)
                                        }
                                        ForEach([(text("execution"),item.execution_state),(text("engineering"),item.engineering_result),(text("review"),item.review_state),(text("acceptance"),item.final_acceptance)],id:\.0) { label,value in
                                            Text(label+": "+ActivityCopy.state(value,language)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        DisclosureGroup(text("technical")) { Text([item.execution_state,item.engineering_result,item.review_state,item.final_acceptance].joined(separator:" · ")).font(.caption).textSelection(.enabled) }
                                    }.frame(maxWidth:.infinity,alignment:.leading)
                                }
                                Text(text("CURRENT_READBACK")+" "+(state.pages.last?.observedAt ?? "")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(text(state.complete && state.journal.comparisonKnown ? (state.newIDs.isEmpty ? "unchanged":"new"):"unknown"))
                    Text(text("history")).font(.title2.bold())
                    Text(text("orderNotice")).font(.caption).foregroundStyle(.secondary)
                    ForEach(state.events) { event in
                        VStack(alignment:.leading,spacing:5) {
                            HStack(alignment:.top) {
                                Text(text(event.fact)).font(.headline)
                                if state.newIDs.contains(event.id) { Image(systemName:"circle.fill").foregroundStyle(.tint).accessibilityLabel(text("new")) }
                            }
                            Text(event.subject)
                            Text(text(event.kind=="INTENT" ? "intent":event.kind=="DECISION" ? "decision":"fact")+" · "+(event.occurredAt ?? text("timeUnknown"))).font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup(text("source")) {
                                VStack(alignment:.leading,spacing:6) {
                                    Text(event.summary).textSelection(.enabled)
                                    Button(text("open")) { Task { await state.open(event.id) } }.disabled(state.busy)
                                    if state.detail?.id == event.id { Text(state.detail?.summary ?? "").textSelection(.enabled) }
                                    DisclosureGroup(text("technical")) {
                                        Text([event.sourceKind,event.sourceRecord,event.sourceRevision,event.sourceDigest,event.sourceURL].joined(separator:"\n")).font(.caption).textSelection(.enabled)
                                    }
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }.accessibilityIdentifier("activity.source."+event.id)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(.quaternary,in:RoundedRectangle(cornerRadius:12))
                    }
                    if state.pages.last?.hasMore == true && !state.historical { Button(text("next")) { Task { await state.fetch() } }.disabled(state.busy) }
                    if state.status=="resync" { Button(text("refresh")) { Task { await state.fetch(restart:true) } }.disabled(state.busy) }
                    Button(text("remember")) { Task { await state.rememberDisplayed(visible:visible && scene == .active) } }.disabled(!state.complete || state.busy)
                }
            }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
        }
        .task { visible=true;await state.reauthorize(await connection()) }
        .onDisappear { visible=false;execution.hide() }
        .onChange(of:client.phase) { _,phase in if phase != "CONNECTED" { state.invalidate();execution.reset() } }
        .onChange(of:client.savedEndpoint) { _,_ in state.invalidate();execution.reset() }
        .onChange(of:client.savedInstance) { _,_ in state.invalidate();execution.reset() }
    }
}
