import AppKit
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class WorklistDependencyGraphTests: XCTestCase {
    let scope = ApprovedWorklistScope(forgeInstanceID: "forge", actorID: "alice", worksetID: "set")
    func item(_ id: String, _ position: Int, dependencies: [String] = []) -> ApprovedWorklistItem {
        ApprovedWorklistItem(key: .init(forgeInstanceID: "forge", actorID: "alice", worksetID: "set", memberID: id),
            subjectID: id, subjectRevision: "subject", committedPosition: position, snapshotRevision: "snapshot", sourceRevision: "source",
            missionID: nil, projectID: nil, title: String(repeating: "Résumé — dépendance · ", count: 8),
            facts: .init(approved: .yes, released: .yes, eligible: .unknown, active: .no, engineeringComplete: .unknown,
                         reviewAccepted: .unknown, finalAccepted: .unknown, completed: .unknown), blockers: [], dependencies: dependencies)
    }
    func snapshot(_ items: [ApprovedWorklistItem], complete: Bool = true) -> ApprovedWorklistSnapshot {
        .init(scope: scope, membershipRevision: "members", selectorRevision: "selector", snapshotRevision: "snapshot", observedAt: "2026-10-07T00:00:00Z", completeWithinScope: complete, freshness: .current, continuation: .unknown, nextMemberID: nil, items: items)
    }
    func layout(_ items: [ApprovedWorklistItem]) throws -> WorklistGraphLayout {
        try XCTUnwrap(WorklistGraphLayout.make(snapshot: snapshot(items), matching: Set(items.map(\.key))))
    }
    func testEmptySingleIndependentAndNoInventedOrderEdges() throws {
        XCTAssertTrue(try layout([]).nodes.isEmpty)
        let single = try layout([item("a", 0)])
        XCTAssertEqual(single.nodes[0].column, 0)
        XCTAssertEqual(single.width, 280)
        let independent = try layout([item("b", 1), item("a", 0)])
        XCTAssertEqual(independent.nodes.map(\.item.key.memberID), ["a", "b"])
        XCTAssertEqual(independent.nodes.map(\.row), [0, 1])
        XCTAssertTrue(independent.edges.isEmpty)
        XCTAssertNil(try layout([]).adjacent(to: nil, direction: 1))
        XCTAssertEqual(independent.adjacent(to: nil, direction: 1), independent.nodes[0].item.key)
        XCTAssertEqual(independent.adjacent(to: independent.nodes[0].item.key, direction: -1), independent.nodes[0].item.key)
        XCTAssertEqual(independent.adjacent(to: independent.nodes[0].item.key, direction: 1), independent.nodes[1].item.key)
        XCTAssertEqual(independent.adjacent(to: independent.nodes[1].item.key, direction: 1), independent.nodes[1].item.key)
    }
    func testBranchFanInStableGeometryAndFilteredContext() throws {
        let rows = [item("a", 0), item("b", 1, dependencies: ["a"]), item("c", 2, dependencies: ["a"]), item("d", 3, dependencies: ["b", "c"])]
        let original = try layout(rows)
        XCTAssertEqual(original.nodes.map(\.column), [0, 1, 1, 2])
        XCTAssertEqual(original.nodes.map(\.row), [0, 0, 1, 0])
        XCTAssertEqual(Set(original.edges), Set([.init(predecessor: "a", dependent: "b"), .init(predecessor: "a", dependent: "c"), .init(predecessor: "b", dependent: "d"), .init(predecessor: "c", dependent: "d")]))
        XCTAssertEqual(original, try layout(rows.reversed()))
        let filtered = try XCTUnwrap(WorklistGraphLayout.make(snapshot: snapshot(rows), matching: [rows[3].key]))
        XCTAssertEqual(filtered.nodes.map(\.contextOnly), [true, true, true, false])
        XCTAssertEqual(filtered.edges, original.edges)
        XCTAssertEqual(filtered.width, original.width)
        XCTAssertEqual(ApprovedWorklistPresentation.selected(rows[0].key, in: snapshot(rows)), rows[0])
        XCTAssertTrue(filtered.nodes.allSatisfy { $0.item.missionID == nil && $0.item.facts.completed == .unknown })
    }
    func testContractMaximumAndMalformedCyclesForeignScope() throws {
        let chain = (0..<64).map { item("n\($0)", $0, dependencies: $0 == 0 ? [] : ["n\($0 - 1)"]) }
        let maximum = try layout(chain)
        XCTAssertEqual(maximum.nodes.count, 64)
        XCTAssertEqual(maximum.edges.count, 63)
        XCTAssertEqual(maximum.nodes.last?.column, 63)
        XCTAssertLessThan(maximum.width, 21_000)
        XCTAssertNil(WorklistGraphLayout.make(snapshot: snapshot(chain + [item("n64", 64)]), matching: []))
        for invalid in [[item("a", 0, dependencies: ["a"])], [item("a", 0, dependencies: ["b"]), item("b", 1, dependencies: ["a"])], [item("a", 0, dependencies: ["foreign"])], [item("a", 0), item("b", 1, dependencies: ["a", "a"])], [item("a", 0), item("a", 1)], [item("a", 0), item("b", 0)]] {
            XCTAssertNil(WorklistGraphLayout.make(snapshot: snapshot(invalid), matching: []))
        }
        let foreign = ApprovedWorklistSnapshot(scope: .init(forgeInstanceID: "other", actorID: "alice", worksetID: "set"), membershipRevision: "m", selectorRevision: "s", snapshotRevision: "snapshot", observedAt: "now", completeWithinScope: true, freshness: .current, continuation: .unknown, nextMemberID: nil, items: [item("a", 0)])
        XCTAssertNil(WorklistGraphLayout.make(snapshot: foreign, matching: []))
        let partial = try XCTUnwrap(WorklistGraphLayout.make(snapshot: snapshot([item("b", 1, dependencies: ["missing"])], complete: false), matching: []))
        XCTAssertEqual(partial.unresolvedDependencies, ["missing"])
        XCTAssertEqual(partial.nodes.count, 1)
        XCTAssertTrue(partial.edges.isEmpty)
    }
    func testViewportBoundsAndInvalidInputs() throws {
        var viewport = WorklistGraphViewport()
        XCTAssertEqual(viewport.zoom, 1)
        viewport.magnify(1.25); XCTAssertEqual(viewport.zoom, 1.25)
        viewport.magnify(100); XCTAssertEqual(viewport.zoom, 2)
        viewport.magnify(0.001); XCTAssertEqual(viewport.zoom, 0.002)
        for invalid in [0.0, -1, .nan, .infinity] { viewport.magnify(invalid); XCTAssertEqual(viewport.zoom, 0.002) }
        let graph = try layout([item("a", 0)])
        viewport.fit(layout: graph, width: graph.width, height: graph.height); XCTAssertEqual(viewport.zoom, 1)
        viewport.fit(layout: graph, width: graph.width / 2, height: graph.height); XCTAssertEqual(viewport.zoom, 0.5)
        for invalid in [0.0, -1, .nan, .infinity] { viewport.fit(layout: graph, width: invalid, height: 500); XCTAssertEqual(viewport.zoom, 0.5) }
        viewport.fit(layout: graph, width: 1, height: 1); XCTAssertEqual(viewport.zoom, min(1 / graph.width, 1 / graph.height))
    }
    func testFitSupportedExtremesAndTransitiveEdgesAvoidNodes() throws {
        let chain = try layout((0..<64).map { item("n\($0)", $0, dependencies: $0 == 0 ? [] : ["n\($0 - 1)"]) })
        let independent = try layout((0..<64).map { item("n\($0)", $0) })
        for graph in [chain, independent] {
            var viewport = WorklistGraphViewport()
            viewport.fit(layout: graph, width: 380, height: 340)
            XCTAssertLessThanOrEqual(graph.width * viewport.zoom, 380.001)
            XCTAssertLessThanOrEqual(graph.height * viewport.zoom, 340.001)
            XCTAssertLessThan(viewport.zoom, 0.2)
            viewport.magnify(1.25)
            XCTAssertGreaterThan(viewport.zoom, min(380 / graph.width, 340 / graph.height))
        }
        let graph = try layout([item("a", 0), item("b", 1, dependencies: ["a"]), item("c", 2, dependencies: ["a", "b"])])
        for (index, edge) in graph.edges.enumerated() {
            let route = graph.route(edge, index: index)
            XCTAssertEqual(route.count, 6)
            XCTAssertLessThan(route[2].y, graph.topInset)
            XCTAssertEqual(route[2].y, route[3].y)
            for node in graph.nodes {
                let rect = CGRect(x: 16 + Double(node.column) * WorklistGraphLayout.columnStride, y: graph.topInset + Double(node.row) * WorklistGraphLayout.rowStride, width: WorklistGraphLayout.nodeWidth, height: WorklistGraphLayout.nodeHeight)
                XCTAssertFalse(rect.contains(route[2]))
                XCTAssertFalse(rect.contains(route[3]))
            }
        }
        XCTAssertEqual(Set(graph.edges.enumerated().map { graph.route($0.element, index: $0.offset)[2].y }).count, 3)
        XCTAssertTrue(graph.route(.init(predecessor: "foreign", dependent: "c"), index: 0).isEmpty)
    }

    @MainActor
    func testFilteredContextIsExplicitInFiveLanguageAccessibleNodeLabels() {
        let row = item("a", 0, dependencies: ["predecessor"])
        for language in ["en", "nl", "de", "fr", "es"] {
            for filtered in [false, true] {
                let label = WorklistDependencyGraph.nodeLabel(.init(item: row, column: 0, row: 0, contextOnly: filtered), language: language)
                XCTAssertEqual(label.contains(WorklistCopy.text("graphFiltered", language: language)), filtered)
                XCTAssertTrue(label.contains("predecessor"))
                XCTAssertTrue(label.contains(WorklistCopy.text("completed", language: language)))
                XCTAssertTrue(label.contains(WorklistCopy.text("unknown", language: language)))
            }
        }
    }

    @MainActor
    func testFiveLocalesThemesNarrowViewsPartialAndInvalidGraphs() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let rows = [item("a", 0), item("b", 1, dependencies: ["a"])]
        for language in ["en", "nl", "de", "fr", "es"] {
            for theme in [ColorScheme.light, .dark] {
                for width in [CGFloat(380), 1000] {
                    for observation in [snapshot(rows), snapshot([]), snapshot([item("b", 1, dependencies: ["missing"])], complete: false), snapshot([item("a", 0, dependencies: ["a"])])] {
                        let view = WorklistDependencyGraph(snapshot: observation, matching: [rows[1].key], selection: .constant(rows[0].key))
                        let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: language)).environment(\.colorScheme, theme))
                        host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
                        host.layoutSubtreeIfNeeded()
                        if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: bitmap) }
                        XCTAssertEqual(host.frame.width, width)
                    }
                    var cache = WorklistObservationCache(); XCTAssertTrue(cache.accept(snapshot(rows), for: scope))
                    let host = NSHostingView(rootView: ApprovedWorklistView(cache: cache, selected: rows[0].key, search: "hidden", graphMode: true).environment(\.locale, Locale(identifier: language)))
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 2400); host.layoutSubtreeIfNeeded()
                }
            }
        }
    }
}
