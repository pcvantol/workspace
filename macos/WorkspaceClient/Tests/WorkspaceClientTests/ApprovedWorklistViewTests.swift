import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class ApprovedWorklistViewTests: XCTestCase {
    private let scope = ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-a", worksetID: "workset-1")

    private func item(mission: String? = "mission-1", title: String? = "Approved subject",
                      blockers: [WorklistBlockReason] = []) -> ApprovedWorklistItem {
        ApprovedWorklistItem(
            key: ApprovedWorklistKey(forgeInstanceID: scope.forgeInstanceID, actorID: scope.actorID,
                                    worksetID: scope.worksetID, memberID: "member-1"),
            subjectID: "candidate-1", subjectRevision: "subject-r1", committedPosition: 0,
            snapshotRevision: "snapshot-r1", sourceRevision: "source-r7", missionID: mission,
            projectID: nil, title: title,
            facts: WorklistFacts(approved: .yes, released: .yes, eligible: .no, active: .no,
                                 engineeringComplete: .yes, reviewAccepted: .unknown,
                                 finalAccepted: .no, completed: .no), blockers: blockers)
    }

    private func cache(_ items: [ApprovedWorklistItem], complete: Bool = true,
                       freshness: WorklistFreshness = .current,
                       continuation: WorklistContinuation = .blocked,
                       next: String? = "member-1") -> WorklistObservationCache {
        var value = WorklistObservationCache()
        let snapshot = ApprovedWorklistSnapshot(scope: scope, membershipRevision: "membership-r1",
            selectorRevision: "selector-r1", snapshotRevision: "snapshot-r1",
            observedAt: "2026-10-07T08:00:00Z", completeWithinScope: complete,
            freshness: freshness, continuation: continuation, nextMemberID: next, items: items)
        XCTAssertTrue(value.accept(snapshot, for: scope))
        return value
    }

    @MainActor
    private func render(_ view: ApprovedWorklistView, language: String,
                        scheme: ColorScheme, width: CGFloat) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let hosting = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, scheme))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 2400)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertEqual(hosting.frame.width, width)
    }

    func testCompleteFiveLanguageCopyAndExplicitFallbacks() {
        for language in ["en", "nl", "de", "fr", "es"] {
            for key in WorklistCopy.keys {
                XCTAssertNotEqual(WorklistCopy.text(key, language: language), key)
                XCTAssertFalse(WorklistCopy.text(key, language: language).isEmpty)
            }
        }
        XCTAssertEqual(WorklistCopy.text("nav"), "Approved worklist")
        XCTAssertEqual(WorklistCopy.text("nav", language: "unsupported"), "Approved worklist")
        XCTAssertEqual(WorklistCopy.text("nav", language: "nl"), "Goedgekeurde werklijst")
        XCTAssertEqual(WorklistCopy.text("not-a-key", language: "fr"), "not-a-key")
    }

    @MainActor
    func testBothThemesWidthsAndScopedStatesRenderWithoutEffects() {
        let blockers = WorklistReasonKind.allCasesForQualification.map {
            WorklistBlockReason(kind: $0, code: "VERIFIED_BLOCK", explanation: $0 == .hold ? nil : "Current scoped evidence")
        }
        let row = item(blockers: blockers)
        let available = cache([row])
        var denied = available
        denied.failed(.denied, for: scope)
        var offline = available
        offline.failed(.offline, for: scope)
        var navigationRequests = 0
        for language in ["en", "nl", "de", "fr", "es"] {
            for scheme in [ColorScheme.light, .dark] {
                for width in [CGFloat(520), 900] {
                    render(ApprovedWorklistView(), language: language, scheme: scheme, width: width)
                    for observation in [denied, offline, cache([row], complete: false),
                                        cache([row], freshness: .stale), cache([row], freshness: .unknown),
                                        cache([], continuation: .idle, next: nil)] {
                        render(ApprovedWorklistView(cache: observation, selected: row.key),
                               language: language, scheme: scheme, width: width)
                    }
                    render(ApprovedWorklistView(cache: available), language: language, scheme: scheme, width: width)
                    render(ApprovedWorklistView(cache: available, selected: row.key,
                                                onOpenReviews: { _ in navigationRequests += 1 }),
                           language: language, scheme: scheme, width: width)
                    render(ApprovedWorklistView(cache: available, selected: row.key,
                                                search: "hidden", filter: .blocked, sort: .title),
                           language: language, scheme: scheme, width: width)
                    let subject = item(mission: nil, title: nil)
                    render(ApprovedWorklistView(cache: cache([subject], continuation: .ready), selected: subject.key),
                           language: language, scheme: scheme, width: width)
                    render(ApprovedWorklistView(cache: cache([row], continuation: .unknown, next: nil),
                                                selected: row.key, sort: .identifier),
                           language: language, scheme: scheme, width: width)
                }
            }
        }
        XCTAssertEqual(navigationRequests, 0, "Rendering/filtering/reading is not a review decision or navigation request")
    }
}

private extension WorklistReasonKind {
    static var allCasesForQualification: [Self] {
        [.dependency, .hold, .evidence, .review, .finalAcceptance, .authority, .budget, .unknown]
    }
}
