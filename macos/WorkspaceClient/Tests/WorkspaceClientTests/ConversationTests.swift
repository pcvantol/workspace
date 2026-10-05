import Foundation
import AppKit
import Security
import SwiftUI
import XCTest
@testable import WorkspaceClient

private final class MemoryDraftGrant: DraftGrantStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: DraftAccess?
    init(_ value: DraftAccess? = nil) { self.value = value }
    func load() throws -> DraftAccess? { lock.withLock { value } }
    func save(_ access: DraftAccess) throws { lock.withLock { value = access } }
    func forget() throws { lock.withLock { value = nil } }
}

private final class MemoryDraftKeychainBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Data] = [:]
    var updateFailure: OSStatus?
    var deleteFailure: OSStatus?
    var readFailure: OSStatus?

    var operations: DraftKeychainOperations {
        DraftKeychainOperations(
            copy: { query in self.lock.withLock {
                if let failure = self.readFailure { return (failure, nil) }
                let account = (query as NSDictionary)[kSecAttrAccount] as? String ?? ""
                return self.stored[account].map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
            } },
            update: { query, values in self.lock.withLock {
                if let failure = self.updateFailure { return failure }
                let account = (query as NSDictionary)[kSecAttrAccount] as? String ?? ""
                guard self.stored[account] != nil else { return errSecItemNotFound }
                self.stored[account] = (values as NSDictionary)[kSecValueData] as? Data
                return errSecSuccess
            } },
            add: { values in self.lock.withLock {
                let account = (values as NSDictionary)[kSecAttrAccount] as? String ?? ""
                self.stored[account] = (values as NSDictionary)[kSecValueData] as? Data
                return errSecSuccess
            } },
            delete: { query in self.lock.withLock {
                if let failure = self.deleteFailure { return failure }
                let account = (query as NSDictionary)[kSecAttrAccount] as? String ?? ""
                guard self.stored[account] != nil else { return errSecItemNotFound }
                self.stored[account] = nil
                return errSecSuccess
            } }
        )
    }

    func put(_ data: Data, account: String = "project-draft-grant") {
        lock.withLock { stored[account] = data }
    }
}

private final class MemoryServerCredentials: CredentialStore, @unchecked Sendable {
    let savedBinding: ServerBinding
    let savedToken: String
    init(endpoint: String, instance: String, token: String) {
        savedBinding = ServerBinding(endpoint: endpoint, instanceID: instance)
        savedToken = token
    }
    func binding() throws -> ServerBinding? { savedBinding }
    func token() throws -> String? { savedToken }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws {}
}

private final class MemoryLocalDrafts: LocalDraftStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LocalDraftSnapshot?
    private var rejectsWrites = false
    func load(scopeHash: String) throws -> LocalDraftSnapshot? {
        lock.withLock { stored?.scopeHash == scopeHash ? stored : nil }
    }
    func save(_ snapshot: LocalDraftSnapshot) throws {
        try lock.withLock {
            if rejectsWrites { throw CocoaError(.fileWriteUnknown) }
            stored = snapshot
        }
    }
    func remove(scopeHash: String) throws {
        lock.withLock { if stored?.scopeHash == scopeHash { stored = nil } }
    }
    func rejectWrites() { lock.withLock { rejectsWrites = true } }
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

final class ConversationTests: XCTestCase {
    let instance = "0123456789abcdef0123456789abcdef"
    let grant = String(repeating: "x", count: 43)

    private func transport(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> ConversationTransport {
        StubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return ConversationTransport(configuration: configuration)
    }

    private var access: DraftAccess {
        DraftAccess(endpoint: "http://127.0.0.1:8765/", instanceID: instance,
                    projectID: "project-a", token: grant)
    }

    private var record: String {
        """
        {"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","actor_id":"alice","project_id":"project-a",\
        "title":"Direction","focus":"Roadmap","mode":"BUSINESS","draft":"First draft",\
        "revision":1,"created_at":"2026-10-04T20:00:00Z","updated_at":"2026-10-04T20:00:00Z",\
        "history":[],"history_availability":"UNQUALIFIED_FORGE","state":"DRAFT_ONLY"}
        """
    }

    private func discoveryRecord(_ id: String, title: String, focus: String, mode: String,
                                 updated: String) -> Conversation {
        Conversation(id: id, actor_id: "alice", project_id: "project-a", title: title,
                     focus: focus, mode: mode, draft: "Unsent", revision: 1,
                     created_at: "2026-10-04T20:00:00+00:00", updated_at: updated,
                     history: [], history_availability: "UNQUALIFIED_FORGE", state: "DRAFT_ONLY")
    }

    func testDiscoveryCombinesSearchModeAndStableSortWithoutNetwork() {
        let alpha = discoveryRecord("a", title: "Álpha", focus: "Roadmap", mode: "BUSINESS",
                                    updated: "2026-10-05T08:00:00+00:00")
        let tied = discoveryRecord("b", title: "alpha", focus: "Design", mode: "UX",
                                   updated: "2026-10-05T08:00:00+00:00")
        let newest = discoveryRecord("c", title: "Beta", focus: "Roadmap", mode: "ARCHITECTURE",
                                     updated: "2026-10-05T08:00:00.5+00:00")
        let records = [tied, newest, alpha]
        XCTAssertEqual(ConversationDiscovery.visible(records, search: "", mode: .all,
                                                     sort: .recentlyChanged).map(\.id),
                       ["c", "a", "b"])
        XCTAssertEqual(ConversationDiscovery.visible(records, search: "", mode: .all,
                                                     sort: .title).map(\.id),
                       ["a", "b", "c"])
        XCTAssertEqual(ConversationDiscovery.visible(records, search: " ROADMAP ", mode: .all,
                                                     sort: .recentlyChanged).map(\.id), ["c", "a"])
        XCTAssertEqual(ConversationDiscovery.visible(records, search: "roadmap", mode: .business,
                                                     sort: .title).map(\.id), ["a"])
        XCTAssertTrue(ConversationDiscovery.visible(records, search: "missing", mode: .ux,
                                                    sort: .title).isEmpty)
    }

    @MainActor
    func testDiscoveryKeepsSelectedUnsavedDraftAndMakesNoExtraRequests() async throws {
        let instance = self.instance
        let first = record
        let second = record.replacingOccurrences(of: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                                 with: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
            .replacingOccurrences(of: "Direction", with: "Design")
            .replacingOccurrences(of: "BUSINESS", with: "UX")
        var draftRequests = 0
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                draftRequests += 1
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[\(first),\(second)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default: XCTFail("Unexpected route"); return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let state = ConversationState(grants: MemoryDraftGrant(access), localDrafts: MemoryLocalDrafts(),
            transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        XCTAssertEqual(state.conversations.count, 2)
        XCTAssertEqual(state.selectedID, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertNil(state.listMessageKey)
        state.newDraft()
        await state.load(client: client)
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.title, "")
        let staleSecond = discoveryRecord("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", title: "Stale title",
                                          focus: "Stale focus", mode: "BUSINESS",
                                          updated: "2026-10-01T00:00:00Z")
        state.select(staleSecond)
        XCTAssertEqual(state.title, "Design")
        XCTAssertEqual(state.mode, "UX")
        state.select(state.conversations[0])
        state.draft = "Keep this local text"
        let selected = state.selectedID
        let requestsBefore = draftRequests
        state.search = "Design"
        state.modeFilter = .ux
        state.sortOrder = .title
        XCTAssertEqual(state.visibleConversations.map(\.title), ["Design"])
        XCTAssertTrue(state.selectedIsHidden)
        XCTAssertEqual(state.selectedID, selected)
        XCTAssertEqual(state.draft, "Keep this local text")
        state.search = "no matching title"
        XCTAssertEqual(state.listMessageKey, "noResults")
        state.search = "Design"
        state.select(state.visibleConversations[0])
        XCTAssertEqual(state.state, "PENDING")
        XCTAssertEqual(state.selectedID, selected)
        XCTAssertEqual(state.draft, "Keep this local text")
        state.resetDiscovery()
        XCTAssertFalse(state.selectedIsHidden)
        XCTAssertFalse(state.hasActiveDiscovery)
        XCTAssertNil(state.listMessageKey)
        await state.handleClientPhase("UNAVAILABLE")
        XCTAssertEqual(state.state, "OFFLINE")
        XCTAssertEqual(state.listMessageKey, "offline")
        XCTAssertEqual(state.draft, "Keep this local text")
        XCTAssertEqual(draftRequests, requestsBefore)
    }

    @MainActor
    func testDisconnectInvalidatesInFlightListAndForgetHidesAuthorizedScope() async throws {
        let instance = self.instance
        let currentRecord = self.record
        let secondListStarted = expectation(description: "Delayed conversation list started")
        let releaseSecondList = DispatchSemaphore(value: 0)
        let listCount = RequestCounter()
        defer { releaseSecondList.signal() }
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity":
                return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status":
                return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.4\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects":
                return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-05T08:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status":
                return (503, Data("{}".utf8))
            case "/v1/conversations":
                if listCount.next() == 2 {
                    secondListStarted.fulfill()
                    XCTAssertEqual(releaseSecondList.wait(timeout: .now() + 5), .success)
                }
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[\(currentRecord)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default:
                XCTFail("Unexpected route")
                return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let local = MemoryLocalDrafts()
        let grants = MemoryDraftGrant(access)
        let state = ConversationState(grants: grants, localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        XCTAssertEqual(state.conversations.count, 1)
        let loading = Task { await state.load(client: client) }
        await fulfillment(of: [secondListStarted], timeout: 5)
        await state.handleClientPhase("UNAVAILABLE")
        releaseSecondList.signal()
        await loading.value
        XCTAssertEqual(state.state, "OFFLINE")
        XCTAssertEqual(state.listMessageKey, "offline")
        state.draft = "Keep this private local edit"
        let prepared = await state.prepareForServerForget()
        XCTAssertTrue(prepared)
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        XCTAssertEqual(state.listMessageKey, "forbidden")
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.draft, "Keep this private local edit")
        XCTAssertTrue(state.dirty)
        XCTAssertFalse(state.canEdit)
        XCTAssertEqual(try local.load(scopeHash: PrivateLocalDraftCache.scopeHash(access))?.draft,
                       "Keep this private local edit")
        let reopened = ConversationState(grants: grants, localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await reopened.prepare(client: client)
        XCTAssertNil(reopened.selectedID)
        XCTAssertEqual(reopened.draft, "Keep this private local edit")
        XCTAssertTrue(reopened.dirty)
        let failing = MemoryLocalDrafts()
        let failedState = ConversationState(grants: grants, localDrafts: failing,
            transport: ConversationTransport(configuration: configuration))
        await failedState.prepare(client: client)
        failedState.draft = "Must not claim durable recovery"
        failing.rejectWrites()
        let failedPreparation = await failedState.prepareForServerForget()
        XCTAssertFalse(failedPreparation)
        XCTAssertEqual(failedState.state, "UNAVAILABLE")
        XCTAssertEqual(failedState.detail, "The private local draft could not be stored.")
        XCTAssertEqual(failedState.conversations.count, 1)
        XCTAssertNotNil(failedState.selectedID)
        XCTAssertTrue(failedState.canEdit)
        let failedRetry = await failedState.prepareForServerForget()
        XCTAssertFalse(failedRetry)
    }

    @MainActor
    func testForgetServerInvalidatesInFlightGrantSave() async throws {
        let instance = self.instance
        let grantListStarted = expectation(description: "Grant verification list started")
        let releaseGrantList = DispatchSemaphore(value: 0)
        defer { releaseGrantList.signal() }
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity":
                return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status":
                return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.4\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects":
                return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-05T08:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status":
                return (503, Data("{}".utf8))
            case "/v1/conversations":
                grantListStarted.fulfill()
                XCTAssertEqual(releaseGrantList.wait(timeout: .now() + 5), .success)
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default:
                XCTFail("Unexpected route")
                return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let grants = MemoryDraftGrant()
        let state = ConversationState(grants: grants, localDrafts: MemoryLocalDrafts(),
            transport: ConversationTransport(configuration: configuration))
        state.selectProject("project-a")
        state.grantEntry = grant
        let saving = Task { await state.saveGrant(client: client) }
        await fulfillment(of: [grantListStarted], timeout: 5)
        await state.handleClientPhase("UNCONFIGURED")
        releaseGrantList.signal()
        await saving.value
        XCTAssertNil(try grants.load())
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        XCTAssertFalse(state.canEdit)
    }

    #if WORKSPACE_ISOLATED_TEST
    func testIsolatedCredentialDocumentAndMemoryStores() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            unsetenv("WORKSPACE_ISOLATED_CREDENTIALS_FILE")
            try? FileManager.default.removeItem(at: root)
        }
        let file = root.appendingPathComponent("credentials.json")
        let document: [String: String] = [
            "endpoint": "http://127.0.0.1:18765/", "instance_id": instance,
            "read_token": "read-only", "project_id": "project-a", "draft_grant": grant,
            "local_root": root.appendingPathComponent("drafts").path
        ]
        try JSONSerialization.data(withJSONObject: document).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        setenv("WORKSPACE_ISOLATED_CREDENTIALS_FILE", file.path, 1)
        let loaded = try IsolatedTestDocument.load()
        XCTAssertEqual(loaded.project_id, "project-a")
        let server = IsolatedServerCredentials(loaded)
        XCTAssertEqual(try server.binding()?.instanceID, instance)
        XCTAssertEqual(try server.token(), "read-only")
        try server.save(binding: ServerBinding(endpoint: loaded.endpoint, instanceID: instance), token: "updated")
        XCTAssertEqual(try server.token(), "updated")
        try server.forget()
        XCTAssertNil(try server.binding())
        let grants = IsolatedDraftGrant(loaded)
        XCTAssertEqual(try grants.load()?.projectID, "project-a")
        try grants.save(DraftAccess(endpoint: loaded.endpoint, instanceID: instance,
                                    projectID: "project-b", token: grant))
        XCTAssertEqual(try grants.load()?.projectID, "project-b")
        try grants.forget()
        XCTAssertNil(try grants.load())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try IsolatedTestDocument.load())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var invalid = document
        invalid["endpoint"] = "https://example.com/"
        try JSONSerialization.data(withJSONObject: invalid).write(to: file)
        XCTAssertThrowsError(try IsolatedTestDocument.load())
        unsetenv("WORKSPACE_ISOLATED_CREDENTIALS_FILE")
        XCTAssertThrowsError(try IsolatedTestDocument.load())
    }
    #endif

    func testDraftGrantKeychainBindingAndFailurePathsWithoutLiveKeychain() throws {
        let backend = MemoryDraftKeychainBackend()
        let keychain = DraftGrantKeychain(operations: backend.operations)
        XCTAssertNil(try keychain.load())
        try keychain.save(access)
        XCTAssertEqual(try keychain.load()?.projectID, "project-a")
        let updated = DraftAccess(endpoint: access.endpoint, instanceID: access.instanceID,
                                  projectID: "project-b", token: access.token)
        try keychain.save(updated)
        XCTAssertEqual(try keychain.load()?.projectID, "project-b")
        try keychain.forget()
        try keychain.forget()
        backend.put(Data("bad-json".utf8))
        XCTAssertThrowsError(try keychain.load())
        backend.readFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.load())
        backend.readFailure = nil
        backend.updateFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.save(access))
        backend.updateFailure = nil
        backend.deleteFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.forget())
    }

    func testServerKeychainBindingPathsWithSimulatedSecurityOperations() throws {
        let backend = MemoryDraftKeychainBackend()
        let keychain = ClientKeychain(operations: backend.operations)
        XCTAssertNil(try keychain.binding())
        XCTAssertNil(try keychain.token())
        let binding = ServerBinding(endpoint: access.endpoint, instanceID: instance)
        try keychain.save(binding: binding, token: "read-only")
        XCTAssertEqual(try keychain.binding(), binding)
        XCTAssertEqual(try keychain.token(), "read-only")
        try keychain.save(binding: binding, token: "second-token")
        XCTAssertEqual(try keychain.token(), "second-token")
        try keychain.forget()
        try keychain.forget()
        XCTAssertNil(try keychain.binding())
        backend.put(Data("bad-json".utf8), account: "server-binding")
        XCTAssertThrowsError(try keychain.binding())
        backend.readFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.binding())
        backend.readFailure = nil
        backend.updateFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.save(binding: binding, token: "read-only"))
        backend.updateFailure = nil
        backend.deleteFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.forget())
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody {
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        }
        guard let stream = request.httpBodyStream else { throw ConversationError.invalidResponse }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw ConversationError.invalidResponse }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    @MainActor
    private func render<V: View>(_ view: V) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 940, height: 700)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.frame.width, 0)
    }

    func testTransportUsesSeparateDraftGrantAndOnlyOwnRoutes() async throws {
        let instance = self.instance
        let grant = self.grant
        let record = self.record
        let client = transport { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer read-only")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Instance"), instance)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Draft-Grant"), grant)
            XCTAssertTrue(request.url!.path.hasPrefix("/v1/conversations"))
            switch (request.httpMethod, request.url!.path) {
            case ("GET", "/v1/conversations"):
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[\(record)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            case ("POST", "/v1/conversations"):
                let body = try self.body(request)
                XCTAssertEqual(body["request_id"] as? String, String(repeating: "b", count: 32))
                XCTAssertNil(body["expected_revision"])
                return (201, Data(record.utf8))
            case ("PATCH", "/v1/conversations/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"):
                let body = try self.body(request)
                XCTAssertEqual(body["expected_revision"] as? Int, 1)
                XCTAssertNil(body["request_id"])
                return (200, Data(record.replacingOccurrences(of: "\"revision\":1", with: "\"revision\":2").utf8))
            default:
                XCTFail("Unexpected route")
                return (404, Data("{}".utf8))
            }
        }
        let endpoint = try ServerEndpoint(access.endpoint)
        let listing = try await client.list(endpoint: endpoint, readToken: "read-only", access: access)
        XCTAssertEqual(listing.conversations.map(\.title), ["Direction"])
        let create = DraftFields(title: "Direction", focus: "Roadmap", mode: "BUSINESS",
                                 draft: "First draft", expected_revision: nil,
                                 request_id: String(repeating: "b", count: 32))
        let created = try await client.create(endpoint: endpoint, readToken: "read-only",
                                              access: access, fields: create)
        XCTAssertEqual(created.id, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        let update = DraftFields(title: "Direction", focus: "Roadmap", mode: "ARCHITECTURE",
                                 draft: "First draft", expected_revision: 1, request_id: nil)
        let updated = try await client.update(endpoint: endpoint, readToken: "read-only",
                                              access: access, id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                                              fields: update)
        XCTAssertEqual(updated.revision, 2)
    }

    func testTransportRejectsWrongScopeAndGrantDenial() async throws {
        let endpoint = try ServerEndpoint(access.endpoint)
        let wrong = transport { _ in
            (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-b\",\"conversations\":[],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
        }
        do {
            _ = try await wrong.list(endpoint: endpoint, readToken: "read-only", access: access)
            XCTFail("Wrong project accepted")
        } catch let error as ConversationError {
            XCTAssertEqual(error, .invalidResponse)
        }
        let denied = transport { _ in (403, Data("{\"error\":\"DRAFT_GRANT_DENIED\"}".utf8)) }
        do {
            _ = try await denied.list(endpoint: endpoint, readToken: "read-only", access: access)
            XCTFail("Denied grant accepted")
        } catch let error as ConversationError {
            XCTAssertEqual(error, .forbidden)
        }
    }

    @MainActor
    func testOfflineDoesNotSubmitOrLoseEditorText() async throws {
        let instance = self.instance
        let record = self.record
        var draftRequests = 0
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities": return (503, Data("{}".utf8))
            case "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                draftRequests += 1
                XCTAssertEqual(request.httpMethod, "GET")
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[\(record)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default: XCTFail("Unexpected route \(request.url!.path)"); return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let server = ServerTransport(configuration: configuration)
        let credentials = MemoryServerCredentials(endpoint: access.endpoint, instance: instance, token: "read-only")
        let client = ClientState(keychain: credentials, transport: server)
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let local = MemoryLocalDrafts()
        let state = ConversationState(grants: MemoryDraftGrant(access),
                                      localDrafts: local,
                                      transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        XCTAssertEqual(state.state, "AVAILABLE")
        state.select(state.conversations[0])
        state.mode = "ARCHITECTURE"
        state.draft = "Offline edit"
        XCTAssertTrue(state.dirty)
        await state.flushLocal()
        let reopened = ConversationState(grants: MemoryDraftGrant(access), localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await reopened.prepare(client: client)
        XCTAssertEqual(reopened.draft, "Offline edit")
        XCTAssertEqual(reopened.mode, "ARCHITECTURE")
        XCTAssertTrue(reopened.dirty)
        client.cancel()
        await reopened.save(client: client)
        XCTAssertEqual(reopened.state, "OFFLINE")
        XCTAssertEqual(reopened.draft, "Offline edit")
        XCTAssertEqual(reopened.mode, "ARCHITECTURE")
        XCTAssertEqual(draftRequests, 2)
    }

    func testPrivateLocalDraftCachePersistsPrivatelyAndRejectsTampering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = PrivateLocalDraftCache(root: root)
        let key = PrivateLocalDraftCache.scopeHash(access)
        let snapshot = LocalDraftSnapshot(scopeHash: key, selectedID: nil, title: "Direction",
            focus: "Roadmap", mode: "BUSINESS", draft: "Offline text", savedRevision: nil,
            requestID: String(repeating: "c", count: 32))
        try cache.save(snapshot)
        XCTAssertEqual(try PrivateLocalDraftCache(root: root).load(scopeHash: key), snapshot)
        let file = root.appendingPathComponent("local-\(key).json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? Int) ?? -1, 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try cache.load(scopeHash: key))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data(repeating: 0x41, count: 48_001).write(to: file)
        XCTAssertThrowsError(try cache.load(scopeHash: key))
    }

    @MainActor
    func testGrantLifecycleSearchAndDeniedDraftWrites() async throws {
        let instance = self.instance
        var deny = false
        var draftMethods = [String]()
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                draftMethods.append(request.httpMethod ?? "")
                if deny { return (403, Data("{}".utf8)) }
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default: XCTFail("Unexpected route"); return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let grants = MemoryDraftGrant()
        let state = ConversationState(grants: grants, localDrafts: MemoryLocalDrafts(),
            transport: ConversationTransport(configuration: configuration))
        state.selectProject("project-a")
        await state.prepare(client: client)
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        XCTAssertEqual(state.listMessageKey, "forbidden")
        state.grantEntry = "bad"
        await state.saveGrant(client: client)
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        state.grantEntry = grant
        await state.saveGrant(client: client)
        XCTAssertEqual(state.state, "AVAILABLE")
        XCTAssertEqual(state.listMessageKey, "noConversations")
        XCTAssertEqual(try grants.load()?.projectID, "project-a")
        XCTAssertEqual(draftMethods, ["GET", "GET"])
        state.search = "missing"
        XCTAssertTrue(state.visibleConversations.isEmpty)
        state.selectProject("project-b")
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        XCTAssertEqual(state.projectID, "project-b")
        state.selectProject("project-a")
        await state.load(client: client)
        XCTAssertEqual(state.state, "AVAILABLE")
        deny = true
        await state.load(client: client)
        XCTAssertEqual(state.state, "UNAUTHORIZED")
        state.title = "Draft"
        state.draft = "Keep locally"
        await state.save(client: client)
        XCTAssertEqual(state.state, "UNAUTHORIZED")
        XCTAssertEqual(state.draft, "Keep locally")
        state.forgetGrant()
        XCTAssertEqual(state.state, "PENDING")
        XCTAssertNotNil(try grants.load())
        state.discardChanges()
        state.forgetGrant()
        for _ in 0..<100 where state.state != "GRANT_REQUIRED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
        XCTAssertNil(try grants.load())
        state.grantEntry = grant
        await state.saveGrant(client: client)
        XCTAssertEqual(state.state, "UNAUTHORIZED")
        XCTAssertNil(try grants.load())
    }

    @MainActor
    func testChangingActorGrantKeepsUnsavedTextAndClearsPriorActorOnSwitch() async throws {
        let instance = self.instance
        let aliceRecord = self.record
        let bobToken = String(repeating: "y", count: 43)
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                let bob = request.value(forHTTPHeaderField: "X-Workspace-Draft-Grant") == bobToken
                return (200, Data("{\"actor_id\":\"\(bob ? "bob" : "alice")\",\"project_id\":\"project-a\",\"conversations\":[\(bob ? "" : aliceRecord)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default: XCTFail("Unexpected route"); return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let grants = MemoryDraftGrant(access)
        let state = ConversationState(grants: grants, localDrafts: MemoryLocalDrafts(),
            transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        XCTAssertEqual(state.title, "Direction")
        state.draft = "Alice's unsaved text"
        state.grantEntry = bobToken
        await state.saveGrant(client: client)
        XCTAssertEqual(state.state, "PENDING")
        XCTAssertEqual(state.draft, "Alice's unsaved text")
        XCTAssertEqual(try grants.load(), access)
        state.discardChanges()
        await state.saveGrant(client: client)
        XCTAssertEqual(state.state, "AVAILABLE")
        XCTAssertEqual(try grants.load()?.token, bobToken)
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.draft, "")
    }

    @MainActor
    func testLaterEditorTextSurvivesDelayedSaveResponse() async throws {
        let instance = self.instance
        let savedRecord = self.record
        let postStarted = expectation(description: "Server received draft")
        let oldListStarted = expectation(description: "Old actor list started")
        let releasePost = DispatchSemaphore(value: 0)
        let releaseOldList = DispatchSemaphore(value: 0)
        let listCount = RequestCounter()
        defer { releasePost.signal(); releaseOldList.signal() }
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                if request.httpMethod == "POST" {
                    postStarted.fulfill()
                    XCTAssertEqual(releasePost.wait(timeout: .now() + 5), .success)
                    return (201, Data(savedRecord.utf8))
                }
                let count = listCount.next()
                if count == 2 {
                    oldListStarted.fulfill()
                    XCTAssertEqual(releaseOldList.wait(timeout: .now() + 5), .success)
                    return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[\(savedRecord)],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
                }
                return (200, Data("{\"actor_id\":\"alice\",\"project_id\":\"project-a\",\"conversations\":[],\"history_availability\":\"UNQUALIFIED_FORGE\"}".utf8))
            default: XCTFail("Unexpected route"); return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let local = MemoryLocalDrafts()
        let state = ConversationState(grants: MemoryDraftGrant(access), localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        state.title = "Direction"
        state.focus = "Roadmap"
        state.draft = "First draft"
        let saving = Task { await state.save(client: client) }
        await fulfillment(of: [postStarted], timeout: 5)
        XCTAssertTrue(state.isBusy)
        XCTAssertFalse(state.canEdit)
        state.draft = "Later local edit"
        releasePost.signal()
        await saving.value
        XCTAssertEqual(state.draft, "Later local edit")
        XCTAssertEqual(state.savedRevision, 1)
        XCTAssertTrue(state.dirty)
        XCTAssertEqual(state.state, "PENDING")
        await state.flushLocal()
        XCTAssertEqual(try local.load(scopeHash: PrivateLocalDraftCache.scopeHash(access))?.draft,
                       "Later local edit")
        state.discardChanges()
        let loading = Task { await state.load(client: client) }
        await fulfillment(of: [oldListStarted], timeout: 5)
        state.selectProject("project-b")
        releaseOldList.signal()
        await loading.value
        XCTAssertEqual(state.projectID, "project-b")
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.title, "")
        XCTAssertEqual(state.state, "GRANT_REQUIRED")
    }

    @MainActor
    func testCreateRenameReopenAndModeSwitchWithoutProviderCall() async throws {
        let instance = self.instance
        var records = [[String: Any]]()
        var draftMethods = [String]()
        var conflictNext = false
        let serverRecord: (String, String, String, Int) -> [String: Any] = { title, mode, draft, revision in
            ["id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "actor_id": "alice", "project_id": "project-a",
             "title": title, "focus": "Roadmap", "mode": mode, "draft": draft, "revision": revision,
             "created_at": "2026-10-04T20:00:00Z", "updated_at": "2026-10-04T20:00:00Z",
             "history": [], "history_availability": "UNQUALIFIED_FORGE", "state": "DRAFT_ONLY"]
        }
        StubProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.3\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"project-a\",\"name\":\"Project A\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-04T20:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities", "/v1/forge/status": return (503, Data("{}".utf8))
            case "/v1/conversations":
                draftMethods.append(request.httpMethod ?? "")
                if request.httpMethod == "GET" {
                    return (200, try JSONSerialization.data(withJSONObject: [
                        "actor_id": "alice", "project_id": "project-a", "conversations": records,
                        "history_availability": "UNQUALIFIED_FORGE"]))
                }
                let body = try self.body(request)
                XCTAssertEqual(body["request_id"] as? String == nil, false)
                XCTAssertNil(body["expected_revision"])
                let record = serverRecord(body["title"] as! String, body["mode"] as! String,
                                          body["draft"] as! String, 1)
                records = [record]
                return (201, try JSONSerialization.data(withJSONObject: record))
            case "/v1/conversations/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":
                draftMethods.append(request.httpMethod ?? "")
                XCTAssertEqual(request.httpMethod, "PATCH")
                if conflictNext {
                    conflictNext = false
                    records = [serverRecord("Other writer", "ARCHITECTURE", "Newer Server text", 3)]
                    return (409, Data("{\"error\":\"DRAFT_CONFLICT\"}".utf8))
                }
                let body = try self.body(request)
                let latestRevision = records.first?["revision"] as? Int ?? 1
                XCTAssertEqual(body["expected_revision"] as? Int, latestRevision)
                let record = serverRecord(body["title"] as! String, body["mode"] as! String,
                                          body["draft"] as! String, latestRevision + 1)
                records = [record]
                return (200, try JSONSerialization.data(withJSONObject: record))
            default:
                XCTFail("Unexpected provider or peer route \(request.url!.path)")
                return (404, Data("{}".utf8))
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let client = ClientState(keychain: MemoryServerCredentials(endpoint: access.endpoint,
            instance: instance, token: "read-only"), transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where client.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(client.phase, "CONNECTED")
        let local = MemoryLocalDrafts()
        let state = ConversationState(grants: MemoryDraftGrant(access), localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await state.prepare(client: client)
        XCTAssertEqual(state.conversations.count, 0)
        state.newDraft()
        state.title = "Direction"
        state.focus = "Roadmap"
        state.draft = "What should we prioritize?"
        state.mode = "BUSINESS"
        await state.save(client: client)
        XCTAssertEqual(state.state, "AVAILABLE")
        XCTAssertFalse(state.dirty)
        XCTAssertEqual(state.conversations.count, 1)
        let before = draftMethods.count
        state.mode = "ARCHITECTURE"
        XCTAssertEqual(draftMethods.count, before)
        state.title = "Architecture direction"
        await state.save(client: client)
        XCTAssertEqual(state.savedRevision, 2)
        XCTAssertEqual(state.conversations[0].history, [])
        state.title = "Local edit"
        state.selectProject("other-project")
        XCTAssertEqual(state.projectID, "project-a")
        XCTAssertEqual(state.title, "Local edit")
        XCTAssertEqual(state.state, "PENDING")
        state.newDraft()
        XCTAssertEqual(state.title, "Local edit")
        state.discardChanges()
        XCTAssertEqual(state.title, "Architecture direction")
        state.title = " "
        await state.save(client: client)
        XCTAssertEqual(state.state, "INVALID")
        state.discardChanges()
        state.title = "Conflict edit"
        conflictNext = true
        await state.save(client: client)
        XCTAssertEqual(state.state, "CONFLICT")
        XCTAssertEqual(state.title, "Conflict edit")
        XCTAssertEqual(state.serverConflict?.title, "Other writer")
        XCTAssertEqual(state.serverConflict?.draft, "Newer Server text")
        state.keepLocalAfterReview()
        XCTAssertEqual(state.title, "Conflict edit")
        XCTAssertEqual(state.savedRevision, 3)
        await state.save(client: client)
        XCTAssertEqual(state.savedRevision, 4)
        let reopened = ConversationState(grants: MemoryDraftGrant(access), localDrafts: local,
            transport: ConversationTransport(configuration: configuration))
        await reopened.prepare(client: client)
        XCTAssertEqual(reopened.conversations[0].title, "Conflict edit")
        XCTAssertEqual(reopened.conversations[0].mode, "ARCHITECTURE")
        XCTAssertEqual(reopened.selectedID, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        XCTAssertEqual(reopened.draft, "What should we prioritize?")
        XCTAssertEqual(draftMethods, ["GET", "POST", "PATCH", "PATCH", "GET", "PATCH", "GET"])
        render(ConversationsView(client: client, state: state))
        render(ServerOverviewView(client: client))
        render(SettingsView(client: client, conversations: state))
    }

    @MainActor
    func testConversationCopyAndViewRenderWithCredentialAdapters() async throws {
        for language in ["en", "nl", "de", "fr", "es"] {
            for key in ["nav", "project", "new", "search", "find", "filter", "all", "sort",
                        "recent", "titleSort", "activeFilters", "resetFilters", "noConversations",
                        "noResults", "selectedHidden", "selected", "title", "focus", "mode", "draft",
                        "save", "context", "sources", "ai", "saved", "offline", "conflict"] {
                XCTAssertNotEqual(ConversationCopy.text(key, language: language), key)
            }
        }
        let client = ClientState(keychain: BrokenCredentials())
        let state = ConversationState(grants: MemoryDraftGrant(), localDrafts: MemoryLocalDrafts())
        let view = ContentView(client: client, conversations: state)
        render(view)
    }
}
