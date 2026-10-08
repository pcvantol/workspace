import SwiftUI
import Combine

struct LiveApprovedWorklistView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var state: WorklistState
    @ObservedObject var controls: WorklistControlState
    var reviewNavigationStatus = ""
    let onOpenReviews: (ApprovedWorklistItem) -> Void
    @Environment(\.locale) private var locale
    @State private var grant = ""
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    init(client: ClientState, state: WorklistState, reviewNavigationStatus: String = "",
         onOpenReviews: @escaping (ApprovedWorklistItem) -> Void) {
        self.client = client; self.state = state; self.controls = state.controls
        self.reviewNavigationStatus = reviewNavigationStatus; self.onOpenReviews = onOpenReviews
    }
    private func copy(_ key: String) -> String {
        WorklistCopy.text(key, language: locale.language.languageCode?.identifier)
    }
    private func connection() async -> WorklistConnection? {
        let endpoint = client.savedEndpoint, instance = client.savedInstance
        guard !endpoint.isEmpty, !instance.isEmpty, client.phase != "FORGETTING" else { return nil }
        let token = client.phase == "CONNECTED" ? try? await client.draftReadToken() : nil
        guard endpoint == client.savedEndpoint, instance == client.savedInstance else { return nil }
        return WorklistConnection(endpoint: endpoint, instanceID: instance, readToken: token)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(copy("refresh")) { Task { await state.refreshWithControls(connection: connection()) } }
                    .disabled(state.isBusy).accessibilityIdentifier("worklist.refresh")
                if state.hasGrant {
                    Button(copy("forgetGrant")) { state.forgetGrant() }.disabled(state.isBusy)
                }
                if state.isBusy { ProgressView().controlSize(.small) }
            }.padding(.horizontal, 18).padding(.top, 12)
            if !state.hasGrant || state.cache.availability == .denied {
                HStack {
                    SecureField(copy("grant"), text: $grant).textFieldStyle(.roundedBorder)
                    Button(copy("saveGrant")) {
                        let submitted = grant
                        grant = ""
                        Task { await state.saveGrant(submitted, connection: connection()) }
                    }.disabled(grant.isEmpty || state.isBusy || client.phase != "CONNECTED")
                }.padding(.horizontal, 18)
            }
            if !state.worksetIDs.isEmpty {
                Picker(copy("workset"), selection: Binding(get: { state.selectedWorkset }, set: { selected in
                    Task { await state.refresh(connection: connection(), selecting: selected) }
                })) {
                    ForEach(state.worksetIDs, id: \.self) { Text($0).tag($0) }
                }.disabled(state.isBusy).padding(.horizontal, 18).accessibilityIdentifier("worklist.workset")
            }
            if !reviewNavigationStatus.isEmpty { Text(copy(reviewNavigationStatus)).foregroundStyle(.orange).padding(.horizontal, 18) }
            WorklistControlView(state: controls, connection: connection, stateScope: state.cache.snapshot?.scope)
            ApprovedWorklistView(cache: state.cache.snapshot != nil &&
                !state.matchesObservedPairing(endpoint: client.savedEndpoint, instanceID: client.savedInstance)
                ? WorklistObservationCache() : state.cache, onOpenReviews: onOpenReviews)
        }
        .task { await state.refreshWithControls(connection: connection()) }
        .onChange(of: state.cache.snapshot?.scope) { _, scope in
            controls.invalidate()
            Task { await controls.refresh(connection: connection(), scope: scope) }
        }
        .onChange(of: controls.current?.workset_revision) { _, _ in
            Task { await state.refresh(connection: connection()) }
        }
        .onChange(of: client.phase) { _, phase in
            if phase == "FORGETTING" { state.invalidatePairing(); controls.invalidate() }
            Task {
                if phase == "CONNECTED" { await state.refreshWithControls(connection: connection()) }
                else { await state.refresh(connection: connection()) }
            }
        }
        .onChange(of: client.savedEndpoint) { _, _ in
            state.invalidatePairing(); controls.invalidate()
            Task { await state.refresh(connection: connection()) }
        }
        .onChange(of: client.savedInstance) { _, _ in
            state.invalidatePairing(); controls.invalidate()
            Task { await state.refresh(connection: connection()) }
        }
        .onReceive(timer) { _ in Task { await state.refreshWithControls(connection: connection()) } }
    }
}
