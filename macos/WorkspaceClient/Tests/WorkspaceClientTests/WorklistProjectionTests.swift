import CryptoKit
import Foundation
import XCTest
@testable import WorkspaceClient

final class WorklistProjectionTests: XCTestCase {
    static let access = WorklistAccess(endpoint: "http://127.0.0.1:8080/", workspaceInstanceID: String(repeating: "a", count: 32), forgeInstanceID: "forge-1", actorID: "actor-a", worksetIDs: ["workset-a"], token: String(repeating: "b", count: 43))
    static func fixture(_ name: String = "allocated") throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: root.appendingPathComponent("worklist-\(name).json"))
    }
    private func changed(_ name: String = "allocated", _ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var document = try JSONSerialization.jsonObject(with: Self.fixture(name)) as! [String: Any]
        mutate(&document)
        let fields = ["contract_version", "instance_id", "installation_id", "scope", "membership_revision", "selector_revision", "workset_revision", "activation_support", "completeness", "items", "continuation"]
        let canonical = try JSONSerialization.data(withJSONObject: document.filter { fields.contains($0.key) }, options: [.sortedKeys, .withoutEscapingSlashes])
        document["snapshot_revision"] = "sha256:" + SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        return try JSONSerialization.data(withJSONObject: document)
    }
    private func reject(_ data: Data) {
        XCTAssertThrowsError(try WorklistProjection.decode(data, access: Self.access, worksetID: "workset-a"))
    }
    func testOnlyPinnedReasonCodesReceiveAnExplanationCategory() {
        let known: [(String, WorklistReasonKind)] = [("DEPENDENCY_NOT_PROVEN", .dependency), ("WORKSET_HELD", .hold), ("COMPLETION_EVIDENCE_UNPROVEN", .evidence), ("FINAL_ACCEPTANCE_REQUIRED", .finalAcceptance), ("PROGRESSION_REVIEW_REQUIRED", .review), ("RELEASE_REVOKED", .authority), ("ACTIVATION_LIMIT_EXHAUSTED", .budget), ("FUTURE_CONDITION", .unknown)]
        for (code, kind) in known { XCTAssertEqual(WorklistProjection.reasonKind(code), kind) }
    }
    func testPythonCanonicalUnicodeProofAndNoPhantomMission() throws {
        let allocated = try WorklistProjection.decode(Self.fixture(), access: Self.access, worksetID: "workset-a")
        XCTAssertEqual(allocated.items.first?.title, "Résumé / safe subject")
        XCTAssertEqual(allocated.items.first?.missionID, "mission-a")
        XCTAssertTrue(allocated.items.first!.reviewDetailAvailable)
        XCTAssertEqual(allocated.items.first?.reviewState, "NONE")
        XCTAssertEqual(allocated.items.first?.facts.reviewAccepted, .unknown)
        XCTAssertEqual(allocated.items.first?.evidence.last?.subjectID, "business-decision-a")
        let pending = try WorklistProjection.decode(Self.fixture("pending"), access: Self.access, worksetID: "workset-a")
        XCTAssertNil(pending.items.first?.missionID)
        XCTAssertFalse(pending.items.first!.reviewDetailAvailable)
        XCTAssertEqual(pending.items.first?.facts.engineeringComplete, .unknown)
        let idle = try WorklistProjection.decode(Self.fixture("idle"), access: Self.access, worksetID: "workset-a")
        XCTAssertEqual(idle.continuation, .idle)
        XCTAssertTrue(idle.items.isEmpty)
        XCTAssertNil(idle.nextMemberID)
    }
    func testForeignOrMalformedHeaderDigestAndScopeCannotBeDisplayed() throws {
        for (key, bad) in [("contract_version", "bad"), ("instance_id", "foreign"), ("installation_id", "../secret"), ("membership_revision", "r1"), ("freshness", "STALE"), ("completeness", "PAGES"), ("activation_support", "IMPLICIT"), ("observed_at", "invalid") ] {
            reject(try changed { $0[key] = bad })
        }
        for value: Any in [false, 1, "true"] { reject(try changed { $0["read_only"] = value }) }
        for value: Any in [0, true, 1.5, "1"] { reject(try changed { $0["workset_revision"] = value }) }
        reject(try changed { $0["extra"] = true })
        reject(try changed { $0["items"] = NSNull() })
        reject(try changed { $0["items"] = Array(repeating: [:], count: 65) })
        reject(try changed { var scope = $0["scope"] as! [String: Any]; scope["principal_id"] = "foreign"; $0["scope"] = scope })
        var damaged = try JSONSerialization.jsonObject(with: Self.fixture()) as! [String: Any]
        damaged["snapshot_revision"] = "sha256:" + String(repeating: "c", count: 64)
        reject(try JSONSerialization.data(withJSONObject: damaged))
        XCTAssertThrowsError(try WorklistProjection.decode(Self.fixture(), access: Self.access, worksetID: "foreign"))
    }
    func testBoundedMembersCanonicalBindingsAndTypedEvidenceFailClosed() throws {
        let changes: [(String, Any)] = [("candidate_id", "../outside"), ("subject_revision", "r1"), ("title", "bad\nspoof"), ("title", String(repeating: "x", count: 161)), ("committed_order", true), ("approved", 1), ("released", NSNull()), ("eligibility", "START"), ("engineering_result", "DONE"), ("review_state", "APPROVED"), ("final_acceptance", "DONE"), ("effect_mode", "LIVE"), ("execution_state", "bad/path"), ("blocking_reasons", ["DUP", "DUP"]), ("blocking_reasons", ["lowercase"]), ("dependencies", ["x", "x"]), ("dependencies", ["../outside"]), ("evidence_references", Array(repeating: [:], count: 17))]
        for (key, bad) in changes {
            reject(try changed { var items = $0["items"] as! [[String: Any]]; items[0][key] = bad; $0["items"] = items })
        }
        for field in ["candidate_id", "subject_revision", "mission_id", "installation_id", "envelope_digest", "kind"] {
            reject(try changed { var items = $0["items"] as! [[String: Any]]; var binding = items[0]["allocation_binding"] as! [String: Any]; binding[field] = "foreign"; items[0]["allocation_binding"] = binding; $0["items"] = items })
        }
        for field in ["kind", "subject_id", "digest"] {
            reject(try changed { var items = $0["items"] as! [[String: Any]]; var refs = items[0]["evidence_references"] as! [[String: Any]]; refs[0][field] = "foreign"; items[0]["evidence_references"] = refs; $0["items"] = items })
        }
        reject(try changed { var items = $0["items"] as! [[String: Any]]; items[0]["detail_reference"] = ["kind": "URL", "mission_id": "mission-a"]; $0["items"] = items })
        reject(try changed("pending") { var items = $0["items"] as! [[String: Any]]; items[0]["mission_state_revision"] = 1; $0["items"] = items })
    }
    func testMissingCurrentMissionStateIsPartialAndCannotOpenReviewDetail() throws {
        let partial = try changed { doc in
            var items = doc["items"] as! [[String: Any]]
            for key in ["mission_state_revision", "allocation_binding", "detail_reference"] { items[0][key] = NSNull() }
            items[0]["execution_state"] = "UNAVAILABLE"
            items[0]["evidence_references"] = [Any]()
            doc["items"] = items
            doc["completeness"] = "PARTIAL"
        }
        let observed = try WorklistProjection.decode(partial, access: Self.access, worksetID: "workset-a")
        XCTAssertFalse(observed.completeWithinScope)
        XCTAssertEqual(observed.items.first?.missionID, "mission-a")
        XCTAssertFalse(observed.items.first!.missionBindingVerified)
        XCTAssertFalse(observed.items.first!.reviewDetailAvailable)
        XCTAssertEqual(observed.items.first?.sourceRevision, observed.snapshotRevision)
    }
    func testPartialDependenciesAndProducerNextPointerRemainDistinct() throws {
        reject(try changed { $0["items"] = ($0["items"] as! [Any]) + ($0["items"] as! [Any]) })
        reject(try changed { var items = $0["items"] as! [[String: Any]]; items[0]["dependencies"] = ["candidate-a"]; $0["items"] = items })
        let partial = try changed { var items = $0["items"] as! [[String: Any]]; items[0]["dependencies"] = ["missing-candidate"]; $0["items"] = items; $0["completeness"] = "PARTIAL" }
        XCTAssertFalse(try WorklistProjection.decode(partial, access: Self.access, worksetID: "workset-a").completeWithinScope)
        for (key, bad) in [("candidate_id", "foreign"), ("mission_id", "foreign"), ("state", "IDLE"), ("state", "START")] {
            reject(try changed { var next = $0["continuation"] as! [String: Any]; next[key] = bad; $0["continuation"] = next })
        }
        reject(try changed("idle") { $0["completeness"] = "PARTIAL" })
        for (eligible, engineering, review, final) in [("ELIGIBLE", "PROVEN", "ACCEPTED", "ACCEPTED"), ("BLOCKED", "UNPROVEN", "WAITING", "NOT_REQUIRED")] {
            let data = try changed { var items = $0["items"] as! [[String: Any]]; items[0]["eligibility"] = eligible; items[0]["engineering_result"] = engineering; items[0]["review_state"] = review; items[0]["final_acceptance"] = final; $0["items"] = items; var next = $0["continuation"] as! [String: Any]; next["state"] = eligible == "ELIGIBLE" ? "READY" : "BLOCKED"; $0["continuation"] = next }
            let result = try WorklistProjection.decode(data, access: Self.access, worksetID: "workset-a")
            XCTAssertEqual(result.items.first?.facts.eligible, eligible == "ELIGIBLE" ? .yes : .no)
            XCTAssertEqual(result.items.first?.facts.finalAccepted, final == "NOT_REQUIRED" ? .notRequired : .yes)
        }
    }
}
