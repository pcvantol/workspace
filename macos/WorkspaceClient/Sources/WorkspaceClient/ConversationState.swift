import Combine
import Foundation

private actor DraftGrantWorker {
    let store: any DraftGrantStore
    init(_ store: any DraftGrantStore) { self.store = store }
    func load() throws -> DraftAccess? { try store.load() }
    func save(_ access: DraftAccess) throws { try store.save(access) }
    func forget() throws { try store.forget() }
}

private actor LocalDraftWorker {
    let store: any LocalDraftStore
    private var latest: [String: Int] = [:]
    init(_ store: any LocalDraftStore) { self.store = store }
    func load(_ key: String) throws -> LocalDraftSnapshot? { try store.load(scopeHash: key) }
    func save(_ snapshot: LocalDraftSnapshot, version: Int) throws {
        guard version >= latest[snapshot.scopeHash, default: -1] else { return }
        try store.save(snapshot)
        latest[snapshot.scopeHash] = version
    }
    func remove(_ key: String, version: Int) throws {
        guard version >= latest[key, default: -1] else { return }
        try store.remove(scopeHash: key)
        latest[key] = version
    }
}

@MainActor
final class ConversationState: ObservableObject {
    private struct PendingArchiveOperation: Equatable {
        let conversationID: String
        let archived: Bool
        let expectedRevision: Int
        let operationID: String
    }
    @Published var projectID = ""
    @Published var selectedID: String?
    @Published var title = ""
    @Published var focus = ""
    @Published var mode = "BUSINESS"
    @Published var draft = ""
    @Published var search = ""
    @Published var modeFilter: ConversationModeFilter = .all
    @Published var archiveFilter: ConversationArchiveFilter = .active
    @Published var sortOrder: ConversationSortOrder = .recentlyChanged
    @Published var grantEntry = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var state = "UNAVAILABLE"
    @Published private(set) var detail = "Connect a Workspace Server and enter a project draft grant."
    @Published private(set) var savedRevision: Int?
    @Published private(set) var savedFields: DraftFields?
    @Published private(set) var serverConflict: Conversation?
    @Published private(set) var isBusy = false
    @Published private(set) var loadingGrant = false
    @Published private(set) var preparingServerForget = false
    @Published private(set) var archiveConfirmation: Bool?

    let advisory: AdvisoryState
    let candidates: CandidateState
    let missionConcepts: MissionConceptState

    private let grants: DraftGrantWorker
    private let localDrafts: LocalDraftWorker
    private let transport: ConversationTransport
    private var access: DraftAccess?
    private var scopeEpoch = 0
    private var loadAttempt = 0
    private var requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var localTask: Task<Void, Never>?
    private var localVersion = 0
    private var creatingNewDraft = false
    private var authorizationSuspended = false
    private var pendingArchiveOperation: PendingArchiveOperation?

    init(grants: any DraftGrantStore = DraftGrantKeychain(),
         localDrafts: any LocalDraftStore = PrivateLocalDraftCache(),
         transport: ConversationTransport = ConversationTransport(),
         advisory: AdvisoryState? = nil,
         candidates: CandidateState? = nil,
         missionConcepts: MissionConceptState? = nil) {
        self.advisory = advisory ?? AdvisoryState()
        self.candidates = candidates ?? CandidateState()
        self.missionConcepts = missionConcepts ?? MissionConceptState()
        self.grants = DraftGrantWorker(grants)
        self.localDrafts = LocalDraftWorker(localDrafts)
        self.transport = transport
    }

    func advisoryConnection(client:ClientState) async -> AdvisoryConnection? {
        guard !authorizationSuspended, !preparingServerForget, let access, let selected=selectedConversation,
              access.projectID==projectID, access.endpoint==client.savedEndpoint, access.instanceID==client.savedInstance,
              client.phase=="CONNECTED", state != "UNAUTHORIZED" else { return nil }
        guard let token=try? await client.draftReadToken(), self.access==access, selectedID==selected.id else { return nil }
        return AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.instanceID,actorID:selected.actor_id,
            workspaceProjectID:projectID,conversationID:selected.id,bearer:token,draftGrant:access.token)
    }

    var visibleConversations: [Conversation] {
        ConversationDiscovery.visible(conversations, search: search, mode: modeFilter,
                                      archive: archiveFilter, sort: sortOrder)
    }

    var hasActiveDiscovery: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            modeFilter != .all || archiveFilter != .active || sortOrder != .recentlyChanged
    }

    var selectedIsHidden: Bool {
        guard let selectedID, conversations.contains(where: { $0.id == selectedID }) else { return false }
        return !visibleConversations.contains(where: { $0.id == selectedID })
    }

    var listMessageKey: String? {
        switch state {
        case "GRANT_REQUIRED", "UNAUTHORIZED": "forbidden"
        case "OFFLINE": "offline"
        case "STALE": "stale"
        case "AVAILABLE" where conversations.isEmpty: "noConversations"
        case "AVAILABLE" where visibleConversations.isEmpty && archiveFilter == .active &&
            conversations.allSatisfy(\.archived): "noActive"
        case "AVAILABLE" where visibleConversations.isEmpty && archiveFilter == .archived &&
            conversations.allSatisfy({ !$0.archived }): "noArchived"
        case "AVAILABLE" where visibleConversations.isEmpty: "noResults"
        default: nil
        }
    }

    func resetDiscovery() {
        search = ""
        modeFilter = .all
        archiveFilter = .active
        sortOrder = .recentlyChanged
    }

    var canEdit: Bool {
        access?.projectID == projectID && selectedConversation?.archived != true &&
            !authorizationSuspended && !isBusy && !loadingGrant
    }

    var canCreate: Bool {
        access?.projectID == projectID && !authorizationSuspended && !isBusy && !loadingGrant
    }

    var selectedConversation: Conversation? {
        guard let selectedID else { return nil }
        return conversations.first(where: { $0.id == selectedID })
    }

    var canChangeArchive: Bool {
        selectedConversation != nil && access?.projectID == projectID && !authorizationSuspended &&
            !isBusy && !loadingGrant && serverConflict == nil
    }

    var dirty: Bool {
        guard let savedFields else {
            return !title.isEmpty || !focus.isEmpty || mode != "BUSINESS" || !draft.isEmpty
        }
        return savedFields.title != title || savedFields.focus != focus ||
            savedFields.mode != mode || savedFields.draft != draft
    }

    func prepare(client: ClientState) async {
        guard !preparingServerForget, !loadingGrant, !isBusy else { return }
        let epoch = scopeEpoch
        loadingGrant = true
        defer { loadingGrant = false }
        do {
            let stored = try await grants.load()
            guard epoch == scopeEpoch else { return }
            if let stored, stored.endpoint == client.savedEndpoint,
               stored.instanceID == client.savedInstance {
                if (access != stored || projectID != stored.projectID) && dirty {
                    state = "PENDING"
                    detail = "Save or discard local changes before switching draft access."
                    return
                }
                if access != stored || projectID != stored.projectID { clearScope() }
                access = stored
                projectID = stored.projectID
                authorizationSuspended = false
                if await restoreLocal(stored) { await load(client: client) }
            } else {
                if dirty {
                    state = "PENDING"
                    detail = "Save or discard local changes before switching draft access."
                    return
                }
                clearScope()
                access = nil
                state = "GRANT_REQUIRED"
                detail = "Enter this project's separate draft grant."
            }
        } catch {
            guard epoch == scopeEpoch else { return }
            state = "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func saveGrant(client: ClientState) async {
        guard !loadingGrant, !isBusy else { return }
        let grant = grantEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard grant.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              !projectID.isEmpty, client.phase == "CONNECTED", !client.savedInstance.isEmpty else {
            state = "GRANT_REQUIRED"
            detail = "Select a project, connect the Server and enter its draft grant."
            return
        }
        let proposed = DraftAccess(endpoint: client.savedEndpoint, instanceID: client.savedInstance,
                                   projectID: projectID, token: grant)
        if access != proposed && dirty {
            state = "PENDING"
            detail = "Save or discard local changes before switching draft access."
            return
        }
        isBusy = true
        scopeEpoch += 1
        let epoch = scopeEpoch
        defer { isBusy = false }
        do {
            guard let snapshot = client.snapshot,
                  case .success(let catalogue) = snapshot.projects, !catalogue.stale,
                  catalogue.projects.contains(where: { $0.id == projectID }) else {
                state = "STALE"
                return
            }
            let endpoint = try ServerEndpoint(proposed.endpoint)
            let readToken = try await client.draftReadToken()
            guard epoch == scopeEpoch else { return }
            _ = try await transport.list(endpoint: endpoint, readToken: readToken, access: proposed)
            guard epoch == scopeEpoch else { return }
            guard proposed.projectID == projectID, !(access != proposed && dirty) else {
                state = "PENDING"
                detail = "Save or discard local changes before switching draft access."
                return
            }
            guard client.phase == "CONNECTED", proposed.endpoint == client.savedEndpoint,
                  proposed.instanceID == client.savedInstance else {
                state = "GRANT_REQUIRED"
                detail = "Reconnect and enter this project's draft grant."
                return
            }
            try await grants.save(proposed)
            guard epoch == scopeEpoch else { return }
            if access != proposed { clearScope() }
            access = proposed
            authorizationSuspended = false
            grantEntry = ""
            if await restoreLocal(proposed) { await load(client: client) }
        } catch {
            guard epoch == scopeEpoch else { return }
            state = [ConversationError.forbidden, .unauthorized].contains(error as? ConversationError ?? .unavailable) ?
                "UNAUTHORIZED" : "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func forgetGrant() {
        guard !loadingGrant, !isBusy else { return }
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before forgetting draft access."
            return
        }
        isBusy = true
        scopeEpoch += 1
        let epoch = scopeEpoch
        Task {
          defer { isBusy = false }
          do {
            if let access {
                localVersion += 1
                try await localDrafts.remove(PrivateLocalDraftCache.scopeHash(access), version: localVersion)
                guard epoch == scopeEpoch else { return }
            }
            try await grants.forget()
            guard epoch == scopeEpoch else { return }
            access = nil
            clearScope()
            state = "GRANT_REQUIRED"
            detail = "Draft grant removed from this Mac. Existing Server drafts remain."
          } catch {
            guard epoch == scopeEpoch else { return }
            state = "UNAVAILABLE"
            detail = error.localizedDescription
          }
        }
    }

    func selectProject(_ id: String) {
        guard !loadingGrant, !isBusy else { return }
        if id == projectID { return }
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before switching projects."
            return
        }
        clearScope()
        projectID = id
        if access?.projectID != id {
            state = "GRANT_REQUIRED"
            detail = "Enter this project's separate draft grant."
        }
    }

    func load(client: ClientState) async {
        guard !authorizationSuspended, let access, access.projectID == projectID,
              access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance else {
            state = "GRANT_REQUIRED"
            detail = "Enter this project's separate draft grant."
            return
        }
        let epoch = scopeEpoch
        loadAttempt += 1
        let attempt = loadAttempt
        guard client.phase == "CONNECTED" else {
            state = "OFFLINE"
            detail = "Server offline. The text in this window has not been submitted."
            return
        }
        if let snapshot = client.snapshot, case .success(let catalogue) = snapshot.projects,
           catalogue.stale {
            state = "STALE"
            detail = "Project source is stale; drafts are not opened until it is current."
            return
        }
        state = "LOADING"
        do {
            let endpoint = try ServerEndpoint(access.endpoint)
            let token = try await client.draftReadToken()
            guard epoch == scopeEpoch, attempt == loadAttempt, self.access == access,
                  projectID == access.projectID else { return }
            let list = try await transport.list(endpoint: endpoint, readToken: token, access: access)
            guard epoch == scopeEpoch, attempt == loadAttempt, self.access == access,
                  projectID == access.projectID else { return }
            conversations = list.conversations
            if let selectedID {
                guard let latest = conversations.first(where: { $0.id == selectedID }) else {
                    serverConflict = nil
                    if dirty {
                        state = "PENDING"
                        detail = "The selected draft is no longer in your authorized list. Local text is retained."
                    } else {
                        self.selectedID = nil
                        clearEditor()
                        state = "AVAILABLE"
                        detail = "The selected draft is no longer available. Choose another conversation."
                    }
                    return
                }
                if dirty && latest.revision != savedRevision {
                    serverConflict = latest
                    state = "CONFLICT"
                    detail = "Review the newer Server draft beside your local text before choosing a version."
                    return
                }
                if let pendingArchiveOperation,
                   pendingArchiveOperation.conversationID == latest.id,
                   pendingArchiveOperation.archived == latest.archived,
                   latest.revision >= pendingArchiveOperation.expectedRevision {
                    self.pendingArchiveOperation = nil
                }
                if !dirty { use(latest) }
            } else if !dirty, !creatingNewDraft, let first = conversations.first {
                use(first)
            }
            serverConflict = nil
            state = "AVAILABLE"
            detail = "Workspace drafts. Advisor history and replies are unavailable."
        } catch {
            guard epoch == scopeEpoch, attempt == loadAttempt, self.access == access else { return }
            state = [ConversationError.forbidden, .unauthorized].contains(error as? ConversationError ?? .unavailable) ?
                "UNAUTHORIZED" : "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func newDraft() {
        guard !loadingGrant, !isBusy else { return }
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before starting another conversation."
            return
        }
        selectedID = nil
        clearEditor()
        creatingNewDraft = true
        state = access?.projectID == projectID ? "AVAILABLE" : "GRANT_REQUIRED"
    }

    func select(_ conversation: Conversation) {
        guard !loadingGrant, !isBusy else { return }
        guard let current = conversations.first(where: {
            $0.id == conversation.id && $0.project_id == projectID
        }) else { return }
        if selectedID == conversation.id { return }
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard the current changes before opening another conversation."
            return
        }
        use(current)
    }

    func handleClientPhase(_ phase: String) async {
        guard ["DISCONNECTED", "UNAVAILABLE", "UNCONFIGURED"].contains(phase) else { return }
        loadAttempt += 1
        guard phase != "UNCONFIGURED" else {
            _ = await prepareForServerForget()
            return
        }
        guard access?.projectID == projectID else { return }
        state = "OFFLINE"
        detail = "Server offline. Local text and the last authorized list remain in this window."
    }

    func prepareForServerForget() async -> Bool {
        guard !preparingServerForget else { return false }
        if authorizationSuspended { return true }
        preparingServerForget = true
        defer { preparingServerForget = false }
        scopeEpoch += 1
        loadAttempt += 1
        let epoch = scopeEpoch
        let retainLocalText = dirty
        let priorConversations = conversations
        let priorSelectedID = selectedID
        let priorConflict = serverConflict
        let priorSavedRevision = savedRevision
        let priorSavedFields = savedFields
        let priorCreatingNewDraft = creatingNewDraft
        authorizationSuspended = true
        conversations = []
        selectedID = nil
        serverConflict = nil
        if retainLocalText {
            savedRevision = nil
            savedFields = nil
            creatingNewDraft = true
            guard await flushLocal() else {
                guard epoch == scopeEpoch else { return false }
                authorizationSuspended = false
                conversations = priorConversations
                selectedID = priorSelectedID
                serverConflict = priorConflict
                savedRevision = priorSavedRevision
                savedFields = priorSavedFields
                creatingNewDraft = priorCreatingNewDraft
                return false
            }
            guard epoch == scopeEpoch, authorizationSuspended else { return false }
        } else {
            creatingNewDraft = false
            clearEditor()
        }
        state = "GRANT_REQUIRED"
        detail = retainLocalText ?
            "Reconnect and enter this project's draft grant. Unsaved local text is retained." :
            "Reconnect and enter this project's draft grant."
        return true
    }

    func discardChanges() {
        guard !loadingGrant, !isBusy else { return }
        if let selectedID, let existing = conversations.first(where: { $0.id == selectedID }) {
            use(existing)
        } else {
            clearEditor()
        }
        state = authorizationSuspended ? "GRANT_REQUIRED" : "AVAILABLE"
        detail = "Unsaved changes discarded."
        persistLocal()
    }

    func requestArchive(_ archived: Bool, client: ClientState) async {
        guard canChangeArchive, let selectedConversation,
              selectedConversation.archived != archived else { return }
        if dirty {
            archiveConfirmation = archived
            state = "PENDING"
            detail = archived ?
                "Save or discard local changes before archiving this conversation." :
                "Save or discard local changes before restoring this conversation."
            return
        }
        await applyArchive(archived, client: client)
    }

    func cancelArchive() {
        archiveConfirmation = nil
        state = authorizationSuspended ? "GRANT_REQUIRED" : "AVAILABLE"
        detail = "Conversation was not changed. Local text remains open."
    }

    func discardAndContinueArchive(_ archived: Bool, client: ClientState) async {
        archiveConfirmation = nil
        // Keep local text until the Server transition commits. `use(result)` below is the
        // actual discard point; offline, denial, timeout and lost-response paths retain it.
        await applyArchive(archived, client: client)
    }

    func saveAndContinueArchive(_ archived: Bool, client: ClientState) async {
        archiveConfirmation = nil
        await save(client: client)
        guard !dirty, state == "AVAILABLE" else { return }
        await applyArchive(archived, client: client)
    }

    private func applyArchive(_ archived: Bool, client: ClientState) async {
        guard !loadingGrant, !isBusy, !authorizationSuspended,
              let access, access.projectID == projectID,
              access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance,
              let selectedConversation, selectedConversation.archived != archived else { return }
        guard client.phase == "CONNECTED" else {
            state = "OFFLINE"
            detail = "Server offline. The conversation and local text were not changed."
            return
        }
        let operation: PendingArchiveOperation
        if let pendingArchiveOperation,
           pendingArchiveOperation.conversationID == selectedConversation.id,
           pendingArchiveOperation.archived == archived,
           pendingArchiveOperation.expectedRevision == selectedConversation.revision {
            operation = pendingArchiveOperation
        } else {
            let command = ArchiveCommand.make(
                conversationID: selectedConversation.id, archived: archived,
                expectedRevision: selectedConversation.revision)
            operation = PendingArchiveOperation(
                conversationID: selectedConversation.id, archived: archived,
                expectedRevision: selectedConversation.revision,
                operationID: command.operation_id)
            pendingArchiveOperation = operation
        }
        isBusy = true
        scopeEpoch += 1
        let epoch = scopeEpoch
        defer { isBusy = false }
        state = "ARCHIVING"
        do {
            let endpoint = try ServerEndpoint(access.endpoint)
            let token = try await client.draftReadToken()
            guard epoch == scopeEpoch, self.access == access,
                  selectedID == operation.conversationID else { return }
            let result = try await transport.setArchived(
                endpoint: endpoint, readToken: token, access: access,
                id: operation.conversationID, archived: archived,
                command: ArchiveCommand(expected_revision: operation.expectedRevision,
                                        operation_id: operation.operationID))
            guard epoch == scopeEpoch, self.access == access,
                  selectedID == operation.conversationID else { return }
            conversations.removeAll(where: { $0.id == result.id })
            conversations.insert(result, at: 0)
            pendingArchiveOperation = nil
            if result.archived != archived {
                state = "STATUS_CONFLICT"
                detail = "Conversation status changed on the Server. Current status is shown; text was preserved."
                return
            }
            use(result)
            state = "AVAILABLE"
            detail = archived ?
                "Conversation archived. Its draft and identity remain available." :
                "Conversation restored. Continue editing the original draft."
        } catch {
            guard epoch == scopeEpoch, self.access == access else { return }
            if let reason = error as? ConversationError {
                if reason == .conflict {
                    pendingArchiveOperation = nil
                    state = "CONFLICT"
                    await load(client: client)
                    return
                }
                if reason == .unsupported { pendingArchiveOperation = nil }
                state = [.unauthorized, .forbidden].contains(reason) ? "UNAUTHORIZED" :
                    (reason == .unsupported ? "UNSUPPORTED" : "UNAVAILABLE")
            } else {
                state = "UNAVAILABLE"
            }
            detail = error.localizedDescription
        }
    }

    func keepLocalAfterReview() {
        guard !loadingGrant, !isBusy else { return }
        guard let latest = serverConflict, latest.id == selectedID,
              latest.project_id == projectID else { return }
        savedRevision = latest.revision
        savedFields = DraftFields(title: latest.title, focus: latest.focus,
                                  mode: latest.mode, draft: latest.draft,
                                  expected_revision: latest.revision, request_id: nil)
        serverConflict = nil
        state = "PENDING"
        detail = "Local text retained. Saving now replaces the reviewed Server draft."
        persistLocal()
    }

    func save(client: ClientState) async {
        guard !loadingGrant, !isBusy else { return }
        guard !authorizationSuspended else {
            state = "GRANT_REQUIRED"
            detail = "Reconnect and enter this project's draft grant. Unsaved local text is retained."
            return
        }
        guard serverConflict == nil else {
            state = "CONFLICT"
            return
        }
        guard let access, access.projectID == projectID,
              access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance else {
            state = "GRANT_REQUIRED"
            detail = "Enter this project's separate draft grant."
            return
        }
        if let selectedID, !conversations.contains(where: { $0.id == selectedID }) {
            state = "PENDING"
            detail = "The selected draft is no longer in your authorized list. Keep the local text or discard it."
            return
        }
        guard client.phase == "CONNECTED" else {
            state = "OFFLINE"
            detail = "Server offline. Your text remains in this window; save after reconnecting."
            return
        }
        if let snapshot = client.snapshot, case .success(let catalogue) = snapshot.projects,
           catalogue.stale {
            state = "STALE"
            detail = "Project source is stale; drafts are not saved until it is current."
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 120, focus.count <= 240, draft.count <= 10_000 else {
            state = "INVALID"
            detail = ConversationError.invalidDraft.localizedDescription
            return
        }
        let fields = DraftFields(title: title, focus: focus, mode: mode, draft: draft,
                                 expected_revision: savedRevision,
                                 request_id: selectedID == nil ? requestID : nil)
        let startingID = selectedID
        isBusy = true
        scopeEpoch += 1
        let epoch = scopeEpoch
        defer { isBusy = false }
        state = "SAVING"
        do {
            let endpoint = try ServerEndpoint(access.endpoint)
            let token = try await client.draftReadToken()
            guard epoch == scopeEpoch, self.access == access else { return }
            let result: Conversation
            if let selectedID {
                result = try await transport.update(endpoint: endpoint, readToken: token,
                                                    access: access, id: selectedID, fields: fields)
            } else {
                result = try await transport.create(endpoint: endpoint, readToken: token,
                                                    access: access, fields: fields)
            }
            guard epoch == scopeEpoch, self.access == access,
                  selectedID == startingID else { return }
            guard result.project_id == projectID else { throw ConversationError.invalidResponse }
            conversations.removeAll(where: { $0.id == result.id })
            conversations.insert(result, at: 0)
            if title != fields.title || focus != fields.focus || mode != fields.mode || draft != fields.draft {
                selectedID = result.id
                savedRevision = result.revision
                savedFields = DraftFields(title: result.title, focus: result.focus,
                                          mode: result.mode, draft: result.draft,
                                          expected_revision: result.revision, request_id: nil)
                state = "PENDING"
                detail = "Earlier text saved; newer local edits remain unsaved."
                persistLocal()
                return
            }
            use(result)
            localTask?.cancel()
            localVersion += 1
            try await localDrafts.remove(PrivateLocalDraftCache.scopeHash(access), version: localVersion)
            guard epoch == scopeEpoch, self.access == access else { return }
            if title != result.title || focus != result.focus || mode != result.mode || draft != result.draft {
                state = "PENDING"
                detail = "Newer local edits remain unsaved."
                persistLocal()
                return
            }
            state = "AVAILABLE"
            detail = "Draft saved to this Workspace Server. No advisor turn was sent."
        } catch {
            guard epoch == scopeEpoch, self.access == access else { return }
            if let reason = error as? ConversationError {
                state = reason == .conflict ? "CONFLICT" :
                    ([.unauthorized, .forbidden].contains(reason) ? "UNAUTHORIZED" : "UNAVAILABLE")
                if reason == .conflict {
                    await load(client: client)
                    return
                }
            } else {
                state = "UNAVAILABLE"
            }
            detail = error.localizedDescription
        }
    }

    private func use(_ conversation: Conversation) {
        serverConflict = nil
        creatingNewDraft = false
        selectedID = conversation.id
        title = conversation.title
        focus = conversation.focus
        mode = conversation.mode
        draft = conversation.draft
        savedRevision = conversation.revision
        savedFields = DraftFields(title: title, focus: focus, mode: mode, draft: draft,
                                  expected_revision: savedRevision, request_id: nil)
    }

    private func clearEditor() {
        serverConflict = nil
        title = ""
        focus = ""
        mode = "BUSINESS"
        draft = ""
        savedRevision = nil
        savedFields = nil
        requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private func clearScope() {
        scopeEpoch += 1
        localTask?.cancel()
        localVersion += 1
        conversations = []
        selectedID = nil
        creatingNewDraft = false
        authorizationSuspended = false
        archiveConfirmation = nil
        pendingArchiveOperation = nil
        resetDiscovery()
        clearEditor()
    }

    private func restoreLocal(_ access: DraftAccess) async -> Bool {
        guard !dirty else { return true }
        do {
            if let snapshot = try await localDrafts.load(PrivateLocalDraftCache.scopeHash(access)) {
                selectedID = snapshot.selectedID
                title = snapshot.title
                focus = snapshot.focus
                mode = snapshot.mode
                draft = snapshot.draft
                savedRevision = snapshot.savedRevision
                requestID = snapshot.requestID
                savedFields = nil
                creatingNewDraft = snapshot.selectedID == nil &&
                    (!snapshot.title.isEmpty || !snapshot.focus.isEmpty ||
                     snapshot.mode != "BUSINESS" || !snapshot.draft.isEmpty)
            }
            return true
        } catch {
            state = "UNAVAILABLE"
            detail = "The private local draft could not be restored."
            return false
        }
    }

    func persistLocal() {
        localVersion += 1
        let version = localVersion
        localTask?.cancel()
        localTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, version == localVersion else { return }
            await flushLocal()
        }
    }

    @discardableResult
    func flushLocal() async -> Bool {
        guard let access, access.projectID == projectID else { return !dirty }
        localVersion += 1
        let version = localVersion
        let key = PrivateLocalDraftCache.scopeHash(access)
        do {
            if dirty {
                try await localDrafts.save(LocalDraftSnapshot(
                    scopeHash: key, selectedID: selectedID, title: title,
                    focus: focus, mode: mode, draft: draft, savedRevision: savedRevision,
                    requestID: requestID), version: version)
            } else {
                try await localDrafts.remove(key, version: version)
            }
            return true
        } catch {
            state = "UNAVAILABLE"
            detail = "The private local draft could not be stored."
            return false
        }
    }
}
