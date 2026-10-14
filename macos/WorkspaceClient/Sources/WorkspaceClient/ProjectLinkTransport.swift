import Foundation
import CoreFoundation

struct ProjectLinkConnection: Equatable, Sendable {
    let endpoint: String
    let workspaceInstanceID: String
    let bearer: String
    // Existing Workspace actor-pairing proof, never an EP token or new issuer.
    let actorPairingToken: String
    let actorID: String
    let peerID: String
    let scope: ProjectLinkAccess
}
private final class ProjectLinkRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct ProjectLinkHTTPReader: ProjectLinkReading {
    let connection: @Sendable () async throws -> ProjectLinkConnection
    let session: URLSession
    init(connection: @escaping @Sendable () async throws -> ProjectLinkConnection, session: URLSession? = nil) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration, delegate: ProjectLinkRedirects(), delegateQueue: nil)
    }
    private func request(_ suffix: String, body: Data? = nil, expected: ProjectLinkAccess? = nil) async throws -> (Data, ProjectLinkConnection) {
        let binding = try await connection()
        try binding.scope.validate()
        guard binding.scope.workspaceInstanceID == binding.workspaceInstanceID, binding.scope.actorID == binding.actorID, binding.scope.peerID == binding.peerID else { throw ProjectLinkError.denied }
        if let expected {
            try expected.validate()
            guard expected == binding.scope else { throw ProjectLinkError.denied }
            guard expected.workspaceInstanceID == binding.workspaceInstanceID, expected.actorID == binding.actorID, expected.peerID == binding.peerID else { throw ProjectLinkError.denied }
        }
        guard !binding.bearer.isEmpty, !binding.actorPairingToken.isEmpty else { throw ProjectLinkError.denied }
        let endpoint = try ServerEndpoint(binding.endpoint)
        let url = endpoint.url.appendingPathComponent("v1/project-links/" + suffix)
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer " + binding.bearer, forHTTPHeaderField: "Authorization")
        request.setValue(binding.workspaceInstanceID, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(binding.actorPairingToken, forHTTPHeaderField: "X-Workspace-Project-Grant")
        if let expected { request.setValue(expected.epoch, forHTTPHeaderField: "X-Workspace-Project-Binding") }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 262144,
              response.url?.absoluteString == url.absoluteString,
              response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true else { throw ProjectLinkError.invalid }
        guard try await connection() == binding else { throw ProjectLinkError.denied }
        switch response.statusCode {
        case 200: return (data, binding)
        case 403:
            if let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               Set(value.keys) == ["error"], value["error"] == "PROJECT_LINK_ACCESS_EXPIRED" { throw ProjectLinkError.expired }
            throw ProjectLinkError.denied
        case 401: throw ProjectLinkError.denied
        case 404: throw ProjectLinkError.notFound
        case 409: throw ProjectLinkError.conflict
        case 503:
            if let value = try? JSONSerialization.jsonObject(with: data) as? [String: String], value["error"] == "PROJECT_LINK_PRODUCER_UNBOUND" { throw ProjectLinkError.unsupported }
            throw ProjectLinkError.unavailable
        default: throw ProjectLinkError.invalid
        }
    }
    private func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], Set(value.keys) == keys else { throw ProjectLinkError.invalid }
        return value
    }
    private func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue <= 1_000_000,
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.intValue
    }
    private func decodeTopology(_ raw: [String: Any], access: ProjectLinkAccess, project: String) throws -> LinkTopology {
        guard Set(raw.keys) == ["peer_id", "project_id", "name", "authority_repository_id", "revision", "observed_at", "repositories"],
              let peer = raw["peer_id"] as? String, let projectID = raw["project_id"] as? String,
              let name = raw["name"] as? String, let authority = raw["authority_repository_id"] as? String,
              let revision = raw["revision"] as? String,
              let stamp = raw["observed_at"] as? String, let observed = WorksetReleaseWire.date(stamp),
              let repositories = raw["repositories"] as? [[String: Any]], repositories.count <= 100 else { throw ProjectLinkError.invalid }
        let items = try repositories.map { row -> LinkedRepository in
            guard Set(row.keys) == ["id", "name", "role", "available_attachments"],
                  let id = row["id"] as? String, let name = row["name"] as? String, let role = row["role"] as? String,
                  (row["available_attachments"] is NSNull || integer(row["available_attachments"]) != nil) else { throw ProjectLinkError.invalid }
            return .init(id: id, name: name, role: role, availableAttachments: integer(row["available_attachments"]))
        }
        let topology = LinkTopology(peerID: peer, projectID: projectID, name: name, authorityID: authority, revision: revision, observedAt: observed, repositories: items)
        try topology.validate(access, project: project); return topology
    }
    func access() async throws -> ProjectLinkAccess {
        let (data, binding) = try await request("access")
        let raw = try object(data, keys: ["workspace_instance_id", "actor_id", "peer_id", "project_ids", "expires_at", "epoch"])
        guard raw["workspace_instance_id"] as? String == binding.workspaceInstanceID,
              raw["actor_id"] as? String == binding.actorID, raw["peer_id"] as? String == binding.peerID,
              let projects = raw["project_ids"] as? [String], Set(projects).count == projects.count,
              let stamp = raw["expires_at"] as? String, let expires = WorksetReleaseWire.date(stamp), let epoch = raw["epoch"] as? String else { throw ProjectLinkError.denied }
        let access = ProjectLinkAccess(workspaceInstanceID: binding.workspaceInstanceID, actorID: binding.actorID, peerID: binding.peerID, projectIDs: Set(projects), expiresAt: expires, epoch: epoch)
        try access.validate(); guard access == binding.scope else { throw ProjectLinkError.denied }; return access
    }
    func discover(_ access: ProjectLinkAccess) async throws -> [LinkProject] {
        try access.validate(); let (data, _) = try await request("projects", expected: access)
        let raw = try object(data, keys: ["projects", "state"])
        guard let rows = raw["projects"] as? [[String: String]], rows.count <= 100,
              raw["state"] as? String == (rows.isEmpty ? "EMPTY" : "AVAILABLE") else { throw ProjectLinkError.invalid }
        return try rows.map { row in
            guard Set(row.keys) == ["id", "name"], let id = row["id"], let name = row["name"], access.projectIDs.contains(id) else { throw ProjectLinkError.invalid }
            return LinkProject(id: id, name: name)
        }
    }
    func inspect(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology {
        try access.validate(); guard access.projectIDs.contains(project), ProjectLinkAccess.validID(project) else { throw ProjectLinkError.denied }
        let (data, _) = try await request(project + "/inspect", expected: access)
        return try decodeTopology(object(data, keys: ["peer_id", "project_id", "name", "authority_repository_id", "revision", "observed_at", "repositories"]), access: access, project: project)
    }
    func link(_ access: ProjectLinkAccess, intent: ProjectLinkIntent) async throws -> String {
        try access.validate(); try intent.validate(access.intentKey(intent.projectID))
        guard access.projectIDs.contains(intent.projectID) else { throw ProjectLinkError.denied }
        let fields: [String: Any] = ["expected_revision": intent.expectedRevision, "authority_id": intent.authorityID, "operation_id": intent.operationID]
        let (data, _) = try await request(intent.projectID + "/link", body: JSONSerialization.data(withJSONObject: fields, options: .sortedKeys), expected: access)
        let raw = try object(data, keys: ["project_id", "operation_id", "state", "engineering_readiness"])
        guard raw["project_id"] as? String == intent.projectID, raw["operation_id"] as? String == intent.operationID,
              raw["state"] as? String == "REFERENCE_SAVED", raw["engineering_readiness"] as? String == "NOT_ASSESSED" else { throw ProjectLinkError.invalid }
        return intent.projectID
    }
    func open(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology {
        try access.validate(); guard access.projectIDs.contains(project), ProjectLinkAccess.validID(project) else { throw ProjectLinkError.denied }
        let (data, _) = try await request(project + "/open", expected: access)
        let raw = try object(data, keys: ["topology", "state", "engineering_readiness"])
        guard let topology = raw["topology"] as? [String: Any], raw["state"] as? String == "VERIFIED_REFERENCE",
              raw["engineering_readiness"] as? String == "NOT_ASSESSED" else { throw ProjectLinkError.invalid }
        return try decodeTopology(topology, access: access, project: project)
    }
}

// Bootstrap only through the existing pinned owning HTTP/actor proof. There is
// no empty/wildcard identity and no caller-selected actor or EP. Every ordinary
// reader request retains its unconditional exact actor/peer comparison.
extension ProjectLinkHTTPReader {
    static func pairedConnection(_ access: DraftAccess, bearer: String, testingSession: URLSession? = nil) async throws -> ProjectLinkConnection {
        let endpoint = try ServerEndpoint(access.endpoint)
        let url = endpoint.url.appendingPathComponent("v1/project-links/access")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.urlCache = nil
        let session = testingSession ?? URLSession(configuration: config, delegate: ProjectLinkRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        request.setValue(access.instanceID, forHTTPHeaderField: "X-Workspace-Instance")
        request.setValue(access.token, forHTTPHeaderField: "X-Workspace-Project-Grant")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.url == url, data.count <= 262144 else { throw ProjectLinkError.invalid }
        if response.statusCode == 403,
           let value = try? JSONSerialization.jsonObject(with: data) as? [String:String],
           Set(value.keys) == ["error"], value["error"] == "PROJECT_LINK_ACCESS_EXPIRED" { throw ProjectLinkError.expired }
        if response.statusCode == 401 || response.statusCode == 403 { throw ProjectLinkError.denied }
        if response.statusCode == 503 { throw ProjectLinkError.unavailable }
        guard response.statusCode == 200,
              response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(raw.keys) == ["workspace_instance_id", "actor_id", "peer_id", "project_ids", "expires_at", "epoch"],
              raw["workspace_instance_id"] as? String == access.instanceID,
              let actor = raw["actor_id"] as? String, let peer = raw["peer_id"] as? String,
              let projects = raw["project_ids"] as? [String], Set(projects).count == projects.count,
              let stamp = raw["expires_at"] as? String, let expiry = WorksetReleaseWire.date(stamp),
              let epoch = raw["epoch"] as? String else { throw ProjectLinkError.invalid }
        let scope = ProjectLinkAccess(workspaceInstanceID: access.instanceID, actorID: actor, peerID: peer,
            projectIDs: Set(projects), expiresAt: expiry, epoch: epoch)
        try scope.validate()
        return ProjectLinkConnection(endpoint: access.endpoint, workspaceInstanceID: access.instanceID,
            bearer: bearer, actorPairingToken: access.token, actorID: actor, peerID: peer, scope: scope)
    }
}
