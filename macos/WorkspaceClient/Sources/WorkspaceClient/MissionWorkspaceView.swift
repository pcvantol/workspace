import SwiftUI

struct MissionWorkspaceView: View {
    let observation: MissionWorkspaceObservation?
    let selectedID: String?
    let canRefine: Bool
    let canApprove: Bool
    let onRefine: (String, String, MissionDefinitionCard?) -> Void
    let onApprove: (MissionDefinitionCard) -> Void
    let onSelect:(MissionDefinitionCard)->Void
    let onSeparate:(MissionSuggestedResult,MissionDefinitionCard)->Void
    @State private var selection: String?
    @State private var search = ""
    @State private var statusFilter = ""
    @State private var panel = "chat"
    @State private var graph = false
    @State private var message = ""
    @State private var lens = "BUSINESS"
    @State private var zoom = 1.0
    @State private var presentationScope: String?
    @FocusState private var messageFocused: Bool
    @Environment(\.locale) private var locale
    @Environment(\.nativeTabCommandsActive) private var commandsActive

    init(observation: MissionWorkspaceObservation?, canRefine: Bool, canApprove: Bool,
         selectedID: String? = nil, draftMessage:String="", activePanel: String = "chat", showGraph: Bool = false,
         onRefine: @escaping (String, String, MissionDefinitionCard?) -> Void, onApprove: @escaping (MissionDefinitionCard) -> Void, onSelect:@escaping(MissionDefinitionCard)->Void = { _ in },onSeparate:@escaping(MissionSuggestedResult,MissionDefinitionCard)->Void = { _, _ in }) {
        self.selectedID=selectedID
        self.observation = observation; self.canRefine = canRefine; self.canApprove = canApprove
        self.onRefine = onRefine; self.onApprove = onApprove;self.onSelect=onSelect;self.onSeparate=onSeparate
        _message=State(initialValue:draftMessage)
        _selection = State(initialValue: observation?.selected(selectedID)?.id)
        _presentationScope = State(initialValue: observation?.scopeKey)
        _panel = State(initialValue: ["overview", "chat", "definition"].contains(activePanel) ? activePanel : "chat")
        _graph = State(initialValue: showGraph)
    }

    private func copy(_ key: String) -> String {
        MissionWorkspaceCopy.text(key, language: locale.language.languageCode?.identifier ?? "en")
    }
    private var card: MissionDefinitionCard? { observation?.selected(selection) ?? observation?.selected(selectedID) }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(copy("missions")).font(.title2.bold())
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }.accessibilityLabel(copy("settings"))
                }
                if geometry.size.width >= 1050 {
                    HSplitView {
                        overview.frame(minWidth:220,idealWidth:260,maxWidth:320).clipped()
                        conversation.frame(minWidth:320,maxWidth:.infinity).clipped()
                        definition.frame(minWidth:280,idealWidth:340,maxWidth:440).clipped()
                    }
                } else {
                    Text(copy("panel")).font(.caption).foregroundStyle(.secondary)
                    Picker(copy("panel"), selection: $panel) {
                        Text(copy("overview")).tag("overview")
                        Text(copy("chat")).tag("chat")
                        Text(copy("definition")).tag("definition")
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(copy("panel")).accessibilityIdentifier("mission.panel")
                    switch panel {
                    case "overview": overview
                    case "definition": definition
                    default: conversation
                    }
                }
            }.padding(20)
        }
        .onChange(of: observation?.scopeKey) { _, scope in
            message = ""
            // A temporarily unavailable snapshot hides content, but should not
            // discard navigation within the same authorized project.
            guard let scope else { return }
            if presentationScope != scope {
                selection = observation?.selected(selectedID)?.id
                search = ""; statusFilter = ""; zoom = 1; panel = "chat"
            }
            presentationScope = scope
        }
        .onChange(of:selectedID) { _, id in
            if let id { selection=observation?.selected(id)?.id }
        }
        .onChange(of: observation?.cards.map(\.id)) { _, ids in
            if let ids, let selection, !ids.contains(selection) { self.selection = nil }
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(copy("search"), text: $search).accessibilityIdentifier("mission.search")
            Text(copy("display")).font(.caption).foregroundStyle(.secondary)
            Picker(copy("display"), selection: $graph) {
                Text(copy("list")).tag(false)
                Text(copy("dependencies")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(copy("display")).accessibilityIdentifier("mission.display")
            if let observation {
                Picker(copy("statusFilter"), selection: $statusFilter) {
                    Text(copy("allStatuses")).tag("")
                    ForEach(Array(Set(observation.cards.map(\.status))).sorted(), id: \.self) { status in
                        Text(copy(status)).tag(status)
                    }
                }.accessibilityIdentifier("mission.status-filter")
                Text(observation.project).font(.headline)
                if graph { dependencyGraph(observation) }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            let cards = observation.matching(search: search, status: statusFilter.isEmpty ? nil : statusFilter)
                            ForEach(Array(Set(cards.map(\.group))).sorted(), id: \.self) { group in
                                DisclosureGroup(group.isEmpty ? copy("concepts") : group) {
                                    ForEach(cards.filter { $0.group == group }) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Button { selection = item.id; panel = "definition";onSelect(item) } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.title).font(.headline)
                                                    Text(item.value).font(.caption).foregroundStyle(.secondary)
                                                    Text(copy(item.status)).font(.caption)
                                                    if !item.labels.isEmpty { Text(item.labels.map { copy($0) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                                }.frame(maxWidth: .infinity, alignment: .leading)
                                            }.buttonStyle(.plain).padding(8)
                                                .focusable(interactions: .edit)
                                                .onKeyPress(keys: [.return, .space]) { _ in
                                                    selection = item.id; panel = "definition"; onSelect(item)
                                                    return .handled
                                                }
                                                .background(selection == item.id ? Color.accentColor.opacity(0.12) : Color.clear)
                                                .accessibilityIdentifier("mission.select." + item.id)
                                            DisclosureGroup(copy("outcomes")) {
                                                Text(item.outcome)
                                            }
                                            DisclosureGroup(copy("done")) {
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
            if let card {
                Text(card.title).font(.title3.bold())
                Text(copy(card.status)).font(.caption).foregroundStyle(.secondary)
            }
            Picker(copy("lens"), selection: $lens) {
                Text(copy("business")).tag("BUSINESS")
                Text(copy("architect")).tag("ARCHITECTURE")
            }.pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if (observation?.transcript ?? []).isEmpty { Text(copy("prompt")).foregroundStyle(.secondary) }
                    ForEach(observation?.transcript ?? []) { line in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(copy(line.role)).font(.caption.bold()).foregroundStyle(.secondary)
                            Text(line.text).textSelection(.enabled)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(line.role == "USER" ? Color.secondary.opacity(0.07) : Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let card, !card.questions.isEmpty {
                        ForEach(card.questions.filter { question in !(observation?.transcript ?? []).contains(where: { $0.text == question }) }, id: \.self) { question in
                            Text(question).padding(12).background(Color.accentColor.opacity(0.08))
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("mission.transcript")
            TextEditor(text: $message).scrollContentBackground(.hidden)
                .padding(10).background(.background,in:RoundedRectangle(cornerRadius:14))
                .frame(minHeight: 90, maxHeight: 150)
                .focused($messageFocused).accessibilityLabel(copy("message"))
                .accessibilityIdentifier("mission.message")
            Button(copy("send")) { onRefine(message, lens, card) }
                .keyboardShortcut(commandsActive ? KeyboardShortcut(.return, modifiers: .command) : nil)
                .disabled(!canRefine || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("mission.refine")
            if !canRefine { Text(copy("connection")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var definition: some View {
        VStack(alignment: .leading, spacing: 12) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy("definition")).font(.headline)
                if let card {
                    Text(card.title).font(.title2.bold())
                    Text(copy(card.status)).foregroundStyle(.secondary)
                    if let objective = card.objective { section("objective", [objective]) }
                    section("value", [card.value])
                    section("outcomes", [card.outcome])
                    section("scope", card.scope)
                    section("components",card.components ?? [])
                    if let results=card.suggestedResults,!results.isEmpty {
                        DisclosureGroup(copy("suggestedResults")) {
                            ForEach(Array(results.enumerated()),id:\.offset) { _,result in
                                VStack(alignment:.leading,spacing:6) {
                                    Text(result.title).font(.headline)
                                    Text(copy("suggestedOnly")).font(.caption).foregroundStyle(.secondary)
                                    Text(result.expected_result)
                                    section("done",result.acceptance_criteria)
                                    Button(copy("separateSuggestion")) { onSeparate(result,card) }
                                        .disabled(!canRefine).accessibilityLabel(copy("separateSuggestion")+": "+result.title)
                                }.padding(.vertical,4)
                            }
                        }
                    }
                    section("excluded", card.exclusions)
                    section("done", card.criteria)
                    section("questions", card.questions)
                    section("changes", card.changes)
                    section("consequences", card.consequences ?? [copy("notEstablished")])
                    section("architectureChoices", card.architectureChoices ?? [])
                    section("risks", card.risks ?? [copy("notEstablished")])
                    let recorded = card.canonicalHistory?.contains { $0.definition_revision == card.revision } == true
                    section(recorded ? "recordedApprovalGates" : "remainingDecisions", card.remainingDecisions ?? [copy("notEstablished")])
                    if let blockers=card.blockers,!blockers.isEmpty {
                        section("blockers",blockers.map { MissionWorkspaceCopy.blocker($0,language:locale.language.languageCode?.identifier ?? "en") })
                    }
                    if let observation {
                        section("dependencies", observation.visibleRelations.filter { $0.dependent == card.id }
                            .map { edge in copy(edge.proposed ? "proposed" : "established") + " · " + (observation.selected(edge.predecessor)?.title ?? "") + (edge.sourceRevision.map { " · "+copy("revision")+" "+String($0) } ?? "") + ": " + edge.reason })
                    }
                    if let history=card.canonicalHistory,!history.isEmpty {
                        section("canonicalHistory",history.map { copy("recordedVersion")+" "+String($0.definition_revision)+($0.definition_revision==card.revision ? "":" · "+copy("olderApproval")) })
                    }
                    if card.physicalExecutionReady==false { section("executionStatus",[copy("executionUnobserved")]) }
                    DisclosureGroup(copy("inspector")) {
                        LabeledContent(copy("revision"), value: String(card.revision))
                    }
                } else { Text(copy("choose")).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if let card {
            Divider()
            Text(card.title + " · " + copy("revision") + " " + String(card.revision)).font(.caption.bold())
            Button(copy("approve")) { onApprove(card) }
                .buttonStyle(.glassProminent)
                .disabled(!canApprove || card.consequences == nil || card.risks == nil || card.remainingDecisions == nil || !card.questions.isEmpty)
                .accessibilityIdentifier("mission.approve")
            Text(copy("approvalEffect")).font(.caption).foregroundStyle(.secondary)
            if !canApprove {
                let recorded = card.canonicalHistory?.contains { $0.definition_revision == card.revision } == true
                Text(copy(recorded ? card.status : "approveUnavailable")).font(.caption).foregroundStyle(.secondary)
            }
        }
        }
    }
    private func section(_ key: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !lines.isEmpty {
                Text(copy(key)).font(.subheadline.bold())
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in Text(key == "consequences" ? copy(line):line).textSelection(.enabled) }
            }
        }
    }
    private func dependencyGraph(_ observation: MissionWorkspaceObservation) -> some View {
        let width = WorklistGraphLayout.nodeWidth
        let height = max(180, Double(observation.cards.count) * WorklistGraphLayout.rowStride + 40)
        let canvasWidth = width + 40
        let matching = Set(observation.matching(search: search, status: statusFilter.isEmpty ? nil : statusFilter).map(\.id))
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                Button(copy("zoomOut")) { zoom = max(0.25, zoom / 1.25) }
                Button(copy("zoomIn")) { zoom = min(2, zoom * 1.25) }
                }
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
                                let a = CGPoint(x: 20 + width / 2,
                                                y: 20 + Double(from) * WorklistGraphLayout.rowStride + 80)
                                let b = CGPoint(x: 20 + width / 2,
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
                            Button { selection = item.id;onSelect(item) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.headline)
                                    Text(copy(item.status)).font(.caption)
                                }.padding(12).frame(width: width, height: 80, alignment: .leading)
                                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selection == item.id ? Color.accentColor : .secondary))
                            }.buttonStyle(.plain)
                                .focusable(interactions: .edit)
                                .onKeyPress(keys: [.return, .space]) { _ in
                                    selection = item.id; onSelect(item)
                                    return .handled
                                }
                                .position(x: 20 + width / 2,
                                          y: 60 + Double(index) * WorklistGraphLayout.rowStride)
                                .opacity(matching.contains(item.id) ? 1 : 0.45)
                                .id(item.id).accessibilityIdentifier("mission.graph.node." + item.id)
                        }
                    }.frame(width: canvasWidth, height: height)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: canvasWidth * zoom, height: height * zoom, alignment: .topLeading)
                }.clipped().accessibilityIdentifier("mission.graph")
            }
            if let selection {
                ForEach(Array(observation.visibleRelations.filter { $0.dependent == selection || $0.predecessor == selection }.enumerated()), id: \.offset) { _, edge in
                    Text(relationLabel(edge, observation: observation))
                        .font(.caption).textSelection(.enabled)
                }
            }
        }
    }
    private func relationLabel(_ edge: MissionRelation, observation: MissionWorkspaceObservation) -> String {
        var label = copy(edge.proposed ? "proposed" : "established")
        label += " · "
        label += observation.selected(edge.predecessor)?.title ?? ""
        label += " → "
        label += observation.selected(edge.dependent)?.title ?? ""
        if let revision = edge.sourceRevision {
            label += " · " + copy("revision") + " " + String(revision)
        }
        label += ": "
        label += edge.reason
        return label
    }
}
