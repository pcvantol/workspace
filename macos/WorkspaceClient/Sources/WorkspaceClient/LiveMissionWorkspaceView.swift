import SwiftUI

// Presentation selection only; it carries no grant or planning authority.
@MainActor final class MissionWorkspaceSelection: ObservableObject {
    @Published var conversationID:String?
    @Published var newDraft=false
    @Published var ownConversationID:String?
    @Published var sceneID=0
}

struct LiveMissionWorkspaceView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var conversations: ConversationState
    @ObservedObject var state: MissionConceptState
    @Environment(\.locale) private var locale
    @ObservedObject private var selection:MissionWorkspaceSelection
    private var activeConversationID:String? {
        get { selection.conversationID }
        nonmutating set { selection.conversationID=newValue }
    }
    init(client:ClientState,conversations:ConversationState) {
        self.client=client;self.conversations=conversations;self.state=conversations.missionConcepts;self.selection=conversations.missionSelection
    }
    private var scope:[String] { [client.savedEndpoint,client.savedInstance,client.phase,conversations.projectID,conversations.observedActorID ?? ""] }
    private func copy(_ key:String)->String { MissionWorkspaceCopy.text(key,language:locale.language.languageCode?.identifier ?? "en") }
    private var projectName:String {
        guard let snapshot=client.snapshot,case .success(let projects)=snapshot.projects,!projects.stale else { return "" }
        return projects.projects.first(where: { $0.id==conversations.projectID })?.name ?? ""
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if state.phase != "current" {
                Text(copy(state.phase)).foregroundStyle(.secondary).padding(.horizontal,20)
            }
            HStack {
                Button(copy("newMission")) { beginNewMission() }
                    .disabled(state.busy || state.pending != nil || state.capability?.workspace_reference_resolution_supported != true || conversations.dirty)
                    .accessibilityIdentifier("mission.new")
                Button(copy("refresh")) { Task { await refresh() } }.disabled(state.busy)
                if state.pending != nil {
                    Button(copy("resume")) { Task { await resume() } }.disabled(state.busy)
                }
                if state.busy { ProgressView().controlSize(.small) }
            }.padding(.horizontal,20)
            MissionWorkspaceView(observation:presentation,

                canRefine:state.capability != nil && !state.busy && state.pending == nil,canApprove:!selection.newDraft && state.packet?.packageData != nil && !state.busy && state.pending == nil && state.approval?.state != "COMPLETE",
                selectedID:selection.newDraft ? nil:state.items.first(where: { $0.conversation_id==activeConversationID })?.object_id,
                onRefine:{ text,lens,card in Task { await refine(text,lens:lens,card:card) } },
                onApprove:{ card in Task { await state.approve(card,connection:await connection()) } },
                onSelect:{ card in Task { await prepare(card) } }).id(selection.sceneID)
        }
        .onChange(of:[client.savedEndpoint,client.savedInstance,conversations.projectID,conversations.observedActorID ?? ""]) { _, _ in
            activeConversationID=nil;selection.ownConversationID=nil;state.invalidate()
        }
        .task(id:scope) { await refresh() }
    }
    private var presentation:MissionWorkspaceObservation? {
        guard let shown=state.presentation(project:projectName) else { return nil }
        guard selection.newDraft else { return shown }
        return .init(scopeKey:shown.scopeKey+"-new",project:shown.project,cards:shown.cards,relations:shown.relations,complete:shown.complete,transcript:[])
    }
    func beginNewMission() {
        guard !state.busy,state.pending==nil,state.capability?.workspace_reference_resolution_supported==true,!conversations.dirty else { return }
        selection.newDraft=true;selection.ownConversationID=nil;activeConversationID=nil;selection.sceneID &+= 1
    }
    func connection() async -> AdvisoryConnection? {
        guard let own=await conversations.missionWorkspaceConnection(client:client) else { return nil }
        if let activeConversationID { return state.producerConnection(own,id:activeConversationID) }
        if own.conversationID.isEmpty { return state.producerConnection(own) }
        if let existing=state.producerConnection(own,id:own.conversationID) { return existing }
        return await state.resolveWorkspace(own)
    }
    func refresh() async {
        guard client.phase=="CONNECTED" else { activeConversationID=nil;selection.ownConversationID=nil;selection.newDraft=false;state.invalidate();return }
        await conversations.prepare(client:client)
        await state.refresh(await connection())
    }
    func resume() async { await state.resume(await connection()) }
    func prepare(_ card:MissionDefinitionCard) async {
        guard let item=state.items.first(where: { $0.object_id==card.id && $0.revision==card.revision }),
              let own=await conversations.missionWorkspaceConnection(client:client),state.producerConnection(own,id:item.conversation_id) != nil else { return }
        selection.newDraft=false
        activeConversationID=item.conversation_id
        let c=await connection()
        await state.refresh(c)
        guard state.items.contains(where: { $0.object_id==card.id && $0.revision==card.revision }) else { return }
        await state.prepare(card,connection:c)
    }
    func refine(_ text:String,lens:String,card:MissionDefinitionCard?) async {
        guard state.canRefine(text,lens:lens) else { return }
        if selection.newDraft || card==nil && state.capability?.workspace_reference_resolution_supported==true {
            let original=[client.savedEndpoint,client.savedInstance,conversations.projectID,conversations.observedActorID ?? ""]
            if selection.ownConversationID==nil {
                guard !conversations.dirty else { return }
                conversations.newDraft()
                guard conversations.selectedID==nil else { return }
                conversations.title=String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(120))
                conversations.focus=String(text.prefix(240));conversations.draft=text;conversations.mode=lens
                await conversations.save(client:client)
                guard !conversations.dirty,let selected=conversations.selectedConversation,
                      original==[client.savedEndpoint,client.savedInstance,conversations.projectID,conversations.observedActorID ?? ""] else { return }
                selection.ownConversationID=selected.id
            }
            guard let own=await conversations.missionWorkspaceConnection(client:client),own.conversationID==selection.ownConversationID,
                  let source=await state.resolveWorkspace(own) else { return }
            activeConversationID=source.conversationID
            await state.refresh(source)
            await state.refine(text,lens:lens,connection:source)
            if state.pending==nil,!state.history.isEmpty { selection.newDraft=false;selection.sceneID &+= 1 }
            return
        }
        if let card {
            guard let item=state.items.first(where: { $0.object_id==card.id && $0.revision==card.revision }),
                  let own=await conversations.missionWorkspaceConnection(client:client),state.producerConnection(own,id:item.conversation_id) != nil else { return }
            activeConversationID=item.conversation_id
            await state.refresh(await connection())
            guard state.items.contains(where: { $0.object_id==card.id && $0.revision==card.revision }) else { return }
        }
        await state.refine(text,lens:lens,connection:await connection())
    }
}

struct MissionSetupView:View {
    @ObservedObject var client:ClientState
    @ObservedObject var conversations:ConversationState
    @ObservedObject var state:MissionConceptState
    @State private var grant=""
    @Environment(\.locale) private var locale
    private func copy(_ key:String)->String { MissionWorkspaceCopy.text(key,language:locale.language.languageCode?.identifier ?? "en") }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(copy("setupOnce")).font(.caption).foregroundStyle(.secondary)
            SecureField(copy("setupAccess"),text:$grant).accessibilityIdentifier("mission.setup-access")
            Button(copy("setupSave")) {
                let entered=grant;grant=""
                Task { await save(entered) }
            }.disabled(state.busy || state.pending != nil || grant.isEmpty || client.phase != "CONNECTED")
                .accessibilityIdentifier("mission.setup-save")
            Text(copy(state.phase)).font(.caption).foregroundStyle(.secondary)
        }
    }
    func save(_ entered:String) async {
        await conversations.prepare(client:client)
        await state.saveGrant(entered,workspace:await conversations.missionWorkspaceConnection(client:client))
    }

}
