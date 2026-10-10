import Foundation

@MainActor final class WorksetReleaseState: ObservableObject {
    @Published private(set) var capability: WorksetReleaseCapability?
    @Published private(set) var preview: WorksetReleasePreview?
    @Published private(set) var observation: WorksetReleaseObservation?
    @Published private(set) var selected: [WorksetReleaseSubject] = []
    @Published private(set) var pending: WorksetReleaseIntent?
    @Published private(set) var history: [WorksetReleaseIntent] = []
    @Published private(set) var busy = false
    @Published private(set) var phase = "unconfigured"
    private let credentials: any WorksetReleaseCredentials
    private let store: any WorksetReleaseIntentStorage
    private let transport: any WorksetReleaseServing
    private var access: WorksetReleaseAccess?
    private var connection: AdvisoryConnection?
    private var attemptedScope: [String]?
    private var generation = 0
    private var selecting = false
    private var journal = WorksetReleaseJournal()
    init(credentials: any WorksetReleaseCredentials = WorksetReleaseKeychain(),
         store: any WorksetReleaseIntentStorage = PrivateWorksetReleaseStore(),
         transport: any WorksetReleaseServing = WorksetReleaseTransport()) {
        self.credentials = credentials; self.store = store; self.transport = transport
    }
    func invalidate() {
        generation &+= 1; selecting = false; attemptedScope = nil; connection = nil; access = nil; busy = false
        capability = nil; preview = nil; observation = nil; selected = []; pending = nil; history = []; phase = "unconfigured"
    }
    func saveGrant(_ token: String, connection: AdvisoryConnection?) async {
        guard !busy, pending == nil, let connection else { return }
        invalidate(); attemptedScope = Self.scope(connection)
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let access = try await transport.probe(connection, token: token)
            guard ticket == generation else { return }
            try credentials.save(access)
            busy = false; await refresh(connection)
        } catch { failed(error, ticket: ticket) }
    }
    func forgetGrant() {
        guard !busy else { return }
        invalidate()
        do { try credentials.forget() } catch { phase = "unavailable" }
    }
    private static func scope(_ connection: AdvisoryConnection) -> [String] {
        [connection.endpoint, connection.workspaceInstanceID, connection.workspaceProjectID, connection.actorID]
    }
    func hasAttempted(_ connection: AdvisoryConnection) -> Bool {
        attemptedScope == Self.scope(connection)
    }
    func refresh(_ connection: AdvisoryConnection?) async {
        guard !busy else { return }
        let previousAccess = access, previousSelection = selected, wasSelecting = selecting
        invalidate()
        guard let connection else { return }
        attemptedScope = Self.scope(connection)
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            guard let access = try credentials.load(), access.matches(connection) else { throw AdvisoryError.denied }
            let cap = try await transport.capability(access, connection)
            guard ticket == generation else { return }
            self.connection = connection; self.access = access; capability = cap
            selecting = wasSelecting && previousAccess == access
            if previousAccess == access { selected = previousSelection.filter { cap.subjects.contains($0) } }
            journal = try store.load(access.scopeKey); history = journal.history
            guard journal.pending?.matches(access) != false else { throw AdvisoryError.denied }
            pending = journal.pending; phase = "current"
            if let intent = pending ?? (selecting ? nil : history.last), intent.matches(access) {
                try await readOriginal(intent, access: access, connection: connection, ticket: ticket)
            }
        } catch { failed(error, ticket: ticket) }
    }
    private func readOriginal(_ intent: WorksetReleaseIntent, access: WorksetReleaseAccess, connection: AdvisoryConnection, ticket: Int) async throws {
        do {
            let result = try await transport.operation(access, connection, intent: intent)
            guard ticket == generation else { return }
            try accept(result, intent: intent, access: access)
        } catch AdvisoryError.missing {
            guard journal.pending == intent else { throw AdvisoryError.missing }
            try await recoverMissing(intent, access: access, connection: connection, ticket: ticket)
        }
    }
    private func recoverMissing(_ intent: WorksetReleaseIntent, access: WorksetReleaseAccess, connection: AdvisoryConnection, ticket: Int) async throws {
        let packet: WorksetReleasePreview
        if intent.command.intent == "release" {
            packet = try await transport.prepare(access, connection, selection: intent.command.selection)
        } else {
            guard let original = journal.history.last(where: { $0.command.intent == "release" && $0.command.package_digest == intent.command.package_digest }) else { throw AdvisoryError.invalid }
            packet = try await transport.operation(access, connection, intent: original).preview
        }
        guard ticket == generation else { return }
        guard packet.digest == intent.command.package_digest else { throw AdvisoryError.invalid }
        preview = packet; selected = packet.selection.subjects; phase = "pending"
    }
    func resume() async {
        guard !busy, let pending, let access, let connection else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            do {
                let result = try await transport.operation(access, connection, intent: pending)
                guard ticket == generation else { return }
                if result.state == "COMPLETE" { try accept(result, intent: pending, access: access); return }
            } catch AdvisoryError.missing {
                guard preview?.digest == pending.command.package_digest else { throw AdvisoryError.invalid }
            }
            // Explicit recovery sends only the durable original request, after a current authorized read.
            let result = try await transport.submit(access, connection, command: pending.command)
            guard ticket == generation else { return }
            try accept(result, intent: pending, access: access)
        } catch { failed(error, ticket: ticket) }
    }
    func subject(_ item: MissionConceptCatalogItem) -> WorksetReleaseSubject? {
        guard let capability else { return nil }
        let current = item.canonical_history.filter { $0.definition_revision == item.revision && $0.subject_current && $0.mission_id == item.mission_id && $0.mission_id != nil }
        guard current.count == 1, let history = current.first, history.candidate_id == item.candidate_id else { return nil }
        let subject = WorksetReleaseSubject(candidate_id: history.candidate_id, subject_revision: history.subject_revision)
        return capability.subjects.contains(subject) ? subject : nil
    }
    func toggle(_ subject: WorksetReleaseSubject) {
        guard !busy, pending == nil, capability?.subjects.contains(subject) == true else { return }
        beginSelection()
        if let index = selected.firstIndex(of: subject) { selected.remove(at: index) }
        else { selected.append(subject) }
    }
    func beginSelection() {
        guard !busy, pending == nil else { return }
        selecting = true; observation = nil; preview = nil; phase = "current"
    }
    func expirePreview(now: Date = Date()) {
        guard let cap = capability, let expiry = WorksetReleaseWire.date(cap.expires_at), expiry <= now else { return }
        invalidate(); phase = "denied"
    }
    func move(_ subject: WorksetReleaseSubject, offset: Int) {
        guard !busy, pending == nil, let index = selected.firstIndex(of: subject), selected.indices.contains(index+offset), abs(offset) == 1 else { return }
        selected.swapAt(index, index+offset); preview = nil
    }
    func prepare() async {
        guard !busy, pending == nil, !selected.isEmpty, let cap = capability,
              let access, let connection else { return }
        let selection = WorksetReleaseSelection(contract_version: WorksetReleaseWire.contract, subjects: selected,
            expires_at: cap.expires_at, maximum_activations: min(selected.count, cap.limits.maximum_activations), progression_mode: "continuous")
        let ticket = generation; busy = true; preview = nil
        defer { if ticket == generation { busy = false } }
        do {
            let packet = try await transport.prepare(access, connection, selection: selection)
            guard ticket == generation else { return }; preview = packet; phase = "preview"
        } catch { failed(error, ticket: ticket) }
    }
    func confirmRelease() async {
        guard !busy, pending == nil, let preview, preview.supported, !preview.members.isEmpty,
              capability?.release_supported == true else { return }
        guard let access, let connection else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let fresh = try await transport.prepare(access, connection, selection: preview.selection)
            guard ticket == generation else { return }
            guard fresh.digest == preview.digest && fresh.supported else {
                self.preview = fresh; phase = "preview"; return
            }
            // A changed preview is shown for new explicit consent; it is never silently substituted.
            busy = false
            await execute(preview: preview, intent: "release", revision: nil)
        } catch { failed(error, ticket: ticket) }
    }
    func observe(_ intent: WorksetReleaseIntent) async {
        guard !busy, pending == nil, history.contains(intent), let access, let connection else { return }
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            let result = try await transport.operation(access, connection, intent: intent)
            guard ticket == generation else { return }
            try accept(result, intent: intent, access: access)
        } catch { failed(error, ticket: ticket) }
    }
    func disarm() async {
        guard !busy, pending == nil, let observation, let revision = observation.currentRevision,
              capability?.disarm_supported == true else { return }
        await execute(preview: observation.preview, intent: "disarm", revision: revision)
    }
    private func execute(preview: WorksetReleasePreview, intent: String, revision: Int?) async {
        guard let access, let connection, journal.history.count < 16 else { return }
        let command = WorksetReleaseCommand(contract_version: WorksetReleaseWire.contract,
            operation_id: UUID().uuidString.lowercased(), intent: intent, selection: preview.selection,
            package_digest: preview.digest, confirm: true, expected_revision: revision)
        let record = WorksetReleaseIntent(accessFingerprint: access.fingerprint, scopeKey: access.scopeKey, command: command)
        let ticket = generation; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            // Fsync the original intent before any effectful network request.
            var next = journal; next.pending = record; try store.save(next, key: access.scopeKey)
            journal = next; pending = record
            let result = try await transport.submit(access, connection, command: command)
            guard ticket == generation else { return }
            try accept(result, intent: record, access: access)
        } catch { failed(error, ticket: ticket) }
    }
    private func accept(_ result: WorksetReleaseObservation, intent: WorksetReleaseIntent, access: WorksetReleaseAccess) throws {
        guard result.operationID == intent.command.operation_id else { throw AdvisoryError.invalid }
        selecting = false; observation = result; preview = nil
        if result.state == "COMPLETE", journal.pending == intent {
            var next = journal; next.pending = nil
            if !next.history.contains(intent) { next.history.append(intent) }
            try store.save(next, key: access.scopeKey); journal = next; pending = nil; history = next.history
        }
        phase = phaseFor(result)
    }
    private func phaseFor(_ result: WorksetReleaseObservation) -> String {
        guard result.state == "COMPLETE", let snapshot = result.snapshot else { return "pending" }
        if snapshot.items.allSatisfy({ $0.facts.released == .no }) { return "withdrawn" }
        if snapshot.items.allSatisfy({ $0.facts.completed == .yes }) { return "completed" }
        if snapshot.items.contains(where: { $0.facts.active == .yes }) { return "active" }
        return "released"
    }
    private func failed(_ error: Error, ticket: Int) {
        guard ticket == generation else { return }
        capability = nil; preview = nil; observation = nil; selected = []
        switch error {
        case AdvisoryError.denied: phase = "denied"; pending = nil; history = []
        case AdvisoryError.missing: phase = "pending"
        case AdvisoryError.state: phase = "blocked"
        default: phase = "unavailable"
        }
    }
}
