import Combine
import Foundation

@MainActor
final class MissionReviewState: ObservableObject {
    @Published private(set) var items: [MissionReviewItem] = []
    @Published private(set) var access: MissionReviewListAccess = .unavailable
    @Published private(set) var statusKey = "grantRequired"
    @Published private(set) var actorID = ""
    @Published private(set) var forgeInstanceID = ""
    @Published private(set) var pendingIntent: MissionReviewIntent?
    @Published private(set) var canRetrySameOperation = false
    @Published private(set) var isBusy = false

    private let credentials: any ReviewCredentialStore
    private let transport: MissionReviewTransport
    private var decision = MissionReviewDecisionState()
    private var loaded = false

    init(credentials: any ReviewCredentialStore = ReviewKeychain(),
         transport: MissionReviewTransport = MissionReviewTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    private func loadSaved() throws -> ReviewAccess? {
        if !loaded {
            if let intent = try credentials.loadIntent() {
                pendingIntent = intent
                decision.restore(intent)
            }
            loaded = true
        }
        return try credentials.loadAccess()
    }

    private func context(client: ClientState) async throws -> (ReviewAccess, String) {
        guard let saved = try loadSaved() else { throw ReviewTransportError.denied }
        guard client.phase == "CONNECTED", saved.endpoint == client.savedEndpoint,
              saved.workspaceInstanceID == client.savedInstance else {
            throw ReviewTransportError.wrongInstance
        }
        return (saved, try await client.draftReadToken())
    }

    func saveGrant(_ token: String, client: ClientState) async {
        guard !isBusy else { return }
        isBusy = true
        statusKey = "loading"
        defer { isBusy = false }
        do {
            guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
                  client.phase == "CONNECTED" else { throw ReviewTransportError.denied }
            let endpoint = try ServerEndpoint(client.savedEndpoint)
            let workspaceToken = try await client.draftReadToken()
            let (newAccess, newItems) = try await transport.probe(
                endpoint: endpoint, workspaceToken: workspaceToken,
                instance: client.savedInstance, reviewToken: token)
            _ = try loadSaved()
            if let pendingIntent,
               (pendingIntent.forgeInstanceID != newAccess.forgeInstanceID ||
                pendingIntent.actorID != newAccess.actorID ||
                !newAccess.missionIDs.contains(pendingIntent.key.missionID)) {
                throw ReviewTransportError.conflict
            }
            try credentials.saveAccess(newAccess)
            actorID = newAccess.actorID
            forgeInstanceID = newAccess.forgeInstanceID
            items = newItems
            access = .available
            statusKey = "available"
        } catch let error as ReviewTransportError {
            statusKey = error == .denied ? "denied" : error == .conflict ? "decisionConflict" : "offline"
            access = error == .denied ? .denied : .offline
        } catch {
            statusKey = "offline"
            access = .offline
        }
    }

    func forgetGrant() {
        guard !isBusy else { return }
        do {
            _ = try loadSaved()
            guard pendingIntent == nil else { return }
            try credentials.forgetAccess()
            actorID = ""
            forgeInstanceID = ""
            items = []
            access = .unavailable
            statusKey = "grantRequired"
        } catch {
            statusKey = "offline"
        }
    }

    func refresh(client: ClientState) async {
        guard !isBusy else { return }
        isBusy = true
        statusKey = "loading"
        defer { isBusy = false }
        do {
            guard let saved = try loadSaved() else {
                access = .unavailable
                statusKey = "grantRequired"
                return
            }
            actorID = saved.actorID
            forgeInstanceID = saved.forgeInstanceID
            guard client.phase == "CONNECTED", saved.endpoint == client.savedEndpoint,
                  saved.workspaceInstanceID == client.savedInstance else {
                access = .offline
                statusKey = "offline"
                return
            }
            let workspaceToken = try await client.draftReadToken()
            if let pendingIntent {
                await recover(saved, workspaceToken: workspaceToken, intent: pendingIntent)
            }
            items = try await transport.list(access: saved, workspaceToken: workspaceToken)
            access = .available
            if pendingIntent == nil && statusKey != "recordedNotice" { statusKey = "available" }
        } catch let error as ReviewTransportError {
            access = error == .unauthorized || error == .denied ? .denied : .offline
            statusKey = error == .unauthorized || error == .denied ? "denied" : "offline"
        } catch {
            access = .offline
            statusKey = "offline"
        }
    }

    func decide(_ item: MissionReviewItem, outcome: MissionReviewOutcome,
                reason: String, client: ClientState) async {
        guard !isBusy, pendingIntent == nil else { return }
        isBusy = true
        statusKey = "loading"
        defer { isBusy = false }
        do {
            let (saved, workspaceToken) = try await context(client: client)
            let current = try await transport.detail(access: saved, workspaceToken: workspaceToken,
                                                     missionID: item.key.missionID)
            guard current.key == item.key, current.subjectDigest == item.subjectDigest,
                  current.missionStateRevision == item.missionStateRevision,
                  current.evidenceDigest == item.evidenceDigest,
                  current.policyRevision == item.policyRevision,
                  current.mayOffer(outcome) else { throw ReviewTransportError.conflict }
            decision.resetAfterRecorded()
            guard decision.prepare(item: current, outcome: outcome, comment: reason),
                  let intent = decision.confirm() else { throw ReviewTransportError.conflict }
            try credentials.saveIntent(intent)
            pendingIntent = intent
            canRetrySameOperation = false
            guard decision.persisted(intent) != nil else { throw ReviewTransportError.invalidResponse }
            await submit(saved, workspaceToken: workspaceToken, intent: intent)
        } catch let error as ReviewTransportError {
            if pendingIntent == nil { decision.cancelBeforeSubmission() }
            statusKey = error == .conflict ? "decisionConflict" : "offline"
        } catch {
            if pendingIntent == nil { decision.cancelBeforeSubmission() }
            statusKey = "offline"
        }
    }

    func readPending(client: ClientState) async {
        guard !isBusy, let intent = pendingIntent else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let (saved, workspaceToken) = try await context(client: client)
            await recover(saved, workspaceToken: workspaceToken, intent: intent)
        } catch {
            statusKey = "offline"
        }
    }

    func retrySameOperation(client: ClientState) async {
        guard !isBusy, canRetrySameOperation, let intent = pendingIntent else { return }
        isBusy = true
        canRetrySameOperation = false
        defer { isBusy = false }
        do {
            let (saved, workspaceToken) = try await context(client: client)
            do {
                _ = try await transport.readback(access: saved, workspaceToken: workspaceToken,
                                                 intent: intent)
                await recover(saved, workspaceToken: workspaceToken, intent: intent)
            } catch ReviewTransportError.missing {
                await submit(saved, workspaceToken: workspaceToken, intent: intent)
            }
        } catch {
            statusKey = "pending"
        }
    }

    private func submit(_ saved: ReviewAccess, workspaceToken: String,
                        intent: MissionReviewIntent) async {
        do {
            _ = try await transport.submit(access: saved, workspaceToken: workspaceToken, intent: intent)
            decision.submissionAcknowledged()
        } catch ReviewTransportError.conflict {
            decision.uncertainAfterTransport()
            await recover(saved, workspaceToken: workspaceToken, intent: intent, afterConflict: true)
            return
        } catch {
            decision.uncertainAfterTransport()
        }
        await recover(saved, workspaceToken: workspaceToken, intent: intent)
    }

    private func recover(_ saved: ReviewAccess, workspaceToken: String,
                         intent: MissionReviewIntent, afterConflict: Bool = false) async {
        do {
            let receipt = try await transport.readback(access: saved, workspaceToken: workspaceToken,
                                                       intent: intent)
            let current = try await transport.detail(access: saved, workspaceToken: workspaceToken,
                                                     missionID: intent.key.missionID)
            guard current.currentMissionRevision >= receipt.current.mission_state_revision else {
                throw ReviewTransportError.invalidResponse
            }
            let readback = MissionReviewOwnerReadback(
                operationID: intent.operationID, key: intent.key,
                subjectID: intent.subjectID, subjectRevision: intent.subjectRevision,
                outcome: intent.outcome, receiptID: receipt.operation.operation_id,
                forgeInstanceID: saved.forgeInstanceID, actorID: saved.actorID,
                currentMissionRevision: current.currentMissionRevision,
                fenceState: current.phase == .waitingForReview ? .blocked : .released)
            var recordedDecision = decision
            guard recordedDecision.applyOwnerReadback(readback, current: current) else {
                throw ReviewTransportError.invalidResponse
            }
            try credentials.forgetIntent()
            decision = recordedDecision
            pendingIntent = nil
            canRetrySameOperation = false
            items.removeAll { $0.key.missionID == current.key.missionID }
            items.append(current)
            statusKey = "recordedNotice"
            access = .available
        } catch ReviewTransportError.missing {
            if afterConflict {
                do {
                    try credentials.forgetIntent()
                    pendingIntent = nil
                    canRetrySameOperation = false
                    decision.stale()
                    statusKey = "decisionConflict"
                } catch {
                    statusKey = "pending"
                }
            } else {
                canRetrySameOperation = true
                statusKey = "pendingMissing"
            }
        } catch ReviewTransportError.unauthorized {
            access = .denied
            statusKey = "denied"
        } catch ReviewTransportError.denied {
            access = .denied
            statusKey = "denied"
        } catch {
            statusKey = "pending"
        }
    }
}
