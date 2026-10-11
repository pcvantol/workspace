import SwiftUI
import AppKit

// The graph receives the same atomic observation and selection as the list.
struct WorklistDependencyGraph: View {
    let snapshot: ApprovedWorklistSnapshot
    let matching: Set<ApprovedWorklistKey>
    @Binding var selection: ApprovedWorklistKey?
    var showScopeMetadata = true
    var humanNames: [String: String] = [:]
    @Environment(\.locale) private var locale
    @State private var viewport = WorklistGraphViewport()
    @State private var focusRequest = 0

    private func copy(_ key: String) -> String {
        WorklistCopy.text(key, language: locale.language.languageCode?.identifier)
    }

    var body: some View {
        if let layout = WorklistGraphLayout.make(snapshot: snapshot, matching: matching) {
            graph(layout)
        } else {
            Text(copy("stale")).accessibilityIdentifier("worklist.graph.invalid")
        }
    }

    private func graph(_ layout: WorklistGraphLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy("graphLegend")).font(.caption)
            Text(copy("graphContext")).font(.caption).foregroundStyle(.secondary)
            if !layout.unresolvedDependencies.isEmpty {
                Text(copy("graphMissing") + (showScopeMetadata ? ": " + layout.unresolvedDependencies.joined(separator: ", ") : ""))
                    .font(.caption).accessibilityIdentifier("worklist.graph.missing")
            }
            GeometryReader { geometry in
                    VStack(alignment: .leading) {
                        controls(layout, size: geometry.size)
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                connections(layout)
                                ForEach(layout.nodes, id: \.item.key) { node in
                                    nodeButton(node)
                                        .frame(width: WorklistGraphLayout.nodeWidth, height: WorklistGraphLayout.nodeHeight)
                                        .background(WorklistGraphFocusTarget(request: selection == node.item.key ? focusRequest : 0))
                                        .position(x: x(node), y: y(node, layout: layout))
                                        .id(node.item.key)
                                }
                            }
                            .frame(width: layout.width, height: layout.height)
                            .scaleEffect(viewport.zoom, anchor: .topLeading)
                            .frame(width: layout.width * viewport.zoom, height: layout.height * viewport.zoom, alignment: .topLeading)
                        }
                        .accessibilityLabel(copy("graphPan"))
                        .accessibilityIdentifier("worklist.graph.canvas")
                    }
            }.frame(height: 420)
        }
    }

    private func controls(_ layout: WorklistGraphLayout, size: CGSize) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { zoomControls(layout, size: size); navigation(layout) }
            VStack(alignment: .leading) { zoomControls(layout, size: size); navigation(layout) }
        }
    }

    private func zoomControls(_ layout: WorklistGraphLayout, size: CGSize) -> some View {
        HStack {
            Button(copy("graphZoomOut")) { viewport.magnify(1 / 1.25) }
                .accessibilityIdentifier("worklist.graph.zoom-out")
            Text("\(copy("graphZoom")): \(viewport.zoom.formatted(.percent.precision(.fractionLength(0))))").monospacedDigit()
            Button(copy("graphZoomIn")) { viewport.magnify(1.25) }
                .accessibilityIdentifier("worklist.graph.zoom-in")
            Button(copy("graphFit")) { viewport.fit(layout: layout, width: size.width, height: max(1, size.height - 80)) }
                .accessibilityIdentifier("worklist.graph.fit")
        }
    }

    private func navigation(_ layout: WorklistGraphLayout) -> some View {
        HStack {
            Button(copy("graphPrevious")) { select(layout.adjacent(to: selection, direction: -1)) }
                .disabled(layout.nodes.isEmpty).accessibilityIdentifier("worklist.graph.previous")
            Button(copy("graphNext")) { select(layout.adjacent(to: selection, direction: 1)) }
                .disabled(layout.nodes.isEmpty).accessibilityIdentifier("worklist.graph.next")
            Button(copy("graphFocus")) { focus() }
                .disabled(!layout.nodes.contains(where: { $0.item.key == selection }))
                .accessibilityIdentifier("worklist.graph.focus")
        }
    }

    private func select(_ key: ApprovedWorklistKey?) {
        selection = key
        focus()
    }

    private func focus() {
        if selection != nil { focusRequest += 1 }
    }

    private func nodeButton(_ node: WorklistGraphNode) -> some View {
        let item = node.item
        return Button { selection = item.key } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle).font(.headline).lineLimit(2)
                if showScopeMetadata { Text(item.key.memberID).font(.caption).lineLimit(1) }
                Text("\(copy("committedPosition")): \(item.committedPosition + 1)").font(.caption)
                Text("\(copy("active")): \(copy(item.facts.active.rawValue)) · \(copy("completed")): \(copy(item.facts.completed.rawValue))").font(.caption)
                Text("\(copy("eligible")): \(copy(item.facts.eligible.rawValue))").font(.caption)
                Text(item.blockers.map { showScopeMetadata ? $0.code : copy($0.kind.rawValue) }.joined(separator: ", ")).font(.caption).lineLimit(2)
                if node.contextOnly { Text(copy("graphFiltered")).font(.caption).italic() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == item.key ? Color.accentColor : Color.secondary, lineWidth: selection == item.key ? 3 : 1))
        }
        .buttonStyle(.plain)
        .opacity(node.contextOnly ? 0.65 : 1)
        .accessibilityLabel(Self.nodeLabel(node, language: locale.language.languageCode?.identifier ?? "en", showScopeMetadata: showScopeMetadata, humanNames: humanNames))
        .accessibilityIdentifier("worklist.graph.node.\(item.key.memberID)")
    }

    static func nodeLabel(_ node: WorklistGraphNode, language: String, showScopeMetadata: Bool = true, humanNames: [String: String] = [:]) -> String {
        let item = node.item
        func text(_ key: String) -> String { WorklistCopy.text(key, language: language) }
        let dependencies = item.dependencies.map { showScopeMetadata ? $0 : humanNames[$0] ?? text("graphMissing") }
        let reasons = item.blockers.map { showScopeMetadata ? $0.code : text($0.kind.rawValue) }
        return "\(item.displayTitle), \(text("committedPosition")) \(item.committedPosition + 1), \(text("active")) \(text(item.facts.active.rawValue)), \(text("completed")) \(text(item.facts.completed.rawValue)), \(text("dependencies")): \(dependencies.joined(separator: ", ")), \(reasons.joined(separator: ", "))" + (node.contextOnly ? ", " + text("graphFiltered") : "")
    }

    private func x(_ node: WorklistGraphNode) -> Double { 16 + Double(node.column) * WorklistGraphLayout.columnStride + WorklistGraphLayout.nodeWidth / 2 }
    private func y(_ node: WorklistGraphNode, layout: WorklistGraphLayout) -> Double { layout.topInset + Double(node.row) * WorklistGraphLayout.rowStride + WorklistGraphLayout.nodeHeight / 2 }

    private func connections(_ layout: WorklistGraphLayout) -> some View {
        Canvas { context, _ in
            for (index, edge) in layout.edges.enumerated() {
                let points = layout.route(edge, index: index)
                if let start = points.first, let end = points.last {
                    var path = Path()
                    path.move(to: start)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.move(to: CGPoint(x: end.x - 8, y: end.y - 5)); path.addLine(to: end)
                    path.addLine(to: CGPoint(x: end.x - 8, y: end.y + 5))
                    context.stroke(path, with: .color(.secondary), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
            }
        }.accessibilityHidden(true)
    }
}

// A positioned SwiftUI canvas target can describe the canvas instead of its card.
// Resolve the actual card through its local AppKit geometry, including outer clips.
struct WorklistGraphFocusTarget: NSViewRepresentable {
    let request: Int
    func makeNSView(context: Context) -> WorklistGraphFocusMarker { WorklistGraphFocusMarker() }
    func updateNSView(_ view: WorklistGraphFocusMarker, context: Context) {
        view.request = request
        guard request > 0, request != view.completedRequest else { return }
        DispatchQueue.main.async { [weak view] in
            guard let view, view.request == request else { return }
            view.layoutSubtreeIfNeeded()
            WorklistGraphFocusMarker.reveal(view)
            view.completedRequest = request
        }
    }
}

final class WorklistGraphFocusMarker: NSView {
    var request = 0
    var completedRequest = 0
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    static func reveal(_ card: NSView) {
        var ancestor = card.superview
        while let view = ancestor {
            if let clip = view as? NSClipView {
                let target = card.convert(card.bounds, to: clip)
                var bounds = clip.bounds
                // Keep oversized cards scrollable; centering never changes zoom.
                bounds.origin = CGPoint(x: target.midX - bounds.width / 2,
                                        y: target.midY - bounds.height / 2)
                let constrained = clip.constrainBoundsRect(bounds)
                clip.scroll(to: constrained.origin)
                clip.enclosingScrollView?.reflectScrolledClipView(clip)
            }
            ancestor = view.superview
        }
    }
}
