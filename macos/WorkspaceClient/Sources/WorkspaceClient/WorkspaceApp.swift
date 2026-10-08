import Combine
import SwiftUI
#if WORKSPACE_ISOLATED_TEST
import AppKit

private enum IsolatedWindowEvidence {
    static func capture(in directory: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard let app=NSApp else { return }
            // Apply the isolated theme after AppKit creates the application.
            if let theme=ProcessInfo.processInfo.environment["WORKSPACE_ISOLATED_THEME"],
               ["light","dark"].contains(theme),
               let appearance=NSAppearance(named:theme=="dark" ? .darkAqua:.aqua) {
                app.appearance=appearance
                try? await Task.sleep(for:.milliseconds(200))
            }
            guard let window = NSApp.windows.first(where: { $0.title == "Workspace" }),
                  let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                      CGWindowID(window.windowNumber),
                                                      [.boundsIgnoreFraming, .bestResolution]) else { return }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
            let root = URL(fileURLWithPath: directory, isDirectory: true)
            let facts:[String:Any]=["pid":ProcessInfo.processInfo.processIdentifier,
                "appearance":window.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua])?.rawValue ?? "unknown",
                "locale":WorkspaceLanguage.current,"preferred_languages":Locale.preferredLanguages,"width":window.frame.width,"height":window.frame.height]
            if let data=try? JSONSerialization.data(withJSONObject:facts,options:.sortedKeys) {
                try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                try? data.write(to:root.appendingPathComponent("window-facts.public.json"),options:.atomic)
            }
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
            advisory: AdvisoryState(credentials: IsolatedAdvisoryCredentials(document)),
            candidates:CandidateState(credentials:IsolatedCandidateCredentials(document),
                store:PrivateCandidateLocalStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("candidate-drafts")))))
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

    @AppStorage(WorkspaceLanguage.key) private var language="system"
    var body: some Scene {
        WindowGroup("Workspace") {
            ContentView(client: client, conversations: conversations, reviews: reviews, worklists: worklists)
                .environment(\.locale,Locale(identifier:WorkspaceLanguage.resolve(language)))
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 900, height: 650)
        Settings {
            SettingsView(client: client, conversations: conversations)
                .environment(\.locale,Locale(identifier:WorkspaceLanguage.resolve(language)))
                .frame(width: 490)
                .padding(24)
        }
    }
}

struct ContentView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var client: ClientState
    @StateObject private var conversations: ConversationState
    @StateObject private var reviews: MissionReviewState
    @StateObject private var worklists: WorklistState
    @State private var selectedTab = 4
    @State private var requestedReview: MissionReviewKey?
    @State private var reviewNavigationStatus = ""

    init(client: ClientState, conversations: ConversationState = ConversationState(),
         reviews: MissionReviewState = MissionReviewState(), worklists: WorklistState = WorklistState()) {
        self.client = client
        _conversations = StateObject(wrappedValue: conversations)
        _reviews = StateObject(wrappedValue: reviews)
        _worklists = StateObject(wrappedValue: worklists)
    }

    private var missionObservation: MissionWorkspaceObservation? {
        #if WORKSPACE_ISOLATED_TEST
        if let path = ProcessInfo.processInfo.environment["WORKSPACE_ISOLATED_MISSION_PREVIEW"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 65536 {
            return try? JSONDecoder().decode(MissionWorkspaceObservation.self, from: data)
        }
        #endif
        return nil
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
            MissionWorkspaceView(observation: missionObservation, canRefine: false, canApprove: false,
                                 onRefine: { _, _ in }, onApprove: { _ in })
                .tabItem { Label(MissionWorkspaceCopy.text("missions", language: locale.language.languageCode?.identifier ?? "en"), systemImage: "bubble.left.and.text.bubble.right") }.tag(4)
            ConversationsView(client: client, state: conversations)
                .environment(\.nativeTabCommandsActive, selectedTab == 0)
                .tabItem { Label(ConversationCopy.text("nav",language:locale.language.languageCode?.identifier), systemImage: "bubble.left.and.bubble.right") }.tag(0)
            LiveMissionReviewsView(client: client, state: reviews, selection: $requestedReview)
                .environment(\.nativeTabCommandsActive, selectedTab == 1)
                .tabItem { Label(MissionReviewCopy.text("nav",language:locale.language.languageCode?.identifier), systemImage: "checkmark.seal") }.tag(1)
            LiveApprovedWorklistView(client: client, state: worklists,
                reviewNavigationStatus: reviewNavigationStatus, onOpenReviews: openReview)
                .environment(\.nativeTabCommandsActive, selectedTab == 2)
                .tabItem { Label(WorklistCopy.text("nav",language:locale.language.languageCode?.identifier), systemImage: "list.bullet.rectangle") }.tag(2)
            ServerOverviewView(client: client)
                .tabItem { Label(WorkspaceCopy.text("Server",language:locale.language.languageCode?.identifier), systemImage: "server.rack") }.tag(3)
        }
    }
}

struct ServerOverviewView: View {
    @Environment(\.locale) private var locale
    @ObservedObject var client: ClientState
    @Environment(\.scenePhase) private var scenePhase
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private func copy(_ key:String) -> String { WorkspaceCopy.text(key,language:locale.language.languageCode?.identifier) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Workspace").font(.largeTitle.bold())
                    Text(copy("Read-only Server connection")).foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Label(copy("Settings"), systemImage: "gearshape") }
                Button(copy("Reconnect")) { client.reconnect() }
                    .disabled(client.savedEndpoint.isEmpty ||
                              ["LOADING", "CONNECTING", "SAVING", "FORGETTING"].contains(client.phase))
                if client.phase == "LOADING" || client.phase == "CONNECTING" {
                    Button(copy("Cancel")) { client.cancel() }
                }
            }
            SectionCard(copy("Connection")) {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(copy("State"), value: copy(client.phase))
                    LabeledContent(copy("Server"), value: client.savedEndpoint.isEmpty ? copy("Not paired") : client.savedEndpoint)
                    LabeledContent(copy("Instance"), value: client.savedInstance.isEmpty ? copy("Not pinned") : client.savedInstance)
                    Text(WorkspaceCopy.detail(client.detail,language:locale.language.languageCode?.identifier)).foregroundStyle(client.phase == "CONNECTED" ? .primary : .secondary)
                        .textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let snapshot = client.snapshot {
                SectionCard(copy("Server")) {
                    VStack(alignment: .leading) {
                        LabeledContent(copy("Version"), value: snapshot.status.version)
                        LabeledContent(copy("State"), value: copy(snapshot.status.state))
                        LabeledContent(copy("Project source"), value: copy(snapshot.status.project_source))
                        LabeledContent(copy("Read at"), value: snapshot.observedAt.formatted(.dateTime.locale(locale)))
                        if client.phase != "CONNECTED" {
                            Text(copy("Cached read — current Server state is unavailable")).foregroundStyle(.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                SectionCard(copy("Forge read")) {
                    VStack(alignment: .leading, spacing: 8) {
                        switch snapshot.forge {
                        case .success(let forge):
                            LabeledContent(copy("State"), value: copy(forge.state))
                            if forge.state == "OBSERVED" {
                                LabeledContent(copy("Forge version"), value: forge.product_version ?? copy("Unknown"))
                                LabeledContent(copy("Instance"), value: forge.instance_id ?? copy("Unknown"))
                                LabeledContent(copy("Repository"), value: forge.repository_id ?? copy("Unknown"))
                                LabeledContent(copy("Availability"), value: copy(forge.availability ?? "Unknown"))
                                LabeledContent(copy("Freshness"), value: copy(forge.freshness ?? "UNKNOWN"))
                                LabeledContent(copy("Source observed"), value: forge.source_observed_at ?? copy("No source time"))
                                LabeledContent(copy("Retrieved"), value: forge.retrieved_at ?? copy("No retrieval time"))
                                if !forge.isCurrent {
                                    Text(copy("Forge has no current available observation"))
                                        .foregroundStyle(.orange)
                                }
                            } else {
                                Text(copy("No verified Forge observation"))
                                    .foregroundStyle(.orange)
                            }
                        case .failure:
                            Text(copy("Forge read unavailable"))
                                .foregroundStyle(.orange)
                        }
                        if client.phase != "CONNECTED" {
                            Text(copy("Cached read — reconnect to check Forge again"))
                                .foregroundStyle(.orange)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top, spacing: 16) {
                    SectionCard(copy("Projects")) {
                        VStack(alignment: .leading, spacing: 8) {
                            switch snapshot.projects {
                            case .success(let catalogue):
                                LabeledContent(copy("State"), value: copy(catalogue.state))
                                LabeledContent(copy("Source"), value: copy(catalogue.source ?? "Unconfigured"))
                                LabeledContent(copy("Observed"), value: catalogue.observed_at ?? copy("No source observation"))
                                if catalogue.partial { Text(copy("Partial source data")).foregroundStyle(.orange) }
                                if catalogue.stale { Text(copy("Stale source data")).foregroundStyle(.orange) }
                                ForEach(catalogue.projects) { project in
                                    HStack { Text(project.name); Spacer(); Text(project.id).foregroundStyle(.secondary) }
                                }
                            case .failure:
                                Text(copy("Unavailable")).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SectionCard(copy("Capabilities")) {
                        VStack(alignment: .leading, spacing: 8) {
                            switch snapshot.capabilities {
                            case .success(let inventory):
                                Text(copy(inventory.peer_operations_qualified ? "Peer operations qualified" : "Peer operations unqualified"))
                                    .foregroundStyle(.secondary)
                                ForEach(inventory.operations) { operation in
                                    HStack { Text(operation.id); Spacer(); Text(copy(operation.exposure)).font(.caption).foregroundStyle(.secondary) }
                                }
                            case .failure:
                                Text(copy("Unavailable")).foregroundStyle(.orange)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                ContentUnavailableView(copy("No Server read yet"), systemImage: "network.slash",
                                       description: Text(copy("Open Settings to pair an installed Workspace Server.")))
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
    @AppStorage(WorkspaceLanguage.key) private var language="system"

    var body: some View {
        Form {
            Section(WorkspaceCopy.text("Language")) {
                Picker(WorkspaceCopy.text("Language"),selection:$language) {
                    Text(WorkspaceCopy.text("Follow system")).tag("system")
                    ForEach(WorkspaceLanguage.supported,id:\.self) { Text(WorkspaceLanguage.names[$0]!).tag($0) }
                }.accessibilityIdentifier("workspace.language")
            }
            Section(WorkspaceCopy.text("Workspace Server")) {
                TextField(WorkspaceCopy.text("Server address"), text: $address, prompt: Text("https://server.example"))
                    .textContentType(.URL)
                SecureField(WorkspaceCopy.text("Instance token"), text: $token)
                Text(WorkspaceCopy.text("Only loopback may use HTTP. Other Server addresses require HTTPS with normal certificate verification."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(WorkspaceCopy.text("Binding")) {
                LabeledContent(WorkspaceCopy.text("Pinned instance"), value: client.savedInstance.isEmpty ? WorkspaceCopy.text("None") : client.savedInstance)
                HStack {
                    Button(WorkspaceCopy.text("Connect")) {
                        guard !forgettingServer, !conversations.preparingServerForget else { return }
                        client.connect(address: address, enteredToken: token)
                        token = ""
                    }.disabled(forgettingServer || conversations.preparingServerForget ||
                               ["LOADING", "SAVING", "FORGETTING"].contains(client.phase))
                    Button(WorkspaceCopy.text("Forget Server")) {
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
                Text(WorkspaceCopy.text("Forget removes this app's current pairing only. Earlier pre-release pairings may still exist in Mac Keychain."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(WorkspaceCopy.detail(client.detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { address = client.savedEndpoint }
    }
}
