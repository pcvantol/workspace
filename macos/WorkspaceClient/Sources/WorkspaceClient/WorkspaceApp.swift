import Combine
import SwiftUI
#if WORKSPACE_ISOLATED_TEST
import AppKit

private enum IsolatedWindowEvidence {
    static func capture(in directory: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.title == "Workspace" }),
                  let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                      CGWindowID(window.windowNumber),
                                                      [.boundsIgnoreFraming, .bestResolution]) else { return }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            let target = root.appendingPathComponent("conversation-window.png")
            guard !FileManager.default.fileExists(atPath: target.path) else { return }
            _ = FileManager.default.createFile(atPath: target.path, contents: png,
                                               attributes: [.posixPermissions: 0o600])
        }
    }
}
#endif

private struct NativeTabCommandsKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var nativeTabCommandsActive: Bool {
        get { self[NativeTabCommandsKey.self] }
        set { self[NativeTabCommandsKey.self] = newValue }
    }
}

@main
struct WorkspaceApp: App {
    @StateObject private var client: ClientState
    @StateObject private var conversations: ConversationState
    @StateObject private var reviews: MissionReviewState
    @StateObject private var worklists: WorklistState

    init() {
        #if WORKSPACE_ISOLATED_TEST
        guard let document = try? IsolatedTestDocument.load() else {
            fatalError("Isolated test credential file is absent or invalid")
        }
        _client = StateObject(wrappedValue: ClientState(keychain: IsolatedServerCredentials(document)))
        _conversations = StateObject(wrappedValue: ConversationState(
            grants: IsolatedDraftGrant(document),
            localDrafts: PrivateLocalDraftCache(root: URL(fileURLWithPath: document.local_root)),
            advisory: AdvisoryState(credentials: IsolatedAdvisoryCredentials(document))))
        _reviews = StateObject(wrappedValue: MissionReviewState(credentials: IsolatedReviewGrant(document)))
        _worklists = StateObject(wrappedValue: WorklistState(credentials: IsolatedWorklistGrant(document),
            controls: WorklistControlState(credentials: IsolatedWorklistControlGrant(document))))
        IsolatedWindowEvidence.capture(in: document.local_root)
        #else
        _client = StateObject(wrappedValue: ClientState())
        _conversations = StateObject(wrappedValue: ConversationState())
        _reviews = StateObject(wrappedValue: MissionReviewState())
        _worklists = StateObject(wrappedValue: WorklistState())
        #endif
    }

    var body: some Scene {
        WindowGroup("Workspace") {
            ContentView(client: client, conversations: conversations, reviews: reviews, worklists: worklists)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 900, height: 650)
        Settings {
            SettingsView(client: client, conversations: conversations)
                .frame(width: 490)
                .padding(24)
        }
    }
}

struct ContentView: View {
    @ObservedObject var client: ClientState
    @StateObject private var conversations: ConversationState
    @StateObject private var reviews: MissionReviewState
    @StateObject private var worklists: WorklistState
    @State private var selectedTab = 0
    @State private var requestedReview: MissionReviewKey?
    @State private var reviewNavigationStatus = ""

    init(client: ClientState, conversations: ConversationState = ConversationState(),
         reviews: MissionReviewState = MissionReviewState(), worklists: WorklistState = WorklistState()) {
        self.client = client
        _conversations = StateObject(wrappedValue: conversations)
        _reviews = StateObject(wrappedValue: reviews)
        _worklists = StateObject(wrappedValue: worklists)
    }

    private func openReview(_ item: ApprovedWorklistItem) {
        Task { @MainActor in
            guard item.reviewDetailAvailable, let mission = item.missionID, !reviews.isBusy else {
                reviewNavigationStatus = "reviewRequired"
                return
            }
            await reviews.refresh(client: client)
            guard reviews.access == .available, reviews.actorID == item.key.actorID,
                  reviews.forgeInstanceID == item.key.forgeInstanceID,
                  let target = reviews.items.first(where: { $0.key.missionID == mission }) else {
                reviewNavigationStatus = "reviewRequired"
                return
            }
            requestedReview = target.key
            reviewNavigationStatus = ""
            selectedTab = 1
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ConversationsView(client: client, state: conversations)
                .environment(\.nativeTabCommandsActive, selectedTab == 0)
                .tabItem { Label(ConversationCopy.text("nav"), systemImage: "bubble.left.and.bubble.right") }.tag(0)
            LiveMissionReviewsView(client: client, state: reviews, selection: $requestedReview)
                .environment(\.nativeTabCommandsActive, selectedTab == 1)
                .tabItem { Label(MissionReviewCopy.text("nav"), systemImage: "checkmark.seal") }.tag(1)
            LiveApprovedWorklistView(client: client, state: worklists,
                reviewNavigationStatus: reviewNavigationStatus, onOpenReviews: openReview)
                .environment(\.nativeTabCommandsActive, selectedTab == 2)
                .tabItem { Label(WorklistCopy.text("nav"), systemImage: "list.bullet.rectangle") }.tag(2)
            ServerOverviewView(client: client)
                .tabItem { Label("Server", systemImage: "server.rack") }.tag(3)
        }
    }
}

struct ServerOverviewView: View {
    @ObservedObject var client: ClientState
    @Environment(\.scenePhase) private var scenePhase
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Workspace").font(.largeTitle.bold())
                    Text("Read-only Server connection").foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Button("Reconnect") { client.reconnect() }
                    .disabled(client.savedEndpoint.isEmpty ||
                              ["LOADING", "CONNECTING", "SAVING", "FORGETTING"].contains(client.phase))
                if client.phase == "LOADING" || client.phase == "CONNECTING" {
                    Button("Cancel") { client.cancel() }
                }
            }
            SectionCard("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("State", value: client.phase)
                    LabeledContent("Server", value: client.savedEndpoint.isEmpty ? "Not paired" : client.savedEndpoint)
                    LabeledContent("Instance", value: client.savedInstance.isEmpty ? "Not pinned" : client.savedInstance)
                    Text(client.detail).foregroundStyle(client.phase == "CONNECTED" ? .primary : .secondary)
                        .textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let snapshot = client.snapshot {
                SectionCard("Server") {
                    VStack(alignment: .leading) {
                        LabeledContent("Version", value: snapshot.status.version)
                        LabeledContent("State", value: snapshot.status.state)
                        LabeledContent("Project source", value: snapshot.status.project_source)
                        LabeledContent("Read at", value: snapshot.observedAt.formatted(date: .abbreviated, time: .standard))
                        if client.phase != "CONNECTED" {
                            Text("Cached read — current Server state is unavailable").foregroundStyle(.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                SectionCard("Forge read") {
                    VStack(alignment: .leading, spacing: 8) {
                        switch snapshot.forge {
                        case .success(let forge):
                            LabeledContent("State", value: forge.state)
                            if forge.state == "OBSERVED" {
                                LabeledContent("Forge version", value: forge.product_version ?? "Unknown")
                                LabeledContent("Instance", value: forge.instance_id ?? "Unknown")
                                LabeledContent("Repository", value: forge.repository_id ?? "Unknown")
                                LabeledContent("Availability", value: forge.availability ?? "Unknown")
                                LabeledContent("Freshness", value: forge.freshness ?? "UNKNOWN")
                                LabeledContent("Source observed", value: forge.source_observed_at ?? "No source time")
                                LabeledContent("Retrieved", value: forge.retrieved_at ?? "No retrieval time")
                                if !forge.isCurrent {
                                    Text("Forge has no current available observation")
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                Text("No verified Forge observation")
                                    .foregroundStyle(.orange)
                            }
                        case .failure(let error):
                            Text("Forge read unavailable: \(error.localizedDescription)")
                                .foregroundStyle(.orange)
                        }
                        if client.phase != "CONNECTED" {
                            Text("Cached read — reconnect to check Forge again")
                                .foregroundStyle(.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 16) {
                    SectionCard("Projects") {
                        VStack(alignment: .leading, spacing: 8) {
                            switch snapshot.projects {
                            case .success(let catalogue):
                                LabeledContent("State", value: catalogue.state)
                                LabeledContent("Source", value: catalogue.source ?? "Unconfigured")
                                LabeledContent("Observed", value: catalogue.observed_at ?? "No source observation")
                                if catalogue.partial { Text("Partial source data").foregroundStyle(.orange) }
                                if catalogue.stale { Text("Stale source data").foregroundStyle(.orange) }
                                ForEach(catalogue.projects) { project in
                                    HStack { Text(project.name); Spacer(); Text(project.id).foregroundStyle(.secondary) }
                                }
                            case .failure(let error):
                                Text("UNAVAILABLE: \(error.localizedDescription)").foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SectionCard("Capabilities") {
                        VStack(alignment: .leading, spacing: 8) {
                            switch snapshot.capabilities {
                            case .success(let inventory):
                                Text(inventory.peer_operations_qualified ? "Peer operations qualified" : "Peer operations unqualified")
                                    .foregroundStyle(.secondary)
                                ForEach(inventory.operations) { operation in
                                    HStack { Text(operation.id); Spacer(); Text(operation.exposure).font(.caption).foregroundStyle(.secondary) }
                                }
                            case .failure(let error):
                                Text("UNAVAILABLE: \(error.localizedDescription)").foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ContentUnavailableView("No Server read yet", systemImage: "network.slash",
                                       description: Text("Open Settings to pair an installed Workspace Server."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
            }
        }
        .padding(24)
        .onAppear { client.reconnect() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { client.reconnect() } }
        .onReceive(refresh) { _ in client.reconnect() }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsView: View {
    @ObservedObject var client: ClientState
    @ObservedObject var conversations: ConversationState
    @State private var address = ""
    @State private var token = ""
    @State private var forgettingServer = false

    var body: some View {
        Form {
            Section("Workspace Server") {
                TextField("Server address", text: $address, prompt: Text("https://server.example"))
                    .textContentType(.URL)
                SecureField("Instance token", text: $token)
                Text("Only loopback may use HTTP. Other Server addresses require HTTPS with normal certificate verification.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Binding") {
                LabeledContent("Pinned instance", value: client.savedInstance.isEmpty ? "None" : client.savedInstance)
                HStack {
                    Button("Connect") {
                        guard !forgettingServer, !conversations.preparingServerForget else { return }
                        client.connect(address: address, enteredToken: token)
                        token = ""
                    }.disabled(forgettingServer || conversations.preparingServerForget ||
                               ["LOADING", "SAVING", "FORGETTING"].contains(client.phase))
                    Button("Forget Server") {
                        guard !forgettingServer else { return }
                        forgettingServer = true
                        Task {
                            guard await conversations.prepareForServerForget() else {
                                forgettingServer = false
                                return
                            }
                            client.forget()
                            address = ""
                            token = ""
                            forgettingServer = false
                        }
                    }.disabled(!client.canForgetBinding ||
                               forgettingServer || conversations.preparingServerForget ||
                               ["SAVING", "FORGETTING"].contains(client.phase))
                }
                Text("Forget removes this app's current pairing only. Earlier pre-release pairings may still exist in Mac Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(client.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { address = client.savedEndpoint }
    }
}
