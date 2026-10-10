import SwiftUI
import Combine

struct WorksetReleaseView: View {
    @ObservedObject var state: WorksetReleaseState
    let items: [MissionConceptCatalogItem]
    let onRefresh: () -> Void
    var onOpenReviews: ((ApprovedWorklistItem) -> Void)? = nil
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private var language: String { locale.language.languageCode?.identifier ?? "en" }
    private func copy(_ key: String) -> String { WorksetReleaseCopy.text(key, language: language) }
    private func title(_ subject: WorksetReleaseSubject) -> String {
        items.first(where: { state.subject($0) == subject })?.title ?? ""
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(copy("list")).font(.title2.bold())
                Spacer()
                Button(copy("close")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                Button(copy("refresh"), action: onRefresh).disabled(state.busy).accessibilityIdentifier("release.refresh")
                if state.busy { ProgressView().controlSize(.small) }
            }.buttonStyle(.borderless)
            if state.pending != nil {
                Text(copy("pending"))
                Button(copy("resume")) { Task { await state.resume() } }
                    .disabled(state.busy || (state.preview == nil && state.observation?.state != "PENDING"))
                    .accessibilityIdentifier("release.resume")
            }
            if let observation = state.observation { current(observation) }
            else { selection }
        }.onReceive(timer) { _ in
            if state.observation != nil, !state.busy { onRefresh() }
        }.padding(20).frame(minWidth: 480, idealWidth: 860, minHeight: 560, idealHeight: 760)
    }
    private var selection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.selected.isEmpty { Text(copy("empty")).foregroundStyle(.secondary) }
                ForEach(Array(state.selected.enumerated()), id: \.element.candidate_id) { index, subject in
                    HStack {
                        Text("\(index+1). "+title(subject)).font(.headline)
                        Spacer()
                        Button { state.move(subject, offset: -1) } label: { Image(systemName: "arrow.up") }
                            .accessibilityLabel(copy("up")+": "+title(subject)).disabled(index == 0 || state.busy)
                        Button { state.move(subject, offset: 1) } label: { Image(systemName: "arrow.down") }
                            .accessibilityLabel(copy("down")+": "+title(subject)).disabled(index+1 == state.selected.count || state.busy)
                    }
                }
                if let preview = state.preview {
                    packet(preview)
                    if state.capability?.release_supported != true { Text(copy("RELEASE_AUTHORITY_UNAVAILABLE")).foregroundStyle(.secondary) }
                }
                else if state.phase != "current" { Text(copy(state.phase)).foregroundStyle(.secondary) }
                if state.preview == nil {
                Button(copy("preview")) { Task { await state.prepare() } }
                    .disabled(state.selected.isEmpty || state.busy || state.pending != nil || state.capability == nil)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("release.preview")
                }
                if let preview = state.preview {
                    Button(copy("release")) { Task { await state.confirmRelease() } }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(!preview.supported || state.busy || state.pending != nil || state.capability?.release_supported != true)
                        .accessibilityIdentifier("release.confirm")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func packet(_ preview: WorksetReleasePreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy("content"))
            LabeledContent(copy("expiry"), value: WorksetReleaseWire.date(preview.selection.expires_at)?.formatted(date: .abbreviated, time: .shortened) ?? "")
            LabeledContent(copy("limit"), value: String(preview.selection.maximum_activations))
            Text(copy(preview.selection.progression_mode)).font(.callout)
            Text(copy("boundary")).font(.callout)
            Text(copy("resources")).font(.callout).foregroundStyle(.secondary)
            ForEach(preview.members) { member in
                VStack(alignment: .leading, spacing: 6) {
                    Text(member.definition.title).font(.headline)
                    Text(member.definition.expected_result)
                    Text(copy(member.effectMode)).font(.callout)
                    ForEach(member.dependencies, id: \.self) { dependency in
                        Text(copy("depends")+" "+(preview.members.first { $0.id == dependency }?.definition.title ?? copy("PREDECESSOR_NOT_SELECTED")))
                    }
                    ForEach(member.humanGates, id: \.self) { Text(WorksetReleaseCopy.entries[$0] == nil ? $0 : copy($0)).font(.caption) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(Array(preview.gaps.enumerated()), id: \.offset) { _, gap in
                Text(copy(gap)).foregroundStyle(.orange)
            }
        }.accessibilityIdentifier("release.packet")
    }
    private func current(_ observation: WorksetReleaseObservation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ForEach(Array(state.history.enumerated()), id: \.element.command.operation_id) { index, intent in
                    Button(copy(intent.command.intent == "release" ? "originalRelease" : "withdrawal")+" \(index+1)") { Task { await state.observe(intent) } }
                        .disabled(state.busy).accessibilityIdentifier("release.history.\(index)")
                }
            }.buttonStyle(.glass)
            if let receipt = observation.originalReceiptData,
               let raw = try? WorksetReleaseWire.object(receipt) {
                Text(copy(raw["intent"] as? String == "release" ? "originalConfirmed" : "withdrawalConfirmed")).font(.callout)
            }
            Text(copy(state.phase)).font(.headline)
            Text(copy("resources")).foregroundStyle(.secondary)
            if let snapshot = observation.snapshot {
                ApprovedWorklistView(cache: cache(snapshot), showScopeMetadata: false, onOpenReviews: { item in onOpenReviews?(item); dismiss() }).frame(minHeight: 340)
            }
            Text(copy("boundary")).font(.callout)
            Button(copy("disarm")) { Task { await state.disarm() } }
                .disabled(state.busy || state.pending != nil || state.capability?.disarm_supported != true || state.phase == "withdrawn")
                .accessibilityIdentifier("release.disarm")
        }
    }
    private func cache(_ snapshot: ApprovedWorklistSnapshot) -> WorklistObservationCache {
        var cache = WorklistObservationCache(); cache.accept(snapshot, for: snapshot.scope); return cache
    }
}


// Owner setup is intentionally in Settings; the mission selection flow contains no technical input.
struct WorksetReleaseSetupView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var conversations: ConversationState
    @ObservedObject var state: WorksetReleaseState
    @State private var token = ""
    private func copy(_ key: String) -> String { WorksetReleaseCopy.text(key, language: WorkspaceLanguage.current) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(copy("setupHint")).font(.caption).foregroundStyle(.secondary)
            SecureField(copy("setupToken"), text: $token).accessibilityIdentifier("release.setup-token")
            HStack {
                Button(copy("pair")) {
                    let supplied = token; token = ""
                    Task { await state.saveGrant(supplied, connection: conversations.missionWorkspaceConnection(client: client)) }
                }.disabled(token.isEmpty || state.busy || client.phase != "CONNECTED")
                Button(copy("forget")) { state.forgetGrant() }.disabled(state.busy)
            }
        }
    }
}
