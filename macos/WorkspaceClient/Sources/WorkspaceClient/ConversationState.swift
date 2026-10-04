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
    @Published var projectID = ""
    @Published var selectedID: String?
    @Published var title = ""
    @Published var focus = ""
    @Published var mode = "BUSINESS"
    @Published var draft = ""
    @Published var search = ""
    @Published var grantEntry = ""
    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var state = "UNAVAILABLE"
    @Published private(set) var detail = "Connect a Workspace Server and enter a project draft grant."
    @Published private(set) var savedRevision: Int?
    @Published private(set) var savedFields: DraftFields?
    @Published private(set) var serverConflict: Conversation?

    private let grants: DraftGrantWorker
    private let localDrafts: LocalDraftWorker
    private let transport: ConversationTransport
    private var access: DraftAccess?
    private var loadingGrant = false
    private var requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private var localTask: Task<Void, Never>?
    private var localVersion = 0

    init(grants: any DraftGrantStore = DraftGrantKeychain(),
         localDrafts: any LocalDraftStore = PrivateLocalDraftCache(),
         transport: ConversationTransport = ConversationTransport()) {
        self.grants = DraftGrantWorker(grants)
        self.localDrafts = LocalDraftWorker(localDrafts)
        self.transport = transport
    }

    var visibleConversations: [Conversation] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? conversations : conversations.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.focus.localizedCaseInsensitiveContains(query)
        }
    }

    var canEdit: Bool { access?.projectID == projectID }

    var dirty: Bool {
        guard let savedFields else { return !title.isEmpty || !focus.isEmpty || !draft.isEmpty }
        return savedFields.title != title || savedFields.focus != focus ||
            savedFields.mode != mode || savedFields.draft != draft
    }

    func prepare(client: ClientState) async {
        guard !loadingGrant else { return }
        loadingGrant = true
        defer { loadingGrant = false }
        do {
            let stored = try await grants.load()
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
            state = "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func saveGrant(client: ClientState) async {
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
        do {
            guard let snapshot = client.snapshot,
                  case .success(let catalogue) = snapshot.projects, !catalogue.stale,
                  catalogue.projects.contains(where: { $0.id == projectID }) else {
                state = "STALE"
                return
            }
            let endpoint = try ServerEndpoint(proposed.endpoint)
            let readToken = try await client.draftReadToken()
            _ = try await transport.list(endpoint: endpoint, readToken: readToken, access: proposed)
            guard proposed.projectID == projectID, !(access != proposed && dirty) else {
                state = "PENDING"
                detail = "Save or discard local changes before switching draft access."
                return
            }
            try await grants.save(proposed)
            if access != proposed { clearScope() }
            access = proposed
            grantEntry = ""
            if await restoreLocal(proposed) { await load(client: client) }
        } catch {
            state = [ConversationError.forbidden, .unauthorized].contains(error as? ConversationError ?? .unavailable) ?
                "UNAUTHORIZED" : "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func forgetGrant() {
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before forgetting draft access."
            return
        }
        Task {
          do {
            if let access {
                localVersion += 1
                try await localDrafts.remove(PrivateLocalDraftCache.scopeHash(access), version: localVersion)
            }
            try await grants.forget()
            access = nil
            clearScope()
            state = "GRANT_REQUIRED"
            detail = "Draft grant removed from this Mac. Existing Server drafts remain."
          } catch {
            state = "UNAVAILABLE"
            detail = error.localizedDescription
          }
        }
    }

    func selectProject(_ id: String) {
        if id == projectID { return }
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before switching projects."
            return
        }
        projectID = id
        selectedID = nil
        conversations = []
        clearEditor()
        if access?.projectID != id {
            state = "GRANT_REQUIRED"
            detail = "Enter this project's separate draft grant."
        }
    }

    func load(client: ClientState) async {
        guard let access, access.projectID == projectID,
              access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance else {
            state = "GRANT_REQUIRED"
            detail = "Enter this project's separate draft grant."
            return
        }
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
            let list = try await transport.list(endpoint: endpoint, readToken: token, access: access)
            conversations = list.conversations
            if dirty, let selectedID, let latest = conversations.first(where: { $0.id == selectedID }),
               latest.revision != savedRevision {
                serverConflict = latest
                state = "CONFLICT"
                detail = "Review the newer Server draft beside your local text before choosing a version."
                return
            }
            serverConflict = nil
            if !dirty, let latest = conversations.first(where: { $0.id == selectedID }) ?? conversations.first {
                use(latest)
            } else if !dirty {
                selectedID = nil
                clearEditor()
            }
            state = "AVAILABLE"
            detail = "Workspace drafts. Advisor history and replies are unavailable."
        } catch {
            state = [ConversationError.forbidden, .unauthorized].contains(error as? ConversationError ?? .unavailable) ?
                "UNAUTHORIZED" : "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func newDraft() {
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard local changes before starting another conversation."
            return
        }
        selectedID = nil
        clearEditor()
        state = access?.projectID == projectID ? "AVAILABLE" : "GRANT_REQUIRED"
    }

    func select(_ conversation: Conversation) {
        guard !dirty else {
            state = "PENDING"
            detail = "Save or discard the current changes before opening another conversation."
            return
        }
        use(conversation)
    }

    func discardChanges() {
        if let selectedID, let existing = conversations.first(where: { $0.id == selectedID }) {
            use(existing)
        } else {
            clearEditor()
        }
        state = "AVAILABLE"
        detail = "Unsaved changes discarded."
        persistLocal()
    }

    func keepLocalAfterReview() {
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
        state = "SAVING"
        do {
            let endpoint = try ServerEndpoint(access.endpoint)
            let token = try await client.draftReadToken()
            let result: Conversation
            if let selectedID {
                result = try await transport.update(endpoint: endpoint, readToken: token,
                                                    access: access, id: selectedID, fields: fields)
            } else {
                result = try await transport.create(endpoint: endpoint, readToken: token,
                                                    access: access, fields: fields)
            }
            guard result.project_id == projectID else { throw ConversationError.invalidResponse }
            conversations.removeAll(where: { $0.id == result.id })
            conversations.insert(result, at: 0)
            use(result)
            localTask?.cancel()
            localVersion += 1
            try await localDrafts.remove(PrivateLocalDraftCache.scopeHash(access), version: localVersion)
            state = "AVAILABLE"
            detail = "Draft saved to this Workspace Server. No advisor turn was sent."
        } catch {
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
        localTask?.cancel()
        localVersion += 1
        conversations = []
        selectedID = nil
        search = ""
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

    func flushLocal() async {
        guard let access, access.projectID == projectID else { return }
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
        } catch {
            state = "UNAVAILABLE"
            detail = "The private local draft could not be stored."
        }
    }
}
