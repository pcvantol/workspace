import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class WorklistMemoryCredentials: WorklistCredentialStore, @unchecked Sendable {
    var stored: WorklistAccess?
    var broken = false
    func loadAccess() throws -> WorklistAccess? {
        if broken { throw CredentialError.corruptBinding }
        return stored
    }
    func saveAccess(_ access: WorklistAccess) throws {
        if broken { throw CredentialError.corruptBinding }
        stored = access
    }
    func forgetAccess() throws {
        if broken { throw CredentialError.corruptBinding }
        stored = nil
    }
}

private final class WorklistResponseLatch: @unchecked Sendable {
    let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var value = false
    var started: Bool { lock.withLock { value } }
    func block() { lock.withLock { value = true }; _ = gate.wait(timeout: .now() + 3) }
}

private struct WorklistServerCredentials: CredentialStore {
    let endpoint: String
    let instance: String
    let tokenValue: String
    func binding() throws -> ServerBinding? { ServerBinding(endpoint: endpoint, instanceID: instance) }
    func token() throws -> String? { tokenValue }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws {}
}

final class WorklistStateTests: XCTestCase {
    let access = WorklistProjectionTests.access
    var calls: [URLRequest] = []
    var status = 200
    var invalidScopes = false
    var invalidProjection = false
    var failure = false
    private func transport() -> WorklistTransport {
        WorklistStubProtocol.handler = { request in
            self.calls.append(request)
            if !(request.url?.path.hasPrefix("/v1/worksets") ?? false) {
                return (404, Data("{\"error\":\"UNIT_READ_UNAVAILABLE\"}".utf8), "application/json")
            }
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Worklist-Grant"), self.access.token)
            if self.failure { throw URLError(.notConnectedToInternet) }
            if request.url?.path == "/v1/worksets" {
                let scopes: [String: Any] = ["contract_version": "forge-workspace-worklist-scopes/v1", "instance_id": self.access.forgeInstanceID, "principal_id": self.invalidScopes ? "foreign" : self.access.actorID, "workset_ids": self.access.worksetIDs, "read_only": true]
                return (self.status, try JSONSerialization.data(withJSONObject: scopes), "application/json")
            }
            return (self.status, self.invalidProjection ? Data("{}".utf8) : try WorklistProjectionTests.fixture(), "application/json")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorklistStubProtocol.self]
        return WorklistTransport(configuration: configuration)
    }
    private var connection: WorklistConnection {
        WorklistConnection(endpoint: access.endpoint, instanceID: access.workspaceInstanceID, readToken: "root-read")
    }
    @MainActor
    func testSaveRefreshRestartOfflineAndRevocationNeverMutateForge() async throws {
        let memory = WorklistMemoryCredentials()
        let transport = transport()
        let state = WorklistState(credentials: memory, transport: transport)
        await state.refresh(connection: connection)
        XCTAssertEqual(state.cache.availability, .unavailable)
        await state.saveGrant(access.token, connection: connection)
        XCTAssertTrue(state.hasGrant)
        XCTAssertEqual(memory.stored, access)
        XCTAssertEqual(state.selectedWorkset, "workset-a")
        XCTAssertEqual(state.cache.availability, .available)
        let revision = state.cache.snapshot?.snapshotRevision
        failure = true
        await state.refresh(connection: connection)
        XCTAssertEqual(state.cache.availability, .offline)
        XCTAssertTrue(state.cache.usingLastObservation)
        XCTAssertEqual(state.cache.snapshot?.snapshotRevision, revision)
        failure = false
        invalidProjection = true
        await state.refresh(connection: connection)
        XCTAssertEqual(state.cache.availability, .stale)
        XCTAssertEqual(state.cache.snapshot?.snapshotRevision, revision)
        invalidProjection = false
        let restarted = WorklistState(credentials: memory, transport: transport)
        XCTAssertNil(restarted.cache.snapshot)
        await restarted.refresh(connection: connection)
        XCTAssertEqual(restarted.cache.availability, .available)
        invalidScopes = true
        await restarted.refresh(connection: connection)
        XCTAssertEqual(restarted.cache.availability, .denied)
        XCTAssertNil(restarted.cache.snapshot)
        invalidScopes = false
        status = 401
        await state.refresh(connection: connection)
        XCTAssertEqual(state.cache.availability, .denied)
        XCTAssertNil(state.cache.snapshot)
        state.forgetGrant()
        XCTAssertFalse(state.hasGrant)
        XCTAssertNil(memory.stored)
        XCTAssertTrue(state.worksetIDs.isEmpty)
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod == "GET" })
    }
    @MainActor
    func testInvalidGrantForeignSelectionAndChangedServerFailBeforeReading() async {
        let memory = WorklistMemoryCredentials()
        let state = WorklistState(credentials: memory, transport: transport())
        await state.saveGrant("bad", connection: connection)
        XCTAssertEqual(state.cache.availability, .denied)
        XCTAssertTrue(calls.isEmpty)
        await state.saveGrant(access.token, connection: nil)
        XCTAssertTrue(calls.isEmpty)
        await state.saveGrant(access.token, connection: connection)
        let count = calls.count
        await state.refresh(connection: connection, selecting: "foreign-workset")
        XCTAssertEqual(calls.count, count)
        XCTAssertNil(state.cache.snapshot)
        await state.refresh(connection: WorklistConnection(endpoint: "http://127.0.0.1:9090/", instanceID: connection.instanceID, readToken: connection.readToken))
        XCTAssertEqual(calls.count, count)
        await state.refresh(connection: WorklistConnection(endpoint: connection.endpoint, instanceID: connection.instanceID, readToken: nil))
        XCTAssertEqual(state.cache.availability, .offline)
        memory.broken = true
        await state.refresh(connection: connection)
        XCTAssertFalse(state.hasGrant)
        XCTAssertNil(state.cache.snapshot)
        state.forgetGrant()
        await state.saveGrant(access.token, connection: connection)
        XCTAssertFalse(state.hasGrant)
    }
    @MainActor
    func testPairingRemovalClearsCacheWhileOfflineKeepsOnlyItsMatchingObservation() async {
        let memory = WorklistMemoryCredentials()
        let state = WorklistState(credentials: memory, transport: transport())
        await state.saveGrant(access.token, connection: connection)
        XCTAssertTrue(state.matchesObservedPairing(endpoint: connection.endpoint, instanceID: connection.instanceID))
        await state.refresh(connection: WorklistConnection(endpoint: connection.endpoint, instanceID: connection.instanceID, readToken: nil))
        XCTAssertEqual(state.cache.availability, .offline)
        XCTAssertNotNil(state.cache.snapshot)
        XCTAssertTrue(state.cache.usingLastObservation)
        await state.refresh(connection: nil)
        XCTAssertNil(state.cache.snapshot)
        XCTAssertTrue(state.worksetIDs.isEmpty)
        XCTAssertFalse(state.hasGrant)
        XCTAssertFalse(state.matchesObservedPairing(endpoint: connection.endpoint, instanceID: connection.instanceID))
    }

    @MainActor
    func testLateProbeScopeAndSnapshotResponsesCannotRestoreAnInvalidatedPairing() async {
        for phase in ["probe", "scopes", "snapshot"] {
            let memory = WorklistMemoryCredentials()
            let state = WorklistState(credentials: memory, transport: transport())
            if phase != "probe" { await state.saveGrant(access.token, connection: connection) }
            let reply = WorklistStubProtocol.handler!
            let latch = WorklistResponseLatch()
            WorklistStubProtocol.handler = { request in
                if request.url?.path == (phase == "snapshot" ? "/v1/worksets/workset-a" : "/v1/worksets") {
                    latch.block()
                }
                return try reply(request)
            }
            let pending = Task {
                if phase == "probe" { await state.saveGrant(access.token, connection: connection) }
                else { await state.refresh(connection: connection) }
            }
            for _ in 0..<100 where !latch.started { try? await Task.sleep(for: .milliseconds(5)) }
            XCTAssertTrue(latch.started)
            await state.refresh(connection: nil)
            latch.gate.signal()
            await pending.value
            XCTAssertNil(state.cache.snapshot, phase)
            XCTAssertTrue(state.worksetIDs.isEmpty, phase)
            XCTAssertFalse(state.hasGrant, phase)
            XCTAssertFalse(state.matchesObservedPairing(endpoint: connection.endpoint, instanceID: connection.instanceID))
            if phase == "probe" { XCTAssertNil(memory.stored) }
        }
    }

    @MainActor
    func testLiveWorklistControlsRenderWithSeparateReadAccess() async {
        let memory = WorklistMemoryCredentials()
        let state = WorklistState(credentials: memory, transport: transport())
        let metadataConfig = URLSessionConfiguration.ephemeral
        metadataConfig.protocolClasses = [WorklistStubProtocol.self]
        let client = ClientState(keychain: WorklistServerCredentials(endpoint: self.access.endpoint, instance: self.access.workspaceInstanceID, tokenValue: "root-read"), transport: ServerTransport(configuration: metadataConfig))
        for _ in 0..<100 where client.savedEndpoint.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        NSApplication.shared.setActivationPolicy(.prohibited)
        func render() {
            let hosting = NSHostingView(rootView: LiveApprovedWorklistView(client: client, state: state, reviewNavigationStatus: "reviewRequired", onOpenReviews: { _ in XCTFail("Rendering must not navigate") }).environment(\.locale, Locale(identifier: "nl")))
            hosting.frame = NSRect(x: 0, y: 0, width: 640, height: 1000)
            hosting.layoutSubtreeIfNeeded()
        }
        render()
        await state.saveGrant(access.token, connection: connection)
        render()
        let original = WorklistStubProtocol.handler!
        WorklistStubProtocol.handler = { request in Thread.sleep(forTimeInterval: 0.05); return try original(request) }
        let pending = Task { await state.refresh(connection: connection) }
        await Task.yield()
        XCTAssertTrue(state.isBusy)
        render()
        await pending.value
        status = 401
        await state.refresh(connection: connection)
        render()
        state.forgetGrant()
        render()
        status = 200
        await state.saveGrant(access.token, connection: connection)
        let hosting = NSHostingView(rootView: LiveApprovedWorklistView(client: client, state: state,
            onOpenReviews: { _ in XCTFail("Lifecycle rendering cannot navigate") }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNotNil(state.cache.snapshot)
        client.forget()
        for _ in 0..<100 where !client.savedEndpoint.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        try? await Task.sleep(for: .milliseconds(20))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNil(state.cache.snapshot)
        XCTAssertTrue(state.worksetIDs.isEmpty)
        window.contentView = nil
    }
}
