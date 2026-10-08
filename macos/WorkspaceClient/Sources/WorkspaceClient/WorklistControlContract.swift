import Foundation
import CryptoKit

struct WorklistHold: Codable, Equatable {
    let operation_id: String
    let control_revision: Int
    let reason_code: String
    let owned_by_principal: Bool
}

struct WorklistControlCurrent: Codable, Equatable {
    let instance_id: String
    let workset_id: String
    let definition_revision: String
    let workset_revision: Int
    let control_revision: Int
    let held: Bool
    let hold: WorklistHold?
    let hold_provenance: String
    let admitted_mission_ids: [String]
    let boundary: String
    let ongoing_work_cancelled: Bool
    let observed_at: String

    var mayHold: Bool { !held && hold == nil && hold_provenance == "NONE" }
    var mayUnhold: Bool { held && hold_provenance == "RECORDED" && hold?.owned_by_principal == true }
}

struct WorklistControlRequest: Codable, Equatable {
    let contract_version: String
    let operation_id: String
    let intent: String
    let instance_id: String
    let workset_id: String
    let definition_revision: String
    let expected_revision: Int
    let hold_operation_id: String?
    let expected_hold_revision: Int?
    let reason_code: String

    init(current: WorklistControlCurrent, intent: String, reason: String, operation: String = UUID().uuidString) {
        contract_version = "forge-worklist-control-request/v1"
        operation_id = operation; self.intent = intent
        instance_id = current.instance_id; workset_id = current.workset_id
        definition_revision = current.definition_revision; expected_revision = current.workset_revision
        hold_operation_id = intent == "unhold" ? current.hold?.operation_id : nil
        expected_hold_revision = intent == "unhold" ? current.hold?.control_revision : nil
        reason_code = reason
    }
    var valid: Bool {
        WorklistWire.identifier(operation_id) && WorklistWire.identifier(instance_id) &&
        WorklistWire.identifier(workset_id) && WorklistWire.digest(definition_revision) &&
        expected_revision > 0 && expected_revision < Int.max - 2 &&
        ["USER_REQUEST", "TEMPORARY_WAIT"].contains(reason_code) &&
        contract_version == "forge-worklist-control-request/v1" &&
        (intent == "hold" ? hold_operation_id == nil && expected_hold_revision == nil :
         intent == "unhold" && hold_operation_id.map(WorklistWire.identifier) == true && (expected_hold_revision ?? 0) > 0)
    }
    func data() throws -> Data {
        guard valid else { throw WorklistControlError.invalid }
        let value: [String: Any] = ["contract_version": contract_version, "operation_id": operation_id,
            "intent": intent, "instance_id": instance_id, "workset_id": workset_id,
            "definition_revision": definition_revision, "expected_revision": expected_revision,
            "hold_operation_id": hold_operation_id as Any? ?? NSNull(),
            "expected_hold_revision": expected_hold_revision as Any? ?? NSNull(), "reason_code": reason_code]
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    var digest: String { (try? data()).map { "sha256:" + SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "" }
}

enum WorklistControlError: Error, Equatable { case denied, missing, conflict, unavailable, invalid, unsupported }

struct WorklistControlReceipt: Codable, Equatable {
    let contract_version: String
    let operation_id: String
    let principal_id: String
    let grant_id: String
    let request: WorklistControlRequest
    let request_digest: String
    let outcome: String
    let effect: WorklistControlCurrent
    let only_target_hold_removed: String?
}

struct WorklistControlObservation {
    let current: WorklistControlCurrent
    let snapshot: ApprovedWorklistSnapshot
    let receipt: WorklistControlReceipt?
    let operationID: String?
    let pending: Bool
}

enum WorklistControlWire {
    static let currentKeys: Set<String> = ["instance_id", "workset_id", "definition_revision", "workset_revision", "control_revision", "held", "hold", "hold_provenance", "admitted_mission_ids", "boundary", "ongoing_work_cancelled", "observed_at"]
    static let requestKeys: Set<String> = ["contract_version", "operation_id", "intent", "instance_id", "workset_id", "definition_revision", "expected_revision", "hold_operation_id", "expected_hold_revision", "reason_code"]
    static func object(_ raw: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let object = raw as? [String: Any], Set(object.keys) == keys else { throw WorklistControlError.invalid }
        return object
    }
    static func decode<T: Decodable>(_ raw: Any, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: raw))
    }
    static func current(_ raw: Any?, access: WorklistAccess, workset: String) throws -> WorklistControlCurrent {
        let value = try object(raw, keys: currentKeys)
        let current = try decode(value, as: WorklistControlCurrent.self)
        guard current.instance_id == access.forgeInstanceID, current.workset_id == workset,
              access.worksetIDs.contains(workset), current.workset_revision > 0, current.control_revision >= 0,
              WorklistWire.digest(current.definition_revision), current.boundary == "FUTURE_ADMISSION_ONLY",
              !current.ongoing_work_cancelled, current.admitted_mission_ids.count <= 64,
              Set(current.admitted_mission_ids).count == current.admitted_mission_ids.count,
              current.admitted_mission_ids.allSatisfy(WorklistWire.identifier),
              current.observed_at.count <= 64, current.observed_at.hasSuffix("Z") || current.observed_at.hasSuffix("+00:00"),
              ISO8601DateFormatter().date(from: current.observed_at) != nil || fractionalDate(current.observed_at) else { throw WorklistControlError.invalid }
        if let hold = current.hold {
            _ = try object(value["hold"], keys: ["operation_id", "control_revision", "reason_code", "owned_by_principal"])
            guard current.held, current.hold_provenance == "RECORDED", WorklistWire.identifier(hold.operation_id),
                  hold.control_revision > 0, hold.control_revision <= current.control_revision,
                  ["USER_REQUEST", "TEMPORARY_WAIT", "OWNER_REQUEST"].contains(hold.reason_code) else { throw WorklistControlError.invalid }
        } else {
            guard current.held ? current.hold_provenance == "LEGACY_UNKNOWN" : current.hold_provenance == "NONE" else { throw WorklistControlError.invalid }
        }
        return current
    }
    private static func fractionalDate(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }
    static func receipt(_ raw: Any?, access: WorklistAccess, workset: String,
                        expected: WorklistControlRequest?) throws -> WorklistControlReceipt {
        let value = try object(raw, keys: ["contract_version", "operation_id", "principal_id", "grant_id", "request", "request_digest", "outcome", "effect", "only_target_hold_removed"])
        _ = try object(value["request"], keys: requestKeys)
        let receipt = try decode(value, as: WorklistControlReceipt.self)
        let request = receipt.request
        let effect = try current(value["effect"], access: access, workset: workset)
        guard receipt.contract_version == "forge-worklist-control-receipt/v1", receipt.outcome == "APPLIED",
              receipt.principal_id == access.actorID, WorklistWire.identifier(receipt.grant_id), request.valid,
              request.instance_id == access.forgeInstanceID, request.workset_id == workset,
              receipt.operation_id == request.operation_id, receipt.request_digest == request.digest,
              expected == nil || request == expected,
              effect.definition_revision == request.definition_revision,
              effect.workset_revision == request.expected_revision + 2 else { throw WorklistControlError.invalid }
        if request.intent == "hold" {
            guard effect.mayUnhold, effect.hold?.operation_id == request.operation_id,
                  effect.hold?.control_revision == effect.control_revision, effect.hold?.reason_code == request.reason_code,
                  receipt.only_target_hold_removed == nil else { throw WorklistControlError.invalid }
        } else {
            guard effect.mayHold, receipt.only_target_hold_removed == request.hold_operation_id else { throw WorklistControlError.invalid }
        }
        return receipt
    }
    static func readback(_ raw: Any?, access: WorklistAccess, workset: String,
                         expected: WorklistControlRequest? = nil) throws -> WorklistControlObservation {
        let value = try object(raw, keys: ["contract_version", "principal_id", "read_only", "operation", "current", "worklist"])
        guard value["contract_version"] as? String == "forge-worklist-control-readback/v1",
              value["principal_id"] as? String == access.actorID,
              (value["read_only"] as? NSNumber)?.objCType.pointee == 99, value["read_only"] as? Bool == true else { throw WorklistControlError.invalid }
        let current = try current(value["current"], access: access, workset: workset)
        let snapshot = try WorklistProjection.decode(JSONSerialization.data(withJSONObject: value["worklist"] as Any), access: access, worksetID: workset)
        guard snapshot.worksetRevision == current.workset_revision,
              Set(current.admitted_mission_ids).isSubset(of: Set(snapshot.items.compactMap(\.missionID))) else { throw WorklistControlError.invalid }
        var original: WorklistControlReceipt?; var operationID: String?; var pending = false
        if !(value["operation"] is NSNull) {
            let record = try object(value["operation"], keys: ["state", "original_receipt", "operation_id", "execution_known"])
            operationID = record["operation_id"] as? String
            guard let expected, operationID == expected.operation_id,
                  (record["execution_known"] as? NSNumber)?.objCType.pointee == 99 else { throw WorklistControlError.invalid }
            if record["state"] as? String == "PENDING" {
                guard record["original_receipt"] is NSNull, record["execution_known"] as? Bool == false else { throw WorklistControlError.invalid }
                pending = true
            } else {
                guard record["state"] as? String == "APPLIED", record["execution_known"] as? Bool == true else { throw WorklistControlError.invalid }
                original = try receipt(record["original_receipt"], access: access, workset: workset, expected: expected)
                guard current.workset_revision >= (original?.effect.workset_revision ?? Int.max) else { throw WorklistControlError.invalid }
            }
        } else if expected != nil { throw WorklistControlError.missing }
        return WorklistControlObservation(current: current, snapshot: snapshot, receipt: original, operationID: operationID, pending: pending)
    }
    static func response(_ data: Data, access: WorklistAccess, workset: String,
                         expected: WorklistControlRequest? = nil, result: Bool = false) throws -> WorklistControlObservation {
        let raw = try JSONSerialization.jsonObject(with: data)
        if !result { return try readback(raw, access: access, workset: workset, expected: expected) }
        let value = try object(raw, keys: ["contract_version", "original_receipt", "recorded", "current_readback"])
        guard let expected, value["contract_version"] as? String == "forge-worklist-control-readback/v1",
              (value["recorded"] as? NSNumber)?.objCType.pointee == 99 else { throw WorklistControlError.invalid }
        let original = try receipt(value["original_receipt"], access: access, workset: workset, expected: expected)
        let observation = try readback(value["current_readback"], access: access, workset: workset, expected: expected)
        guard observation.receipt == original else { throw WorklistControlError.invalid }
        return observation
    }
}
