import Combine
import SwiftUI
#if WORKSPACE_ISOLATED_TEST
import AppKit
import ScreenCaptureKit
import CoreGraphics

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
            // Test capture is opt-in and must never request permission at startup.
            guard IsolatedWindowCapturePolicy.permitted(environment:ProcessInfo.processInfo.environment,
                                                        preflight:CGPreflightScreenCaptureAccess) else { return }
            guard let window=NSApp.windows.first(where: { $0.title=="Workspace" }),
                  let available=try? await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true),
                  let owned=available.windows.first(where: { $0.windowID==CGWindowID(window.windowNumber) && $0.owningApplication?.processID==ProcessInfo.processInfo.processIdentifier }) else { return }
            let configuration=SCStreamConfiguration()
            configuration.width=Int(window.frame.width*window.backingScaleFactor)
            configuration.height=Int(window.frame.height*window.backingScaleFactor)
            configuration.showsCursor=false
            guard let image=try? await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:owned),configuration:configuration) else { return }
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
        let ownClient = ClientState(keychain: IsolatedServerCredentials(document))
        _client = StateObject(wrappedValue: ownClient)
        let ownConversations = ConversationState(
            grants: IsolatedDraftGrant(document),
            localDrafts: PrivateLocalDraftCache(root: URL(fileURLWithPath: document.local_root)),
            advisory: AdvisoryState(credentials: IsolatedAdvisoryCredentials(document)),
            candidates:CandidateState(credentials:IsolatedCandidateCredentials(document),
                store:PrivateCandidateLocalStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("candidate-drafts"))),
            missionConcepts:MissionConceptState(credentials:IsolatedAdvisoryCredentials(document,mission:true),store:PrivateMissionIntentStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("mission-intents"))),
            worksetReleases:WorksetReleaseState(credentials:IsolatedWorksetReleaseCredentials(document),
                store:PrivateWorksetReleaseStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("workset-release-intents"))))
        _conversations = StateObject(wrappedValue: ownConversations)
        ownClient.bindReleaseAuthority(ownConversations.worksetReleases)
        _reviews = StateObject(wrappedValue: MissionReviewState(credentials: IsolatedReviewGrant(document)))
        _worklists = StateObject(wrappedValue: WorklistState(credentials: IsolatedWorklistGrant(document),
            controls: WorklistControlState(credentials: IsolatedWorklistControlGrant(document))))
        IsolatedWindowEvidence.capture(in: document.local_root)
        #else
        let ownClient = ClientState()
        _client = StateObject(wrappedValue: ownClient)
        let ownConversations = ConversationState()
        _conversations = StateObject(wrappedValue: ownConversations)
        ownClient.bindReleaseAuthority(ownConversations.worksetReleases)
        _reviews = StateObject(wrappedValue: MissionReviewState())
        _worklists = StateObject(wrappedValue: WorklistState())
        #endif
    }

    @AppStorage(WorkspaceLanguage.key) private var language="system"
    var body: some Scene {
        WindowGroup("Workspace") {
            ContentView(client: client, conversations: conversations, reviews: reviews, worklists: worklists)
                .environment(\.locale,Locale(identifier:WorkspaceLanguage.resolve(language)))
                .frame(minWidth: 560, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 780)
        .windowToolbarStyle(.unifiedCompact)
        Settings {
            SettingsView(client: client, conversations: conversations)
                .environment(\.locale,Locale(identifier:WorkspaceLanguage.resolve(language)))
                .frame(width: 490)
                .padding(24)
        }
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ObservedObject var client: ClientState
    @StateObject private var conversations: ConversationState
    @StateObject private var reviews: MissionReviewState
    @StateObject private var worklists: WorklistState
    @StateObject private var projectLinks = ProjectLinkState()
    @StateObject private var concepts = ProjectConceptState()
    @StateObject private var activity = ActivityState()
    @StateObject private var order = OrderState()
    private let conceptGrants: any DraftGrantStore
    @State private var selectedTab = 4
    @State private var requestedReview: MissionReviewKey?
    @State private var reviewNavigationStatus = ""

    init(client: ClientState, conversations: ConversationState = ConversationState(),
         reviews: MissionReviewState = MissionReviewState(), worklists: WorklistState = WorklistState()) {
        self.client = client
        let linkIntents: PrivateProjectLinkIntents
        #if WORKSPACE_ISOLATED_TEST
        if let document = try? IsolatedTestDocument.load() {
            conceptGrants = IsolatedDraftGrant(document)
            linkIntents = PrivateProjectLinkIntents(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("project-link-intents"))
            _order = StateObject(wrappedValue:OrderState(credentials:IsolatedOrderCredentials(document),store:OrderIntentStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("order-intents"))))
            _activity = StateObject(wrappedValue:ActivityState(credentials:IsolatedActivityCredentials(document),store:ActivityLocalStore(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("activity-views"))))
            _concepts = StateObject(wrappedValue:ProjectConceptState(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("project-concept-intents")))
        } else { conceptGrants = DraftGrantKeychain(); linkIntents = PrivateProjectLinkIntents() }
        #else
        conceptGrants = DraftGrantKeychain()
        linkIntents = PrivateProjectLinkIntents()
        #endif
        let linkGrants = conceptGrants
        _projectLinks = StateObject(wrappedValue: ProjectLinkState(reader: ProjectLinkHTTPReader(connection: { @MainActor in
            guard !client.authorizationLost else { throw ProjectLinkError.denied }
            guard client.phase == "CONNECTED" else { throw ProjectLinkError.unavailable }
            guard let access = try await Task.detached { try linkGrants.load() }.value,
                  access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance else { throw ProjectLinkError.denied }
            let token = try await client.draftReadToken()
            let paired = try await ProjectLinkHTTPReader.pairedConnection(access, bearer: token)
            guard client.phase == "CONNECTED", !client.authorizationLost,
                  access.endpoint == client.savedEndpoint, access.instanceID == client.savedInstance,
                  try await Task.detached { try linkGrants.load() }.value == access else { throw ProjectLinkError.denied }
            return paired
        }), intents:linkIntents))
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
        WorkspaceNavigationShell(selected:$selectedTab,language:locale.language.languageCode?.identifier ?? "en") { destination in
            switch destination {
            case 8:
                ProjectLinkView(state:projectLinks)
            case 5:
                ProjectConceptView(state:concepts,client:client,grants:conceptGrants)
                    .environment(\.nativeTabCommandsActive,true)
            case 0:
                ConversationsView(client:client,state:conversations)
                    .environment(\.nativeTabCommandsActive,true)
            case 1:
                LiveMissionReviewsView(client:client,state:reviews,selection:$requestedReview)
                    .environment(\.nativeTabCommandsActive,true)
            case 2:
                LiveApprovedWorklistView(client:client,state:worklists,
                    reviewNavigationStatus:reviewNavigationStatus,onOpenReviews:openReview)
                    .environment(\.nativeTabCommandsActive,true)
            case 7:
                WorksetOrderView(state:order,client:client,grants:conceptGrants,onApplied:{ access,workset in
                    if let bound=activity.access,activity.selected==workset,
                       bound.scope==access.binding.scope,bound.installation_id==access.binding.installation_id,
                       bound.worksets==access.binding.worksets,bound.actorID==access.binding.actorID,
                       bound.workspaceProjectID==access.binding.workspaceProjectID { await activity.fetch(restart:true) }
                })
            case 6:
                WorksetActivityView(state:activity,client:client,grants:conceptGrants)
            case 3:
                ServerOverviewView(client:client)
            default:
                Group {
                    if let preview=missionObservation {
                        MissionWorkspaceView(observation:preview,canRefine:false,canApprove:false,onRefine:{ _, _, _ in },onApprove:{ _ in })
                    } else {
                        LiveMissionWorkspaceView(client:client,conversations:conversations,onOpenReviews:openReview)
                    }
                }.environment(\.nativeTabCommandsActive,true)
            }
        }
        .onChange(of:[client.phase,client.savedEndpoint,client.savedInstance]) { _,_ in activity.invalidate();order.invalidate();projectLinks.invalidate() }
        .onChange(of:[conversations.projectID,conversations.observedActorID ?? ""]) { _,_ in activity.invalidate();order.invalidate();projectLinks.invalidate() }
        .onChange(of:client.authorizationLost) { _,lost in if lost { activity.invalidate();order.invalidate();projectLinks.invalidate() } }
        .tint(WorkspaceAppearance.accent(for:colorScheme))
        .background(WorkspaceAppearance.backdrop(for:colorScheme))
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
        .onChange(of: scenePhase) { _, phase in if phase == .active, !client.releaseInteractionActive { client.reconnect() } }
        .onReceive(refresh) { _ in if !client.releaseInteractionActive { client.reconnect() } }
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
            Section(MissionWorkspaceCopy.text("setupTitle",language:WorkspaceLanguage.current)) {
                MissionSetupView(client:client,conversations:conversations,state:conversations.missionConcepts)
            }
            Section(WorksetReleaseCopy.text("setup", language: WorkspaceLanguage.current)) {
                WorksetReleaseSetupView(client:client,conversations:conversations,state:conversations.worksetReleases)
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
