import SwiftUI

// The graph receives the same atomic observation and selection as the list.
struct WorklistDependencyGraph: View {
    let snapshot: ApprovedWorklistSnapshot
    let matching: Set<ApprovedWorklistKey>
    @Binding var selection: ApprovedWorklistKey?
    @Environment(\.locale) private var locale
    @State private var viewport = WorklistGraphViewport()

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
                Text(copy("graphMissing") + ": " + layout.unresolvedDependencies.joined(separator: ", "))
                    .font(.caption).accessibilityIdentifier("worklist.graph.missing")
            }
            GeometryReader { geometry in
                ScrollViewReader { reader in
                    VStack(alignment: .leading) {
                        controls(layout, reader: reader, size: geometry.size)
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                connections(layout)
                                ForEach(layout.nodes, id: \.item.key) { node in
                                    nodeButton(node)
                                        .frame(width: WorklistGraphLayout.nodeWidth, height: WorklistGraphLayout.nodeHeight)
                                        .position(x: x(node), y: y(node))
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
                }
            }.frame(height: 420)
        }.accessibilityIdentifier("worklist.graph")
    }

    private func controls(_ layout: WorklistGraphLayout, reader: ScrollViewProxy, size: CGSize) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { zoomControls(layout, size: size); navigation(layout, reader: reader) }
            VStack(alignment: .leading) { zoomControls(layout, size: size); navigation(layout, reader: reader) }
        }
    }

    private func zoomControls(_ layout: WorklistGraphLayout, size: CGSize) -> some View {
        HStack {
            Button(copy("graphZoomOut")) { viewport.magnify(1 / 1.25) }
                .accessibilityIdentifier("worklist.graph.zoom-out")
            Text(viewport.zoom, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                .accessibilityLabel(copy("graphZoom"))
            Button(copy("graphZoomIn")) { viewport.magnify(1.25) }
                .accessibilityIdentifier("worklist.graph.zoom-in")
            Button(copy("graphFit")) { viewport.fit(layout: layout, width: size.width, height: max(1, size.height - 80)) }
                .accessibilityIdentifier("worklist.graph.fit")
        }
    }

    private func navigation(_ layout: WorklistGraphLayout, reader: ScrollViewProxy) -> some View {
        HStack {
            Button(copy("graphPrevious")) { select(layout.adjacent(to: selection, direction: -1), reader: reader) }
                .disabled(layout.nodes.isEmpty).accessibilityIdentifier("worklist.graph.previous")
            Button(copy("graphNext")) { select(layout.adjacent(to: selection, direction: 1), reader: reader) }
                .disabled(layout.nodes.isEmpty).accessibilityIdentifier("worklist.graph.next")
            Button(copy("graphFocus")) { focus(reader) }
                .disabled(!layout.nodes.contains(where: { $0.item.key == selection }))
                .accessibilityIdentifier("worklist.graph.focus")
        }
    }

    private func select(_ key: ApprovedWorklistKey?, reader: ScrollViewProxy) {
        selection = key
        focus(reader)
    }

    private func focus(_ reader: ScrollViewProxy) {
        if let selection { reader.scrollTo(selection, anchor: .center) }
    }

    private func nodeButton(_ node: WorklistGraphNode) -> some View {
        let item = node.item
        return Button { selection = item.key } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle).font(.headline).lineLimit(2)
                Text(item.key.memberID).font(.caption).lineLimit(1)
                Text("\(copy("committedPosition")): \(item.committedPosition + 1)").font(.caption)
                Text("\(copy("active")): \(copy(item.facts.active.rawValue)) · \(copy("completed")): \(copy(item.facts.completed.rawValue))").font(.caption)
                Text("\(copy("eligible")): \(copy(item.facts.eligible.rawValue))").font(.caption)
                Text(item.blockers.map(\.code).joined(separator: ", ")).font(.caption).lineLimit(2)
                if node.contextOnly { Text(copy("graphFiltered")).font(.caption).italic() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(10)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == item.key ? Color.accentColor : Color.secondary, lineWidth: selection == item.key ? 3 : 1))
        }
        .buttonStyle(.plain)
        .opacity(node.contextOnly ? 0.65 : 1)
        .accessibilityLabel("\(item.displayTitle), \(copy("committedPosition")) \(item.committedPosition + 1), \(copy("active")) \(copy(item.facts.active.rawValue)), \(copy("completed")) \(copy(item.facts.completed.rawValue)), \(copy("dependencies")): \(item.dependencies.joined(separator: ", ")), \(item.blockers.map(\.code).joined(separator: ", "))")
        .accessibilityIdentifier("worklist.graph.node.\(item.key.memberID)")
    }

    private func x(_ node: WorklistGraphNode) -> Double { 16 + Double(node.column) * WorklistGraphLayout.columnStride + WorklistGraphLayout.nodeWidth / 2 }
    private func y(_ node: WorklistGraphNode) -> Double { 16 + Double(node.row) * WorklistGraphLayout.rowStride + WorklistGraphLayout.nodeHeight / 2 }

    private func connections(_ layout: WorklistGraphLayout) -> some View {
        Canvas { context, _ in
            let byID = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.item.key.memberID, $0) })
            for edge in layout.edges {
                if let from = byID[edge.predecessor], let to = byID[edge.dependent] {
                    let start = CGPoint(x: x(from) + WorklistGraphLayout.nodeWidth / 2, y: y(from))
                    let end = CGPoint(x: x(to) - WorklistGraphLayout.nodeWidth / 2, y: y(to))
                    var path = Path()
                    path.move(to: start)
                    path.addCurve(to: end, control1: CGPoint(x: start.x + 36, y: start.y), control2: CGPoint(x: end.x - 36, y: end.y))
                    path.move(to: CGPoint(x: end.x - 8, y: end.y - 5)); path.addLine(to: end)
                    path.addLine(to: CGPoint(x: end.x - 8, y: end.y + 5))
                    context.stroke(path, with: .color(.secondary), lineWidth: 2)
                }
            }
        }.accessibilityHidden(true)
    }
}
