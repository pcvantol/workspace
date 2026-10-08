import SwiftUI

struct MissionWorkspaceView: View {
    let observation: MissionWorkspaceObservation?
    let canRefine: Bool
    let canApprove: Bool
    let onRefine: (String, String) -> Void
    let onApprove: (MissionDefinitionCard) -> Void
    @State private var selection: String?
    @State private var search = ""
    @State private var panel = "chat"
    @State private var graph = false
    @State private var message = ""
    @State private var lens = "BUSINESS"
    @State private var zoom = 1.0
    @FocusState private var messageFocused: Bool
    @Environment(\.locale) private var locale

    init(observation: MissionWorkspaceObservation?, canRefine: Bool, canApprove: Bool,
         selectedID: String? = nil, activePanel: String = "chat", showGraph: Bool = false,
         onRefine: @escaping (String, String) -> Void, onApprove: @escaping (MissionDefinitionCard) -> Void) {
        self.observation = observation; self.canRefine = canRefine; self.canApprove = canApprove
        self.onRefine = onRefine; self.onApprove = onApprove
        _selection = State(initialValue: observation?.selected(selectedID)?.id)
        _panel = State(initialValue: ["overview", "chat", "definition"].contains(activePanel) ? activePanel : "chat")
        _graph = State(initialValue: showGraph)
    }

    private func copy(_ key: String) -> String {
        MissionWorkspaceCopy.text(key, language: locale.language.languageCode?.identifier ?? "en")
    }
    private var card: MissionDefinitionCard? { observation?.selected(selection) }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(copy("missions")).font(.title2.bold())
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }.accessibilityLabel(copy("settings"))
                }
                if geometry.size.width >= 1050 {
                    HStack(alignment: .top, spacing: 20) {
                        overview.frame(width: 280)
                        conversation.frame(maxWidth: .infinity)
                        definition.frame(width: 340)
                    }
                } else {
                    Picker(copy("panel"), selection: $panel) {
                        Text(copy("overview")).tag("overview")
                        Text(copy("chat")).tag("chat")
                        Text(copy("definition")).tag("definition")
                    }.pickerStyle(.segmented).accessibilityIdentifier("mission.panel")
                    switch panel {
                    case "overview": overview
                    case "definition": definition
                    default: conversation
                    }
                }
            }.padding(20)
        }
        .onChange(of: observation?.project) { _, _ in selection = nil; message = "" }
        .onChange(of: observation?.cards.map(\.id)) { _, ids in
            if let selection, !(ids ?? []).contains(selection) { self.selection = nil }
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(copy("search"), text: $search).accessibilityIdentifier("mission.search")
            Picker(copy("display"), selection: $graph) {
                Text(copy("list")).tag(false)
                Text(copy("dependencies")).tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("mission.display")
            if let observation {
                Text(observation.project).font(.headline)
                if graph { dependencyGraph(observation) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            let cards = observation.matching(search: search, status: nil)
                            ForEach(Array(Set(cards.map(\.group))).sorted(), id: \.self) { group in
                                DisclosureGroup(group) {
                                    ForEach(cards.filter { $0.group == group }) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Button { selection = item.id; panel = "definition" } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.title).font(.headline)
                                                    Text(item.value).font(.caption).foregroundStyle(.secondary)
                                                    Text(copy(item.status)).font(.caption)
                                                }.frame(maxWidth: .infinity, alignment: .leading)
                                            }.buttonStyle(.plain).padding(8)
                                                .background(selection == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                                .accessibilityIdentifier("mission.select." + item.id)
                                            DisclosureGroup(copy("outcomes")) {
                                                Text(item.outcome)
                                                ForEach(item.criteria, id: \.self) { Text("• " + $0) }
                                            }.font(.caption)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !observation.complete { Text(copy("partial")).font(.caption).foregroundStyle(.secondary) }
                }
            } else { ContentUnavailableView(copy("empty"), systemImage: "list.bullet.rectangle", description: Text(copy("connection"))) }
        }
    }
    private var conversation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy("chat")).font(.headline)
            Picker(copy("lens"), selection: $lens) {
                Text(copy("business")).tag("BUSINESS")
                Text(copy("architect")).tag("ARCHITECTURE")
            }.pickerStyle(.segmented)
            Spacer()
            Text(copy("prompt")).foregroundStyle(.secondary)
            if let card, !card.questions.isEmpty {
                ForEach(card.questions, id: \.self) { Text($0).padding(12).background(Color.accentColor.opacity(0.08)) }
            }
            TextEditor(text: $message).frame(minHeight: 90, maxHeight: 150)
                .focused($messageFocused).accessibilityLabel(copy("message"))
                .accessibilityIdentifier("mission.message")
            Button(copy("send")) { onRefine(message, lens) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRefine || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("mission.refine")
            if !canRefine { Text(copy("connection")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var definition: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy("definition")).font(.headline)
                if let card {
                    Text(card.title).font(.title2.bold())
                    Text(copy(card.status)).foregroundStyle(.secondary)
                    section("value", [card.value])
                    section("outcomes", [card.outcome])
                    section("scope", card.scope)
                    section("excluded", card.exclusions)
                    section("done", card.criteria)
                    section("questions", card.questions)
                    section("changes", card.changes)
                    if let observation {
                        section("dependencies", observation.visibleRelations.filter { $0.dependent == card.id }
                            .map { edge in (observation.selected(edge.predecessor)?.title ?? "") + ": " + edge.reason })
                    }
                    Button(copy("approve")) { onApprove(card) }
                        .buttonStyle(.borderedProminent).disabled(!canApprove)
                        .accessibilityIdentifier("mission.approve")
                    Text(copy("approvalEffect")).font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup(copy("inspector")) {
                        LabeledContent(copy("revision"), value: String(card.revision))
                    }
                } else { Text(copy("choose")).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func section(_ key: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !lines.isEmpty {
                Text(copy(key)).font(.subheadline.bold())
                ForEach(lines, id: \.self) { Text($0).textSelection(.enabled) }
            }
        }
    }
    private func dependencyGraph(_ observation: MissionWorkspaceObservation) -> some View {
        let width = WorklistGraphLayout.nodeWidth
        let stride = WorklistGraphLayout.columnStride
        let height = max(180, Double(observation.cards.count) * WorklistGraphLayout.rowStride + 40)
        let canvasWidth = stride + width + 40
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(copy("zoomOut")) { zoom = max(0.25, zoom / 1.25) }
                Button(copy("zoomIn")) { zoom = min(2, zoom * 1.25) }
                Button(copy("fit")) { zoom = min(1, 260 / canvasWidth) }
            }
            Text(copy("edgeLegend")).font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { reader in
                Button(copy("focus")) { if let selection { reader.scrollTo(selection, anchor: .center) } }
                    .disabled(card == nil)
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for edge in observation.visibleRelations {
                                guard let from = observation.cards.firstIndex(where: { $0.id == edge.predecessor }),
                                      let to = observation.cards.firstIndex(where: { $0.id == edge.dependent }) else { continue }
                                let a = CGPoint(x: 20 + Double(from % 2) * stride + width / 2,
                                                y: 20 + Double(from) * WorklistGraphLayout.rowStride + 80)
                                let b = CGPoint(x: 20 + Double(to % 2) * stride + width / 2,
                                                y: 20 + Double(to) * WorklistGraphLayout.rowStride)
                                var path = Path()
                                path.move(to: a); path.addLine(to: b)
                                let angle = atan2(b.y - a.y, b.x - a.x)
                                path.move(to: CGPoint(x: b.x - 10 * cos(angle - .pi / 6), y: b.y - 10 * sin(angle - .pi / 6)))
                                path.addLine(to: b)
                                path.addLine(to: CGPoint(x: b.x - 10 * cos(angle + .pi / 6), y: b.y - 10 * sin(angle + .pi / 6)))
                                let selected = edge.predecessor == selection || edge.dependent == selection
                                context.stroke(path, with: .color(selected ? .accentColor : .secondary),
                                               style: StrokeStyle(lineWidth: selected ? 3 : 1.5, dash: edge.proposed ? [6, 4] : []))
                            }
                        }.accessibilityHidden(true)
                        ForEach(Array(observation.cards.enumerated()), id: \.element.id) { index, item in
                            Button { selection = item.id } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.headline)
                                    Text(copy(item.status)).font(.caption)
                                }.padding(12).frame(width: width, height: 80, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == item.id ? Color.accentColor : .secondary))
                            }.buttonStyle(.plain)
                                .position(x: 20 + Double(index % 2) * stride + width / 2,
                                          y: 60 + Double(index) * WorklistGraphLayout.rowStride)
                                .id(item.id).accessibilityIdentifier("mission.graph.node." + item.id)
                        }
                    }.frame(width: canvasWidth, height: height)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: canvasWidth * zoom, height: height * zoom, alignment: .topLeading)
                }.accessibilityIdentifier("mission.graph")
            }
            if let selection {
                ForEach(Array(observation.visibleRelations.filter { $0.dependent == selection || $0.predecessor == selection }.enumerated()), id: \.offset) { _, edge in
                    Text((observation.selected(edge.predecessor)?.title ?? "") + " → " +
                         (observation.selected(edge.dependent)?.title ?? "") + ": " + edge.reason)
                        .font(.caption).textSelection(.enabled)
                }
            }
        }
    }
}
