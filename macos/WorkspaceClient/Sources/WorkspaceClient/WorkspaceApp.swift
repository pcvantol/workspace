import Combine
import SwiftUI

@main
struct WorkspaceApp: App {
    @StateObject private var client = ClientState()

    var body: some Scene {
        WindowGroup("Workspace") {
            ContentView(client: client)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 900, height: 650)
        Settings {
            SettingsView(client: client)
                .frame(width: 490)
                .padding(24)
        }
    }
}

struct ContentView: View {
    @ObservedObject var client: ClientState
    @Environment(\.scenePhase) private var scenePhase
    private let refresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Workspace").font(.largeTitle.bold())
                    Text("Read-only Server connection").foregroundStyle(.secondary)
                }
                Spacer()
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Button("Reconnect") { client.reconnect() }
                    .disabled(client.savedEndpoint.isEmpty || client.phase == "CONNECTING")
                if client.phase == "CONNECTING" {
                    Button("Cancel") { client.cancel() }
                }
            }
            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("State", value: client.phase)
                    LabeledContent("Server", value: client.savedEndpoint.isEmpty ? "Not paired" : client.savedEndpoint)
                    LabeledContent("Instance", value: client.savedInstance.isEmpty ? "Not pinned" : client.savedInstance)
                    Text(client.detail).foregroundStyle(client.phase == "CONNECTED" ? .primary : .secondary)
                        .textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let snapshot = client.snapshot {
                GroupBox("Server") {
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
                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Projects") {
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
                    GroupBox("Capabilities") {
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
        .padding(24)
        .onAppear { client.reconnect() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { client.reconnect() } }
        .onReceive(refresh) { _ in client.reconnect() }
    }
}

struct SettingsView: View {
    @ObservedObject var client: ClientState
    @State private var address = ""
    @State private var token = ""

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
                        client.connect(address: address, enteredToken: token)
                        token = ""
                    }
                    Button("Forget Server") {
                        client.forget()
                        address = ""
                        token = ""
                    }.disabled(client.savedInstance.isEmpty)
                }
                Text(client.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { address = client.savedEndpoint }
    }
}
