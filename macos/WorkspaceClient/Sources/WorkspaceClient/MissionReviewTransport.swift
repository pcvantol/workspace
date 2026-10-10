import CryptoKit
import Foundation
import Security

struct ReviewAccess: Codable, Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let forgeInstanceID: String
    let actorID: String
    let missionIDs: [String]
    let token: String
}

protocol ReviewCredentialStore: Sendable {
    func loadAccess() throws -> ReviewAccess?
    func saveAccess(_ access: ReviewAccess) throws
    func forgetAccess() throws
    func loadIntent() throws -> MissionReviewIntent?
    func saveIntent(_ intent: MissionReviewIntent) throws
    func forgetIntent() throws
}

struct ReviewKeychain: ReviewCredentialStore {
    private let service = "com.pcvantol.workspace.native-client.reviews.v1"
    private let operations: DraftKeychainOperations

    init(operations: DraftKeychainOperations = .live) { self.operations = operations }

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }

    private func load(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(request as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        return data
    }

    private func save(_ data: Data, account: String) throws {
        let request = query(account)
        let status = operations.update(request as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var item = request
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = operations.add(item as CFDictionary)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

    private func forget(_ account: String) throws {
        let status = operations.delete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }

    func loadAccess() throws -> ReviewAccess? {
        guard let data = try load("actor-grant") else { return nil }
        guard let access = try? JSONDecoder().decode(ReviewAccess.self, from: data),
              access.token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              access.workspaceInstanceID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              !access.forgeInstanceID.isEmpty, !access.actorID.isEmpty,
              (try? ServerEndpoint(access.endpoint))?.url.absoluteString == access.endpoint else {
            throw CredentialError.corruptBinding
        }
        return access
    }

    func saveAccess(_ access: ReviewAccess) throws {
        try save(JSONEncoder().encode(access), account: "actor-grant")
    }

    func forgetAccess() throws { try forget("actor-grant") }

    func loadIntent() throws -> MissionReviewIntent? {
        guard let data = try load("pending-intent") else { return nil }
        guard let intent = try? JSONDecoder().decode(MissionReviewIntent.self, from: data),
              !intent.forgeInstanceID.isEmpty, !intent.actorID.isEmpty, !intent.subjectDigest.isEmpty,
              intent.missionStateRevision > 0, !intent.comment.isEmpty else {
            throw CredentialError.corruptBinding
        }
        return intent
    }

    func saveIntent(_ intent: MissionReviewIntent) throws {
        try save(JSONEncoder().encode(intent), account: "pending-intent")
    }

    func forgetIntent() throws { try forget("pending-intent") }
}

struct ForgeReviewAuthority: Decodable, Sendable {
    let principal_id: String
    let role: String
    let role_actor: String
    let capability: String
    let expires_at: String
}

struct ForgeReviewRequirement: Decodable, Sendable {
    let requirement_id: String
    let subject_digest: String
    let subject_revision: String?
    let mission_state_revision: Int
    let completed_action_id: String?
    let evidence_digest: String?
    let policy_revision: String?
    let policy_digest: String?
    let required_role: String
    let required_role_actor: String?
    let required_capability: String
    let reason: String?
    let blocking_scope: [String]
    let blocking_scope_redacted: Bool
    let status: String?
}

struct ForgeReviewDecision: Decodable, Sendable {
    let decision_id: String?
    let outcome: String
    let decision_digest: String
}

struct ForgeReviewEvidence: Decodable, Sendable {
    let kind: String
    let digest: String
    let receipt_id: String?
}

struct ForgeReviewAction: Decodable, Sendable {
    let action_id: String
    let status: String?
    let outcome: String?
    let evidence_reference: ForgeReviewEvidence?
}

struct ForgeReviewItem: Decodable, Sendable {
    let contract_version: String
    let instance_id: String
    let mission_id: String
    let authority: ForgeReviewAuthority
    let title: String?
    let lifecycle_state: String
    let mission_state_revision: Int
    let review_kind: String
    let decision: ForgeReviewDecision?
    let requirement: ForgeReviewRequirement?
    let action_result: ForgeReviewAction?
    let allowed_outcomes: [String]
    let observed_at: String
    let freshness: String

    private func validObservedTime() -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: observed_at) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: observed_at) != nil
    }

    func valid(for access: ReviewAccess) -> Bool {
        guard contract_version == "forge-workspace-review-inbox/v1",
              instance_id == access.forgeInstanceID, access.missionIDs.contains(mission_id),
              authority.principal_id == access.actorID,
              authority.role == "platform_architect", authority.role_actor == "primary_operator",
              authority.capability == "ARCHITECTURE_APPROVAL",
              freshness == "CURRENT_FORGE_RUNTIME_READBACK", mission_state_revision > 0,
              validObservedTime(),
              Set(allowed_outcomes).count == allowed_outcomes.count,
              allowed_outcomes.allSatisfy({ MissionReviewOutcome(rawValue: $0) != nil }) else { return false }
        if !allowed_outcomes.isEmpty {
            guard review_kind == "PROGRESSION", lifecycle_state == "AWAITING_APPROVAL",
                  decision == nil, let requirement,
                  requirement.mission_state_revision > 0,
                  requirement.mission_state_revision <= mission_state_revision,
                  requirement.evidence_digest?.hasPrefix("sha256:") == true,
                  requirement.policy_revision?.isEmpty == false,
                  requirement.required_role == authority.role,
                  requirement.required_role_actor == authority.role_actor,
                  requirement.required_capability == authority.capability else { return false }
        }
        if review_kind != "PROGRESSION" && !allowed_outcomes.isEmpty { return false }
        if ["NONE", "EXTERNAL_GATE"].contains(review_kind) && requirement != nil { return false }
        return ["PROGRESSION", "FINAL_ACCEPTANCE", "EXTERNAL_GATE", "NONE"].contains(review_kind)
    }

    func displayItem() -> MissionReviewItem {
        let requirementID = requirement?.requirement_id ?? ""
        let phase: MissionReviewPhase = switch review_kind {
        case "FINAL_ACCEPTANCE": .finalAcceptance
        case "PROGRESSION" where decision != nil: .decisionRecorded
        case "PROGRESSION": .waitingForReview
        case "NONE": .noReview
        case "EXTERNAL_GATE": .externalGate
        default: .unknown
        }
        var references: [MissionEvidenceReference] = []
        if let evidence = action_result?.evidence_reference {
            references.append(.init(kind: .actionResult, identifier: evidence.digest))
            if let receipt = evidence.receipt_id {
                references.append(.init(kind: .forgeReceipt, identifier: receipt))
            }
        }
        let actionText = [action_result?.status, action_result?.outcome]
            .compactMap { $0 }.joined(separator: " · ")
        return MissionReviewItem(
            key: .init(missionID: mission_id, requirementID: requirementID),
            subjectID: requirement?.completed_action_id ?? requirement?.subject_digest ?? "",
            subjectRevision: requirement?.subject_revision ?? "",
            projectID: nil, title: title,
            actionResult: actionText.isEmpty ? nil : actionText,
            waitingReason: requirement?.reason,
            phase: phase, authority: review_kind == "PROGRESSION" ? .forge : .external,
            freshness: freshness == "CURRENT_FORGE_RUNTIME_READBACK" ? .current : .unavailable,
            allowedOutcomes: Set(allowed_outcomes.compactMap(MissionReviewOutcome.init(rawValue:))),
            requiredRole: requirement?.required_role,
            blockingScope: requirement?.blocking_scope.joined(separator: " · "),
            policySource: requirement?.policy_revision,
            evidence: references, observedAt: observed_at,
            forgeInstanceID: instance_id, actorID: authority.principal_id,
            subjectDigest: requirement?.subject_digest ?? "",
            missionStateRevision: requirement?.mission_state_revision ?? mission_state_revision,
            currentMissionRevision: mission_state_revision,
            evidenceDigest: requirement?.evidence_digest ?? "",
            policyRevision: requirement?.policy_revision ?? "",
            lifecycleState: lifecycle_state, decisionID: decision?.decision_id,
            decisionDigest: decision?.decision_digest,
            decisionOutcome: decision.flatMap { MissionReviewOutcome(rawValue: $0.outcome) })
    }
}

struct ForgeReviewScope: Decodable, Sendable {
    let kind: String
    let principal_id: String
    let mission_ids: [String]
    let complete_within_scope: Bool
}

struct ForgeReviewInbox: Decodable, Sendable {
    let contract_version: String
    let instance_id: String
    let scope: ForgeReviewScope
    let items: [ForgeReviewItem]
    let read_only: Bool

    func valid(for access: ReviewAccess) -> Bool {
        contract_version == "forge-workspace-review-inbox/v1" && instance_id == access.forgeInstanceID &&
        scope.kind == "EXPLICIT_MISSION_SET" && scope.principal_id == access.actorID &&
        scope.complete_within_scope && read_only &&
        Set(scope.mission_ids) == Set(access.missionIDs) && scope.mission_ids.count == access.missionIDs.count &&
        items.count == access.missionIDs.count &&
        Set(items.map(\.mission_id)) == Set(access.missionIDs) &&
        items.allSatisfy { $0.valid(for: access) }
    }
}

struct ForgeReviewOperation: Decodable, Sendable {
    let operation_id: String
    let mission_id: String
    let requirement_id: String
    let subject_digest: String
    let decision: String
    let decision_digest: String
    let request_digest: String
    let recorded_at: String
}

struct ForgeReviewOperationResponse: Decodable, Sendable {
    let contract_version: String
    let operation: ForgeReviewOperation
    let current: ForgeReviewItem
    let read_only: Bool?
    let recorded: Bool?
    let runtime_status: String?

    func valid(for access: ReviewAccess, intent: MissionReviewIntent, isReadback: Bool) -> Bool {
        guard let expectedDigest = try? ForgeReviewDecisionRequest(intent).requestDigest(
            missionID: intent.key.missionID) else { return false }
        return contract_version == "forge-workspace-review-operation/v1" &&
        access.actorID == intent.actorID &&
        matchesOperation(intent, expectedDigest: expectedDigest) &&
        current.mission_id == intent.key.missionID && current.valid(for: access) &&
        current.mission_state_revision >= intent.missionStateRevision &&
        (isReadback ? read_only == true : recorded != nil)
    }
    private func matchesOperation(_ intent: MissionReviewIntent, expectedDigest: String) -> Bool {
        operation.operation_id == intent.operationID.uuidString.lowercased() &&
        operation.mission_id == intent.key.missionID &&
        operation.requirement_id == intent.key.requirementID &&
        operation.subject_digest == intent.subjectDigest &&
        operation.decision == intent.outcome.rawValue &&
        operation.request_digest == expectedDigest
    }

}

struct ForgeReviewDecisionRequest: Encodable, Sendable {
    let contract_version = "forge-workspace-review-decision/v1"
    let operation_id: String
    let requirement_id: String
    let subject_digest: String
    let mission_state_revision: Int
    let evidence_digest: String
    let policy_revision: String
    let decision: String
    let reason: String

    init(_ intent: MissionReviewIntent) {
        operation_id = intent.operationID.uuidString.lowercased()
        requirement_id = intent.key.requirementID
        subject_digest = intent.subjectDigest
        mission_state_revision = intent.missionStateRevision
        evidence_digest = intent.evidenceDigest
        policy_revision = intent.policyRevision
        decision = intent.outcome.rawValue
        reason = intent.comment
    }

    func requestDigest(missionID: String) throws -> String {
        let encoded = try JSONEncoder().encode(self)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw ReviewTransportError.invalidResponse
        }
        object["mission_id"] = missionID
        let canonical = try JSONSerialization.data(withJSONObject: object,
                                                    options: [.sortedKeys, .withoutEscapingSlashes])
        return "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
}

enum ReviewTransportError: Error, LocalizedError, Equatable {
    case unavailable, unauthorized, denied, missing, conflict, invalidResponse, wrongInstance

    var errorDescription: String? {
        switch self {
        case .unavailable: "Review state is unavailable. Read the same operation before retrying."
        case .unauthorized: "The Server or Forge review credential was rejected."
        case .denied: "This actor has no access to that Mission review."
        case .missing: "Forge has no receipt for this operation yet."
        case .conflict: "The Mission or review changed, or this operation ID has a different request."
        case .invalidResponse: "The review response failed exact scope or receipt validation."
        case .wrongInstance: "The Workspace Server binding changed."
        }
    }
}

struct MissionReviewTransport: Sendable {
    let session: URLSession

    init(configuration supplied: URLSessionConfiguration? = nil) {
        let configuration = supplied ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    private func request<T: Decodable>(_ type: T.Type, endpoint: ServerEndpoint,
                                       workspaceToken: String, instance: String,
                                       reviewToken: String, path: String, body: Data? = nil) async throws -> T {
        var request = URLRequest(url: endpoint.route(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(workspaceToken)", forHTTPHeaderField: "Authorization")
        request.setValue(instance, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(reviewToken, forHTTPHeaderField: "X-Workspace-Review-Grant")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ReviewTransportError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ReviewTransportError.invalidResponse }
        switch http.statusCode {
        case 200, 201: break
        case 401: throw ReviewTransportError.unauthorized
        case 403: throw ReviewTransportError.denied
        case 404: throw ReviewTransportError.missing
        case 409: throw ReviewTransportError.conflict
        default: throw ReviewTransportError.unavailable
        }
        guard data.count <= 256_000,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw ReviewTransportError.invalidResponse
        }
        return decoded
    }

    func probe(endpoint: ServerEndpoint, workspaceToken: String, instance: String,
               reviewToken: String) async throws -> (ReviewAccess, [MissionReviewItem]) {
        let inbox = try await request(ForgeReviewInbox.self, endpoint: endpoint,
                                      workspaceToken: workspaceToken, instance: instance,
                                      reviewToken: reviewToken, path: "/v1/reviews")
        let access = ReviewAccess(endpoint: endpoint.url.absoluteString, workspaceInstanceID: instance,
                                  forgeInstanceID: inbox.instance_id, actorID: inbox.scope.principal_id,
                                  missionIDs: inbox.scope.mission_ids, token: reviewToken)
        guard access.missionIDs.count >= 1, access.missionIDs.count <= 32,
              inbox.valid(for: access) else { throw ReviewTransportError.invalidResponse }
        return (access, inbox.items.map { $0.displayItem() })
    }

    func list(access: ReviewAccess, workspaceToken: String) async throws -> [MissionReviewItem] {
        let endpoint = try ServerEndpoint(access.endpoint)
        let inbox = try await request(ForgeReviewInbox.self, endpoint: endpoint,
                                      workspaceToken: workspaceToken,
                                      instance: access.workspaceInstanceID,
                                      reviewToken: access.token, path: "/v1/reviews")
        guard inbox.valid(for: access) else { throw ReviewTransportError.invalidResponse }
        return inbox.items.map { $0.displayItem() }
    }

    func detail(access: ReviewAccess, workspaceToken: String,
                missionID: String) async throws -> MissionReviewItem {
        guard access.missionIDs.contains(missionID) else { throw ReviewTransportError.denied }
        let endpoint = try ServerEndpoint(access.endpoint)
        let value = try await request(ForgeReviewItem.self, endpoint: endpoint,
                                      workspaceToken: workspaceToken,
                                      instance: access.workspaceInstanceID,
                                      reviewToken: access.token,
                                      path: "/v1/reviews/missions/\(missionID)")
        guard value.valid(for: access), value.mission_id == missionID else {
            throw ReviewTransportError.invalidResponse
        }
        return value.displayItem()
    }

    func submit(access: ReviewAccess, workspaceToken: String,
                intent: MissionReviewIntent) async throws -> ForgeReviewOperationResponse {
        guard access.forgeInstanceID == intent.forgeInstanceID,
              access.actorID == intent.actorID,
              access.missionIDs.contains(intent.key.missionID) else { throw ReviewTransportError.denied }
        let endpoint = try ServerEndpoint(access.endpoint)
        let body = try JSONEncoder().encode(ForgeReviewDecisionRequest(intent))
        let response = try await request(ForgeReviewOperationResponse.self, endpoint: endpoint,
                                         workspaceToken: workspaceToken,
                                         instance: access.workspaceInstanceID,
                                         reviewToken: access.token,
                                         path: "/v1/reviews/missions/\(intent.key.missionID)/decisions",
                                         body: body)
        guard response.valid(for: access, intent: intent, isReadback: false) else {
            throw ReviewTransportError.invalidResponse
        }
        return response
    }

    func readback(access: ReviewAccess, workspaceToken: String,
                  intent: MissionReviewIntent) async throws -> ForgeReviewOperationResponse {
        guard access.forgeInstanceID == intent.forgeInstanceID,
              access.actorID == intent.actorID,
              access.missionIDs.contains(intent.key.missionID) else { throw ReviewTransportError.denied }
        let endpoint = try ServerEndpoint(access.endpoint)
        let path = "/v1/reviews/missions/\(intent.key.missionID)/decisions/\(intent.operationID.uuidString.lowercased())"
        let response = try await request(ForgeReviewOperationResponse.self, endpoint: endpoint,
                                         workspaceToken: workspaceToken,
                                         instance: access.workspaceInstanceID,
                                         reviewToken: access.token, path: path)
        guard response.valid(for: access, intent: intent, isReadback: true) else {
            throw ReviewTransportError.invalidResponse
        }
        return response
    }
}
