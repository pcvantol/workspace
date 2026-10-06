import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class MissionReviewsViewTests: XCTestCase {
    private func item(evidence: [MissionEvidenceReference] = [], project: String? = nil,
                      phase: MissionReviewPhase = .waitingForReview) -> MissionReviewItem {
        MissionReviewItem(
            key: MissionReviewKey(missionID: "mission-1", requirementID: "review-1"),
            subjectID: "action-1", subjectRevision: "r7", projectID: project,
            title: "Action delivered", actionResult: "Delivered", waitingReason: "Review fence",
            phase: phase, authority: .forge, freshness: .current,
            allowedOutcomes: [.approve], requiredRole: "ARCHITECT",
            blockingScope: "MISSION", policySource: "assignment-r2",
            evidence: evidence, observedAt: "2026-10-06T08:00:00Z",
            forgeInstanceID: "forge-1", actorID: "reviewer-1",
            subjectDigest: "sha256:" + String(repeating: "a", count: 64),
            missionStateRevision: 7, currentMissionRevision: 7,
            evidenceDigest: "sha256:" + String(repeating: "b", count: 64), policyRevision: "policy-r1")
    }

    @MainActor
    private func render(_ view: MissionReviewsView, language: String, width: CGFloat) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let hosting = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 1800)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.frame.width, width)
    }

    func testAllFiveLocalesHaveConcreteReviewCopy() {
        let keys = ["nav", "subtitle", "search", "focusSearch", "filter", "all", "waiting",
                    "recorded", "unavailable", "denied", "offline", "noItems", "noMatches",
                    "hidden", "choose", "mission", "requirement", "subject", "revision",
                    "project", "action", "reason", "role", "scope", "policy", "evidence",
                    "observed", "freshness", "authority", "phase", "unknown", "noEvidence",
                    "decisionUnavailable", "waitingForReview", "decisionRecorded",
                    "engineeringResult", "finalAcceptance", "forge", "external", "current",
                    "stale", "freshUnavailable", "actionResultRef", "forgeReceipt", "sourceRevision"]
        for language in ["en", "nl", "de", "fr", "es"] {
            for key in keys {
                XCTAssertNotEqual(MissionReviewCopy.text(key, language: language), key,
                                  "Missing \(language) copy for \(key)")
            }
        }
        XCTAssertEqual(MissionReviewCopy.text("nav", language: "xx"), "Missions & reviews")
        XCTAssertEqual(MissionReviewCopy.text("absent", language: "en"), "absent")
    }

    @MainActor
    func testNarrowAndWideViewsRenderDistinctAccessAndDetails() {
        let row = item(evidence: [.init(kind: .forgeReceipt, identifier: "receipt-1")],
                       project: "project-1")
        for language in ["en", "nl", "de", "fr", "es"] {
            render(MissionReviewsView(), language: language, width: 520)
            render(MissionReviewsView(items: [row], access: .denied), language: language, width: 520)
            render(MissionReviewsView(items: [row], access: .offline), language: language, width: 520)
            render(MissionReviewsView(items: [], access: .available), language: language, width: 520)
            render(MissionReviewsView(items: [row], access: .available, selected: row.key),
                   language: language, width: 520)
            render(MissionReviewsView(items: [row], access: .available, selected: row.key,
                                      onDecision: { _, _ in }), language: language, width: 520)
            render(MissionReviewsView(items: [row], access: .available, selected: row.key,
                                      search: "no match", filter: .waiting),
                   language: language, width: 900)
            render(MissionReviewsView(items: [item(phase: .decisionRecorded)], access: .available,
                                      selected: row.key, filter: .recorded),
                   language: language, width: 900)
            render(MissionReviewsView(items: [item()], access: .available, selected: row.key),
                   language: language, width: 900)
            render(MissionReviewsView(items: [item(phase: .finalAcceptance)], access: .available,
                                      selected: row.key, onDecision: { _, _ in }),
                   language: language, width: 900)
        }
    }
}
