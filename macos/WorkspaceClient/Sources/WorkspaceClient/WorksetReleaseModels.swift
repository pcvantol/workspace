import Foundation
import CryptoKit

struct WorksetReleaseSubject: Codable, Equatable, Hashable, Sendable {
    let candidate_id: String
    let subject_revision: String
    var valid: Bool { WorklistWire.identifier(candidate_id) && WorklistWire.digest(subject_revision) }
}
struct WorksetReleaseSelection: Codable, Equatable, Sendable {
    let contract_version: String
    let subjects: [WorksetReleaseSubject]
    let expires_at: String
    let maximum_activations: Int
    let progression_mode: String
}
struct WorksetReleaseCapability: Codable, Equatable, Sendable {
    struct Limits: Codable, Equatable, Sendable { let maximum_releases: Int; let maximum_activations: Int }
    let contract_version: String
    let scope: AdvisoryScope
    let principal_id: String
    let permissions: [String]
    let subjects: [WorksetReleaseSubject]
    let limits: Limits
    let expires_at: String
    let release_supported: Bool
    let disarm_supported: Bool
    let read_only: Bool
    let additional_model_calls: Int
}
struct WorksetReleaseCommand: Codable, Equatable, Sendable {
    let contract_version: String
    let operation_id: String
    let intent: String
    let selection: WorksetReleaseSelection
    let package_digest: String
    let confirm: Bool
    let expected_revision: Int?
    func data() throws -> Data {
        guard (intent == "release" && expected_revision == nil) ||
              (intent == "disarm" && (expected_revision ?? 0) >= 1) else { throw AdvisoryError.invalid }
        let raw: [String: Any] = ["contract_version": contract_version, "operation_id": operation_id,
            "intent": intent, "selection": try JSONSerialization.jsonObject(with: JSONEncoder().encode(selection)),
            "package_digest": package_digest, "confirm": confirm, "expected_revision": expected_revision as Any? ?? NSNull()]
        try WorksetReleaseWire.validate(raw, kind: "request")
        return try JSONSerialization.data(withJSONObject: raw)
    }
}
struct WorksetReleaseAccess: Codable, Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let workspaceProjectID: String
    let actorID: String
    let forgeInstanceID: String
    let forgeProjectID: String
    let repositoryID: String
    let subjects: [WorksetReleaseSubject]
    let token: String
    var valid: Bool {
        (try? ServerEndpoint(endpoint))?.url.absoluteString == endpoint &&
        workspaceInstanceID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil &&
        [workspaceProjectID, actorID, forgeInstanceID, forgeProjectID, repositoryID].allSatisfy(WorklistWire.identifier) &&
        (1...16).contains(subjects.count) && subjects.allSatisfy(\.valid) &&
        Set(subjects.map(\.candidate_id)).count == subjects.count &&
        token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil
    }
    func matches(_ connection: AdvisoryConnection) -> Bool {
        valid && endpoint == connection.endpoint && workspaceInstanceID == connection.workspaceInstanceID &&
        workspaceProjectID == connection.workspaceProjectID && actorID == connection.actorID
    }
    var fingerprint: String { SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined() }
    var scopeKey: String {
        SHA256.hash(data: Data([endpoint, workspaceInstanceID, workspaceProjectID, actorID,
            forgeInstanceID, forgeProjectID, repositoryID].joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
struct WorksetReleaseIntent: Codable, Equatable, Sendable {
    let accessFingerprint: String
    let scopeKey: String
    let command: WorksetReleaseCommand
    func matches(_ access: WorksetReleaseAccess) -> Bool {
        scopeKey == access.scopeKey && accessFingerprint == access.fingerprint &&
        command.selection.subjects.allSatisfy { access.subjects.contains($0) }
    }
}
struct WorksetReleaseMember: Sendable, Identifiable {
    let subject: WorksetReleaseSubject
    let missionID: String
    let definition: MissionConceptDefinition
    let dependencies: [String]
    let humanGates: [String]
    let effectMode: String
    var id: String { subject.candidate_id }
}
struct WorksetReleasePreview: Sendable {
    let packageData: Data
    let digest: String
    let selection: WorksetReleaseSelection
    let members: [WorksetReleaseMember]
    let gaps: [String]
    let supported: Bool
    let worksetID: String
}
struct WorksetReleaseObservation: Sendable {
    let data: Data
    let operationID: String
    let state: String
    let preview: WorksetReleasePreview
    let originalReceiptData: Data?
    let currentData: Data?
    let currentRevision: Int?
    let snapshot: ApprovedWorklistSnapshot?
}
