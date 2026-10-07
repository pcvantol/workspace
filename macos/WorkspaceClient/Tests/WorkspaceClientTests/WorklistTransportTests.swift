import Foundation
import Security
import XCTest
@testable import WorkspaceClient

final class WorklistStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data, String?))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        do {
            let (code, data, contentType) = try Self.handler!(request)
            let headers = contentType.map { ["Content-Type": $0] } ?? [:]
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

private final class WorklistKeychainBackend: @unchecked Sendable {
    var stored: Data?
    var copyStatus: OSStatus?
    var updateStatus: OSStatus?
    var addStatus: OSStatus?
    var deleteStatus: OSStatus?
    var queries: [[CFString: Any]] = []

    var operations: DraftKeychainOperations {
        DraftKeychainOperations(copy: { query in
            self.queries.append(query as! [CFString: Any])
            if let status = self.copyStatus { return (status, nil) }
            return self.stored.map { (errSecSuccess, $0) } ?? (errSecItemNotFound, nil)
        }, update: { query, values in
            self.queries.append(query as! [CFString: Any])
            if let status = self.updateStatus { return status }
            guard self.stored != nil else { return errSecItemNotFound }
            self.stored = (values as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }, add: { values in
            self.queries.append(values as! [CFString: Any])
            if let status = self.addStatus { return status }
            self.stored = (values as NSDictionary)[kSecValueData] as? Data
            return errSecSuccess
        }, delete: { query in
            self.queries.append(query as! [CFString: Any])
            if let status = self.deleteStatus { return status }
            guard self.stored != nil else { return errSecItemNotFound }
            self.stored = nil
            return errSecSuccess
        })
    }
}

final class WorklistTransportTests: XCTestCase {
    private let endpoint = "http://127.0.0.1:8765/"
    private let instance = String(repeating: "a", count: 32)
    private let forge = String(repeating: "f", count: 32)
    private let token = String(repeating: "W", count: 43)

    private func access(actor: String = "actor-a", worksets: [String] = ["workset-a"],
                        endpoint address: String? = nil, instance pin: String? = nil,
                        forge source: String? = nil, token grant: String? = nil) -> WorklistAccess {
        WorklistAccess(endpoint: address ?? endpoint, workspaceInstanceID: pin ?? instance,
                       forgeInstanceID: source ?? forge, actorID: actor,
                       worksetIDs: worksets, token: grant ?? token)
    }

    private func body(actor: String = "actor-a", worksets: [String] = ["workset-a"],
                      source: String? = nil, readOnly: Bool = true) -> [String: Any] {
        ["contract_version": "forge-workspace-worklist-scopes/v1", "instance_id": source ?? forge,
         "principal_id": actor, "workset_ids": worksets, "read_only": readOnly]
    }

    private func transport(_ reply: @escaping (URLRequest) throws -> (Int, Data, String?)) -> WorklistTransport {
        WorklistStubProtocol.handler = reply
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorklistStubProtocol.self]
        return WorklistTransport(configuration: configuration)
    }

    func testProbeAndRefreshOnlyReadTheExactWorksetScopeWithSeparateCredential() async throws {
        var calls: [String] = []
        let data = try JSONSerialization.data(withJSONObject: body())
        let client = transport { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.url?.path, "/v1/worksets")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Instance"), self.instance)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Worklist-Grant"), self.token)
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Workspace-Review-Grant"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer root-read")
            calls.append(request.httpMethod!)
            return (200, data, "application/json; charset=utf-8")
        }
        let granted = try await client.probe(endpoint: ServerEndpoint(endpoint), workspaceToken: "root-read",
                                             instance: instance, worklistToken: token)
        XCTAssertEqual(granted, access())
        let current = try await client.scopes(access: granted, workspaceToken: "root-read")
        XCTAssertEqual(current, ["workset-a"])
        XCTAssertEqual(calls, ["GET", "GET"])
    }

    func testForeignChangedDuplicateAndUnboundedScopesCannotBeMerged() async throws {
        for invalid in [body(actor: "actor-b"), body(worksets: ["workset-b"]), body(source: "foreign"),
                        body(worksets: []), body(worksets: ["workset-a", "workset-a"]),
                        body(worksets: (0..<17).map { "workset-\($0)" }), body(readOnly: false)] {
            let data = try JSONSerialization.data(withJSONObject: invalid)
            let client = transport { _ in (200, data, "application/json") }
            do {
                _ = try await client.scopes(access: access(), workspaceToken: "read")
                XCTFail("Invalid scope was accepted")
            } catch WorklistTransportError.denied {}
        }
        var extra = body()
        extra["project_id"] = "unproven"
        let data = try JSONSerialization.data(withJSONObject: extra)
        let client = transport { _ in (200, data, "application/json") }
        do {
            _ = try await client.probe(endpoint: ServerEndpoint(endpoint), workspaceToken: "read", instance: instance, worklistToken: token)
            XCTFail("Unexpected scope field was accepted")
        } catch WorklistTransportError.invalidResponse {}
    }

    func testFailuresRemainDistinctAndInvalidAccessMakesNoRequest() async throws {
        let cases: [(Int, String, WorklistTransportError)] = [
            (401, "DENIED", .unauthorized), (403, "DENIED", .denied), (404, "NOT_FOUND", .missing),
            (409, "WRONG_INSTANCE", .wrongInstance), (503, "WORKLIST_UNAVAILABLE", .unavailable),
            (503, "WORKLIST_INVALID_RESPONSE", .inconsistentSnapshot),
            (503, "WORKLIST_INCONSISTENT_SNAPSHOT", .inconsistentSnapshot), (301, "", .unavailable)]
        for (status, code, expected) in cases {
            let data = try JSONSerialization.data(withJSONObject: ["error": code])
            let client = transport { _ in (status, data, "application/json") }
            do {
                _ = try await client.scopes(access: access(), workspaceToken: "read")
                XCTFail("Failed status was accepted")
            } catch let error as WorklistTransportError { XCTAssertEqual(error, expected) }
        }
        var called = false
        let client = transport { _ in called = true; throw URLError(.notConnectedToInternet) }
        do {
            _ = try await client.scopes(access: access(token: "bad"), workspaceToken: "read")
            XCTFail("Invalid credential was sent")
        } catch WorklistTransportError.denied {}
        XCTAssertFalse(called)
        do {
            _ = try await client.scopes(access: access(), workspaceToken: "read")
            XCTFail("Offline transport was accepted")
        } catch WorklistTransportError.unavailable {}
    }

    func testMalformedOversizedAndWrongMediaTypeFailClosed() async throws {
        for (data, media) in [(Data("{\"read_only\":1}".utf8), "application/json"),
                              (Data("[]".utf8), "application/json"),
                              (Data(repeating: 32, count: 1_000_001), "application/json"),
                              (try JSONSerialization.data(withJSONObject: body()), "text/plain")] {
            let client = transport { _ in (200, data, media) }
            do {
                _ = try await client.scopes(access: access(), workspaceToken: "read")
                XCTFail("Invalid body was accepted")
            } catch WorklistTransportError.invalidResponse {}
        }
        XCTAssertTrue(WorklistWire.digest("sha256:" + String(repeating: "a", count: 64)))
        XCTAssertFalse(WorklistWire.digest("../path"))
    }

    func testSavedCredentialBoundsAndSeparateInjectedKeychainNamespace() throws {
        let backend = WorklistKeychainBackend()
        let keychain = WorklistKeychain(operations: backend.operations)
        XCTAssertNil(try keychain.loadAccess())
        try keychain.saveAccess(access())
        XCTAssertEqual(try keychain.loadAccess(), access())
        try keychain.saveAccess(access(actor: "actor-b", worksets: ["workset-b"]))
        XCTAssertEqual(try keychain.loadAccess()?.actorID, "actor-b")
        for query in backend.queries {
            XCTAssertEqual(query[kSecAttrService] as? String, "com.pcvantol.workspace.native-client.worklists.v1")
        }
        try keychain.forgetAccess()
        try keychain.forgetAccess()
        XCTAssertNil(try keychain.loadAccess())
        for invalid in [access(actor: "../foreign"), access(worksets: []),
                        access(worksets: ["duplicate", "duplicate"]), access(worksets: ["../foreign"]),
                        access(instance: "foreign"), access(forge: ""), access(token: "bad"),
                        access(endpoint: "http://127.0.0.1:8765")] {
            XCTAssertFalse(invalid.valid)
            XCTAssertThrowsError(try keychain.saveAccess(invalid))
        }
        backend.stored = Data("bad".utf8)
        XCTAssertThrowsError(try keychain.loadAccess())
    }

    func testCredentialBackendFailuresDoNotAuthorizeOrEraseBinding() throws {
        let backend = WorklistKeychainBackend()
        let keychain = WorklistKeychain(operations: backend.operations)
        backend.copyStatus = errSecAuthFailed
        XCTAssertThrowsError(try keychain.loadAccess())
        backend.copyStatus = nil
        backend.updateStatus = errSecAuthFailed
        XCTAssertThrowsError(try keychain.saveAccess(access()))
        backend.updateStatus = nil
        backend.addStatus = errSecAuthFailed
        XCTAssertThrowsError(try keychain.saveAccess(access()))
        backend.addStatus = nil
        try keychain.saveAccess(access())
        backend.deleteStatus = errSecAuthFailed
        XCTAssertThrowsError(try keychain.forgetAccess())
        XCTAssertEqual(try keychain.loadAccess(), access())
    }
}
