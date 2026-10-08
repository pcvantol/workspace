import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI
import XCTest
@testable import WorkspaceClient

final class ControlMemoryCredentials: WorklistControlCredentials, @unchecked Sendable {
    var access: WorklistAccess?
    var intent: WorklistControlIntent?
    var broken = false
    func loadAccess() throws -> WorklistAccess? { if broken { throw CredentialError.corruptBinding }; return access }
    func saveAccess(_ value: WorklistAccess) throws { if broken { throw CredentialError.corruptBinding }; access = value }
    func forgetAccess() throws { if broken { throw CredentialError.corruptBinding }; access = nil }
    func loadIntent() throws -> WorklistControlIntent? { if broken { throw CredentialError.corruptBinding }; return intent }
    func saveIntent(_ value: WorklistControlIntent) throws { if broken { throw CredentialError.corruptBinding }; intent = value }
    func forgetIntent() throws { if broken { throw CredentialError.corruptBinding }; intent = nil }
}

private final class ControlResponseGate: @unchecked Sendable {
    private let semaphore=DispatchSemaphore(value:0)
    private let lock=NSLock()
    private var began=false
    var started: Bool { lock.withLock { began } }
    func block() { lock.withLock { began=true }; _=semaphore.wait(timeout:.now()+3) }
    func release() { semaphore.signal() }
}

final class WorklistControlTests: XCTestCase {
    let access = WorklistProjectionTests.access
    let scope = ApprovedWorklistScope(forgeInstanceID: "forge-1", actorID: "actor-a", worksetID: "workset-a")
    var calls: [URLRequest] = []
    var code = 200
    var held = false
    var revision = 1
    var old: [String: Any]?
    var dropPost = false
    var pendingResponse = false
    var mutateCurrent: ((inout [String: Any]) -> Void)?
    var beforeReply: (() -> Void)?

    func current(held: Bool? = nil, revision: Int? = nil) -> [String: Any] {
        let active = held ?? self.held
        var value: [String: Any] = ["instance_id":"forge-1", "workset_id":"workset-a", "definition_revision":"sha256:" + String(repeating: "a", count: 64),
            "workset_revision": revision ?? self.revision, "control_revision": active ? 1 : 0, "held":active,
            "hold":active ? ["operation_id":"own-hold", "control_revision":1, "reason_code":"USER_REQUEST", "owned_by_principal":true] : NSNull(),
            "hold_provenance":active ? "RECORDED" : "NONE", "admitted_mission_ids":[],
            "boundary":"FUTURE_ADMISSION_ONLY", "ongoing_work_cancelled":false, "observed_at":"2026-10-08T00:00:00Z"]
        if active, let old, let effect = old["effect"] as? [String:Any], (effect["held"] as? Bool) == true { value["hold"] = effect["hold"] }
        mutateCurrent?(&value); return value
    }
    func snapshot(revision: Int) throws -> [String: Any] {
        var value = try JSONSerialization.jsonObject(with: WorklistProjectionTests.fixture("pending")) as! [String: Any]
        value["workset_revision"] = revision
        let keys = ["contract_version", "instance_id", "installation_id", "scope", "membership_revision", "selector_revision", "workset_revision", "activation_support", "completeness", "items", "continuation"]
        let data = try JSONSerialization.data(withJSONObject: value.filter { keys.contains($0.key) }, options: [.sortedKeys, .withoutEscapingSlashes])
        value["snapshot_revision"] = "sha256:" + SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined()
        return value
    }
    func readback(operation: [String: Any]? = nil) throws -> [String: Any] {
        ["contract_version":"forge-worklist-control-readback/v1", "principal_id":"actor-a", "read_only":true,
         "operation": operation as Any? ?? NSNull(), "current":current(), "worklist":try snapshot(revision: revision)]
    }
    func transport() -> WorklistControlTransport {
        StubProtocol.handler = { request in
            self.calls.append(request)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Worklist-Control-Grant"), self.access.token)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Instance"), self.access.workspaceInstanceID)
            self.beforeReply?()
            if self.code != 200 { return (self.code, Data("{}".utf8)) }
            if request.url!.path == "/v1/workset-controls" {
                return (200, try JSONSerialization.data(withJSONObject:["contract_version":"workspace-worklist-control-access/v1", "instance_id":"forge-1", "principal_id":"actor-a", "workset_ids":["workset-a"]]))
            }
            var document: [String: Any]
            if request.httpMethod == "POST" {
                let data = try request.httpBody ?? self.body(request)
                let body = try JSONDecoder().decode(WorklistControlRequest.self, from:data)
                let dict = try JSONSerialization.jsonObject(with: body.data()) as! [String:Any]
                self.held = body.intent == "hold"; self.revision = body.expected_revision + 2
                var effect = self.current()
                if self.held { effect["hold"] = ["operation_id":body.operation_id, "control_revision":1, "reason_code":body.reason_code, "owned_by_principal":true] }
                self.old = ["contract_version":"forge-worklist-control-receipt/v1", "operation_id":body.operation_id,
                    "principal_id":"actor-a", "grant_id":"grant-a", "request":dict, "request_digest":body.digest,
                    "outcome":"APPLIED", "effect":effect, "only_target_hold_removed":body.hold_operation_id as Any? ?? NSNull()]
                if self.dropPost { throw URLError(.networkConnectionLost) }
                document = ["contract_version":"forge-worklist-control-readback/v1", "recorded":true, "original_receipt":self.old!,
                    "current_readback":try self.readback(operation:["state":"APPLIED", "execution_known":true, "operation_id":body.operation_id, "original_receipt":self.old!])]
            } else if request.url!.path.contains("/commands/") {
                let operationID = request.url!.lastPathComponent
                if self.pendingResponse {
                    document = try self.readback(operation:["state":"PENDING", "execution_known":false, "operation_id":operationID, "original_receipt":NSNull()])
                } else if let old = self.old {
                    document = try self.readback(operation:["state":"APPLIED", "execution_known":true, "operation_id":operationID, "original_receipt":old])
                } else { return (404, Data("{}".utf8)) }
            } else { document = try self.readback() }
            return (200, try JSONSerialization.data(withJSONObject:document))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return WorklistControlTransport(configuration:config)
    }
    func body(_ request: URLRequest) throws -> Data {
        guard let stream = request.httpBodyStream else { throw WorklistControlError.invalid }
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating:0,count:4096); let count = stream.read(&bytes,maxLength:bytes.count)
        return Data(bytes.prefix(max(0,count)))
    }
    var connection: WorklistConnection { .init(endpoint:access.endpoint,instanceID:access.workspaceInstanceID,readToken:"read-bearer") }

    func testClosedRequestsCurrentAndForeignLegacyNegatives() throws {
        let current = try WorklistControlWire.current(self.current(),access:access,workset:"workset-a")
        XCTAssertTrue(current.mayHold)
        let hold = WorklistControlRequest(current:current,intent:"hold",reason:"USER_REQUEST")
        XCTAssertTrue(hold.valid)
        let keys = try JSONSerialization.jsonObject(with:hold.data()) as! [String:Any]
        XCTAssertEqual(Set(keys.keys),WorklistControlWire.requestKeys)
        XCTAssertTrue(keys["hold_operation_id"] is NSNull)
        XCTAssertFalse(WorklistControlRequest(current:current,intent:"arm",reason:"USER_REQUEST").valid)
        XCTAssertFalse(WorklistControlRequest(current:current,intent:"hold",reason:"OWNER_REQUEST").valid)
        for (key,value) in [("instance_id","foreign" as Any),("workset_id","foreign"),("control_revision",true),("held",1),("boundary","CANCEL"),("ongoing_work_cancelled",true),("observed_at","wrong"),("admitted_mission_ids",["same","same"]),("hold_provenance","WRONG")] {
            var bad = self.current();bad[key]=value
            XCTAssertThrowsError(try WorklistControlWire.current(bad,access:access,workset:"workset-a"))
        }
        var legacy = self.current(held:true); legacy["hold"]=NSNull();legacy["hold_provenance"]="LEGACY_UNKNOWN"
        XCTAssertFalse(try WorklistControlWire.current(legacy,access:access,workset:"workset-a").mayUnhold)
        var foreign = self.current(held:true);var raw = foreign["hold"] as! [String:Any];raw["owned_by_principal"]=false;foreign["hold"]=raw
        XCTAssertFalse(try WorklistControlWire.current(foreign,access:access,workset:"workset-a").mayUnhold)
        let own = try WorklistControlWire.current(self.current(held:true),access:access,workset:"workset-a")
        XCTAssertTrue(WorklistControlRequest(current:own,intent:"unhold",reason:"TEMPORARY_WAIT").valid)
    }
    @MainActor
    func testConfirmationPersistenceLostResponseRestartReadbackNoAutomaticPost() async throws {
        let credentials = ControlMemoryCredentials();credentials.access=access
        let transport = transport();let state = WorklistControlState(credentials:credentials,transport:transport)
        await state.refresh(connection:connection,scope:scope)
        XCTAssertTrue(state.hasGrant);XCTAssertNotNil(state.current)
        state.prepare(intent:"hold",reason:"USER_REQUEST");state.prepare(intent:"hold",reason:"USER_REQUEST")
        let operation = try XCTUnwrap(state.confirmation?.operation_id)
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,0)
        state.cancelConfirmation();XCTAssertNil(state.confirmation)
        state.prepare(intent:"hold",reason:"USER_REQUEST");let confirmed = try XCTUnwrap(state.confirmation?.operation_id)
        XCTAssertNotEqual(operation,confirmed)
        dropPost=true;await state.confirm(connection:connection)
        XCTAssertEqual(credentials.intent?.request.operation_id,confirmed)
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        let reopened = WorklistControlState(credentials:credentials,transport:transport)
        let readCredentials = WorklistMemoryCredentials(); readCredentials.stored = access
        WorklistStubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            if request.url?.path == "/v1/worksets" {
                return (200, try JSONSerialization.data(withJSONObject: ["contract_version":"forge-workspace-worklist-scopes/v1", "instance_id":"forge-1", "principal_id":"actor-a", "workset_ids":["workset-a"], "read_only":true]), "application/json")
            }
            return (200, try JSONSerialization.data(withJSONObject:self.snapshot(revision:self.revision)), "application/json")
        }
        let readConfig = URLSessionConfiguration.ephemeral; readConfig.protocolClasses = [WorklistStubProtocol.self]
        let reader = WorklistState(credentials:readCredentials, transport:WorklistTransport(configuration:readConfig), controls:reopened)
        await reader.refreshWithControls(connection:connection)
        XCTAssertEqual(reader.cache.snapshot?.scope,scope)
        XCTAssertTrue(calls.contains { $0.url?.path == "/v1/workset-controls/workset-a/commands/" + confirmed && $0.httpMethod == "GET" })
        XCTAssertEqual(reopened.phase,"controlApplied");XCTAssertTrue(reopened.current?.held == true)
        XCTAssertNil(credentials.intent);XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        await reopened.resume(connection:connection);XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        await reader.refreshWithControls(connection:.init(endpoint:connection.endpoint,instanceID:connection.instanceID,readToken:nil))
        XCTAssertNil(reopened.current)
        await reader.refreshWithControls(connection:connection)
        XCTAssertTrue(reopened.current?.held == true)
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        dropPost=false;reopened.prepare(intent:"unhold",reason:"USER_REQUEST");await reopened.confirm(connection:connection)
        XCTAssertFalse(reopened.current?.held ?? true);XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,2)
    }
    @MainActor
    func testPersistenceDenialScopeAndExplicitResumeMissingFrozenIntent() async throws {
        let store=ControlMemoryCredentials();store.access=access
        let state=WorklistControlState(credentials:store,transport:transport())
        await state.refresh(connection:connection,scope:scope)
        state.prepare(intent:"hold",reason:"USER_REQUEST");store.broken=true
        await state.confirm(connection:connection);XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,0)
        store.broken=false;await state.refresh(connection:connection,scope:scope)
        let preview=try XCTUnwrap(state.current);let request=WorklistControlRequest(current:preview,intent:"hold",reason:"USER_REQUEST")
        store.intent=WorklistControlIntent(accessFingerprint:WorklistControlIntent.fingerprint(access),endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,request:request)
        await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlPending")
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,0)
        await state.saveGrant(access.token,connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlConflict")
        state.forgetGrant();XCTAssertNotNil(store.access)
        await state.resume(connection:connection);XCTAssertEqual(state.phase,"controlApplied")
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        code=403;await state.refresh(connection:connection,scope:scope);XCTAssertNil(state.current);XCTAssertEqual(state.phase,"controlDenied")
        code=409;await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlConflict")
        code=503;await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlOffline")
        code=400;await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlInvalid")
        code=404;await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlUnsupported")
        await state.refresh(connection:nil,scope:scope);XCTAssertNil(state.current)
        code=200;await state.saveGrant(access.token,connection:connection,scope:scope);XCTAssertTrue(state.hasGrant)
        state.forgetGrant();XCTAssertFalse(state.hasGrant)
    }
    @MainActor
    func testPendingExplicitRecoveryConflictAndDiscardNeverRebases() async throws {
        let store=ControlMemoryCredentials();store.access=access
        let transport=transport();let state=WorklistControlState(credentials:store,transport:transport)
        await state.refresh(connection:connection,scope:scope)
        let frozen=WorklistControlRequest(current:try XCTUnwrap(state.current),intent:"hold",reason:"TEMPORARY_WAIT")
        store.intent=WorklistControlIntent(accessFingerprint:WorklistControlIntent.fingerprint(access),endpoint:access.endpoint,
            workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,request:frozen)
        pendingResponse=true;await state.refresh(connection:connection,scope:scope)
        XCTAssertEqual(state.phase,"controlPending");XCTAssertNotNil(store.intent)
        await state.resolveOrDiscardUnrecorded(connection:connection)
        XCTAssertEqual(state.phase,"controlConflict");XCTAssertNotNil(store.intent)
        pendingResponse=false;revision=2
        await state.resume(connection:connection)
        XCTAssertEqual(state.phase,"controlConflict");XCTAssertEqual(store.intent?.request.expected_revision,1)
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,0)
        await state.resolveOrDiscardUnrecorded(connection:connection)
        XCTAssertNil(store.intent);XCTAssertEqual(state.current?.workset_revision,2)
        state.prepare(intent:"hold",reason:"USER_REQUEST");await state.confirm(connection:connection)
        XCTAssertEqual(state.current?.workset_revision,4)
        let oldReceipt=try XCTUnwrap(state.receipt);held=false;revision=6
        let oldRequest=oldReceipt.request
        store.intent=WorklistControlIntent(accessFingerprint:WorklistControlIntent.fingerprint(access),endpoint:access.endpoint,
            workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,request:oldRequest)
        await state.refresh(connection:connection,scope:scope)
        XCTAssertFalse(state.current?.held ?? true);XCTAssertTrue(state.receipt?.effect.held == true)
        XCTAssertNil(store.intent)
        // Fresh same-scope stale callbacks cannot restore state after pairing invalidation.
        let gate=ControlResponseGate()
        beforeReply={ gate.block() }
        let delayed=Task { await state.refresh(connection:self.connection,scope:self.scope) }
        for _ in 0..<100 where !gate.started { try? await Task.sleep(for:.milliseconds(5)) }
        XCTAssertTrue(gate.started);state.invalidate();gate.release()
        await delayed.value;XCTAssertNil(state.current);XCTAssertFalse(state.busy)
        beforeReply=nil;store.access=nil
        await state.refresh(connection:connection,scope:scope);XCTAssertEqual(state.phase,"controlReadOnly")
    }

    @MainActor
    func testCurrentStatusAndConfirmationRenderInFiveLocalesBothThemesAndNarrowWindows() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let store=ControlMemoryCredentials();store.access=access
        let state=WorklistControlState(credentials:store,transport:transport())
        await state.refresh(connection:connection,scope:scope)
        func render() {
            for language in ["en","nl","de","fr","es"] {
                for key in WorklistControlCopy.values.keys {
                    XCTAssertNotEqual(WorklistControlCopy.text(key,language:language),key)
                }
                for theme in [ColorScheme.light,.dark] {
                    for width in [CGFloat(380),1000] {
                        let host=NSHostingView(rootView:WorklistControlView(state:state,connection:{ self.connection },stateScope:scope)
                            .environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,theme))
                        host.frame=NSRect(x:0,y:0,width:width,height:1800);host.layoutSubtreeIfNeeded()
                        XCTAssertEqual(host.frame.width,width)
                    }
                }
            }
        }
        render();state.prepare(intent:"hold",reason:"USER_REQUEST");render();await state.confirm(connection:connection);render()
        state.prepare(intent:"unhold",reason:"TEMPORARY_WAIT");render();state.cancelConfirmation()
        var raw=current(held:true);raw["hold"]=NSNull();raw["hold_provenance"]="LEGACY_UNKNOWN"
        mutateCurrent={ value in value=raw };await state.refresh(connection:connection,scope:scope);render()
        mutateCurrent=nil;raw=current(held:true);var hold=raw["hold"] as! [String:Any];hold["owned_by_principal"]=false;raw["hold"]=hold
        await state.refresh(connection:connection,scope:scope);render()
        mutateCurrent=nil;code=403;await state.refresh(connection:connection,scope:scope);render()
        code=503;await state.refresh(connection:connection,scope:scope);render()
        state.invalidate();render()
        XCTAssertEqual(WorklistControlCopy.text("controlHold",language:"unsupported"),"Put in hold")
        XCTAssertEqual(WorklistControlCopy.text("unknownKey",language:"nl"),"unknownKey")
    }

    @MainActor
    func testReadbackClosedShapesAndReceiptTamperingCannotShowApplied() async throws {
        let transport=transport()
        let preview=try await transport.read(access:access,bearer:"read-bearer",workset:"workset-a")
        let request=WorklistControlRequest(current:preview.current,intent:"hold",reason:"USER_REQUEST")
        let applied=try await transport.submit(access:access,bearer:"read-bearer",request:request)
        XCTAssertTrue(applied.current.held)
        for field in ["principal_id","grant_id","request_digest","outcome","operation_id","only_target_hold_removed"] {
            var bad=old!;bad[field]=field=="grant_id" ? "foreign/id" : "foreign"
            XCTAssertThrowsError(try WorklistControlWire.receipt(bad,access:access,workset:"workset-a",expected:request))
        }
        var badEffect=old!;var effect=badEffect["effect"] as! [String:Any];effect["workset_revision"]=2;badEffect["effect"]=effect
        XCTAssertThrowsError(try WorklistControlWire.receipt(badEffect,access:access,workset:"workset-a",expected:request))
        var bad=try readback();bad["read_only"]=1
        XCTAssertThrowsError(try WorklistControlWire.readback(bad,access:access,workset:"workset-a"))
        bad=try readback();var raw=bad["current"] as! [String:Any];raw["admitted_mission_ids"]=["phantom"];bad["current"]=raw
        XCTAssertThrowsError(try WorklistControlWire.readback(bad,access:access,workset:"workset-a"))
        bad=try readback();bad["operation"]=["state":"APPLIED","execution_known":true,"operation_id":"wrong","original_receipt":old!]
        XCTAssertThrowsError(try WorklistControlWire.readback(bad,access:access,workset:"workset-a",expected:request))
        for status in [400,401,403,404,409,503,302] {
            code=status
            do { _=try await transport.read(access:access,bearer:"read-bearer",workset:"workset-a");XCTFail("Non200 accepted") }
            catch { XCTAssertTrue(error is WorklistControlError) }
        }
    }

}
