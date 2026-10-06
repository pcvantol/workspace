import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class ReviewStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

private final class ReviewWireBackend: @unchecked Sendable {
    let workspaceInstance = "0123456789abcdef0123456789abcdef"
    let forgeInstance = String(repeating: "f", count: 32)
    let reviewToken = String(repeating: "R", count: 43)
    let mission = "mission-1"
    let subject = "sha256:" + String(repeating: "a", count: 64)
    let evidence = "sha256:" + String(repeating: "b", count: 64)
    let decisionDigest = "sha256:" + String(repeating: "d", count: 64)
    private let lock = NSLock()
    private var recorded: [String: Any]?
    private var posted = 0
    private var operationReads = 0
    var lostResponse = false
    var dropBeforeRecord = false
    var unavailableReadback = false
    var wrongActor = false
    var wrongDigest = false
    var postConflict = false
    var forcedReviewStatus: Int?

    var postCount: Int { lock.withLock { posted } }
    var readbackCount: Int { lock.withLock { operationReads } }

    private func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func currentItem() -> [String: Any] {
        let prior = lock.withLock { recorded }
        let requirement: [String: Any] = [
            "requirement_id": "review-1", "subject_digest": subject,
            "subject_revision": "r7", "mission_state_revision": 7,
            "completed_action_id": "action-1", "evidence_digest": evidence,
            "policy_revision": "policy-r1",
            "policy_digest": "sha256:" + String(repeating: "c", count: 64),
            "required_role": "platform_architect", "required_role_actor": "primary_operator",
            "required_capability": "ARCHITECTURE_APPROVAL", "reason": "Completed Action waits",
            "blocking_scope": ["action-1"], "blocking_scope_redacted": false,
            "status": "AWAITING_APPROVAL",
        ]
        let action: [String: Any] = [
            "action_id": "action-1", "status": "COMPLETE", "outcome": "complete",
            "evidence_reference": ["kind": "FORGE_EXECUTION_EVIDENCE", "digest": evidence,
                                   "receipt_id": "receipt-1"],
        ]
        let decision: Any = prior.map {
            ["decision_id": $0["operation_id"]!, "outcome": $0["decision"]!,
             "decision_digest": decisionDigest]
        } ?? NSNull()
        return [
            "contract_version": "forge-workspace-review-inbox/v1", "instance_id": forgeInstance,
            "mission_id": mission,
            "authority": ["principal_id": wrongActor ? "foreign" : "reviewer-alice",
                          "role": "platform_architect", "role_actor": "primary_operator",
                          "capability": "ARCHITECTURE_APPROVAL",
                          "expires_at": "2026-10-07T12:00:00Z"],
            "title": "Review Action", "lifecycle_state": "AWAITING_APPROVAL",
            "mission_state_revision": prior == nil ? 7 : 8,
            "review_kind": "PROGRESSION", "decision": decision, "requirement": requirement,
            "action_result": action,
            "allowed_outcomes": prior == nil ? ["approve", "reject", "amend", "defer"] : [],
            "observed_at": "2026-10-06T12:00:00Z",
            "freshness": "CURRENT_FORGE_RUNTIME_READBACK",
        ]
    }

    private func receipt(readOnly: Bool) -> [String: Any] {
        let request = lock.withLock { recorded! }
        var digestObject = request
        digestObject["mission_id"] = mission
        let canonical = try! JSONSerialization.data(withJSONObject: digestObject,
                                                    options: [.sortedKeys, .withoutEscapingSlashes])
        let digest = "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        let operation: [String: Any] = [
            "operation_id": request["operation_id"]!, "mission_id": mission,
            "requirement_id": request["requirement_id"]!, "subject_digest": subject,
            "decision": request["decision"]!, "decision_digest": decisionDigest,
            "request_digest": wrongDigest ? "sha256:" + String(repeating: "0", count: 64) : digest,
            "recorded_at": "2026-10-06T12:00:01Z",
        ]
        var result: [String: Any] = ["contract_version": "forge-workspace-review-operation/v1",
                                     "operation": operation, "current": currentItem()]
        if readOnly {
            result["read_only"] = true
        } else {
            result["runtime_status"] = "AWAITING_APPROVAL"
            result["recorded"] = true
        }
        return result
    }

    func handle(_ request: URLRequest) throws -> (Int, Data) {
        let path = request.url!.path
        if path == "/v1/identity" {
            return (200, json(["instance_id": workspaceInstance]))
        }
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer workspace-read" else {
            return (401, json(["error": "UNAUTHORIZED"]))
        }
        guard request.value(forHTTPHeaderField: "X-Workspace-Instance") == workspaceInstance else {
            return (409, json(["error": "WRONG_INSTANCE"]))
        }
        switch path {
        case "/v1/status":
            return (200, json(["instance_id": workspaceInstance, "version": "2.8.5",
                               "state": "READY", "project_source": "UNCONFIGURED"]))
        case "/v1/projects":
            return (200, json(["state": "UNCONFIGURED", "projects": [], "source": NSNull(),
                               "partial": false, "stale": false]))
        case "/v1/capabilities":
            return (503, json(["error": "SOURCE_UNAVAILABLE"]))
        case "/v1/forge/status":
            return (503, json(["error": "SOURCE_UNAVAILABLE"]))
        default: break
        }
        guard request.value(forHTTPHeaderField: "X-Workspace-Review-Grant") == reviewToken else {
            return (403, json(["error": "REVIEW_GRANT_REQUIRED"]))
        }
        if let forcedReviewStatus { return (forcedReviewStatus, json(["error": "FORCED_TEST_STATUS"])) }
        if path == "/v1/reviews" {
            return (200, json(["contract_version": "forge-workspace-review-inbox/v1",
                               "instance_id": forgeInstance,
                               "scope": ["kind": "EXPLICIT_MISSION_SET",
                                         "principal_id": "reviewer-alice", "mission_ids": [mission],
                                         "complete_within_scope": true],
                               "items": [currentItem()], "read_only": true]))
        }
        if path == "/v1/reviews/missions/\(mission)" {
            return (200, json(currentItem()))
        }
        let decisions = "/v1/reviews/missions/\(mission)/decisions"
        if path == decisions && request.httpMethod == "POST" {
            if postConflict { return (409, json(["error": "REVIEW_CONFLICT"])) }
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(buffer, count: count)
                }
            }
            guard let parsed = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return (400, json(["error": "INVALID_BODY"]))
            }
            if dropBeforeRecord { throw URLError(.networkConnectionLost) }
            lock.withLock { posted += 1; recorded = parsed }
            if lostResponse { throw URLError(.networkConnectionLost) }
            return (201, json(receipt(readOnly: false)))
        }
        if path.hasPrefix(decisions + "/") {
            lock.withLock { operationReads += 1 }
            if unavailableReadback { return (503, json(["error": "REVIEW_UNAVAILABLE"])) }
            guard let saved = lock.withLock({ recorded }),
                  path == decisions + "/" + (saved["operation_id"] as! String) else {
                return (404, json(["error": "REVIEW_NOT_FOUND"]))
            }
            return (200, json(receipt(readOnly: true)))
        }
        return (404, json(["error": "NOT_FOUND"]))
    }
}

private final class ReviewMemoryStore: ReviewCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var access: ReviewAccess?
    private var intent: MissionReviewIntent?
    var failIntentSave = false

    func loadAccess() throws -> ReviewAccess? { lock.withLock { access } }
    func saveAccess(_ value: ReviewAccess) throws { lock.withLock { access = value } }
    func forgetAccess() throws { lock.withLock { access = nil } }
    func loadIntent() throws -> MissionReviewIntent? { lock.withLock { intent } }
    func saveIntent(_ value: MissionReviewIntent) throws {
        if failIntentSave { throw CredentialError.corruptBinding }
        lock.withLock { intent = value }
    }
    func forgetIntent() throws { lock.withLock { intent = nil } }
}

private final class ReviewKeychainBackend: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Data] = [:]
    var copyFailure: OSStatus?
    var updateFailure: OSStatus?
    var deleteFailure: OSStatus?

    var operations: DraftKeychainOperations {
        DraftKeychainOperations(
            copy: { query in self.lock.withLock {
                if let failure = self.copyFailure { return (failure, nil) }
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
            } })
    }

    func corrupt(_ account: String) { lock.withLock { stored[account] = Data("invalid".utf8) } }
}

final class MissionReviewTransportTests: XCTestCase {
    private let address = "http://127.0.0.1:8765/"

    private func configuration(_ backend: ReviewWireBackend) -> URLSessionConfiguration {
        ReviewStubProtocol.handler = { try backend.handle($0) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewStubProtocol.self]
        return config
    }

    @MainActor
    private func renderReview(_ view: LiveMissionReviewsView) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let hosting = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "nl")))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 1300)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.frame.width, 900)
    }

    @MainActor
    private func client(_ backend: ReviewWireBackend,
                        configuration: URLSessionConfiguration) async -> ClientState {
        let credentials = IsolatedReviewServerCredentials(endpoint: address,
                                                           instance: backend.workspaceInstance)
        let state = ClientState(keychain: credentials,
                                transport: ServerTransport(configuration: configuration))
        for _ in 0..<100 where state.phase != "CONNECTED" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(state.phase, "CONNECTED")
        return state
    }

    func testExactForgeDigestWithUnicodeReason() throws {
        let intent = MissionReviewIntent(
            operationID: UUID(uuidString: "dff33888-f15e-43fa-b15b-3a486b7494cd")!,
            key: MissionReviewKey(missionID: "mission-1", requirementID: "review-1"),
            subjectID: "action-1", subjectRevision: "r7", outcome: .deferred,
            comment: "Contrôle résumé", forgeInstanceID: "forge-1", actorID: "reviewer-alice",
            subjectDigest: "sha256:" + String(repeating: "a", count: 64),
            missionStateRevision: 7,
            evidenceDigest: "sha256:" + String(repeating: "b", count: 64),
            policyRevision: "policy-r1")
        XCTAssertEqual(try ForgeReviewDecisionRequest(intent).requestDigest(missionID: "mission-1"),
                       "sha256:d5ae5130c73e0ab48edfd871d6749f455ebad58f34c765edcf792acce87535fe")
    }

    func testReviewKeychainSeparatesGrantAndPendingIntentAndRejectsCorruption() throws {
        let backend = ReviewKeychainBackend()
        let keychain = ReviewKeychain(operations: backend.operations)
        XCTAssertNil(try keychain.loadAccess())
        XCTAssertNil(try keychain.loadIntent())
        let access = ReviewAccess(endpoint: "http://127.0.0.1:8765/",
                                  workspaceInstanceID: "0123456789abcdef0123456789abcdef",
                                  forgeInstanceID: "forge-a", actorID: "actor-a",
                                  missionIDs: ["mission-1"], token: String(repeating: "R", count: 43))
        let intent = MissionReviewIntent(
            operationID: UUID(), key: MissionReviewKey(missionID: "mission-1", requirementID: "review-1"),
            subjectID: "action-1", subjectRevision: "r1", outcome: .approve,
            comment: "Reviewed", forgeInstanceID: "forge-a", actorID: "actor-a",
            subjectDigest: "sha256:" + String(repeating: "a", count: 64),
            missionStateRevision: 1, evidenceDigest: "sha256:" + String(repeating: "b", count: 64),
            policyRevision: "policy-r1")
        try keychain.saveAccess(access)
        try keychain.saveIntent(intent)
        XCTAssertEqual(try keychain.loadAccess(), access)
        XCTAssertEqual(try keychain.loadIntent(), intent)
        try keychain.saveAccess(access)
        try keychain.saveIntent(intent)
        try keychain.forgetAccess()
        XCTAssertEqual(try keychain.loadIntent(), intent)
        try keychain.forgetIntent()
        try keychain.forgetIntent()
        backend.corrupt("actor-grant")
        XCTAssertThrowsError(try keychain.loadAccess())
        backend.corrupt("pending-intent")
        XCTAssertThrowsError(try keychain.loadIntent())
        backend.copyFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.loadAccess())
        backend.copyFailure = nil
        backend.updateFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.saveAccess(access))
        backend.updateFailure = nil
        backend.deleteFailure = errSecAuthFailed
        XCTAssertThrowsError(try keychain.forgetIntent())
    }

    func testReviewTransportRejectsDeniedAndMalformedReplies() async throws {
        let backend = ReviewWireBackend()
        let transport = MissionReviewTransport(configuration: configuration(backend))
        let endpoint = try ServerEndpoint(address)
        for (code, expected) in [(401, ReviewTransportError.unauthorized),
                                 (403, .denied), (404, .missing), (409, .conflict),
                                 (503, .unavailable)] {
            backend.forcedReviewStatus = code
            do {
                _ = try await transport.probe(endpoint: endpoint, workspaceToken: "workspace-read",
                                              instance: backend.workspaceInstance,
                                              reviewToken: backend.reviewToken)
                XCTFail("Accepted HTTP status \(code)")
            } catch let error as ReviewTransportError {
                XCTAssertEqual(error, expected)
            }
        }
        backend.forcedReviewStatus = nil
        let (access, rows) = try await transport.probe(
            endpoint: endpoint, workspaceToken: "workspace-read", instance: backend.workspaceInstance,
            reviewToken: backend.reviewToken)
        XCTAssertEqual(rows.count, 1)
        let invalid = ReviewAccess(endpoint: access.endpoint, workspaceInstanceID: access.workspaceInstanceID,
                                   forgeInstanceID: access.forgeInstanceID, actorID: "foreign",
                                   missionIDs: access.missionIDs, token: access.token)
        do {
            _ = try await transport.list(access: invalid, workspaceToken: "workspace-read")
            XCTFail("Accepted actor mismatch")
        } catch ReviewTransportError.invalidResponse {}
    }

    func testScopedTransportHeadersAndReceiptValidation() async throws {
        let backend = ReviewWireBackend()
        let transport = MissionReviewTransport(configuration: configuration(backend))
        let endpoint = try ServerEndpoint(address)
        let (access, rows) = try await transport.probe(
            endpoint: endpoint, workspaceToken: "workspace-read", instance: backend.workspaceInstance,
            reviewToken: backend.reviewToken)
        XCTAssertEqual(access.actorID, "reviewer-alice")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].key.requirementID, "review-1")
        XCTAssertEqual(rows[0].evidence.count, 2)
        let listed = try await transport.list(access: access, workspaceToken: "workspace-read")
        XCTAssertEqual(listed, rows)
        let detailed = try await transport.detail(access: access, workspaceToken: "workspace-read",
                                                  missionID: backend.mission)
        XCTAssertEqual(detailed, rows[0])
        let intent = MissionReviewIntent(
            operationID: UUID(uuidString: "dff33888-f15e-43fa-b15b-3a486b7494cd")!,
            key: rows[0].key, subjectID: rows[0].subjectID,
            subjectRevision: rows[0].subjectRevision, outcome: .deferred,
            comment: "Exact Action reviewed", forgeInstanceID: access.forgeInstanceID,
            actorID: access.actorID,
            subjectDigest: rows[0].subjectDigest, missionStateRevision: rows[0].missionStateRevision,
            evidenceDigest: rows[0].evidenceDigest, policyRevision: rows[0].policyRevision)
        let result = try await transport.submit(access: access, workspaceToken: "workspace-read", intent: intent)
        XCTAssertEqual(result.operation.operation_id, intent.operationID.uuidString.lowercased())
        XCTAssertEqual(backend.postCount, 1)
        let readback = try await transport.readback(access: access,
                                                    workspaceToken: "workspace-read", intent: intent)
        XCTAssertEqual(readback.operation.request_digest, result.operation.request_digest)
        XCTAssertTrue(readback.current.allowed_outcomes.isEmpty)
        backend.wrongDigest = true
        do {
            _ = try await transport.readback(access: access, workspaceToken: "workspace-read",
                                             intent: intent)
            XCTFail("Tampered receipt was accepted")
        } catch ReviewTransportError.invalidResponse {}
        backend.wrongDigest = false
        backend.wrongActor = true
        do {
            _ = try await transport.list(access: access, workspaceToken: "workspace-read")
            XCTFail("Foreign actor was accepted")
        } catch ReviewTransportError.invalidResponse {}
        do {
            _ = try await transport.detail(access: access, workspaceToken: "workspace-read",
                                           missionID: "foreign-mission")
            XCTFail("Foreign Mission was requested")
        } catch ReviewTransportError.denied {}
    }

    @MainActor
    func testNativeDecisionAndLostResponseRecoverTheSameOperation() async throws {
        let backend = ReviewWireBackend()
        backend.lostResponse = true
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let state = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant(backend.reviewToken, client: client)
        XCTAssertEqual(state.actorID, "reviewer-alice")
        XCTAssertEqual(state.items.count, 1)
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .deferred, reason: "Wait for exact evidence", client: client)
        XCTAssertEqual(backend.postCount, 1)
        XCTAssertGreaterThanOrEqual(backend.readbackCount, 1)
        XCTAssertNil(state.pendingIntent)
        XCTAssertEqual(state.statusKey, "recordedNotice")
        XCTAssertNil(try memory.loadIntent())
        await state.refresh(client: client)
        XCTAssertEqual(state.items.first?.phase, .decisionRecorded)
    }

    @MainActor
    func testRestartReadsPendingBeforeAnyRetry() async throws {
        let backend = ReviewWireBackend()
        backend.lostResponse = true
        backend.unavailableReadback = true
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let first = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await first.saveGrant(backend.reviewToken, client: client)
        let row = try XCTUnwrap(first.items.first)
        await first.decide(row, outcome: .reject, reason: "Evidence mismatch", client: client)
        XCTAssertEqual(backend.postCount, 1)
        XCTAssertNotNil(first.pendingIntent)
        XCTAssertNotNil(try memory.loadIntent())
        backend.unavailableReadback = false
        let restarted = MissionReviewState(credentials: memory,
                                           transport: MissionReviewTransport(configuration: config))
        await restarted.refresh(client: client)
        XCTAssertNil(restarted.pendingIntent)
        XCTAssertEqual(backend.postCount, 1)
        XCTAssertNil(try memory.loadIntent())
    }

    @MainActor
    func testNoReceiptOffersOnlyExplicitSameOperationRetry() async throws {
        let backend = ReviewWireBackend()
        backend.dropBeforeRecord = true
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let state = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant(backend.reviewToken, client: client)
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .amend, reason: "Revise Action evidence", client: client)
        XCTAssertEqual(backend.postCount, 0)
        XCTAssertTrue(state.canRetrySameOperation)
        let same = try XCTUnwrap(state.pendingIntent?.operationID)
        backend.dropBeforeRecord = false
        await state.retrySameOperation(client: client)
        XCTAssertEqual(backend.postCount, 1)
        XCTAssertNil(state.pendingIntent)
        XCTAssertEqual(try memory.loadIntent(), nil)
        XCTAssertFalse(state.canRetrySameOperation)
        XCTAssertNotNil(same)
    }

    @MainActor
    func testConflictReadsSameOperationAndReleasesUnrecordedIntent() async throws {
        let backend = ReviewWireBackend()
        backend.postConflict = true
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let state = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant(backend.reviewToken, client: client)
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .approve, reason: "Reviewed evidence", client: client)
        XCTAssertEqual(backend.postCount, 0)
        XCTAssertEqual(backend.readbackCount, 1)
        XCTAssertNil(state.pendingIntent)
        XCTAssertNil(try memory.loadIntent())
        XCTAssertFalse(state.canRetrySameOperation)
        XCTAssertEqual(state.statusKey, "decisionConflict")
    }

    @MainActor
    func testFailedPersistenceAndGrantRotationNeverSendDecision() async throws {
        let backend = ReviewWireBackend()
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let state = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant("invalid", client: client)
        XCTAssertEqual(state.access, .denied)
        await state.saveGrant(backend.reviewToken, client: client)
        XCTAssertEqual(state.access, .available)
        memory.failIntentSave = true
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .reject, reason: "Evidence mismatch", client: client)
        XCTAssertEqual(backend.postCount, 0)
        XCTAssertNil(state.pendingIntent)
        XCTAssertNil(try memory.loadIntent())
        memory.failIntentSave = false
        state.forgetGrant()
        XCTAssertEqual(state.access, .unavailable)
        XCTAssertNil(try memory.loadAccess())
    }

    @MainActor
    func testPendingBlocksGrantDeletionAndNewDecisionUntilReadback() async throws {
        let backend = ReviewWireBackend()
        backend.lostResponse = true
        backend.unavailableReadback = true
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let memory = ReviewMemoryStore()
        let state = MissionReviewState(credentials: memory,
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant(backend.reviewToken, client: client)
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .deferred, reason: "Need more evidence", client: client)
        XCTAssertNotNil(state.pendingIntent)
        state.forgetGrant()
        XCTAssertNotNil(try memory.loadAccess())
        await state.decide(row, outcome: .approve, reason: "Different decision", client: client)
        XCTAssertEqual(backend.postCount, 1)
        backend.unavailableReadback = false
        await state.readPending(client: client)
        XCTAssertNil(state.pendingIntent)
        XCTAssertEqual(state.statusKey, "recordedNotice")
    }

    @MainActor
    func testLiveViewRendersGrantDecisionAndRecoveryControls() async throws {
        let backend = ReviewWireBackend()
        let config = configuration(backend)
        let client = await client(backend, configuration: config)
        let denied = MissionReviewState(credentials: ReviewMemoryStore(),
                                        transport: MissionReviewTransport(configuration: config))
        await denied.saveGrant("invalid", client: client)
        renderReview(LiveMissionReviewsView(client: client, state: denied))

        let state = MissionReviewState(credentials: ReviewMemoryStore(),
                                       transport: MissionReviewTransport(configuration: config))
        await state.saveGrant(backend.reviewToken, client: client)
        renderReview(LiveMissionReviewsView(client: client, state: state))
        backend.lostResponse = true
        backend.unavailableReadback = true
        let row = try XCTUnwrap(state.items.first)
        await state.decide(row, outcome: .approve, reason: "Reviewed", client: client)
        XCTAssertNotNil(state.pendingIntent)
        renderReview(LiveMissionReviewsView(client: client, state: state))
    }
}

private final class IsolatedReviewServerCredentials: CredentialStore, @unchecked Sendable {
    private let endpoint: String
    private let instance: String
    init(endpoint: String, instance: String) { self.endpoint = endpoint; self.instance = instance }
    func binding() throws -> ServerBinding? { ServerBinding(endpoint: endpoint, instanceID: instance) }
    func token() throws -> String? { "workspace-read" }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws {}
}
