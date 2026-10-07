import Combine
import Foundation

struct WorklistConnection: Equatable, Sendable {
    let endpoint: String
    let instanceID: String
    let readToken: String
}

@MainActor
final class WorklistState: ObservableObject {
    @Published private(set) var cache = WorklistObservationCache()
    @Published private(set) var worksetIDs: [String] = []
    @Published private(set) var selectedWorkset = ""
    @Published private(set) var isBusy = false
    @Published private(set) var hasGrant = false
    private let credentials: any WorklistCredentialStore
    private let transport: WorklistTransport

    init(credentials: any WorklistCredentialStore = WorklistKeychain(),
         transport: WorklistTransport = WorklistTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    private func expected(_ access: WorklistAccess) -> ApprovedWorklistScope {
        ApprovedWorklistScope(forgeInstanceID: access.forgeInstanceID,
                             actorID: access.actorID, worksetID: selectedWorkset)
    }

    func saveGrant(_ token: String, connection: WorklistConnection?) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let connection, token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw WorklistTransportError.denied
            }
            let access = try await transport.probe(endpoint: ServerEndpoint(connection.endpoint),
                workspaceToken: connection.readToken, instance: connection.instanceID, worklistToken: token)
            try credentials.saveAccess(access)
            cache = WorklistObservationCache()
            hasGrant = true
            worksetIDs = access.worksetIDs
            selectedWorkset = worksetIDs[0]
            try await read(access, connection: connection)
        } catch { fail(error) }
    }

    func refresh(connection: WorklistConnection?, selecting workset: String? = nil) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard let access = try credentials.loadAccess(), access.valid else {
                hasGrant = false
                worksetIDs = []
                selectedWorkset = ""
                cache = WorklistObservationCache()
                return
            }
            hasGrant = true
            worksetIDs = access.worksetIDs
            let selected = workset ?? (selectedWorkset.isEmpty ? worksetIDs[0] : selectedWorkset)
            guard worksetIDs.contains(selected) else { throw WorklistTransportError.denied }
            if selected != selectedWorkset { cache = WorklistObservationCache() }
            selectedWorkset = selected
            guard let connection else { throw WorklistTransportError.unavailable }
            guard connection.endpoint == access.endpoint, connection.instanceID == access.workspaceInstanceID else {
                throw WorklistTransportError.wrongInstance
            }
            _ = try await transport.scopes(access: access, workspaceToken: connection.readToken)
            try await read(access, connection: connection)
        } catch { fail(error) }
    }

    private func read(_ access: WorklistAccess, connection: WorklistConnection) async throws {
        let snapshot = try await transport.snapshot(access: access,
            workspaceToken: connection.readToken, worksetID: selectedWorkset)
        _ = cache.accept(snapshot, for: expected(access))
    }

    private func fail(_ error: Error) {
        let state: WorklistAvailability
        switch error {
        case WorklistTransportError.unauthorized, WorklistTransportError.denied,
             WorklistTransportError.wrongInstance, WorklistTransportError.missing:
            state = .denied
        case WorklistTransportError.invalidResponse, WorklistTransportError.inconsistentSnapshot:
            state = .stale
        default: state = .offline
        }
        // Credential corruption never permits a cached actor's view to be retained.
        if error is CredentialError {
            cache = WorklistObservationCache()
            hasGrant = false
            worksetIDs = []
        }
        if let scope = cache.snapshot?.scope {
            cache.failed(state, for: scope)
        } else { cache = WorklistObservationCache(); cache.failed(state, for: ApprovedWorklistScope(forgeInstanceID: "", actorID: "", worksetID: selectedWorkset)) }
    }

    func forgetGrant() {
        guard !isBusy else { return }
        do {
            try credentials.forgetAccess()
            hasGrant = false
            worksetIDs = []
            selectedWorkset = ""
            cache = WorklistObservationCache()
        } catch { fail(error) }
    }
}
