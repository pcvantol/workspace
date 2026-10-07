import Foundation
import CryptoKit
import CoreFoundation

// Validate a whole, scoped observation before exposing any member to presentation.
enum WorklistProjection {
    private static let boundFields: Set<String> = ["contract_version", "instance_id", "installation_id", "scope", "membership_revision", "selector_revision", "workset_revision", "activation_support", "completeness", "items", "continuation"]
    private static let itemFields: Set<String> = ["candidate_id", "subject_revision", "committed_order", "title", "mission_id", "mission_state_revision", "approved", "released", "eligibility", "blocking_reasons", "active", "execution_state", "engineering_result", "review_state", "final_acceptance", "completed", "effect_mode", "dependencies", "detail_reference", "allocation_binding", "evidence_references"]

    private static func require(_ condition: Bool) throws {
        guard condition else { throw WorklistTransportError.inconsistentSnapshot }
    }
    private static func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
        guard let value = value as? [String: Any], Set(value.keys) == keys else {
            throw WorklistTransportError.inconsistentSnapshot
        }
        return value
    }
    private static func text(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw WorklistTransportError.inconsistentSnapshot }
        return value
    }
    private static func integer(_ value: Any?, minimum: Int = 0, maximum: Int = Int.max) throws -> Int {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              String(cString: value.objCType) != "d", String(cString: value.objCType) != "f",
              let parsed = Int(value.stringValue), (minimum...maximum).contains(parsed) else {
            throw WorklistTransportError.inconsistentSnapshot
        }
        return parsed
    }
    private static func boolean(_ value: Any?) throws -> Bool {
        guard let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else {
            throw WorklistTransportError.inconsistentSnapshot
        }
        return value.boolValue
    }
    private static func code(_ value: String) -> Bool {
        value.range(of: "^[A-Z][A-Z0-9_]{0,63}$", options: .regularExpression) != nil
    }
    private static func codes(_ value: Any?) throws -> [String] {
        guard let values = value as? [String], values.count <= 64,
              Set(values).count == values.count, values.allSatisfy(code) else {
            throw WorklistTransportError.inconsistentSnapshot
        }
        return values
    }
    private static func optionalID(_ value: Any?) throws -> String? {
        if value is NSNull { return nil }
        let result = try text(value)
        try require(WorklistWire.identifier(result))
        return result
    }
    private static func fact(_ value: String, yes: String, no: String) -> WorklistFact {
        value == yes ? .yes : value == no ? .no : .unknown
    }

    static func decode(_ data: Data, access: WorklistAccess, worksetID: String) throws -> ApprovedWorklistSnapshot {
        try require(access.valid && access.worksetIDs.contains(worksetID) && data.count <= 1_000_000)
        let raw = try JSONSerialization.jsonObject(with: data)
        let top = try object(raw, keys: boundFields.union(["snapshot_revision", "observed_at", "freshness", "read_only"]))
        try require(try text(top["contract_version"]) == "forge-workspace-worklist/v1" && text(top["instance_id"]) == access.forgeInstanceID && boolean(top["read_only"]))
        let installation = try text(top["installation_id"])
        try require(WorklistWire.identifier(installation))
        let scope = try object(top["scope"], keys: ["kind", "principal_id", "workset_id", "project_id"])
        try require(try text(scope["kind"]) == "EXPLICIT_WORKSET" && text(scope["principal_id"]) == access.actorID && text(scope["workset_id"]) == worksetID && scope["project_id"] is NSNull)
        let memberRevision = try text(top["membership_revision"])
        let selectorRevision = try text(top["selector_revision"])
        let snapshotRevision = try text(top["snapshot_revision"])
        try require([memberRevision, selectorRevision, snapshotRevision].allSatisfy(WorklistWire.digest))
        let worksetRevision = try integer(top["workset_revision"], minimum: 1)
        let observedAt = try text(top["observed_at"])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let validTime = formatter.date(from: observedAt) != nil || ISO8601DateFormatter().date(from: observedAt) != nil
        try require(observedAt.count <= 64 && validTime && (observedAt.hasSuffix("Z") || observedAt.hasSuffix("+00:00")))
        let completeness = try text(top["completeness"])
        let activation = try text(top["activation_support"])
        try require(try text(top["freshness"]) == "CURRENT_READBACK" && ["COMPLETE_WITHIN_SCOPE", "PARTIAL"].contains(completeness) && ["NOT_YET_QUALIFIED", "QUALIFIED_SERIAL_APPROVED_WORKLIST"].contains(activation))
        guard let rawItems = top["items"] as? [Any], rawItems.count <= 64 else { throw WorklistTransportError.inconsistentSnapshot }
        let scoped = ApprovedWorklistScope(forgeInstanceID: access.forgeInstanceID, actorID: access.actorID, worksetID: worksetID)
        let items = try rawItems.map { try item($0, scope: scoped, installation: installation, revision: snapshotRevision) }
        try require(Set(items.map(\.key.memberID)).count == items.count && Set(items.map(\.committedPosition)).count == items.count)
        let complete = completeness == "COMPLETE_WITHIN_SCOPE"
        if complete { try require(Set(items.map(\.committedPosition)) == Set(0..<items.count)) }
        for item in items {
            for dependency in item.dependencies {
                if let preceding = items.first(where: { $0.key.memberID == dependency }) {
                    try require(preceding.committedPosition < item.committedPosition)
                } else { try require(!complete) }
            }
        }
        let continuation = try object(top["continuation"], keys: ["state", "candidate_id", "mission_id", "committed_order", "reason_codes"])
        let state = try text(continuation["state"])
        try require(["READY", "BLOCKED", "IDLE", "UNKNOWN"].contains(state))
        let reasons = try codes(continuation["reason_codes"])
        let next = try optionalID(continuation["candidate_id"])
        let mission = try optionalID(continuation["mission_id"])
        if let next {
            guard let selected = items.first(where: { $0.key.memberID == next }) else { throw WorklistTransportError.inconsistentSnapshot }
            try require(try state != "IDLE" && mission == selected.missionID && integer(continuation["committed_order"], maximum: 63) == selected.committedPosition)
        } else {
            try require(mission == nil && continuation["committed_order"] is NSNull && ["IDLE", "UNKNOWN"].contains(state) && (state != "IDLE" || complete))
        }
        let canonical = try JSONSerialization.data(withJSONObject: top.filter { boundFields.contains($0.key) }, options: [.sortedKeys, .withoutEscapingSlashes])
        let digest = "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        try require(digest == snapshotRevision)
        return ApprovedWorklistSnapshot(scope: scoped, membershipRevision: memberRevision, selectorRevision: selectorRevision, snapshotRevision: snapshotRevision, observedAt: observedAt, completeWithinScope: complete, freshness: .current, continuation: state == "READY" ? .ready : state == "BLOCKED" ? .blocked : state == "IDLE" ? .idle : .unknown, nextMemberID: next, items: items, installationID: installation, worksetRevision: worksetRevision, activationSupport: activation, continuationReasons: reasons)
    }

    static func reasonKind(_ code: String) -> WorklistReasonKind {
        switch code {
        case "DEPENDENCY_NOT_PROVEN": .dependency
        case "WORKSET_HELD": .hold
        case "COMPLETION_EVIDENCE_UNPROVEN", "SUBJECT_UNAVAILABLE", "SUBJECT_STALE", "MISSION_STATE_UNAVAILABLE": .evidence
        case "FINAL_ACCEPTANCE_REQUIRED": .finalAcceptance
        case "PROGRESSION_REVIEW_REQUIRED": .review
        case "RELEASE_REVOKED", "RELEASE_EXPIRED", "NOT_RELEASED", "WORKSET_UNAPPROVED", "SUBJECT_UNAPPROVED", "RUNTIME_GENERATION_CHANGED": .authority
        case "ACTIVATION_LIMIT_EXHAUSTED": .budget
        default: .unknown
        }
    }

    private static func item(_ raw: Any, scope: ApprovedWorklistScope, installation: String, revision: String) throws -> ApprovedWorklistItem {
        let value = try object(raw, keys: itemFields)
        let candidate = try text(value["candidate_id"])
        let subject = try text(value["subject_revision"])
        let title = try text(value["title"])
        try require(WorklistWire.identifier(candidate) && WorklistWire.digest(subject) && title.count <= 160 && !title.unicodeScalars.contains(where: { $0.value < 32 }))
        let order = try integer(value["committed_order"], maximum: 63)
        let mission = try optionalID(value["mission_id"])
        let missionRevision: Int?
        if let mission {
            missionRevision = try integer(value["mission_state_revision"])
            let allocation = try object(value["allocation_binding"], keys: ["kind", "candidate_id", "subject_revision", "mission_id", "installation_id", "envelope_digest"])
            try require(try text(allocation["kind"]) == "CANONICAL_CANDIDATE_INTAKE" && text(allocation["candidate_id"]) == candidate && text(allocation["subject_revision"]) == subject && text(allocation["mission_id"]) == mission && text(allocation["installation_id"]) == installation && WorklistWire.digest(text(allocation["envelope_digest"])))
            if !(value["detail_reference"] is NSNull) {
                let detail = try object(value["detail_reference"], keys: ["kind", "mission_id"])
                try require(try text(detail["kind"]) == "MISSION_REVIEW" && text(detail["mission_id"]) == mission)
            }
        } else {
            missionRevision = nil
            try require(value["mission_state_revision"] is NSNull && value["allocation_binding"] is NSNull && value["detail_reference"] is NSNull)
        }
        let eligibility = try text(value["eligibility"])
        let engineering = try text(value["engineering_result"])
        let review = try text(value["review_state"])
        let final = try text(value["final_acceptance"])
        let execution = try text(value["execution_state"])
        let effect = try text(value["effect_mode"])
        try require(["ELIGIBLE", "BLOCKED", "UNKNOWN"].contains(eligibility) && ["PROVEN", "UNPROVEN", "UNKNOWN"].contains(engineering) && ["WAITING", "ACCEPTED", "NONE", "UNKNOWN"].contains(review) && ["WAITING", "ACCEPTED", "NOT_REQUIRED", "UNKNOWN"].contains(final) && code(execution) && ["READ_ONLY_ASSESSMENT", "DOCUMENTATION_ONLY", "ARCHITECTURE_DESIGN_ONLY", "BOUNDED_REPOSITORY_CHANGE", "UNKNOWN"].contains(effect))
        let blockers = try codes(value["blocking_reasons"]).map { WorklistBlockReason(kind: reasonKind($0), code: $0, explanation: nil) }
        guard let dependencies = value["dependencies"] as? [String], dependencies.count <= 64,
              Set(dependencies).count == dependencies.count, dependencies.allSatisfy(WorklistWire.identifier),
              let references = value["evidence_references"] as? [Any], references.count <= 16 else { throw WorklistTransportError.inconsistentSnapshot }
        let evidence = try references.map { raw -> WorklistEvidenceReference in
            let ref = try object(raw, keys: ["kind", "subject_id", "digest"])
            let kind = try text(ref["kind"]), id = try text(ref["subject_id"]), digest = try text(ref["digest"])
            try require(["MISSION_COMPLETION", "FINAL_BUSINESS_ACCEPTANCE"].contains(kind) && WorklistWire.identifier(id) && WorklistWire.digest(digest) && mission != nil && (kind != "MISSION_COMPLETION" || id == mission))
            return WorklistEvidenceReference(kind: kind, subjectID: id, digest: digest)
        }
        try require(Set(evidence).count == evidence.count)
        let facts = try WorklistFacts(approved: boolean(value["approved"]) ? .yes : .no, released: boolean(value["released"]) ? .yes : .no, eligible: fact(eligibility, yes: "ELIGIBLE", no: "BLOCKED"), active: boolean(value["active"]) ? .yes : .no, engineeringComplete: fact(engineering, yes: "PROVEN", no: "UNPROVEN"), reviewAccepted: fact(review, yes: "ACCEPTED", no: "WAITING"), finalAccepted: final == "NOT_REQUIRED" ? .notRequired : fact(final, yes: "ACCEPTED", no: "WAITING"), completed: boolean(value["completed"]) ? .yes : .no)
        return ApprovedWorklistItem(key: ApprovedWorklistKey(forgeInstanceID: scope.forgeInstanceID, actorID: scope.actorID, worksetID: scope.worksetID, memberID: candidate), subjectID: candidate, subjectRevision: subject, committedPosition: order, snapshotRevision: revision, sourceRevision: missionRevision.map(String.init) ?? subject, missionID: mission, projectID: nil, title: title, facts: facts, blockers: blockers, executionState: execution, reviewState: review, effectMode: effect, dependencies: dependencies, evidence: evidence, reviewDetailAvailable: !(value["detail_reference"] is NSNull))
    }
}
