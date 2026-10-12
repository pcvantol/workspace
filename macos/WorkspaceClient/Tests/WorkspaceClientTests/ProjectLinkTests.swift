import Foundation
import SwiftUI
import AppKit
import XCTest
@testable import WorkspaceClient

private final class LinkFixture: ProjectLinkReading, @unchecked Sendable {
    var current = ProjectLinkAccess(workspaceInstanceID: "workspace", actorID: "actor", peerID: "ep", projectIDs: ["atlas"], expiresAt: Date().addingTimeInterval(3600), epoch: "1")
    var rows = [LinkProject(id: "atlas", name: "Atlas")]
    var value = LinkTopology(peerID: "ep", projectID: "atlas", name: "Atlas", authorityID: "core", revision: 1, observedAt: Date(), repositories: [.init(id: "core", name: "Core", role: "authority", availableAttachments: 2), .init(id: "client", name: "Client", role: "child", availableAttachments: 0)])
    var error: ProjectLinkError?
    var linkError: ProjectLinkError?
    var commands: [ProjectLinkIntent] = []
    var openCalls = 0
    var hold: CheckedContinuation<[LinkProject], Error>?
    var holdDiscovery = false
    func access() async throws -> ProjectLinkAccess { if let error { throw error }; return current }
    func discover(_ access: ProjectLinkAccess) async throws -> [LinkProject] {
        if holdDiscovery { return try await withCheckedThrowingContinuation { hold = $0 } }; return rows
    }
    func inspect(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology { if let error { throw error }; return value }
    func link(_ access: ProjectLinkAccess, intent: ProjectLinkIntent) async throws -> String {
        commands.append(intent); if let linkError { throw linkError }; return value.projectID
    }
    func open(_ access: ProjectLinkAccess, project: String) async throws -> LinkTopology { openCalls += 1; if let error { throw error }; return value }
}
final class ProjectLinkTests: XCTestCase {
    @MainActor func testChooseInspectDurableOriginalIntentRestartAndNoRepeatedClick() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = LinkFixture(), store = PrivateProjectLinkIntents(root: root)
        let state = ProjectLinkState(reader: fixture, intents: store)
        await state.select("unknown"); await state.linkAndOpen(); XCTAssertNil(state.opened)
        await state.refresh(); XCTAssertEqual(state.phase, "choose")
        await state.select("atlas"); XCTAssertEqual(state.topology?.repositories.count, 2)
        fixture.linkError = .unavailable
        await state.linkAndOpen(); XCTAssertEqual(state.phase, "unavailable")
        let original = try XCTUnwrap(store.load(fixture.current.intentKey("atlas")))
        let restart = ProjectLinkState(reader: fixture, intents: store)
        fixture.linkError = nil
        await restart.refresh(); await restart.select("atlas"); await restart.linkAndOpen()
        XCTAssertEqual(restart.phase, "opened"); XCTAssertEqual(fixture.commands.count, 2)
        XCTAssertEqual(fixture.commands[0], fixture.commands[1]); XCTAssertEqual(original, fixture.commands[1])
        XCTAssertEqual(restart.opened?.authorityID, "core")
        XCTAssertNotEqual(fixture.current.intentKey("atlas"), fixture.current.intentKey("other"))
        restart.invalidate(); XCTAssertNil(restart.opened); XCTAssertTrue(restart.projects.isEmpty)
        XCTAssertEqual(try store.load(fixture.current.intentKey("atlas")), original)
    }
    @MainActor func testEmptyErrorsAndLateResponseAfterClosingNeverRestoreData() async throws {
        let fixture = LinkFixture(); let state = ProjectLinkState(reader: fixture)
        fixture.rows = []; await state.refresh(); XCTAssertEqual(state.phase, "empty")
        for error in [ProjectLinkError.denied, .unavailable, .unsupported, .expired, .conflict, .invalid, .notFound] {
            fixture.error = error; await state.refresh(); XCTAssertNil(state.access); XCTAssertTrue(state.projects.isEmpty)
        }
        fixture.error = nil; fixture.rows = [.init(id: "outside", name: "Not permitted")]
        await state.refresh(); XCTAssertEqual(state.phase, "invalid")
        fixture.rows = [.init(id: "atlas", name: "Atlas")]; fixture.holdDiscovery = true
        let task = Task { await state.refresh() }
        for _ in 0..<100 where fixture.hold == nil { await Task.yield() }
        XCTAssertNotNil(fixture.hold); state.invalidate()
        fixture.hold?.resume(returning: fixture.rows); await task.value
        XCTAssertTrue(state.projects.isEmpty); XCTAssertNil(state.access); XCTAssertFalse(state.busy)
    }
    @MainActor func testTopologyIdentityAuthorityAndCurrentExpiryAreGuards() async throws {
        let fixture = LinkFixture(); try fixture.value.validate(fixture.current, project: "atlas")
        for scope in [ProjectLinkAccess(workspaceInstanceID:"w",actorID:"actor",peerID:"wrong",projectIDs:["atlas"],expiresAt:Date().addingTimeInterval(3600),epoch:"1"),
            ProjectLinkAccess(workspaceInstanceID:"w",actorID:"actor",peerID:"ep",projectIDs:[],expiresAt:Date().addingTimeInterval(3600),epoch:"1") ] {
            XCTAssertThrowsError(try fixture.value.validate(scope, project:"atlas"))
        }
        XCTAssertThrowsError(try fixture.value.validate(fixture.current, project:"wrong"))
        for scope in [ProjectLinkAccess(workspaceInstanceID:"bad/path",actorID:"actor",peerID:"ep",projectIDs:["atlas"],expiresAt:Date().addingTimeInterval(3600),epoch:"1"),
            ProjectLinkAccess(workspaceInstanceID:"w",actorID:"actor",peerID:"ep",projectIDs:["atlas"],expiresAt:Date().addingTimeInterval(-1),epoch:"1") ] {
            XCTAssertThrowsError(try scope.validate())
        }
        let bad = LinkTopology(peerID:"ep",projectID:"atlas",name:"Atlas",authorityID:"unknown",revision:1,observedAt:Date(),repositories:fixture.value.repositories)
        XCTAssertThrowsError(try bad.validate(fixture.current,project:"atlas"))
        let state = ProjectLinkState(reader:fixture)
        await state.refresh(); fixture.value = bad; await state.select("atlas")
        XCTAssertEqual(state.phase,"invalid"); XCTAssertNil(state.topology)
        let key = fixture.current.intentKey("atlas")
        let invalid = ProjectLinkIntent(scopeKey:key,projectID:"atlas",expectedRevision:0,operationID:"x",authorityID:"core")
        XCTAssertThrowsError(try invalid.validate(key))
    }
    @MainActor func testAllFiveLocalesAndActualSourceViewStates() async throws {
        for language in ["en","nl","de","fr","es"] {
            for key in ProjectLinkCopy.values.keys { XCTAssertNotEqual(ProjectLinkCopy.text(key,language:language),key) }
            XCTAssertFalse(ProjectLinkCopy.text("authority",language:language).isEmpty)
        }
        XCTAssertEqual(ProjectLinkCopy.text("unknown",language:"nl"),"unknown")
        XCTAssertEqual(ProjectLinkCopy.text("title",language:"unsupported"),"Projects")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = LinkFixture(); let state = ProjectLinkState(reader:fixture, intents:PrivateProjectLinkIntents(root:root))
        let view = NSHostingView(rootView:ProjectLinkView(state:state)); view.frame = NSRect(x:0,y:0,width:640,height:780)
        view.layoutSubtreeIfNeeded(); await state.refresh(); view.layoutSubtreeIfNeeded()
        await state.select("atlas"); view.layoutSubtreeIfNeeded()
        await state.linkAndOpen(); view.layoutSubtreeIfNeeded(); XCTAssertEqual(state.phase,"opened")
        state.invalidate(); view.layoutSubtreeIfNeeded(); XCTAssertNil(state.topology)
    }
    func testUnboundProducerCannotReturnFixtureSuccess() async throws {
        let fixture = LinkFixture(), reader = UnboundProjectLinkReader()
        for action in 0..<5 {
            do {
                switch action {
                case 0: _ = try await reader.access()
                case 1: _ = try await reader.discover(fixture.current)
                case 2: _ = try await reader.inspect(fixture.current,project:"atlas")
                case 3: _ = try await reader.link(fixture.current,intent:.init(scopeKey:"key",projectID:"atlas",expectedRevision:1,operationID:"op",authorityID:"core"))
                default: _ = try await reader.open(fixture.current,project:"atlas")
                }; XCTFail("Unbound reader must not succeed")
            } catch ProjectLinkError.unsupported {} catch { XCTFail("Unexpected error") }
        }
    }
}

private final class LinkHTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (Int, [String: Any]) = (503, ["error":"PROJECT_LINK_PRODUCER_UNBOUND"])
    nonisolated(unsafe) static var last: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.last = request
        let response = HTTPURLResponse(url:request.url!,statusCode:Self.reply.0,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:Self.reply.1))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
extension ProjectLinkTests {
    func testClosedOwnIPCHeadersAndBindingsRejectMalformedOrDeniedReplies() async throws {
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[LinkHTTPFixtureProtocol.self]
        let connection=ProjectLinkConnection(endpoint:"http://127.0.0.1:8765/",workspaceInstanceID:"workspace",bearer:"own-server",actorPairingToken:"existing-actor-proof",actorID:"actor",peerID:"ep")
        let reader=ProjectLinkHTTPReader(connection:{connection},session:URLSession(configuration:configuration))
        let scope=ProjectLinkAccess(workspaceInstanceID:"workspace",actorID:"actor",peerID:"ep",projectIDs:["atlas"],expiresAt:Date().addingTimeInterval(3600),epoch:"one")
        let formatter=ISO8601DateFormatter()
        let access:[String:Any]=["workspace_instance_id":"workspace","actor_id":"actor","peer_id":"ep","project_ids":["atlas"],"expires_at":formatter.string(from:scope.expiresAt),"epoch":"one"]
        LinkHTTPFixtureProtocol.reply=(200,access);let actual=try await reader.access();XCTAssertEqual(actual.actorID,"actor")
        XCTAssertEqual(LinkHTTPFixtureProtocol.last?.value(forHTTPHeaderField:"X-Workspace-Project-Grant"),"existing-actor-proof")
        XCTAssertEqual(LinkHTTPFixtureProtocol.last?.value(forHTTPHeaderField:"X-Workspace-Instance"),"workspace")
        LinkHTTPFixtureProtocol.reply=(200,["projects":[["id":"atlas","name":"Atlas"]],"state":"AVAILABLE"])
        let rows=try await reader.discover(scope);XCTAssertEqual(rows.map(\.name),["Atlas"])
        let topology:[String:Any]=["peer_id":"ep","project_id":"atlas","name":"Atlas","authority_repository_id":"core","revision":1,"observed_at":formatter.string(from:Date()),"repositories":[["id":"core","name":"Core","role":"authority","available_attachments":2]]]
        LinkHTTPFixtureProtocol.reply=(200,topology);let detail=try await reader.inspect(scope,project:"atlas");XCTAssertEqual(detail.authorityID,"core")
        let intent=ProjectLinkIntent(scopeKey:scope.intentKey("atlas"),projectID:"atlas",expectedRevision:1,operationID:"operation",authorityID:"core")
        LinkHTTPFixtureProtocol.reply=(200,["project_id":"atlas","operation_id":"operation","state":"REFERENCE_SAVED","engineering_readiness":"NOT_ASSESSED"])
        let linked=try await reader.link(scope,intent:intent);XCTAssertEqual(linked,"atlas")
        XCTAssertEqual(LinkHTTPFixtureProtocol.last?.httpMethod,"POST")
        LinkHTTPFixtureProtocol.reply=(200,["topology":topology,"state":"VERIFIED_REFERENCE","engineering_readiness":"NOT_ASSESSED"])
        let opened=try await reader.open(scope,project:"atlas");XCTAssertEqual(opened.projectID,"atlas")
        for code in [401,403,404,409,503,500] {
            LinkHTTPFixtureProtocol.reply=(code,["error":"PROJECT_LINK_PRODUCER_UNBOUND"])
            do { _=try await reader.access();XCTFail("Error response cannot qualify scope") } catch {}
        }
        for invalid in [access.merging(["actor_id":"different"]){ _,new in new },access.merging(["project_ids":["atlas","atlas"]]){ _,new in new },access.merging(["extra":"no"]){ _,new in new }] {
            LinkHTTPFixtureProtocol.reply=(200,invalid)
            do { _=try await reader.access();XCTFail("Malformed scope cannot qualify") } catch {}
        }
        for invalid in [topology.merging(["revision":true]){ _,new in new },topology.merging(["repositories":[["id":"core","name":"Core","role":"authority","available_attachments":true]]]){ _,new in new }] {
            LinkHTTPFixtureProtocol.reply=(200,invalid)
            do { _=try await reader.inspect(scope,project:"atlas");XCTFail("Bool is not integer") } catch {}
        }
        do { _=try await reader.open(scope,project:"outside");XCTFail("Out of scope") } catch {}
        let absent=ProjectLinkHTTPReader(connection:{throw ProjectLinkError.unsupported})
        do { _=try await absent.access();XCTFail("Missing accepted binding") } catch {}
    }
    @MainActor func testKnownExpiryClearsProtectedSourceWithoutDeletingDurableIntent() async throws {
        let fixture=LinkFixture();let state=ProjectLinkState(reader:fixture)
        await state.refresh();await state.select("atlas")
        state.expireIfNecessary(now:fixture.current.expiresAt.addingTimeInterval(1))
        XCTAssertEqual(state.phase,"expired");XCTAssertTrue(state.projects.isEmpty);XCTAssertNil(state.topology)
    }
}
