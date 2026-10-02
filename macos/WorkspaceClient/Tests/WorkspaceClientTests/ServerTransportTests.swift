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

final class ServerTransportTests: XCTestCase {
    let instance = "0123456789abcdef0123456789abcdef"

    private func transport(_ handler: @escaping (URLRequest) throws -> (Int, Data)) -> ServerTransport {
        StubProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return ServerTransport(session: URLSession(configuration: config))
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
        XCTAssertEqual(Set(paths), Set(["/v1/identity", "/v1/status", "/v1/projects", "/v1/capabilities"]))
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
        let client = ServerTransport(session: URLSession(configuration: config))
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
}
