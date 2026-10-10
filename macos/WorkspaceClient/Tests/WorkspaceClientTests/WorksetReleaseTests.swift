import Foundation
import Security
import SwiftUI
import AppKit
import XCTest
@testable import WorkspaceClient

final class WorksetReleaseTests: XCTestCase {
    private func prepared() throws -> [String: Any] {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/workset-release-source/prepared.json")
        return try WorksetReleaseWire.object(Data(contentsOf: path))
    }
    private func access(_ packet: [String: Any]) -> WorksetReleaseAccess {
        let scope = packet["scope"] as! [String: String]
        let subjects = packet["subjects"] as! [[String: Any]]
        return .init(endpoint: "http://127.0.0.1:8080/", workspaceInstanceID: String(repeating: "a", count: 32),
                     workspaceProjectID: "ws-project", actorID: String((packet["principal_reference"] as! String).split(separator: ":").last!),
                     forgeInstanceID: scope["instance_id"]!, forgeProjectID: scope["project_id"]!, repositoryID: scope["repository_id"]!,
                     subjects: subjects.map { .init(candidate_id: $0["candidate_id"] as! String, subject_revision: $0["subject_revision"] as! String) },
                     token: String(repeating: "b", count: 43))
    }
    func testActualProductPreparedPacketAndCorruptMemberOrSemanticKeyReject() throws {
        let raw = try prepared(), packet = raw["package"] as! [String: Any], access = access(packet)
        let selection = try AdvisoryWire.decode(packet["selection"]!, as: WorksetReleaseSelection.self)
        let valid = try WorksetReleaseWire.prepared(JSONSerialization.data(withJSONObject: raw), access: access, selection: selection)
        XCTAssertEqual(valid.members.map { $0.definition.title }, ["Assessment A", "Assessment B"])
        XCTAssertEqual(valid.members[1].dependencies, [valid.members[0].id]); XCTAssertTrue(valid.supported)
        var changed = packet; changed["release_key"] = "sha256:"+String(repeating: "0", count: 64)
        XCTAssertThrowsError(try WorksetReleaseWire.package(changed, access: access))
        changed = packet; var definition = changed["definition"] as! [String: Any]
        var members = definition["members"] as! [[String: Any]]; members[1]["dependencies"] = []
        definition["members"] = members; changed["definition"] = definition
        XCTAssertThrowsError(try WorksetReleaseWire.package(changed, access: access))
    }
    func testReleaseCommandRetainsExplicitNullRevisionAndPrivateJournalSurvivesRestart() throws {
        let raw = try prepared(), packet = raw["package"] as! [String: Any], access = access(packet)
        let selection = try AdvisoryWire.decode(packet["selection"]!, as: WorksetReleaseSelection.self)
        let command = WorksetReleaseCommand(contract_version: WorksetReleaseWire.contract, operation_id: "original-intent", intent: "release", selection: selection,
            package_digest: raw["package_digest"] as! String, confirm: true, expected_revision: nil)
        let body = try WorksetReleaseWire.object(command.data()); XCTAssertTrue(body["expected_revision"] is NSNull)
        let temporary = ProcessInfo.processInfo.environment["WORKSPACE_NATIVE_TEST_TEMP_ROOT"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let root = temporary.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let intent = WorksetReleaseIntent(accessFingerprint: access.fingerprint, scopeKey: access.scopeKey, command: command)
        let journal = WorksetReleaseJournal(pending: intent)
        try PrivateWorksetReleaseStore(root: root).save(journal, key: access.scopeKey)
        let recovered = try PrivateWorksetReleaseStore(root: root).load(access.scopeKey)
        XCTAssertEqual(recovered.pending?.command.operation_id, "original-intent"); XCTAssertTrue(recovered.pending!.matches(access))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("workset-release-"+access.scopeKey+".json").path)
        XCTAssertEqual((attributes[.posixPermissions] as! Int) & 0o077, 0)
    }
    func testFiveLanguageReleaseCopyAndPhysicalBoundaryAreComplete() {
        for values in WorksetReleaseCopy.entries.values {
            XCTAssertEqual(values.count, 5); XCTAssertTrue(values.allSatisfy { !$0.isEmpty })
        }
        for language in WorksetReleaseCopy.languages {
            XCTAssertFalse(WorksetReleaseCopy.text("resources", language: language).isEmpty)
            XCTAssertFalse(WorksetReleaseCopy.text("boundary", language: language).isEmpty)
        }
        XCTAssertEqual(WorksetReleaseCopy.text("release", language: "unknown"), "Release for execution")
    }
}

private struct ReleaseTestCredentials: WorksetReleaseCredentials {
    let access: WorksetReleaseAccess
    func load() throws -> WorksetReleaseAccess? { access }
    func save(_ access: WorksetReleaseAccess) throws {}
    func forget() throws {}
}
private final class ReleaseTestStore: WorksetReleaseIntentStorage, @unchecked Sendable {
    var journal = WorksetReleaseJournal()
    func load(_ key: String) throws -> WorksetReleaseJournal { journal }
    func save(_ journal: WorksetReleaseJournal, key: String) throws { self.journal = journal }
}

extension WorksetReleaseTests {
    @MainActor func testSelectionSurvivesSameScopeRefreshAndPreviewUsesOnlyReadPreparation() async throws {
        let raw = try prepared(), packet = raw["package"] as! [String: Any], access = access(packet)
        let selected = try AdvisoryWire.decode(packet["selection"]!, as: WorksetReleaseSelection.self)
        let connection = AdvisoryConnection(endpoint: access.endpoint, workspaceInstanceID: access.workspaceInstanceID,
            actorID: access.actorID, workspaceProjectID: access.workspaceProjectID, conversationID: "a",
            bearer: "read-only", draftGrant: String(repeating: "c", count: 43))
        let cap: [String: Any] = ["contract_version": WorksetReleaseWire.contract, "scope": packet["scope"]!,
            "principal_id": access.actorID, "permissions": ["READ", "RELEASE", "DISARM"],
            "subjects": (packet["selection"] as! [String: Any])["subjects"]!, "limits": ["maximum_releases": 1, "maximum_activations": 2],
            "expires_at": selected.expires_at, "release_supported": true, "disarm_supported": true, "read_only": true, "additional_model_calls": 0]
        var posts: [String] = []
        WorklistStubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Workspace-Workset-Release-Grant"), access.token)
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Workspace-Advisory-Grant"))
            if request.httpMethod == "POST" { posts.append(request.url!.path) }
            let value = request.url!.path.hasSuffix("capability") ? cap : raw
            return (200, try JSONSerialization.data(withJSONObject: value), "application/json")
        }
        defer { WorklistStubProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [WorklistStubProtocol.self]
        let state = WorksetReleaseState(credentials: ReleaseTestCredentials(access: access), store: ReleaseTestStore(),
            transport: WorksetReleaseTransport(configuration: config, clock: { WorksetReleaseWire.date(selected.expires_at)!.addingTimeInterval(-60) }))
        await state.refresh(connection)
        XCTAssertEqual(state.phase, "current")
        access.subjects.forEach { state.toggle($0) }
        await state.refresh(connection)
        XCTAssertEqual(state.selected, access.subjects)
        await state.prepare()
        XCTAssertEqual(state.phase, "preview"); XCTAssertNotNil(state.preview)
        XCTAssertEqual(posts, ["/v1/workset-releases/prepare"])
        state.invalidate(); XCTAssertNil(state.preview); XCTAssertTrue(state.selected.isEmpty)
    }
}

extension WorksetReleaseTests {
    func testActualNativeReleaseDisarmAndOriginalReceiptWithIndependentCurrent() throws {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/workset-release-source")
        for file in ["operation-released.json","operation-disarmed.json","operation-original-withdrawn.json"] {
            let data=try Data(contentsOf:directory.appendingPathComponent(file)), raw=try WorksetReleaseWire.object(data)
            let access=access(raw["frozen_package"] as! [String:Any])
            let command=try AdvisoryWire.decode(raw["original_request"]!,as:WorksetReleaseCommand.self)
            let observation=try WorksetReleaseWire.operation(data,access:access,expected:command)
            XCTAssertEqual(observation.state,"COMPLETE");XCTAssertEqual(observation.snapshot?.items.count,2)
            XCTAssertNotNil(observation.originalReceiptData)
            if file != "operation-released.json" { XCTAssertTrue(observation.snapshot!.items.allSatisfy { $0.facts.released == .no }) }
            var changed=raw;changed["operation_id"]="foreign-operation"
            XCTAssertThrowsError(try WorksetReleaseWire.operation(JSONSerialization.data(withJSONObject:changed),access:access,expected:command))
        }
    }
}

private actor ReleaseReplayPeer: WorksetReleaseServing {
    let released: Data
    let disarmed: Data
    var replies: [String: WorksetReleaseCommand] = [:]
    var sends: [WorksetReleaseCommand] = []
    var reads = 0
    var lostAfterApply = false
    var lostBeforeApply = false
    var deny = false
    init(released: Data, disarmed: Data) { self.released=released;self.disarmed=disarmed }
    func configure(after: Bool = false, before: Bool = false, denied: Bool = false) {
        lostAfterApply=after;lostBeforeApply=before;deny=denied
    }
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> WorksetReleaseAccess { throw AdvisoryError.denied }
    func capability(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection) async throws -> WorksetReleaseCapability {
        if deny { throw AdvisoryError.denied }
        let raw=try WorksetReleaseWire.object(released), packet=raw["frozen_package"] as! [String:Any]
        let selection=try AdvisoryWire.decode(packet["selection"]!,as:WorksetReleaseSelection.self)
        return .init(contract_version:WorksetReleaseWire.contract,scope:try AdvisoryWire.decode(packet["scope"]!,as:AdvisoryScope.self),
            principal_id:access.actorID,permissions:["READ","RELEASE","DISARM"],subjects:access.subjects,
            limits:.init(maximum_releases:1,maximum_activations:2),expires_at:selection.expires_at,
            release_supported:true,disarm_supported:true,read_only:true,additional_model_calls:0)
    }
    func prepare(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, selection: WorksetReleaseSelection) async throws -> WorksetReleasePreview {
        if deny { throw AdvisoryError.denied }
        let raw=try WorksetReleaseWire.object(released)
        let packet=try WorksetReleaseWire.package(raw["frozen_package"] as! [String:Any],access:access)
        guard packet.selection==selection else { throw AdvisoryError.invalid };return packet
    }
    func submit(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, command: WorksetReleaseCommand) async throws -> WorksetReleaseObservation {
        if deny { throw AdvisoryError.denied }
        sends.append(command)
        if lostBeforeApply { lostBeforeApply=false;throw AdvisoryError.unavailable }
        replies[command.operation_id]=command
        if lostAfterApply { lostAfterApply=false;throw AdvisoryError.unavailable }
        return try response(command,access:access)
    }
    func operation(_ access: WorksetReleaseAccess, _ connection: AdvisoryConnection, intent: WorksetReleaseIntent) async throws -> WorksetReleaseObservation {
        reads+=1
        if deny { throw AdvisoryError.denied }
        guard let command=replies[intent.command.operation_id] else { throw AdvisoryError.missing }
        return try response(command,access:access)
    }
    private func response(_ command: WorksetReleaseCommand, access: WorksetReleaseAccess) throws -> WorksetReleaseObservation {
        // Declared unit HTTP alias response over genuinely captured canonical records; never installed acceptance.
        var raw=try WorksetReleaseWire.object(command.intent=="release" ? released:disarmed)
        raw["operation_id"]=command.operation_id
        raw["original_request"]=try WorksetReleaseWire.object(command.data())
        return try WorksetReleaseWire.operation(JSONSerialization.data(withJSONObject:raw),access:access,expected:command)
    }
}
private final class ReleaseMutableCredentials: WorksetReleaseCredentials, @unchecked Sendable {
    var access: WorksetReleaseAccess?
    var failure=false
    init(_ access: WorksetReleaseAccess?) { self.access=access }
    func load() throws -> WorksetReleaseAccess? { if failure { throw AdvisoryError.unavailable };return access }
    func save(_ value: WorksetReleaseAccess) throws { if failure { throw AdvisoryError.unavailable };access=value }
    func forget() throws { if failure { throw AdvisoryError.unavailable };access=nil }
}
private final class ReleaseFailingStore: WorksetReleaseIntentStorage, @unchecked Sendable {
    var journal=WorksetReleaseJournal()
    var failure=false
    func load(_ key: String) throws -> WorksetReleaseJournal { journal }
    func save(_ value: WorksetReleaseJournal, key: String) throws { if failure { throw AdvisoryError.unavailable };journal=value }
}

extension WorksetReleaseTests {
    private func replayFixture() throws -> (WorksetReleaseAccess,AdvisoryConnection,ReleaseReplayPeer) {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/workset-release-source")
        let released=try Data(contentsOf:directory.appendingPathComponent("operation-released.json"))
        let disarmed=try Data(contentsOf:directory.appendingPathComponent("operation-disarmed.json"))
        let raw=try WorksetReleaseWire.object(released), access=access(raw["frozen_package"] as! [String:Any])
        let connection=AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,
            actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,conversationID:"a",bearer:"reader",draftGrant:String(repeating:"c",count:43))
        return (access,connection,ReleaseReplayPeer(released:released,disarmed:disarmed))
    }
    @MainActor func testOriginalIntentBeforeSendLostReplyRestartAndFutureDisarm() async throws {
        let (access,connection,peer)=try replayFixture(), credentials=ReleaseMutableCredentials(access),store=ReleaseFailingStore()
        let state=WorksetReleaseState(credentials:credentials,store:store,transport:peer)
        await state.refresh(connection);XCTAssertTrue(state.hasAttempted(connection))
        access.subjects.forEach { state.toggle($0) }
        state.move(access.subjects[1],offset:-1);XCTAssertEqual(state.selected.first,access.subjects[1])
        state.move(access.subjects[1],offset:1);await state.prepare()
        await peer.configure(after:true)
        await state.confirmRelease()
        let original=try XCTUnwrap(store.journal.pending)
        let captured1 = await peer.sends.count; XCTAssertEqual(captured1,1);XCTAssertNil(state.observation)
        await state.confirmRelease();let captured2 = await peer.sends.count; XCTAssertEqual(captured2,1)
        let restarted=WorksetReleaseState(credentials:credentials,store:store,transport:peer)
        await restarted.refresh(connection)
        XCTAssertNil(restarted.pending);XCTAssertEqual(restarted.history.first?.command.operation_id,original.command.operation_id)
        XCTAssertEqual(restarted.phase,"released");let captured3 = await peer.sends.count; XCTAssertEqual(captured3,1)
        await restarted.disarm();XCTAssertEqual(restarted.phase,"withdrawn");XCTAssertEqual(store.journal.history.count,2)
        let captured4 = await peer.sends.last?.intent; XCTAssertEqual(captured4,"disarm")
        await restarted.observe(restarted.history[0]);let captured5 = await peer.sends.count; XCTAssertEqual(captured5,2)
        await peer.configure(denied:true);await restarted.refresh(connection)
        XCTAssertEqual(restarted.phase,"denied");XCTAssertNil(restarted.observation);XCTAssertTrue(restarted.history.isEmpty)
        XCTAssertEqual(store.journal.history.count,2)
    }
    @MainActor func testBeforeApplyFailureOnlyExplicitRecoveryReusesOriginalIDAndSaveFailureNeverPosts() async throws {
        let (access,connection,peer)=try replayFixture(), credentials=ReleaseMutableCredentials(access),store=ReleaseFailingStore()
        let state=WorksetReleaseState(credentials:credentials,store:store,transport:peer)
        await state.refresh(connection);access.subjects.forEach { state.toggle($0) };await state.prepare()
        await peer.configure(before:true);await state.confirmRelease()
        let original=try XCTUnwrap(store.journal.pending)
        await state.refresh(connection)
        XCTAssertEqual(state.phase,"pending");XCTAssertNotNil(state.preview);let captured6 = await peer.sends.count; XCTAssertEqual(captured6,1)
        await state.resume();XCTAssertEqual(state.phase,"released")
        let sends=await peer.sends;XCTAssertEqual(sends.map(\.operation_id),[original.command.operation_id,original.command.operation_id])
        let unsavedStore=ReleaseFailingStore();unsavedStore.failure=true
        let unsaved=WorksetReleaseState(credentials:credentials,store:unsavedStore,transport:peer)
        await unsaved.refresh(connection);access.subjects.forEach { unsaved.toggle($0) };await unsaved.prepare();await unsaved.confirmRelease()
        let captured7 = await peer.sends.count; XCTAssertEqual(captured7,2);XCTAssertEqual(unsaved.phase,"unavailable");XCTAssertNil(unsaved.pending)
        credentials.failure=true;unsaved.forgetGrant();XCTAssertEqual(unsaved.phase,"unavailable")
        credentials.failure=false;unsaved.forgetGrant();XCTAssertNil(credentials.access)
        await unsaved.refresh(connection);XCTAssertEqual(unsaved.phase,"denied")
        await unsaved.refresh(nil);XCTAssertEqual(unsaved.phase,"unconfigured")
    }
}

private final class ReleaseKeychainBackend: @unchecked Sendable {
    let lock=NSLock()
    var stored:Data?
    var failure:OSStatus?
    var queries:[[CFString:Any]]=[]
    var operations:DraftKeychainOperations {
        .init(copy:{ query in self.lock.withLock {
            self.queries.append(query as! [CFString:Any])
            if let failure=self.failure { return (failure,nil) }
            return self.stored.map { (errSecSuccess,$0) } ?? (errSecItemNotFound,nil)
        }},update:{ query,attributes in self.lock.withLock {
            self.queries.append(query as! [CFString:Any])
            if let failure=self.failure { return failure }
            guard self.stored != nil else { return errSecItemNotFound }
            self.stored=(attributes as! [CFString:Any])[kSecValueData] as? Data;return errSecSuccess
        }},add:{ query in self.lock.withLock {
            let q=query as! [CFString:Any];self.queries.append(q)
            if let failure=self.failure { return failure }
            self.stored=q[kSecValueData] as? Data;return errSecSuccess
        }},delete:{ query in self.lock.withLock {
            self.queries.append(query as! [CFString:Any])
            if let failure=self.failure { return failure }
            self.stored=nil;return errSecSuccess
        }})
    }
}
extension WorksetReleaseTests {
    func testDedicatedKeychainNamespaceBoundsFailuresAndOriginalIntentValidation() throws {
        let raw=try prepared(), access=access(raw["package"] as! [String:Any])
        let backend=ReleaseKeychainBackend(),store=WorksetReleaseKeychain(operations:backend.operations)
        XCTAssertNil(try store.load());try store.save(access);XCTAssertEqual(try store.load(),access)
        try store.save(access);try store.forget();XCTAssertNil(try store.load())
        XCTAssertTrue(backend.queries.allSatisfy { $0[kSecAttrService] as? String == "com.pcvantol.workspace.native-client.workset-release.v1" })
        XCTAssertTrue(backend.queries.contains { $0[kSecAttrAccessible] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String })
        backend.failure=errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.load());XCTAssertThrowsError(try store.save(access));XCTAssertThrowsError(try store.forget())
        backend.failure=nil;backend.stored=Data("{}".utf8);XCTAssertThrowsError(try store.load())
        let selection=try AdvisoryWire.decode((raw["package"] as! [String:Any])["selection"]!,as:WorksetReleaseSelection.self)
        let body=WorksetReleaseCommand(contract_version:WorksetReleaseWire.contract,operation_id:"one",intent:"release",selection:selection,
            package_digest:raw["package_digest"] as! String,confirm:true,expected_revision:1)
        XCTAssertThrowsError(try body.data())
        let invalid=WorksetReleaseJournal(history:[.init(accessFingerprint:"bad",scopeKey:access.scopeKey,command:body)])
        XCTAssertThrowsError(try invalid.validate(key:access.scopeKey));XCTAssertThrowsError(try invalid.validate(key:"foreign"))
    }
    @MainActor func testHumanPreviewAndCurrentViewsInFiveLanguagesThemesAndWidthsNeverExecuteOnRender() async throws {
        let (access,connection,peer)=try replayFixture(),credentials=ReleaseMutableCredentials(access),store=ReleaseFailingStore()
        let state=WorksetReleaseState(credentials:credentials,store:store,transport:peer)
        func render() {
            for language in WorksetReleaseCopy.languages {
                for width in [640.0,1280.0] {
                    for scheme in [ColorScheme.light,.dark] {
                        let view=WorksetReleaseView(state:state,items:[],onRefresh:{})
                        let host=NSHostingView(rootView:view.environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme))
                        host.frame=NSRect(x:0,y:0,width:width,height:720);host.layoutSubtreeIfNeeded()
                        XCTAssertGreaterThan(host.fittingSize.height,0)
                    }
                }
            }
        }
        render();await state.refresh(connection);access.subjects.forEach { state.toggle($0) };await state.prepare();render()
        let before=await peer.sends.count;XCTAssertEqual(before,0)
        await state.confirmRelease();render();await state.disarm();render()
        let after=await peer.sends.count;XCTAssertEqual(after,2)
        await peer.configure(denied:true);await state.refresh(connection);render()
        XCTAssertNil(state.observation);XCTAssertNil(state.preview);XCTAssertTrue(state.selected.isEmpty)
        let final=await peer.sends.count;XCTAssertEqual(final,2)
    }
}

extension WorksetReleaseTests {
    @MainActor func testClosedNativeTransportProbeCommandsOriginalReadAndErrorBoundaries() async throws {
        let directory=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/workset-release-source")
        let originalData=try Data(contentsOf:directory.appendingPathComponent("operation-released.json"))
        let raw=try WorksetReleaseWire.object(originalData), packet=raw["frozen_package"] as! [String:Any], access=access(packet)
        let command=try AdvisoryWire.decode(raw["original_request"]!,as:WorksetReleaseCommand.self)
        let selection=command.selection
        let connection=AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,
            actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,conversationID:"a",bearer:"reader",draftGrant:String(repeating:"c",count:43))
        let cap:[String:Any]=["contract_version":WorksetReleaseWire.contract,"scope":packet["scope"]!,
            "principal_id":access.actorID,"permissions":["READ","RELEASE","DISARM"],
            "subjects":(packet["selection"] as! [String:Any])["subjects"]!,
            "limits":["maximum_releases":1,"maximum_activations":2],"expires_at":selection.expires_at,
            "release_supported":true,"disarm_supported":true,"read_only":true,"additional_model_calls":0]
        let metadata:[String:Any]=["contract_version":"workspace-workset-release-access/v1","actor_id":access.actorID,
            "workspace_project_id":access.workspaceProjectID,"instance_id":access.forgeInstanceID,
            "project_id":access.forgeProjectID,"repository_id":access.repositoryID,"subjects":cap["subjects"]!]
        var status=200, badMetadata=false, paths:[String]=[]
        WorklistStubProtocol.handler={ request in
            paths.append(request.url!.path)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Workset-Release-Grant"),access.token)
            XCTAssertNil(request.value(forHTTPHeaderField:"X-Workspace-Worklist-Grant"))
            if status != 200 { return (status,Data("{\"error\":\"WORKSET_RELEASE_CONFLICT\"}".utf8),"application/json") }
            let path=request.url!.path
            var result=path.hasSuffix("/access") ? metadata : path.hasSuffix("/capability") ? cap:raw
            if badMetadata && path.hasSuffix("/access") { result["actor_id"]="foreign" }
            return (200,try JSONSerialization.data(withJSONObject:result),"application/json")
        }
        defer { WorklistStubProtocol.handler=nil }
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[WorklistStubProtocol.self]
        let transport=WorksetReleaseTransport(configuration:configuration,clock:{ WorksetReleaseWire.date(selection.expires_at)!.addingTimeInterval(-60) })
        let probed=try await transport.probe(connection,token:access.token);XCTAssertEqual(probed,access)
        let result=try await transport.submit(access,connection,command:command);XCTAssertEqual(result.operationID,command.operation_id)
        let intent=WorksetReleaseIntent(accessFingerprint:access.fingerprint,scopeKey:access.scopeKey,command:command)
        let current=try await transport.operation(access,connection,intent:intent);XCTAssertEqual(current.state,"COMPLETE")
        XCTAssertEqual(paths.filter { $0.hasSuffix("/commands") }.count,1)
        badMetadata=true
        do { _=try await transport.probe(connection,token:access.token);XCTFail("foreign actor accepted") } catch {}
        badMetadata=false
        for code in [401,403,404,400,409,503,302] {
            status=code
            do { _=try await transport.capability(access,connection);XCTFail("HTTP failure accepted") } catch {}
        }
        let before=paths.count
        do { _=try await transport.probe(connection,token:"not-a-private-grant");XCTFail() } catch {}
        XCTAssertEqual(paths.count,before)
        let state=WorksetReleaseState(credentials:ReleaseMutableCredentials(access),store:ReleaseFailingStore(),transport:transport)
        let host=NSHostingView(rootView:WorksetReleaseSetupView(client:ClientState(),conversations:ConversationState(),state:state))
        host.frame=NSRect(x:0,y:0,width:640,height:400);host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height,0)
    }
}
