import Combine
import Foundation

struct WorklistConnection: Equatable, Sendable {
    let endpoint: String
    let instanceID: String
    // Known pairing without a current read token is temporarily offline; nil context is unpaired.
    let readToken: String?
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
    private var pairingGeneration = 0
    private var observedBinding: ServerBinding?

    init(credentials: any WorklistCredentialStore = WorklistKeychain(),
         transport: WorklistTransport = WorklistTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    func matchesObservedPairing(endpoint: String, instanceID: String) -> Bool {
        observedBinding == ServerBinding(endpoint: endpoint, instanceID: instanceID)
    }

    func invalidatePairing() {
        pairingGeneration &+= 1
        observedBinding = nil
        cache = WorklistObservationCache()
        worksetIDs = []
        selectedWorkset = ""
        hasGrant = false
    }

    private func expected(_ access: WorklistAccess) -> ApprovedWorklistScope {
        ApprovedWorklistScope(forgeInstanceID: access.forgeInstanceID,
                             actorID: access.actorID, worksetID: selectedWorkset)
    }

    func saveGrant(_ token: String, connection: WorklistConnection?) async {
        guard !isBusy else { return }
        let generation = pairingGeneration
        isBusy = true
        defer { isBusy = false }
        do {
            guard let connection, let readToken = connection.readToken,
                  token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw WorklistTransportError.denied
            }
            let access = try await transport.probe(endpoint: ServerEndpoint(connection.endpoint),
                workspaceToken: readToken, instance: connection.instanceID, worklistToken: token)
            guard generation == pairingGeneration else { return }
            try credentials.saveAccess(access)
            cache = WorklistObservationCache()
            hasGrant = true
            worksetIDs = access.worksetIDs
            selectedWorkset = worksetIDs[0]
            try await read(access, connection: connection, readToken: readToken, generation: generation)
        } catch { if generation == pairingGeneration { fail(error) } }
    }

    func refresh(connection: WorklistConnection?, selecting workset: String? = nil) async {
        guard let connection else { invalidatePairing(); return }
        guard !isBusy else { return }
        let generation = pairingGeneration
        isBusy = true
        defer { isBusy = false }
        do {
            guard let access = try credentials.loadAccess(), access.valid else {
                invalidatePairing()
                return
            }
            guard connection.endpoint == access.endpoint, connection.instanceID == access.workspaceInstanceID else {
                throw WorklistTransportError.wrongInstance
            }
            hasGrant = true
            worksetIDs = access.worksetIDs
            let selected = workset ?? (selectedWorkset.isEmpty ? worksetIDs[0] : selectedWorkset)
            guard worksetIDs.contains(selected) else { throw WorklistTransportError.denied }
            if selected != selectedWorkset { cache = WorklistObservationCache() }
            selectedWorkset = selected
            guard let readToken = connection.readToken else { throw WorklistTransportError.unavailable }
            _ = try await transport.scopes(access: access, workspaceToken: readToken)
            guard generation == pairingGeneration else { return }
            try await read(access, connection: connection, readToken: readToken, generation: generation)
        } catch { if generation == pairingGeneration { fail(error) } }
    }

    private func read(_ access: WorklistAccess, connection: WorklistConnection,
                      readToken: String, generation: Int) async throws {
        let snapshot = try await transport.snapshot(access: access,
            workspaceToken: readToken, worksetID: selectedWorkset)
        guard generation == pairingGeneration else { return }
        observedBinding = ServerBinding(endpoint: connection.endpoint, instanceID: connection.instanceID)
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
        if error is CredentialError || state == .denied { invalidatePairing() }
        if let scope = cache.snapshot?.scope {
            cache.failed(state, for: scope)
        } else { cache = WorklistObservationCache(); cache.failed(state, for: ApprovedWorklistScope(forgeInstanceID: "", actorID: "", worksetID: selectedWorkset)) }
    }

    func forgetGrant() {
        guard !isBusy else { return }
        do { try credentials.forgetAccess(); invalidatePairing() }
        catch { fail(error) }
    }
}
