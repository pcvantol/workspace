import XCTest
import Foundation
import SwiftUI
import AppKit
import Security
import Combine
@testable import WorkspaceClient

final class ActivityTests:XCTestCase {
    static let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Activity")
    static func data(_ name:String) throws -> Data { try Data(contentsOf:root.appendingPathComponent(name+".json")) }
    static func raw(_ name:String) throws -> [String:Any] { try JSONSerialization.jsonObject(with:data(name)) as! [String:Any] }
    static var connection:AdvisoryConnection {
        let cap=try! raw("capability")
        return AdvisoryConnection(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),actorID:cap["actor_id"] as! String,
            workspaceProjectID:cap["workspace_project_id"] as! String,conversationID:"",bearer:String(repeating:"b",count:43),draftGrant:String(repeating:"c",count:43))
    }
    static func access() throws -> ActivityAccess { try ActivityWire.access(data("capability"),connection:connection,token:String(repeating:"d",count:43),now:Date()) }
    func testSourceDerivedPageExactCurrentIdentityDigestAndUnknownTime() throws {
        let access=try Self.access(),workset=access.worksets[0].workset_id
        XCTAssertTrue(access.valid);XCTAssertTrue(access.matches(Self.connection))
        XCTAssertNotEqual(access.key(workset,draft:"one"),access.key(workset,draft:"two"))
        let page=try ActivityWire.page(Self.data("page"),access:access,workset:workset)
        XCTAssertEqual(page.events.count,11);XCTAssertFalse(page.hasMore);XCTAssertEqual(page.current.count,3)
        XCTAssertFalse(page.events[0].summary.isEmpty);XCTAssertEqual(page.current[0].title,"Assessment A")
        let event=try ActivityWire.detail(Self.data("detail"),workset:workset,id:page.events[0].id)
        XCTAssertEqual(event.id,page.events[0].id)
        var raw=try Self.raw("detail");var e=raw["event"] as! [String:Any]
        e["occurred_at"]=NSNull();e["time_status"]="UNKNOWN";raw["event"]=e
        let unknown=try ActivityWire.detail(JSONSerialization.data(withJSONObject:raw),workset:workset,id:event.id)
        XCTAssertNil(unknown.occurredAt)
        for language in ["en","nl","de","fr","es"] { XCTAssertEqual(ActivityCopy.text("FUTURE_VALID_FACT",language),ActivityCopy.text("fact",language)) }
    }
    func testMandatoryContractScopeCursorAndDigestRejects() throws {
        let access=try Self.access(),workset=access.worksets[0].workset_id
        var raw=try Self.raw("page")
        for (key,value) in [("workset_id","foreign"),("cursor","../../escape"),("contract_version","unknown/v2")] {
            var changed=raw;changed[key]=value
            XCTAssertThrowsError(try ActivityWire.page(JSONSerialization.data(withJSONObject:changed),access:access,workset:workset))
        }
        for key in ["instance_id","installation_id","membership_revision","snapshot_revision"] {
            var current=raw["current"] as! [String:Any];current[key]=key.contains("revision") ? "sha256:"+String(repeating:"f",count:64):"foreign"
            var changed=raw;changed["current"]=current
            XCTAssertThrowsError(try ActivityWire.page(JSONSerialization.data(withJSONObject:changed),access:access,workset:workset))
        }
        raw["extra_mandatory"]=true
        XCTAssertThrowsError(try ActivityWire.page(JSONSerialization.data(withJSONObject:raw),access:access,workset:workset))
        XCTAssertThrowsError(try ActivityWire.detail(Self.data("detail"),workset:"foreign",id:String(repeating:"a",count:64)))
        XCTAssertThrowsError(try ActivityWire.object(Data(repeating:32,count:32769)))
        var cap=try Self.raw("capability");cap["expires_at"]="2001-01-01T00:00:00Z"
        XCTAssertThrowsError(try ActivityWire.access(JSONSerialization.data(withJSONObject:cap),connection:Self.connection,token:String(repeating:"d",count:43),now:Date()))
    }
}

private final class ActivityMemoryCredentials:ActivityCredentials,@unchecked Sendable {
    let lock=NSLock()
    var value:ActivityAccess?
    init(_ value:ActivityAccess?) { self.value=value }
    func load() throws -> ActivityAccess? { lock.withLock { value } }
    func save(_ value:ActivityAccess) throws { lock.withLock { self.value=value } }
    func forget() throws { lock.withLock { value=nil } }
}
private actor ActivityScriptedServer:ActivityServing {
    var access:ActivityAccess
    var pageData:Data
    var mode="normal"
    var cursors:[String?]=[]
    init() throws { access=try ActivityTests.access();pageData=try ActivityTests.data("page") }
    func setMode(_ value:String) { mode=value }
    func setAccess(_ value:ActivityAccess) { access=value }
    func setPage(_ data:Data) { pageData=data }
    func probe(_ connection:AdvisoryConnection,token:String) throws -> ActivityAccess {
        if mode=="denied" { throw AdvisoryError.denied }
        if mode=="unsupported" { throw AdvisoryError.state("UNSUPPORTED") }
        if mode=="offline" { throw AdvisoryError.unavailable }
        if mode=="foreign" {
            return ActivityAccess(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,token:access.token,binding_id:access.binding_id,
                scope:ActivityScope(instance_id:"foreign",project_id:access.scope.project_id,repository_id:access.scope.repository_id),installation_id:access.installation_id,worksets:access.worksets,expires_at:access.expires_at)
        }
        return access
    }
    func page(_ connection:AdvisoryConnection,access:ActivityAccess,workset:String,cursor:String?) throws -> ActivityPage {
        cursors.append(cursor)
        if mode=="resync" || (mode=="invalid-checkpoint" && cursor != nil) { throw AdvisoryError.state("RESYNC_REQUIRED") }
        if mode=="lost" { throw AdvisoryError.unavailable }
        return try ActivityWire.page(pageData,access:access,workset:workset)
    }
    func detail(_ connection:AdvisoryConnection,access:ActivityAccess,workset:String,id:String) throws -> ActivityEvent {
        if mode=="denied" { throw AdvisoryError.denied }
        return try ActivityWire.detail(ActivityTests.data("detail"),workset:workset,id:id)
    }
}
extension ActivityTests {
    @MainActor func testDisplayedCheckpointSeparateFromPagingAndRestartDelta() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let store=ActivityLocalStore(root:root),transport=try ActivityScriptedServer(),access=try Self.access(),credentials=ActivityMemoryCredentials(access)
        let state=ActivityState(transport:transport,credentials:credentials,store:store)
        await state.connect(Self.connection);XCTAssertEqual(state.status,"choose")
        await state.choose(access.worksets[0].workset_id);XCTAssertTrue(state.complete);XCTAssertEqual(state.events.count,11)
        await state.rememberDisplayed(visible:false);XCTAssertFalse(state.journal.comparisonKnown)
        await state.rememberDisplayed(visible:true);XCTAssertTrue(state.journal.comparisonKnown);XCTAssertTrue(state.newIDs.isEmpty)
        XCTAssertEqual(state.journal.previousCursor,state.journal.cursor)
        await state.open(state.events[0].id);XCTAssertEqual(state.detail?.id,state.events[0].id)
        let key=access.key(state.selected,draft:Self.connection.draftGrant)
        XCTAssertEqual(try store.load(key).lastViewedIDs.count,11)
        state.invalidate()
        let restarted=ActivityState(transport:transport,credentials:credentials,store:store)
        await restarted.connect(Self.connection);await restarted.choose(access.worksets[0].workset_id)
        XCTAssertTrue(restarted.complete);XCTAssertTrue(restarted.journal.comparisonKnown);XCTAssertTrue(restarted.newIDs.isEmpty)
        // New source event is separately displayed without changing the prior full checkpoint.
        var raw=try Self.raw("page"),events=raw["events"] as! [[String:Any]],event=events[0]
        event["event_id"]=String(repeating:"e",count:64)
        var reference=event["source_reference"] as! [String:Any];reference["url"]=ActivityWire.prefix+access.worksets[0].workset_id+"/events/"+String(repeating:"e",count:64);event["source_reference"]=reference
        events.append(event);raw["events"]=events
        await transport.setPage(try JSONSerialization.data(withJSONObject:raw));await restarted.fetch(restart:true)
        XCTAssertEqual(restarted.events.count,12);XCTAssertEqual(restarted.newIDs,[String(repeating:"e",count:64)])
        XCTAssertEqual(restarted.journal.lastViewedIDs.count,11)
        await restarted.rememberDisplayed(visible:true);XCTAssertTrue(restarted.newIDs.isEmpty)
        restarted.forget();XCTAssertNil(try credentials.load());XCTAssertTrue(restarted.events.isEmpty)
    }
    @MainActor func testResyncLostReadAndKnownDenialPreserveDifferentBoundaries() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let transport=try ActivityScriptedServer(),access=try Self.access(),store=ActivityLocalStore(root:root)
        let state=ActivityState(transport:transport,credentials:ActivityMemoryCredentials(access),store:store)
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id);await state.rememberDisplayed(visible:true)
        let previous=state.journal.previousCursor
        await transport.setMode("lost");await state.fetch(restart:true)
        XCTAssertEqual(state.status,"unavailable");XCTAssertTrue(state.historical);XCTAssertEqual(state.events.count,11);XCTAssertFalse(state.complete)
        XCTAssertEqual(state.journal.previousCursor,previous)
        await transport.setMode("resync");await state.fetch(restart:true)
        XCTAssertEqual(state.status,"resync");XCTAssertTrue(state.historical);XCTAssertNil(state.journal.cursor)
        XCTAssertFalse(state.journal.comparisonKnown);XCTAssertEqual(state.journal.previousCursor,previous)
        await transport.setMode("normal");await state.fetch(restart:true)
        XCTAssertTrue(state.complete);XCTAssertFalse(state.journal.comparisonKnown)
        await transport.setMode("foreign");await state.fetch(restart:true)
        XCTAssertEqual(state.status,"denied");XCTAssertNil(state.access);XCTAssertTrue(state.events.isEmpty)
        await transport.setMode("unsupported");await state.connect(Self.connection)
        XCTAssertEqual(state.status,"unsupported")
        await transport.setMode("normal");await state.connect(Self.connection);await state.choose("foreign")
        XCTAssertTrue(state.selected.isEmpty);state.invalidate()
    }
    func testOpaqueMaximumCursorPrivateStorageAndCorruption() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let store=ActivityLocalStore(root:root),key=String(repeating:"a",count:64)
        XCTAssertTrue(try store.load(key).pageKeys.isEmpty)
        var value=ActivityJournal();value.cursor=String(repeating:"b",count:32768);value.previousCursor=String(repeating:"c",count:32768)
        value.lastViewedIDs=(0..<128).map { String(format:"%064x",$0) };value.comparisonKnown=true
        try store.save(value,key);let loaded=try store.load(key)
        XCTAssertEqual(loaded.cursor,value.cursor);XCTAssertEqual(loaded.previousCursor,value.previousCursor);XCTAssertEqual(loaded.lastViewedIDs,value.lastViewedIDs)
        value.cursor="../bad";XCTAssertThrowsError(try store.save(value,key))
        XCTAssertThrowsError(try store.commit(value,key,page:Data(repeating:0,count:32769),pageKey:key))
        let pageKey=String(repeating:"d",count:64)
        var journal=ActivityJournal();journal.pageKeys=[pageKey];try store.commit(journal,key,page:Self.data("page"),pageKey:pageKey);XCTAssertEqual(try store.pages(journal,key).count,1)
        journal.pageKeys=[String(repeating:"e",count:64)];XCTAssertThrowsError(try store.pages(journal,key))
    }
    func testFiveLanguagesDoNotExposeCodesAsPrimaryCopy() {
        for key in ActivityCopy.values.keys {
            for language in ["en","nl","de","fr","es"] { XCTAssertFalse(ActivityCopy.text(key,language).isEmpty) }
        }
        XCTAssertEqual(ActivityCopy.state("FUTURE_STATE","nl"),ActivityCopy.text("stateUnknown","nl"))
        XCTAssertEqual(ActivityCopy.text("nav","unknown"),"Activity")
    }
}

private final class ActivityHTTPProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var handler:((URLRequest)throws->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        do {
            let (code,data)=try Self.handler!(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
extension ActivityTests {
    func testTransportUsesOnlyFiniteGetPathsAndAllAuthorityHeaders() async throws {
        let connection=Self.connection,access=try Self.access(),workset=access.worksets[0].workset_id
        let cap=try Self.data("capability"),page=try Self.data("page"),detail=try Self.data("detail")
        ActivityHTTPProtocol.handler={ request in
            XCTAssertEqual(request.httpMethod,"GET");XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+connection.bearer)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Instance"),connection.workspaceInstanceID)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),connection.draftGrant)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Activity-Grant"),access.token)
            let path=request.url!.path
            return (200,path=="/v1/workset-activity" ? cap:path.contains("/events/") ? detail:page)
        }
        defer { ActivityHTTPProtocol.handler=nil }
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[ActivityHTTPProtocol.self]
        let transport=ActivityTransport(configuration:configuration)
        let probed=try await transport.probe(connection,token:access.token);XCTAssertEqual(probed,access)
        let received=try await transport.page(connection,access:access,workset:workset,cursor:"opaque.original")
        XCTAssertEqual(received.events.count,11)
        let event=try await transport.detail(connection,access:access,workset:workset,id:received.events[0].id)
        XCTAssertEqual(event.id,received.events[0].id)
        for (status,code) in [(401,"DENIED"),(403,"DENIED"),(409,"ACTIVITY_RESYNC_REQUIRED"),(409,"WRONG_INSTANCE"),(404,"ACTIVITY_UNSUPPORTED"),(404,"ACTIVITY_EVENT_UNAVAILABLE"),(503,"UNAVAILABLE"),(400,"INVALID") ] {
            ActivityHTTPProtocol.handler={ _ in (status,try JSONSerialization.data(withJSONObject:["error":code])) }
            do { _=try await transport.probe(connection,token:access.token);XCTFail("Accepted failing status \(status)") } catch { }
        }
        do { _=try await transport.probe(connection,token:"bad");XCTFail("Accepted malformed local token") } catch { }
        do { _=try await transport.page(connection,access:access,workset:"foreign",cursor:nil);XCTFail("Accepted foreign workset") } catch { }
        do { _=try await transport.page(connection,access:access,workset:workset,cursor:"../bad");XCTFail("Accepted foreign cursor path") } catch { }
        do { _=try await transport.detail(connection,access:access,workset:workset,id:"bad");XCTFail("Accepted malformed event path") } catch { }
        ActivityHTTPProtocol.handler={_ in (200,Data(repeating:32,count:32769))}
        do { _=try await transport.probe(connection,token:access.token);XCTFail("Accepted oversized response") } catch { }
    }
    @MainActor func testPartialPagingUsesOriginalCursorAndChangedWatermarkCannotMixSnapshots() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let transport=try ActivityScriptedServer(),access=try Self.access(),credentials=ActivityMemoryCredentials(access),store=ActivityLocalStore(root:root)
        var initial=try Self.raw("page");let all=initial["events"] as! [[String:Any]]
        initial["events"]=Array(all.prefix(5));initial["has_more"]=true;initial["cursor"]="originalFirstPage.signed"
        await transport.setPage(try JSONSerialization.data(withJSONObject:initial))
        let state=ActivityState(transport:transport,credentials:credentials,store:store)
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id)
        XCTAssertFalse(state.complete);XCTAssertEqual(state.events.count,5)
        await state.rememberDisplayed(visible:true);XCTAssertFalse(state.journal.comparisonKnown)
        state.invalidate()
        var next=try Self.raw("page");next["events"]=Array(all.dropFirst(5));next["cursor"]="originalSecondPage.signed"
        await transport.setPage(try JSONSerialization.data(withJSONObject:next))
        let restarted=ActivityState(transport:transport,credentials:credentials,store:store)
        await restarted.connect(Self.connection);await restarted.choose(access.worksets[0].workset_id)
        let cursor=await transport.cursors.last!;XCTAssertEqual(cursor,"originalFirstPage.signed")
        XCTAssertTrue(restarted.complete);XCTAssertEqual(restarted.events.count,11)
        await restarted.rememberDisplayed(visible:true)
        await transport.setPage(try JSONSerialization.data(withJSONObject:initial));await restarted.fetch(restart:true)
        next["source_watermark"]=String(repeating:"f",count:64)
        await transport.setPage(try JSONSerialization.data(withJSONObject:next));await restarted.fetch()
        XCTAssertEqual(restarted.status,"resync");XCTAssertEqual(restarted.events.count,5)
        XCTAssertTrue(restarted.historical);XCTAssertFalse(restarted.complete);XCTAssertFalse(restarted.journal.comparisonKnown)
        restarted.invalidate()
    }
}

private struct ActivityEmptyDraft:DraftGrantStore {
    func load() throws -> DraftAccess? { nil }
    func save(_ access:DraftAccess) throws {}
    func forget() throws {}
}
extension ActivityTests {
    @MainActor func testFiniteSourcePresentationHasTranslatedCurrentAndHistoryWithoutPhaseClaims() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let server=try ActivityScriptedServer(),access=try Self.access(),state=ActivityState(transport:server,credentials:ActivityMemoryCredentials(access),store:ActivityLocalStore(root:root))
        let client=ClientState(keychain:ActivityEmptyServer())
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id)
        for language in ["en","nl","de","fr","es"] {
            for width in [340.0,560.0,760.0,1180.0] {
                let host=NSHostingView(rootView:WorksetActivityView(state:state,client:client,grants:ActivityEmptyDraft()).environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:width,height:780);host.layoutSubtreeIfNeeded()
                XCTAssertEqual(host.frame.width,width)

            }
        }
        await server.setMode("lost");await state.fetch(restart:true)
        let historical=NSHostingView(rootView:WorksetActivityView(state:state,client:client,grants:ActivityEmptyDraft()))
        historical.frame=NSRect(x:0,y:0,width:560,height:780);historical.layoutSubtreeIfNeeded()
        state.invalidate()
        let denied=NSHostingView(rootView:WorksetActivityView(state:state,client:client,grants:ActivityEmptyDraft()))
        denied.frame=NSRect(x:0,y:0,width:560,height:780);denied.layoutSubtreeIfNeeded()
        XCTAssertFalse(ActivityWire.matches("a\n","^a$"));XCTAssertFalse(ActivityWire.identifier("scope\n"))
    }
}

private struct ActivityEmptyServer:CredentialStore {
    func binding() throws -> ServerBinding? { nil }
    func token() throws -> String? { nil }
    func save(binding:ServerBinding,token:String) throws {}
    func forget() throws {}
}

private final class ActivityKeychainBackend:@unchecked Sendable {
    let lock=NSLock()
    var stored:Data?
    var failure:OSStatus?
    var services:[String]=[]
    var operations:DraftKeychainOperations {
        .init(copy:{ q in self.lock.withLock {
            self.services.append((q as! [CFString:Any])[kSecAttrService] as! String)
            if let failure=self.failure { return (failure,nil) };return self.stored.map {(errSecSuccess,$0)} ?? (errSecItemNotFound,nil)
        }},update:{ _,attributes in self.lock.withLock {
            if let failure=self.failure { return failure };guard self.stored != nil else { return errSecItemNotFound }
            self.stored=(attributes as! [CFString:Any])[kSecValueData] as? Data;return errSecSuccess
        }},add:{ q in self.lock.withLock {
            if let failure=self.failure { return failure };self.stored=(q as! [CFString:Any])[kSecValueData] as? Data;return errSecSuccess
        }},delete:{ _ in self.lock.withLock {
            if let failure=self.failure { return failure };self.stored=nil;return errSecSuccess
        }})
    }
}
extension ActivityTests {
    func testPrivateKeychainNamespaceRoundTripAndLockedFailure() throws {
        let backend=ActivityKeychainBackend(),keychain=ActivityKeychain(operations:backend.operations),access=try Self.access()
        XCTAssertNil(try keychain.load());try keychain.save(access);XCTAssertEqual(try keychain.load(),access)
        try keychain.save(access);XCTAssertEqual(try keychain.load(),access)
        XCTAssertEqual(Set(backend.services),["com.pcvantol.workspace.native-client.workset-activity.v1"])
        backend.failure=errSecInteractionNotAllowed
        XCTAssertThrowsError(try keychain.load());XCTAssertThrowsError(try keychain.save(access));XCTAssertThrowsError(try keychain.forget())
        backend.failure=nil;backend.stored=Data("bad private record".utf8);XCTAssertThrowsError(try keychain.load())
        try keychain.forget();XCTAssertNil(try keychain.load());try keychain.forget()
        var raw=try JSONSerialization.jsonObject(with:JSONEncoder().encode(access)) as! [String:Any];raw["token"]="bad"
        let invalid=try JSONDecoder().decode(ActivityAccess.self,from:JSONSerialization.data(withJSONObject:raw))
        XCTAssertThrowsError(try keychain.save(invalid))
    }
    func testScopedCachePrunesOrphansAndKeepsHistoricalPagesAndBothOriginalCursors() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let store=ActivityLocalStore(root:root),key=String(repeating:"a",count:64),pageKey=String(repeating:"b",count:64)
        var journal=ActivityJournal();journal.cursor="original.signed";journal.previousCursor="originalPrevious.signed";journal.pageKeys=[pageKey]
        try store.commit(journal,key,page:Self.data("page"),pageKey:pageKey)
        let scoped=PrivateLocalRecordStore(root:root.appendingPathComponent(key),namespace:"workset-activity")
        let orphan=String(repeating:"c",count:64);try scoped.save(Data("own orphan".utf8),key:orphan)
        let unrelated=scoped.root.appendingPathComponent("keep-user-note.txt");try Data("preserved".utf8).write(to:unrelated)
        journal.historicalKeys=[pageKey];journal.pageKeys=[];journal.cursor=nil
        try store.save(journal,key)
        XCTAssertNil(try scoped.load(orphan));XCTAssertEqual(try Data(contentsOf:unrelated),Data("preserved".utf8))
        let loaded=try store.load(key);XCTAssertEqual(loaded.historicalKeys,[pageKey]);XCTAssertEqual(loaded.previousCursor,"originalPrevious.signed")
        var history=loaded;history.pageKeys=history.historicalKeys;XCTAssertEqual(try store.pages(history,key).count,1)
        let bad=String(repeating:"d",count:64),link=scoped.root.appendingPathComponent("workset-activity-"+bad+".json")
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:unrelated)
        XCTAssertThrowsError(try store.save(loaded,key));XCTAssertTrue(FileManager.default.fileExists(atPath:unrelated.path))
    }
    @MainActor func testExpiryClearsWithoutVisiblePaneAndReauthorizationRetainsSelection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let transport=try ActivityScriptedServer(),base=try Self.access()
        let state=ActivityState(transport:transport,credentials:ActivityMemoryCredentials(base),store:ActivityLocalStore(root:root))
        await state.connect(Self.connection);await state.choose(base.worksets[0].workset_id)
        let selected=state.selected;await state.reauthorize(Self.connection);XCTAssertEqual(state.selected,selected);XCTAssertEqual(state.events.count,11)
        state.invalidate()
        let expiry=ISO8601DateFormatter().string(from:Date().addingTimeInterval(1.5))
        let access=ActivityAccess(endpoint:base.endpoint,workspaceInstanceID:base.workspaceInstanceID,actorID:base.actorID,workspaceProjectID:base.workspaceProjectID,token:base.token,binding_id:base.binding_id,scope:base.scope,installation_id:base.installation_id,worksets:base.worksets,expires_at:expiry)
        await transport.setAccess(access)
        let expiring=ActivityState(transport:transport,credentials:ActivityMemoryCredentials(access),store:ActivityLocalStore(root:root))
        await expiring.connect(Self.connection);await expiring.choose(selected)
        XCTAssertFalse(expiring.events.isEmpty)
        try await Task.sleep(for:.seconds(2))
        XCTAssertNil(expiring.access);XCTAssertTrue(expiring.events.isEmpty);XCTAssertEqual(expiring.status,"denied")
        expiring.invalidate()
    }
}

extension ActivityTests {
    @MainActor func testInvalidOriginalFullCheckpointCannotBecomeHealthyUnchangedByStartingAtFirstPage() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let transport=try ActivityScriptedServer(),access=try Self.access(),state=ActivityState(transport:transport,credentials:ActivityMemoryCredentials(access),store:ActivityLocalStore(root:root))
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id);await state.rememberDisplayed(visible:true)
        XCTAssertTrue(state.journal.comparisonKnown);let original=state.journal.previousCursor
        await transport.setMode("invalid-checkpoint");await state.fetch(restart:true)
        XCTAssertEqual(state.status,"resync");XCTAssertFalse(state.journal.comparisonKnown);XCTAssertTrue(state.historical)
        XCTAssertEqual(state.events.count,11);XCTAssertEqual(state.journal.previousCursor,original);XCTAssertFalse(state.complete)
        let forwarded=await transport.cursors.last!;XCTAssertEqual(forwarded,original)
        state.invalidate()
    }
}

// Controlled suspended answers test the publication fence, rather than merely a canceled task.
private actor ActivityDelayedServer:ActivityServing {
    let base:ActivityScriptedServer
    var held=false
    var waiting:CheckedContinuation<Void,Never>?
    init() throws { base=try ActivityScriptedServer() }
    func hold() { held=true }
    func pending() -> Bool { waiting != nil }
    func release() { held=false;waiting?.resume();waiting=nil }
    func probe(_ connection:AdvisoryConnection,token:String) async throws -> ActivityAccess { try await base.probe(connection,token:token) }
    func page(_ connection:AdvisoryConnection,access:ActivityAccess,workset:String,cursor:String?) async throws -> ActivityPage {
        if held { await withCheckedContinuation { waiting=$0 };throw AdvisoryError.state("RESYNC_REQUIRED") }
        return try await base.page(connection,access:access,workset:workset,cursor:cursor)
    }
    func detail(_ connection:AdvisoryConnection,access:ActivityAccess,workset:String,id:String) async throws -> ActivityEvent {
        if held { await withCheckedContinuation { waiting=$0 } }
        return try await base.detail(connection,access:access,workset:workset,id:id)
    }
}
extension ActivityTests {
    @MainActor func testLateDetailAndResyncAfterAuthorityChangeCannotPublishOrRewriteCheckpoint() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let transport=try ActivityDelayedServer(),access=try Self.access(),store=ActivityLocalStore(root:root)
        let state=ActivityState(transport:transport,credentials:ActivityMemoryCredentials(access),store:store)
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id);await state.rememberDisplayed(visible:true)
        let id=state.events[0].id,key=access.key(state.selected,draft:Self.connection.draftGrant),old=try store.load(key)
        await transport.hold()
        let detail=Task { await state.open(id) }
        while !(await transport.pending()) { await Task.yield() }
        state.invalidate();await transport.release();await detail.value
        XCTAssertNil(state.detail);XCTAssertTrue(state.events.isEmpty);XCTAssertNil(state.access)
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id)
        await transport.hold()
        let paging=Task { await state.fetch(restart:true) }
        while !(await transport.pending()) { await Task.yield() }
        state.invalidate();await transport.release();await paging.value
        let retained=try store.load(key)
        XCTAssertEqual(retained.pageKeys,old.pageKeys);XCTAssertEqual(retained.previousCursor,old.previousCursor)
        XCTAssertEqual(retained.comparisonKnown,old.comparisonKnown);XCTAssertEqual(retained.lastViewedIDs,old.lastViewedIDs)
        XCTAssertNil(state.access);XCTAssertEqual(state.status,"denied")
    }
}

private final class ActivityExpiryDelay:@unchecked Sendable {
    private let lock=NSLock()
    private var enabled=false
    private let fails:Bool
    init(fails:Bool=false) { self.fails=fails }
    func enable() { lock.withLock { enabled=true } }
    func synchronize(_ descriptor:Int32) -> Int32 {
        let delay=lock.withLock { let value=enabled;enabled=false;return value }
        if delay { Thread.sleep(forTimeInterval:1.5);if fails { return -1 } }
        return Darwin.fsync(descriptor)
    }
}
extension ActivityTests {
    @MainActor func testCacheReadCrossingExpiryCannotBrieflyPublishProtectedHistory() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let server=try ActivityScriptedServer(),base=try Self.access(),initial=ActivityState(transport:server,credentials:ActivityMemoryCredentials(base),store:ActivityLocalStore(root:root))
        await initial.connect(Self.connection);await initial.choose(base.worksets[0].workset_id);await initial.rememberDisplayed(visible:true);initial.invalidate()
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let finite=ActivityAccess(endpoint:base.endpoint,workspaceInstanceID:base.workspaceInstanceID,actorID:base.actorID,workspaceProjectID:base.workspaceProjectID,token:base.token,binding_id:base.binding_id,scope:base.scope,installation_id:base.installation_id,worksets:base.worksets,expires_at:formatter.string(from:Date().addingTimeInterval(1)))
        await server.setAccess(finite)
        let delay=ActivityExpiryDelay(),privateRecords=PrivateLocalRecordStore(root:root,namespace:"workset-activity",synchronizeDirectory:{ delay.synchronize($0) })
        let state=ActivityState(transport:server,credentials:ActivityMemoryCredentials(finite),store:ActivityLocalStore(records:privateRecords))
        var expiredPublication=false
        let observation=state.$pages.sink { values in
            if !values.isEmpty,WorksetReleaseWire.date(finite.expires_at)!<=Date() { expiredPublication=true }
        }
        defer { observation.cancel() }
        await state.connect(Self.connection);delay.enable();await state.choose(base.worksets[0].workset_id)
        // No yield here: MainActor expiry monitor cannot conceal an unsafe transient cache publication.
        XCTAssertFalse(expiredPublication)
        XCTAssertNil(state.access);XCTAssertTrue(state.pages.isEmpty);XCTAssertTrue(state.events.isEmpty);XCTAssertEqual(state.status,"denied")
        state.invalidate()
    }
    func testForeignCurrentProjectWithValidSnapshotDigestStillRejectsPinnedNullScope() throws {
        let access=try Self.access();var raw=try Self.raw("page"),current=raw["current"] as! [String:Any],scope=current["scope"] as! [String:Any]
        scope["project_id"]="foreign-project";current["scope"]=scope
        var signed=current;for key in ["snapshot_revision","observed_at","freshness","read_only"] { signed.removeValue(forKey:key) }
        current["snapshot_revision"]="sha256:"+ActivityWire.hash(try CanonicalJSON.data(signed,ascii:false));raw["current"]=current
        XCTAssertThrowsError(try ActivityWire.page(JSONSerialization.data(withJSONObject:raw),access:access,workset:access.worksets[0].workset_id))
        for language in ["en","nl","de","fr","es"] {
            XCTAssertEqual(ActivityCopy.limitation("FUTURE_LIMIT",language),ActivityCopy.text("limitationUnknown",language))
            XCTAssertEqual(ActivityCopy.limitation("NO_BACKFILL_OF_MUTABLE_SNAPSHOTS",language),ActivityCopy.text("NO_BACKFILL_OF_MUTABLE_SNAPSHOTS",language))
        }
    }
}

extension ActivityTests {
    @MainActor func testResyncSaveCrossingExpiryCannotPublishProtectedCheckpointOrRetainView() async throws {
        for failedWrite in [false,true] {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let server=try ActivityScriptedServer(),base=try Self.access()
        let delay=ActivityExpiryDelay(fails:failedWrite),records=PrivateLocalRecordStore(root:root,namespace:"workset-activity",synchronizeDirectory:{ delay.synchronize($0) })
        let state=ActivityState(transport:server,credentials:ActivityMemoryCredentials(base),store:ActivityLocalStore(records:records))
        await state.connect(Self.connection);await state.choose(base.worksets[0].workset_id);await state.rememberDisplayed(visible:true)
        state.invalidate()
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let finite=ActivityAccess(endpoint:base.endpoint,workspaceInstanceID:base.workspaceInstanceID,actorID:base.actorID,workspaceProjectID:base.workspaceProjectID,token:base.token,binding_id:base.binding_id,scope:base.scope,installation_id:base.installation_id,worksets:base.worksets,expires_at:formatter.string(from:Date().addingTimeInterval(1)))
        await server.setAccess(finite)
        let resumed=ActivityState(transport:server,credentials:ActivityMemoryCredentials(finite),store:ActivityLocalStore(records:records))
        await resumed.connect(Self.connection);await resumed.choose(base.worksets[0].workset_id)
        XCTAssertTrue(resumed.complete)
        var expiredPublication=false
        let observation=resumed.$journal.sink { value in
            if !value.lastViewedIDs.isEmpty,WorksetReleaseWire.date(finite.expires_at)!<=Date() { expiredPublication=true }
        }
        defer { observation.cancel() }
        await server.setMode("resync");delay.enable();await resumed.fetch(restart:true)
        XCTAssertFalse(expiredPublication);XCTAssertNil(resumed.access);XCTAssertTrue(resumed.pages.isEmpty)
        XCTAssertTrue(resumed.journal.lastViewedIDs.isEmpty);XCTAssertEqual(resumed.status,"denied")
        resumed.invalidate()
        }
    }
}

extension ActivityTests {
    @MainActor func testResyncFreshObservationCannotOverwriteRetainedHistoricalPageBytes() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer { try? FileManager.default.removeItem(at:root) }
        let server=try ActivityScriptedServer(),access=try Self.access(),store=ActivityLocalStore(root:root)
        let state=ActivityState(transport:server,credentials:ActivityMemoryCredentials(access),store:store)
        await state.connect(Self.connection);await state.choose(access.worksets[0].workset_id);await state.rememberDisplayed(visible:true)
        let key=access.key(state.selected,draft:Self.connection.draftGrant),oldJournal=state.journal,oldBytes=try store.pages(oldJournal,key)
        await server.setMode("resync");await state.fetch(restart:true)
        XCTAssertEqual(state.journal.historicalKeys,oldJournal.pageKeys)
        var raw=try Self.raw("page"),current=raw["current"] as! [String:Any]
        current["observed_at"]="2026-10-12T17:00:00Z";raw["current"]=current
        await server.setPage(try JSONSerialization.data(withJSONObject:raw));await server.setMode("normal")
        await state.fetch(restart:true)
        XCTAssertTrue(state.complete);XCTAssertFalse(state.journal.comparisonKnown)
        XCTAssertTrue(Set(state.journal.pageKeys).isDisjoint(with:oldJournal.pageKeys))
        var history=state.journal;history.pageKeys=history.historicalKeys
        XCTAssertEqual(try store.pages(history,key),oldBytes)
        state.invalidate()
    }
}
