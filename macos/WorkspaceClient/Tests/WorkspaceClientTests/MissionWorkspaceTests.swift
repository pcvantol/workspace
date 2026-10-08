import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class MissionWorkspaceTests: XCTestCase {
    func card(_ id: String, _ status: String = "CONCEPT") -> MissionDefinitionCard {
        .init(id: id, revision: 1, title: "Client portal " + id, value: "View invoices", outcome: "Customers see their invoices",
              scope: ["Read invoices"], exclusions: ["Payments"], criteria: ["Only own invoices visible"], questions: [], changes: [],
              group: "Customers", labels: ["Research"], status: status)
    }
    func testSameObjectsAcrossListSelectionAndRelationsWithoutInventedEndpoints() {
        let o = MissionWorkspaceObservation(project: "Own project", cards: [card("A"),card("B","REFINEMENT_REQUIRED")], relations: [
            .init(predecessor: "A", dependent: "B", reason: "Needs invoice access", proposed: true),
            .init(predecessor: "foreign", dependent: "B", reason: "Never disclose foreign name", proposed: false)], complete: false)
        XCTAssertEqual(o.visibleRelations.count, 1)
        XCTAssertEqual(o.neighbors("B"), ["A","B"])
        XCTAssertEqual(o.neighbors(nil), [])
        XCTAssertEqual(o.neighbors("foreign"), [])
        XCTAssertEqual(o.selected("A")?.revision,1)
        XCTAssertNil(o.selected("foreign"))
        XCTAssertEqual(o.matching(search: " invoices ",status: nil).count,2)
        XCTAssertEqual(o.matching(search: "portal",status: "REFINEMENT_REQUIRED").map(\.id),["B"])
        XCTAssertEqual(o.matching(search: "missing",status: nil),[])
        XCTAssertEqual(o.matching(search: "",status: nil).count,2)
    }
    func testFiveLanguagesAndExplicitFallback() {
        for language in ["en","nl","de","fr","es"] {
            XCTAssertFalse(MissionWorkspaceCopy.text("definition",language:language).isEmpty)
            XCTAssertNotEqual(MissionWorkspaceCopy.text("approve",language:language),"approve")
        }
        XCTAssertEqual(MissionWorkspaceCopy.text("approve",language:"unknown"),"Approve and prepare")
        XCTAssertEqual(MissionWorkspaceCopy.text("unknown",language:"en"),"unknown")
    }
    @MainActor func testPresentationAcrossLanguagesWidthsAndPanelsHasNoSideEffects() {
        let o = MissionWorkspaceObservation(project: "Synthetic project", cards: [card("A"), card("B")], relations: [
            .init(predecessor: "A", dependent: "B", reason: "A before B", proposed: true)], complete: false)
        for language in ["en", "nl", "de", "fr", "es"] {
            for width in [640.0, 1280.0] {
                for panel in ["overview", "chat", "definition"] {
                    for graph in [false, true] {
                        let view = MissionWorkspaceView(observation: o, canRefine: false, canApprove: false,
                            selectedID: "B", activePanel: panel, showGraph: graph,
                            onRefine: { _, _ in XCTFail("Rendering must not generate") },
                            onApprove: { _ in XCTFail("Rendering must not approve") })
                        let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)))
                        host.frame = NSRect(x: 0, y: 0, width: width, height: 720)
                        host.layoutSubtreeIfNeeded()
                        XCTAssertEqual(host.frame.width, width)
                        XCTAssertGreaterThan(host.fittingSize.height, 0)
                    }
                }
            }
        }
        let host = NSHostingView(rootView: MissionWorkspaceView(observation: nil, canRefine: false, canApprove: false,
            selectedID: "foreign", activePanel: "unsupported", onRefine: { _, _ in XCTFail() }, onApprove: { _ in XCTFail() }))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 720); host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }

}
