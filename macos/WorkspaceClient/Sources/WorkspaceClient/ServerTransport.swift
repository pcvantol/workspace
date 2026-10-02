import Foundation

struct ServerEndpoint: Equatable, Sendable {
    let url: URL

    init(_ input: String) throws {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port == nil || (1...65535).contains(components.port!) else {
            throw ClientError.invalidEndpoint
        }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw ClientError.insecureEndpoint
        }
        var canonical = URLComponents()
        canonical.scheme = scheme
        canonical.host = host
        canonical.port = components.port
        canonical.path = "/"
        guard let url = canonical.url else { throw ClientError.invalidEndpoint }
        self.url = url
    }

    func route(_ path: String) -> URL {
        url.appending(path: String(path.dropFirst()))
    }
}

enum ClientError: Error, LocalizedError, Equatable {
    case invalidEndpoint, insecureEndpoint, wrongInstance, unauthorized
    case invalidResponse, unavailable, server(Int), noToken, bindingChanged

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a Server address without a path, query or credentials."
        case .insecureEndpoint: "A Server outside this Mac requires HTTPS."
        case .wrongInstance: "The Server identity differs from the saved binding. Forget it explicitly before pairing another Server."
        case .unauthorized: "The Server rejected the token."
        case .invalidResponse: "The Server returned an invalid or inconsistent response."
        case .unavailable: "The Server is unavailable. The last successful observation remains labelled with its time."
        case .server(let code): "The Server returned HTTP \(code)."
        case .noToken: "Enter the Server token."
        case .bindingChanged: "The Server address differs from the saved binding. Forget it explicitly before changing Server."
        }
    }
}

struct Identity: Decodable, Sendable {
    let instance_id: String
}

struct ServerStatus: Decodable, Sendable {
    let instance_id: String
    let version: String
    let state: String
    let project_source: String
}

struct Project: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct ProjectCatalogue: Decodable, Sendable {
    let state: String
    let projects: [Project]
    let source: String?
    let observed_at: String?
    let partial: Bool
    let stale: Bool
}

struct Capability: Decodable, Identifiable, Sendable {
    let id: String
    let exposure: String
    let auth: String
    let method: String?
    let path: String?
}

struct CapabilityInventory: Decodable, Sendable {
    let schema_version: Int
    let product_version: String
    let instance_id: String
    let operations: [Capability]
    let peer_operations_qualified: Bool
}

struct ForgeObservation: Decodable, Sendable {
    let schema_version: Int
    let state: String
    let instance_id: String?
    let repository_id: String?
    let product_version: String?
    let availability: String?
    let freshness: String?
    let source_observed_at: String?
    let retrieved_at: String?

    var isCurrent: Bool {
        state == "OBSERVED" && availability == "AVAILABLE" && freshness == "CURRENT"
    }

    private func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private func validRetrievedTime(_ value: String) -> Bool {
        guard matches(value, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$") else {
            return false
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }

    private func validSourceTime(_ value: String) -> Bool {
        guard value.count <= 128 else { return false }
        // The Server validates and preserves Python's ISO week, compact and reduced-time spellings.
        let pattern = "^([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{8}|[0-9]{4}-W[0-9]{2}-[1-7]).([0-9]{2})(?::?([0-9]{2}))?(?::?([0-9]{2}))?(?:[.,][0-9]+)?(Z|[+-][0-9]{2}(?::?[0-9]{2})?(?::?[0-9]{2})?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return false
        }
        func part(_ index: Int) -> String? {
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
        guard let date = part(1), let hour = part(2), let zone = part(5),
              let h = Int(hour), h < 24,
              part(3).flatMap(Int.init).map({ $0 < 60 }) ?? true,
              part(4).flatMap(Int.init).map({ $0 < 60 }) ?? true else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        formatter.dateFormat = date.contains("W") ? "YYYY-'W'ww-e" :
            (date.contains("-") ? "yyyy-MM-dd" : "yyyyMMdd")
        guard formatter.date(from: date) != nil else { return false }
        if zone == "Z" { return true }
        let offset = String(zone.dropFirst()).replacingOccurrences(of: ":", with: "")
        guard [2, 4, 6].contains(offset.count), let zoneHours = Int(offset.prefix(2)),
              zoneHours < 24 else { return false }
        if offset.count >= 4 && (Int(offset.dropFirst(2).prefix(2)) ?? 60) >= 60 { return false }
        if offset.count == 6 && (Int(offset.suffix(2)) ?? 60) >= 60 { return false }
        return true
    }

    var isValid: Bool {
        let errors = ["UNCONFIGURED", "INVALID_CONFIGURATION", "READ_SCOPE_UNVERIFIED",
                      "WRONG_INSTANCE", "INVALID_RESPONSE", "UNAUTHORIZED", "DENIED",
                      "UNAVAILABLE", "TLS_UNTRUSTED"]
        guard schema_version == 1 else { return false }
        if errors.contains(state) {
            return availability == nil && freshness == nil && source_observed_at == nil &&
                retrieved_at == nil && product_version == nil
        }
        guard state == "OBSERVED", let instance_id,
              matches(instance_id, "^[A-Za-z0-9_-]{8,128}$"),
              let repository_id, matches(repository_id, "^[A-Za-z0-9_.:-]{1,128}$"),
              let product_version,
              product_version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              let availability, ["AVAILABLE", "UNAVAILABLE"].contains(availability),
              let freshness, ["CURRENT", "STALE", "UNKNOWN", "UNAVAILABLE"].contains(freshness),
              let retrieved_at, validRetrievedTime(retrieved_at) else { return false }
        return !(["CURRENT", "STALE"].contains(freshness) && source_observed_at == nil) &&
            !((availability == "UNAVAILABLE") != (freshness == "UNAVAILABLE")) &&
            (source_observed_at.map(validSourceTime) ?? true)
    }
}

struct ServerSnapshot: Sendable {
    let identity: Identity
    let status: ServerStatus
    let projects: Result<ProjectCatalogue, ClientError>
    let capabilities: Result<CapabilityInventory, ClientError>
    let forge: Result<ForgeObservation, ClientError>
    let observedAt: Date
}

final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ServerTransport: Sendable {
    let session: URLSession

    init(configuration supplied: URLSessionConfiguration? = nil) {
        let configuration = supplied ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    private func read<T: Decodable>(_ type: T.Type, endpoint: ServerEndpoint, path: String,
                                     token: String? = nil, pin: String? = nil) async throws -> T {
        var request = URLRequest(url: endpoint.route(path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let token, let pin {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(pin, forHTTPHeaderField: "X-Workspace-Instance")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw ClientError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw ClientError.unauthorized
        case 409: throw ClientError.wrongInstance
        default: throw ClientError.server(http.statusCode)
        }
        guard data.count <= 1_000_000,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw ClientError.invalidResponse
        }
        return decoded
    }

    func connect(endpoint: ServerEndpoint, token: String, pinnedInstance: String?) async throws -> ServerSnapshot {
        guard !token.isEmpty else { throw ClientError.noToken }
        let identity = try await read(Identity.self, endpoint: endpoint, path: "/v1/identity")
        guard identity.instance_id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw ClientError.invalidResponse
        }
        if let pinnedInstance, pinnedInstance != identity.instance_id { throw ClientError.wrongInstance }
        let status = try await read(ServerStatus.self, endpoint: endpoint, path: "/v1/status",
                                    token: token, pin: identity.instance_id)
        guard status.instance_id == identity.instance_id, status.state == "READY",
              status.version.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil,
              ["UNCONFIGURED", "EMPTY", "PARTIAL", "STALE", "AVAILABLE", "SOURCE_UNAVAILABLE"].contains(status.project_source) else {
            throw ClientError.invalidResponse
        }
        async let projectRead: Result<ProjectCatalogue, ClientError> = optionalRead(
            ProjectCatalogue.self, endpoint: endpoint, path: "/v1/projects", token: token,
            pin: identity.instance_id, validate: { catalogue in
                guard catalogue.projects.count <= 100,
                      Set(catalogue.projects.map(\.id)).count == catalogue.projects.count else { return false }
                if catalogue.state == "UNCONFIGURED" {
                    return catalogue.projects.isEmpty && catalogue.source == nil &&
                        catalogue.observed_at == nil && !catalogue.partial && !catalogue.stale
                }
                let expected = catalogue.stale ? "STALE" : catalogue.partial ? "PARTIAL" :
                    (catalogue.projects.isEmpty ? "EMPTY" : "AVAILABLE")
                return catalogue.state == expected && ["LOCAL", "DEMO"].contains(catalogue.source ?? "") &&
                    !(catalogue.observed_at ?? "").isEmpty
            })
        async let capabilityRead: Result<CapabilityInventory, ClientError> = optionalRead(
            CapabilityInventory.self, endpoint: endpoint, path: "/v1/capabilities", token: token,
            pin: identity.instance_id, validate: { inventory in
                inventory.schema_version == 1 && inventory.instance_id == identity.instance_id &&
                inventory.product_version == status.version && !inventory.peer_operations_qualified &&
                Set(inventory.operations.map(\.id)).count == inventory.operations.count
            })
        async let forgeRead: Result<ForgeObservation, ClientError> = optionalRead(
            ForgeObservation.self, endpoint: endpoint, path: "/v1/forge/status", token: token,
            pin: identity.instance_id, validate: { $0.isValid })
        let projects = await projectRead
        let capabilities = await capabilityRead
        let forge = await forgeRead
        if case .failure(.unauthorized) = projects { throw ClientError.unauthorized }
        if case .failure(.wrongInstance) = projects { throw ClientError.wrongInstance }
        if case .failure(.unauthorized) = capabilities { throw ClientError.unauthorized }
        if case .failure(.wrongInstance) = capabilities { throw ClientError.wrongInstance }
        if case .failure(.unauthorized) = forge { throw ClientError.unauthorized }
        if case .failure(.wrongInstance) = forge { throw ClientError.wrongInstance }
        return ServerSnapshot(identity: identity, status: status, projects: projects,
                              capabilities: capabilities, forge: forge, observedAt: Date())
    }

    private func optionalRead<T: Decodable & Sendable>(_ type: T.Type, endpoint: ServerEndpoint,
        path: String, token: String, pin: String, validate: @escaping @Sendable (T) -> Bool
    ) async -> Result<T, ClientError> {
        do {
            let value = try await read(type, endpoint: endpoint, path: path, token: token, pin: pin)
            return validate(value) ? .success(value) : .failure(.invalidResponse)
        } catch is CancellationError {
            return .failure(.unavailable)
        } catch let error as ClientError {
            return .failure(error)
        } catch {
            return .failure(.unavailable)
        }
    }
}
