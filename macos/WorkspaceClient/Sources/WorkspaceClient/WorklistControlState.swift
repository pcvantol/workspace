import Combine
import Foundation

@MainActor
final class WorklistControlState: ObservableObject {
    @Published private(set) var current: WorklistControlCurrent?
    @Published private(set) var phase = "controlReadOnly"
    @Published private(set) var busy = false
    @Published private(set) var hasGrant = false
    @Published private(set) var pending: WorklistControlIntent?
    @Published private(set) var confirmation: WorklistControlRequest?
    @Published private(set) var receipt: WorklistControlReceipt?
    private let credentials: any WorklistControlCredentials
    private let transport: WorklistControlTransport
    private var generation = 0
    private var scope: ApprovedWorklistScope?
    private var pairing: ServerBinding?

    init(credentials: any WorklistControlCredentials = WorklistControlKeychain(),
         transport: WorklistControlTransport = WorklistControlTransport()) {
        self.credentials = credentials; self.transport = transport
    }
    func invalidate() {
        generation &+= 1; current = nil; scope = nil; pairing = nil; confirmation = nil
        receipt = nil; phase = "controlReadOnly"; hasGrant = false; busy = false
        // Never erase a durable uncertain operation because pairing or selection changed.
        pending = try? credentials.loadIntent()
    }
    private func admit(_ connection: WorklistConnection?, scope newScope: ApprovedWorklistScope?) -> Bool {
        guard let connection, let newScope else { invalidate(); return false }
        let newPair = ServerBinding(endpoint: connection.endpoint, instanceID: connection.instanceID)
        if newScope != scope || newPair != pairing { invalidate(); scope = newScope; pairing = newPair }
        return true
    }
    private func access(_ connection: WorklistConnection) throws -> WorklistAccess {
        guard let access = try credentials.loadAccess(), access.valid,
              access.endpoint == connection.endpoint, access.workspaceInstanceID == connection.instanceID,
              let scope, access.actorID == scope.actorID, access.forgeInstanceID == scope.forgeInstanceID,
              access.worksetIDs.contains(scope.worksetID) else { throw WorklistControlError.denied }
        return access
    }
    private func accept(_ observation: WorklistControlObservation) {
        current = observation.current; receipt = observation.receipt
        phase = observation.pending ? "controlPending" : observation.receipt != nil ? "controlApplied" : "controlCurrent"
    }
    private func fail(_ error: Error) {
        confirmation = nil
        switch error {
        case WorklistControlError.denied: current = nil; receipt = nil; phase = "controlDenied"
        case WorklistControlError.conflict: current = nil; phase = "controlConflict"
        case WorklistControlError.missing: current = nil; phase = pending == nil ? "controlUnsupported" : "controlPending"
        case WorklistControlError.invalid: current = nil; phase = "controlInvalid"
        default: current = nil; phase = "controlOffline"
        }
    }
    func refresh(connection: WorklistConnection?, scope: ApprovedWorklistScope?) async {
        guard admit(connection, scope: scope), !busy, let connection else { return }
        let revision = generation; busy = true
        defer { if revision == generation { busy = false } }
        do {
            pending = try credentials.loadIntent()
            guard try credentials.loadAccess() != nil else { phase = "controlReadOnly"; hasGrant = false; current = nil; confirmation = nil; return }
            let access = try access(connection); hasGrant = true
            guard let bearer = connection.readToken else { throw WorklistControlError.unavailable }
            let intent = pending?.matches(access) == true && pending?.request.workset_id == scope?.worksetID ? pending?.request : nil
            let value = try await transport.read(access: access, bearer: bearer, workset: scope!.worksetID, intent: intent)
            guard revision == generation else { return }
            accept(value)
            if let pending, intent != nil, value.receipt?.request == pending.request {
                try credentials.forgetIntent(); self.pending = nil
            }
        } catch { if revision == generation { fail(error) } }
    }
    func saveGrant(_ token: String, connection: WorklistConnection?, scope: ApprovedWorklistScope?) async {
        guard admit(connection, scope: scope), !busy, let connection else { return }
        let revision = generation; busy = true
        defer { if revision == generation { busy = false } }
        do {
            guard try credentials.loadIntent() == nil else { throw WorklistControlError.conflict }
            let access = try await transport.probe(connection: connection, token: token)
            guard revision == generation else { return }
            guard access.actorID == scope?.actorID, access.forgeInstanceID == scope?.forgeInstanceID,
                  access.worksetIDs.contains(scope?.worksetID ?? "") else { throw WorklistControlError.denied }
            try credentials.saveAccess(access); hasGrant = true
            guard let bearer = connection.readToken else { throw WorklistControlError.unavailable }
            let observation = try await transport.read(access: access, bearer: bearer, workset: scope!.worksetID)
            guard revision == generation else { return }; accept(observation)
        } catch { if revision == generation { fail(error) } }
    }
    func forgetGrant() {
        guard !busy else { return }
        do {
            guard try credentials.loadIntent() == nil else { throw WorklistControlError.conflict }
            try credentials.forgetAccess(); invalidate()
        } catch { fail(error) }
    }
    func prepare(intent: String, reason: String) {
        guard !busy, pending == nil, confirmation == nil, let current,
              current.workset_id == scope?.worksetID,
              intent == "hold" ? current.mayHold : intent == "unhold" && current.mayUnhold else { return }
        let request = WorklistControlRequest(current: current, intent: intent, reason: reason)
        guard request.valid else { return }; confirmation = request
    }
    func cancelConfirmation() { confirmation = nil }
    func confirm(connection: WorklistConnection?) async {
        guard !busy, pending == nil, let request = confirmation, let connection else { return }
        let revision = generation; busy = true; confirmation = nil
        defer { if revision == generation { busy = false } }
        do {
            let access = try access(connection)
            guard let bearer = connection.readToken else { throw WorklistControlError.unavailable }
            let intent = WorklistControlIntent(accessFingerprint: WorklistControlIntent.fingerprint(access), endpoint: access.endpoint,
                workspaceInstanceID: access.workspaceInstanceID, actorID: access.actorID, request: request)
            // Saving the exact operation is mandatory before the first and only initial POST.
            try credentials.saveIntent(intent); pending = intent; phase = "controlSending"
            _ = try await transport.submit(access: access, bearer: bearer, request: request)
            guard revision == generation else { return }; phase = "controlPending"
            // Separate authorized operation GET; a POST acknowledgement alone is not completion.
            let verified = try await transport.read(access: access, bearer: bearer, workset: request.workset_id, intent: request)
            guard revision == generation else { return }; accept(verified)
            if verified.receipt?.request == request { try credentials.forgetIntent(); pending = nil }
        } catch { if revision == generation { fail(error) } }
    }
    func resume(connection: WorklistConnection?) async {
        guard !busy, let pending, let connection else { return }
        let revision = generation; busy = true
        defer { if revision == generation { busy = false } }
        do {
            let access = try access(connection)
            guard pending.matches(access), pending.request.workset_id == scope?.worksetID,
                  let bearer = connection.readToken else { throw WorklistControlError.denied }
            var observation: WorklistControlObservation?
            do { observation = try await transport.read(access: access, bearer: bearer, workset: pending.request.workset_id, intent: pending.request) }
            catch WorklistControlError.missing {
                let preview = try await transport.read(access: access, bearer: bearer, workset: pending.request.workset_id)
                guard preview.current.definition_revision == pending.request.definition_revision,
                      preview.current.workset_revision == pending.request.expected_revision else { throw WorklistControlError.conflict }
            }
            guard revision == generation else { return }
            if observation?.receipt == nil {
                // Only this explicit user action reconciles the same durable ID/payload.
                _ = try await transport.submit(access: access, bearer: bearer, request: pending.request)
                guard revision == generation else { return }
                observation = try await transport.read(access: access, bearer: bearer, workset: pending.request.workset_id, intent: pending.request)
            }
            guard revision == generation, let observation else { return }; accept(observation)
            if observation.receipt?.request == pending.request { try credentials.forgetIntent(); self.pending = nil }
        } catch { if revision == generation { fail(error) } }
    }
    func resolveOrDiscardUnrecorded(connection: WorklistConnection?) async {
        guard !busy, let pending, let connection else { return }
        let revision = generation; busy = true
        defer { if revision == generation { busy = false } }
        do {
            let access = try access(connection)
            guard pending.matches(access), pending.request.workset_id == scope?.worksetID,
                  let bearer = connection.readToken else { throw WorklistControlError.denied }
            let observation: WorklistControlObservation
            do {
                let found = try await transport.read(access: access, bearer: bearer, workset: pending.request.workset_id, intent: pending.request)
                guard found.receipt != nil else { throw WorklistControlError.conflict }
                observation = found
            } catch WorklistControlError.missing {
                // Only an authorized absence plus fresh current read can abandon a local unrecorded intent.
                observation = try await transport.read(access: access, bearer: bearer, workset: pending.request.workset_id)
            }
            guard revision == generation else { return }
            try credentials.forgetIntent(); self.pending = nil; accept(observation)
        } catch { if revision == generation { fail(error) } }
    }

}
