import Foundation

protocol WorksetReleaseServing: Sendable {
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> WorksetReleaseAccess
    func capability(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection) async throws -> WorksetReleaseCapability
    func prepare(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, selection: WorksetReleaseSelection) async throws -> WorksetReleasePreview
    func submit(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, command: WorksetReleaseCommand) async throws -> WorksetReleaseObservation
    func operation(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, intent: WorksetReleaseIntent) async throws -> WorksetReleaseObservation
}
final class WorksetReleaseTransport: WorksetReleaseServing, @unchecked Sendable {
    private let clock: @Sendable () -> Date
    private let session: URLSession
    private let redirects = RejectRedirects()
    init(configuration: URLSessionConfiguration = .ephemeral, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
    }
    private func request(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, suffix: String, body: Data? = nil, validUntil: Date? = nil) async throws -> Data {
        guard access.matches(connection) else { throw AdvisoryError.denied }
        return try await request(connection, token: access.token, suffix: suffix, body: body, validUntil: validUntil)
    }
    private func request(_ connection: AdvisoryConnection, token: String, suffix: String, body: Data? = nil, validUntil: Date? = nil) async throws -> Data {
        guard token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else { throw AdvisoryError.denied }
        let endpoint = try ServerEndpoint(connection.endpoint)
        guard let url = URL(string: "/v1/workset-releases/"+suffix, relativeTo: endpoint.url)?.absoluteURL else { throw AdvisoryError.invalid }
        var request = URLRequest(url: url); request.timeoutInterval = 65
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer "+connection.bearer, forHTTPHeaderField: "Authorization")
        request.setValue(connection.workspaceInstanceID, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(connection.draftGrant, forHTTPHeaderField: "X-Workspace-Draft-Grant")
        request.setValue(token, forHTTPHeaderField: "X-Workspace-Workset-Release-Grant")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try Task.checkCancellation()
        guard validUntil.map({ $0 > clock() }) ?? true else { throw AdvisoryError.denied }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 1_000_000,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else { throw AdvisoryError.invalid }
        return try answer(http.statusCode, data: data)
    }
    private func answer(_ status: Int, data: Data) throws -> Data {
        switch status {
        case 200: return data
        case 401, 403: throw AdvisoryError.denied
        case 404: throw AdvisoryError.missing
        case 400, 409, 503:
            let raw = try WorksetReleaseWire.object(data)
            guard Set(raw.keys) == ["error"], let code = raw["error"] as? String,
                  code.range(of: "^[A-Z][A-Z0-9_]{0,127}$", options: .regularExpression) != nil else { throw AdvisoryError.invalid }
            throw AdvisoryError.state(code)
        default: throw AdvisoryError.unavailable
        }
    }
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> WorksetReleaseAccess {
        let raw = try WorksetReleaseWire.object(await request(connection, token: token, suffix: "access"))
        guard Set(raw.keys) == ["contract_version", "actor_id", "workspace_project_id", "instance_id", "project_id", "repository_id", "subjects"],
              raw["contract_version"] as? String == "workspace-workset-release-access/v1",
              raw["actor_id"] as? String == connection.actorID,
              raw["workspace_project_id"] as? String == connection.workspaceProjectID,
              let instance = raw["instance_id"] as? String, let project = raw["project_id"] as? String,
              let repository = raw["repository_id"] as? String else { throw AdvisoryError.denied }
        let access = WorksetReleaseAccess(endpoint: connection.endpoint, workspaceInstanceID: connection.workspaceInstanceID,
            workspaceProjectID: connection.workspaceProjectID, actorID: connection.actorID, forgeInstanceID: instance,
            forgeProjectID: project, repositoryID: repository, subjects: try AdvisoryWire.decode(raw["subjects"]!, as: [WorksetReleaseSubject].self), token: token)
        guard access.valid else { throw AdvisoryError.invalid }
        _ = try await capability(access, connection)
        return access
    }
    func capability(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection) async throws -> WorksetReleaseCapability {
        try WorksetReleaseWire.capability(await request(access, connection, suffix: "capability"), access: access, now: clock())
    }
    func prepare(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, selection: WorksetReleaseSelection) async throws -> WorksetReleasePreview {
        let cap = try await capability(access, connection)
        try WorksetReleaseWire.selection(selection, capability: cap, now: clock())
        let data = try JSONEncoder().encode(selection)
        return try WorksetReleaseWire.prepared(await request(access, connection, suffix: "prepare", body: data, validUntil: WorksetReleaseWire.date(cap.expires_at)), access: access, selection: selection)
    }
    func submit(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, command: WorksetReleaseCommand) async throws -> WorksetReleaseObservation {
        let cap = try await capability(access, connection)
        try WorksetReleaseWire.selection(command.selection, capability: cap, now: clock())
        guard command.intent == "release" ? cap.release_supported : cap.disarm_supported else { throw AdvisoryError.denied }
        return try WorksetReleaseWire.operation(await request(access, connection, suffix: "commands", body: command.data(), validUntil: WorksetReleaseWire.date(cap.expires_at)), access: access, expected: command)
    }
    func operation(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, intent: WorksetReleaseIntent) async throws -> WorksetReleaseObservation {
        guard intent.matches(access), WorklistWire.identifier(intent.command.operation_id) else { throw AdvisoryError.denied }
        let cap = try await capability(access, connection)
        return try WorksetReleaseWire.operation(await request(access, connection, suffix: "operations/"+intent.command.operation_id, validUntil: WorksetReleaseWire.date(cap.expires_at)), access: access, expected: intent.command)
    }
}
