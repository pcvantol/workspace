import Foundation
import XCTest
@testable import WorkspaceClient

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

final class HangingProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

final class RedirectProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var destination = ""
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.requests.append(request)
        let identity = request.url?.path == "/v1/identity"
        let code = identity ? 200 : 302
        let headers = identity ? ["Content-Type": "application/json"] :
            ["Content-Type": "application/json", "Location": Self.destination]
        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if identity {
            client?.urlProtocol(self, didLoad: Data("{\"instance_id\":\"0123456789abcdef0123456789abcdef\"}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class BrokenCredentials: CredentialStore, @unchecked Sendable {
    var forgotten = false
    func binding() throws -> ServerBinding? { throw CredentialError.corruptBinding }
    func token() throws -> String? { nil }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws { forgotten = true }
}

final class OrphanCredentials: CredentialStore, @unchecked Sendable {
    var forgotten = false
    func binding() throws -> ServerBinding? { nil }
    func token() throws -> String? { forgotten ? nil : "orphan-secret" }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws { forgotten = true }
}

final class PendingCredentials: CredentialStore, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    func binding() throws -> ServerBinding? {
        release.wait()
        return nil
    }
    func token() throws -> String? { nil }
    func save(binding: ServerBinding, token: String) throws {}
    func forget() throws {}
}

final class PendingSaveCredentials: CredentialStore, @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private(set) var savedBinding: ServerBinding?
    private(set) var savedToken: String?
    func binding() throws -> ServerBinding? { savedBinding }
    func token() throws -> String? { savedToken }
    func save(binding: ServerBinding, token: String) throws {
        release.wait()
        savedBinding = binding
        savedToken = token
    }
    func forget() throws {
        savedBinding = nil
        savedToken = nil
    }
}

final class ServerTransportTests: XCTestCase {
    let instance = "0123456789abcdef0123456789abcdef"

    @MainActor
    private static func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Client state did not settle")
    }

    private func transport(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> ServerTransport {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ServerTransport(configuration: config)
    }

    func testEndpointSecurityAndCanonicalAddress() throws {
        XCTAssertEqual(try ServerEndpoint("http://127.0.0.1:8765").url.absoluteString,
                       "http://127.0.0.1:8765/")
        XCTAssertEqual(try ServerEndpoint("https://server.example:443/").url.scheme, "https")
        for address in ["http://server.example:8765", "http://192.0.2.1:8765"] {
            XCTAssertThrowsError(try ServerEndpoint(address)) { error in
                XCTAssertEqual(error as? ClientError, .insecureEndpoint)
            }
        }
        for address in ["https://user:secret@server.example", "https://server.example/v1/status",
                        "https://server.example/?x=1", "file:///tmp/server", "http://127.0.0.1:70000"] {
            XCTAssertThrowsError(try ServerEndpoint(address))
        }
    }

    func testRealRouteHeadersAndIndependentReadbacks() async throws {
        let instance = self.instance
        var paths: [String] = []
        let client = transport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let path = request.url!.path
            paths.append(path)
            if path != "/v1/identity" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Instance"), instance)
            }
            switch path {
            case "/v1/identity": return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status": return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.4.67\",\"state\":\"READY\",\"project_source\":\"AVAILABLE\"}".utf8))
            case "/v1/projects": return (200, Data("{\"state\":\"AVAILABLE\",\"projects\":[{\"id\":\"one\",\"name\":\"One\"}],\"source\":\"LOCAL\",\"observed_at\":\"2026-10-02T10:00:00Z\",\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities": return (503, Data("{\"error\":\"SOURCE_UNAVAILABLE\"}".utf8))
            case "/v1/forge/status": return (200, Data("{\"schema_version\":1,\"state\":\"OBSERVED\",\"instance_id\":\"forge-runtime-one\",\"repository_id\":\"repo-1\",\"product_version\":\"2.7.59\",\"availability\":\"AVAILABLE\",\"freshness\":\"CURRENT\",\"source_observed_at\":\"2026-10-02T10:00:00Z\",\"retrieved_at\":\"2026-10-02T10:00:01Z\"}".utf8))
            default: XCTFail("Unexpected route \(path)"); return (404, Data())
            }
        }
        let result = try await client.connect(endpoint: ServerEndpoint("http://127.0.0.1:8765"),
                                              token: "secret", pinnedInstance: nil)
        XCTAssertEqual(result.status.version, "2.4.67")
        if case .success(let projects) = result.projects {
            XCTAssertEqual(projects.projects.map(\.name), ["One"])
        } else { XCTFail("Project read failed") }
        if case .failure(.server(503)) = result.capabilities {} else { XCTFail("Capabilities should be unavailable") }
        if case .success(let forge) = result.forge {
            XCTAssertEqual(forge.repository_id, "repo-1")
            XCTAssertEqual(forge.freshness, "CURRENT")
        } else { XCTFail("Forge read failed") }
        XCTAssertEqual(Set(paths), Set(["/v1/identity", "/v1/status", "/v1/projects", "/v1/capabilities", "/v1/forge/status"]))
    }

    func testForgeProjectionKeepsSourceFreshnessDistinct() throws {
        let current = try JSONDecoder().decode(ForgeObservation.self, from: Data("{\"schema_version\":1,\"state\":\"OBSERVED\",\"instance_id\":\"forge-runtime-one\",\"repository_id\":\"repo-1\",\"product_version\":\"2.7.59\",\"availability\":\"AVAILABLE\",\"freshness\":\"CURRENT\",\"source_observed_at\":\"2026-10-02T10:00:00Z\",\"retrieved_at\":\"2026-10-02T10:00:01Z\"}".utf8))
        XCTAssertTrue(current.isValid)
        XCTAssertTrue(current.isCurrent)
        let stale = ForgeObservation(schema_version: 1, state: "OBSERVED", instance_id: current.instance_id,
            repository_id: current.repository_id, product_version: current.product_version,
            availability: "AVAILABLE", freshness: "STALE", source_observed_at: current.source_observed_at,
            retrieved_at: current.retrieved_at)
        XCTAssertTrue(stale.isValid)
        XCTAssertFalse(stale.isCurrent)
        let unverified = ForgeObservation(schema_version: 1, state: "READ_SCOPE_UNVERIFIED",
            instance_id: current.instance_id, repository_id: current.repository_id, product_version: nil,
            availability: nil, freshness: nil, source_observed_at: nil, retrieved_at: nil)
        XCTAssertTrue(unverified.isValid)
        XCTAssertFalse(unverified.isCurrent)
        let invalid = ForgeObservation(schema_version: 1, state: "OBSERVED", instance_id: current.instance_id,
            repository_id: current.repository_id, product_version: current.product_version,
            availability: "AVAILABLE", freshness: "CURRENT", source_observed_at: nil,
            retrieved_at: current.retrieved_at)
        XCTAssertFalse(invalid.isValid)
    }

    func testOwnForgeRouteAuthorizationDenialRejectsConnection() async throws {
        let instance = self.instance
        let client = transport { request in
            switch request.url!.path {
            case "/v1/identity":
                return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status":
                return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.8.0\",\"state\":\"READY\",\"project_source\":\"UNCONFIGURED\"}".utf8))
            case "/v1/forge/status":
                return (401, Data("{\"error\":\"UNAUTHORIZED\"}".utf8))
            default:
                return (404, Data("{\"error\":\"NOT_FOUND\"}".utf8))
            }
        }
        do {
            _ = try await client.connect(endpoint: ServerEndpoint("http://127.0.0.1:8765"),
                                         token: "denied", pinnedInstance: nil)
            XCTFail("Forge route authorization denial became a connected state")
        } catch let error as ClientError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testPinnedIdentityMismatchStopsBeforeCredentials() async throws {
        let instance = self.instance
        var paths: [String] = []
        let client = transport { request in
            paths.append(request.url!.path)
            return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
        }
        do {
            _ = try await client.connect(endpoint: ServerEndpoint("http://localhost:8765"),
                                         token: "secret", pinnedInstance: "ffffffffffffffffffffffffffffffff")
            XCTFail("Identity mismatch accepted")
        } catch let error as ClientError {
            XCTAssertEqual(error, .wrongInstance)
        }
        XCTAssertEqual(paths, ["/v1/identity"])
    }

    func testUnauthorizedStatusDoesNotBecomeConnected() async throws {
        let instance = self.instance
        let client = transport { request in
            request.url!.path == "/v1/identity" ?
                (200, Data("{\"instance_id\":\"\(instance)\"}".utf8)) :
                (401, Data("{\"error\":\"UNAUTHORIZED\"}".utf8))
        }
        do {
            _ = try await client.connect(endpoint: ServerEndpoint("http://localhost:8765"),
                                         token: "bad", pinnedInstance: nil)
            XCTFail("Unauthorized Server accepted")
        } catch let error as ClientError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testCancellingPendingIdentityReadStopsConnection() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingProtocol.self]
        let client = ServerTransport(configuration: config)
        let task = Task {
            try await client.connect(endpoint: ServerEndpoint("https://server.example"),
                                     token: "secret", pinnedInstance: nil)
        }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled request became a connection")
        } catch is CancellationError {
            // Expected: the pending URLSession request is cancelled.
        }
    }

    func testRedirectCannotDowngradeOrChangeCredentialDestination() async throws {
        for destination in ["http://other.example/v1/status", "https://other.example/v1/status"] {
            RedirectProtocol.destination = destination
            RedirectProtocol.requests = []
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [RedirectProtocol.self]
            let client = ServerTransport(configuration: config)
            do {
                _ = try await client.connect(endpoint: ServerEndpoint("https://server.example"),
                                             token: "secret", pinnedInstance: nil)
                XCTFail("Redirect followed to \(destination)")
            } catch let error as ClientError {
                XCTAssertEqual(error, .server(302))
            }
            XCTAssertEqual(RedirectProtocol.requests.map { $0.url?.host }, ["server.example", "server.example"])
            XCTAssertEqual(RedirectProtocol.requests.map { $0.url?.path }, ["/v1/identity", "/v1/status"])
        }
    }

    func testCorruptBindingCanBeForgotten() async {
        let credentials = BrokenCredentials()
        let state = await MainActor.run { ClientState(keychain: credentials) }
        await Self.waitUntil { state.phase == "UNAVAILABLE" }
        await MainActor.run { state.forget() }
        await Self.waitUntil { state.phase == "UNCONFIGURED" }
        XCTAssertTrue(credentials.forgotten)
        await MainActor.run { XCTAssertFalse(state.canForgetBinding) }
    }

    func testTokenOnlyPartialSaveCanBeForgotten() async {
        let credentials = OrphanCredentials()
        let state = await MainActor.run { ClientState(keychain: credentials) }
        await Self.waitUntil { state.phase == "UNAVAILABLE" }
        await MainActor.run {
            XCTAssertTrue(state.canForgetBinding)
            state.connect(address: "https://server.example")
        }
        await Self.waitUntil { state.phase == "UNAVAILABLE" && state.detail.contains("token was saved without") }
        await MainActor.run { state.forget() }
        await Self.waitUntil { state.phase == "UNCONFIGURED" }
        XCTAssertTrue(credentials.forgotten)
        await MainActor.run { XCTAssertFalse(state.canForgetBinding) }
    }

    func testPendingKeychainReadDoesNotBlockWindowInitialization() async {
        let credentials = PendingCredentials()
        let state = await MainActor.run { ClientState(keychain: credentials) }
        await MainActor.run {
            XCTAssertEqual(state.phase, "LOADING")
            XCTAssertEqual(state.detail, "Checking the saved Server binding.")
        }
        credentials.release.signal()
        await Self.waitUntil { state.phase == "UNCONFIGURED" }
    }

    func testCancelledPendingCredentialReadCannotRestoreStaleBinding() async {
        let credentials = PendingCredentials()
        let state = await MainActor.run { ClientState(keychain: credentials) }
        await MainActor.run {
            XCTAssertEqual(state.phase, "LOADING")
            state.cancel()
            XCTAssertEqual(state.phase, "UNAVAILABLE")
        }
        credentials.release.signal()
        try? await Task.sleep(for: .milliseconds(30))
        await MainActor.run { XCTAssertEqual(state.phase, "UNAVAILABLE") }
    }

    func testPendingPinSaveCannotBeCancelledOrSuperseded() async {
        let credentials = PendingSaveCredentials()
        let instance = self.instance
        let client = transport { request in
            switch request.url!.path {
            case "/v1/identity":
                return (200, Data("{\"instance_id\":\"\(instance)\"}".utf8))
            case "/v1/status":
                return (200, Data("{\"instance_id\":\"\(instance)\",\"version\":\"2.5.1\",\"state\":\"READY\",\"project_source\":\"UNCONFIGURED\"}".utf8))
            case "/v1/projects":
                return (200, Data("{\"state\":\"UNCONFIGURED\",\"projects\":[],\"source\":null,\"observed_at\":null,\"partial\":false,\"stale\":false}".utf8))
            case "/v1/capabilities":
                return (200, Data("{\"peer_operations_qualified\":false,\"operations\":[]}".utf8))
            case "/v1/forge/status":
                return (404, Data("{\"error\":\"NOT_FOUND\"}".utf8))
            default:
                XCTFail("Unexpected route")
                return (404, Data())
            }
        }
        let state = await MainActor.run { ClientState(keychain: credentials, transport: client) }
        await Self.waitUntil { state.phase == "UNCONFIGURED" }
        await MainActor.run { state.connect(address: "http://127.0.0.1:8765", enteredToken: "secret") }
        await Self.waitUntil { state.phase == "SAVING" }
        await MainActor.run {
            state.cancel()
            state.connect(address: "https://other.example", enteredToken: "other")
            state.forget()
            XCTAssertEqual(state.phase, "SAVING")
        }
        credentials.release.signal()
        await Self.waitUntil { state.phase == "CONNECTED" }
        XCTAssertEqual(credentials.savedBinding?.instanceID, instance)
        XCTAssertEqual(credentials.savedBinding?.endpoint, "http://127.0.0.1:8765/")
        XCTAssertEqual(credentials.savedToken, "secret")
    }
}
