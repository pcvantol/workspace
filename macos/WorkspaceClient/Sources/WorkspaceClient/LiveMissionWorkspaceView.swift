import SwiftUI

struct LiveMissionWorkspaceView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var conversations: ConversationState
    @ObservedObject var state: MissionConceptState
    @Environment(\.locale) private var locale
    @State private var activeConversationID:String?
    init(client:ClientState,conversations:ConversationState) {
        self.client=client;self.conversations=conversations;self.state=conversations.missionConcepts
    }
    private var scope:[String] { [client.savedEndpoint,client.savedInstance,client.phase,conversations.projectID,conversations.selectedConversation?.actor_id ?? ""] }
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
                Button(copy("refresh")) { Task { await refresh() } }.disabled(state.busy)
                if state.pending != nil {
                    Button(copy("resume")) { Task { await state.resume(await connection()) } }.disabled(state.busy)
                }
                if state.busy { ProgressView().controlSize(.small) }
            }.padding(.horizontal,20)
            MissionWorkspaceView(observation:state.presentation(project:projectName),
                canRefine:state.capability != nil && !state.busy && state.pending == nil,canApprove:state.packet?.packageData != nil && !state.busy && state.pending == nil && state.approval?.state != "COMPLETE",
                onRefine:{ text,lens,card in Task { await refine(text,lens:lens,card:card) } },
                onApprove:{ card in Task { await state.approve(card,connection:await connection()) } },
                onSelect:{ card in Task { await prepare(card) } })
        }
        .onChange(of:[client.savedEndpoint,client.savedInstance,conversations.projectID,conversations.selectedConversation?.actor_id ?? ""]) { _, _ in
            activeConversationID=nil;state.invalidate()
        }
        .task(id:scope) { await refresh() }
    }
    func connection() async -> AdvisoryConnection? {
        guard let base=await conversations.advisoryConnection(client:client) else { return nil }
        guard let activeConversationID else { return base }
        guard conversations.conversations.contains(where: { $0.id==activeConversationID && $0.actor_id==base.actorID }) else { return nil }
        return AdvisoryConnection(endpoint:base.endpoint,workspaceInstanceID:base.workspaceInstanceID,actorID:base.actorID,
            workspaceProjectID:base.workspaceProjectID,conversationID:activeConversationID,bearer:base.bearer,draftGrant:base.draftGrant)
    }
    func refresh() async {
        guard client.phase=="CONNECTED" else { state.invalidate();return }
        await conversations.prepare(client:client)
        await state.refresh(await connection())
    }
    func prepare(_ card:MissionDefinitionCard) async {
        guard let item=state.items.first(where: { $0.object_id==card.id && $0.revision==card.revision }),
              conversations.conversations.contains(where: { $0.id==item.conversation_id }) else { return }
        activeConversationID=item.conversation_id
        let c=await connection()
        await state.refresh(c)
        guard state.items.contains(where: { $0.object_id==card.id && $0.revision==card.revision }) else { return }
        await state.prepare(card,connection:c)
    }
    func refine(_ text:String,lens:String,card:MissionDefinitionCard?) async {
        if let card {
            guard let item=state.items.first(where: { $0.object_id==card.id && $0.revision==card.revision }),
                  let conversation=conversations.conversations.first(where: { $0.id==item.conversation_id }) else { return }
            activeConversationID=conversation.id
            await state.refresh(await connection())
            guard state.items.contains(where: { $0.object_id==card.id && $0.revision==card.revision }) else { return }
        }
        await state.refine(text,lens:lens,connection:await connection())
    }
}
