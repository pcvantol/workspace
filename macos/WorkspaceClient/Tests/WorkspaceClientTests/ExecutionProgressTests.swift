import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

// Source-only fixtures. These tests are not installed producer/GUI qualification.
enum ExecutionFixture {
    static var connection:AdvisoryConnection {ActivityTests.connection}
    static func query() throws->ExecutionQuery {
        let a=try ActivityTests.access()
        return ExecutionQuery(connection:connection,activity:a,workset:a.worksets[0].workset_id,mission:"mission")
    }
    static func raw(_ q:ExecutionQuery) throws->[String:Any] {
        let file=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ExecutionProgress/source-only.json")
        var packet=try JSONSerialization.jsonObject(with:Data(contentsOf:file)) as! [String:Any]
        packet["selected_mission_id"]=q.mission
        var selection=packet["selection"] as! [String:Any];selection["mission_ids"]=[q.mission];packet["selection"]=selection
        var rows=packet["records"] as! [[String:Any]];rows[0]["mission_id"]=q.mission;packet["records"]=rows
        if let run=q.run {packet["selected_run_id"]=run;packet["completeness"]="EXACT_RUN"}
        return ["contract_version":"workspace-execution-progress/1","actor_id":q.connection.actorID,"context_id":q.connection.workspaceProjectID,"workspace_instance_id":q.connection.workspaceInstanceID,"binding_id":"binding","activity_binding_id":q.activity.binding_id,"forge_instance_id":q.activity.scope.instance_id,"workset_id":q.workset,"producer_source":ExecutionWire.source,"expires_at":"2099-01-01T00:00:00Z","packet":packet]
    }
    static func envelope(_ q:ExecutionQuery,wrong:Bool=false) throws->ExecutionEnvelope {
        var raw=try raw(q)
        if wrong {var p=raw["packet"] as! [String:Any];var rows=p["records"] as! [[String:Any]];rows[0]["submission_id"]="different-submission";rows[0]["engineering_action_id"]="different-action";p["records"]=rows;raw["packet"]=p}
        return try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q)
    }
}
private actor ExecutionSource:ExecutionServing {
    var mode="normal";var calls:[ExecutionQuery]=[];var delay=false;var expiry:String?
    func set(_ mode:String) {self.mode=mode}
    func slow(_ value:Bool) {delay=value}
    func expire(_ value:String) {expiry=value}
    func read(_ query:ExecutionQuery) async throws->ExecutionEnvelope {
        calls.append(query);let selectedMode=mode
        if delay {try? await Task.sleep(for:.milliseconds(180))}
        switch selectedMode {
        case "denied":throw ExecutionError.denied
        case "snapshot":throw ExecutionError.snapshot
        case "unavailable":throw ExecutionError.unavailable
        case "unbound":throw ExecutionError.unbound
        case "notFound":throw ExecutionError.notFound
        case "unsupported":throw ExecutionError.unsupported
        case "corrupt":throw ExecutionError.corrupt
        case "invalid":throw ExecutionError.invalid
        default:
            var value=try ExecutionFixture.envelope(query,wrong:query.run != nil && selectedMode=="wrong")
            if let expiry {
                var raw=try ExecutionFixture.raw(query);raw["expires_at"]=expiry;value=try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),query)
            }
            if selectedMode=="empty" {
                var raw=try ExecutionFixture.raw(query);var packet=raw["packet"] as! [String:Any];packet["records"]=[];packet["logical_action_count"]=0;raw["packet"]=packet;value=try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),query)
            }
            return value
        }
    }
}
final class ExecutionProgressTests:XCTestCase {
    func testClosedActualProducerSchemaIdentitySnapshotAndTechnicalAcceptance() throws {
        let q=try ExecutionFixture.query();let data=try JSONSerialization.data(withJSONObject:ExecutionFixture.raw(q));let e=try ExecutionWire.decode(data,q)
        XCTAssertEqual(e.packet.records[0].result.forge_mission_acceptance,"NOT_OWNED_BY_EP")
        XCTAssertEqual(e.packet.groups.count,1);XCTAssertEqual(e.packet.groups[0].records[0].id,"sub")
        for key in ["actor_id","context_id","workspace_instance_id","activity_binding_id","forge_instance_id","workset_id","producer_source"] {
            var raw=try ExecutionFixture.raw(q);raw[key]="foreign"
            XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q),key)
        }
        var changed=q;changed.expectedSnapshot=String(repeating:"b",count:64)
        XCTAssertThrowsError(try ExecutionWire.decode(data,changed))
        changed=q;changed.binding="foreign";XCTAssertThrowsError(try ExecutionWire.decode(data,changed))
        changed=q;changed.run="run";XCTAssertThrowsError(try changed.validate())
        changed=q;changed.expectedSnapshot="bad";XCTAssertThrowsError(try changed.validate())
        var raw=try ExecutionFixture.raw(q);var p=raw["packet"] as! [String:Any];p["business_mutations"]=false;raw["packet"]=p
        XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q))
    }
    func testScopeDuplicateRunsAndPrivateDescriptionsRejected() throws {
        let q=try ExecutionFixture.query()
        for key in ["project_id","repository_id","producer_id","mission_id"] {
            var raw=try ExecutionFixture.raw(q);var p=raw["packet"] as! [String:Any];var rows=p["records"] as! [[String:Any]];rows[0][key]="foreign";p["records"]=rows;raw["packet"]=p
            XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q),key)
        }
        for value in ["/Users/private/secret","C:\\private","line\nsecret"] {
            var raw=try ExecutionFixture.raw(q);var p=raw["packet"] as! [String:Any];var rows=p["records"] as! [[String:Any]];rows[0]["description"]=value;rows[0]["description_status"]="AVAILABLE";p["records"]=rows;raw["packet"]=p
            XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q))
        }
        var raw=try ExecutionFixture.raw(q);var p=raw["packet"] as! [String:Any];let rows=p["records"] as! [[String:Any]];p["records"]=rows+rows;raw["packet"]=p
        XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q))
    }
    func testQualifiedCannotConcealFailedTechnicalResult() throws {
        let q=try ExecutionFixture.query();var raw=try ExecutionFixture.raw(q);var p=raw["packet"] as! [String:Any];var rows=p["records"] as! [[String:Any]];var result=rows[0]["result"] as! [String:Any];var qualification=result["qualification"] as! [String:Any]
        qualification["run_qualification"]="QUALIFIED";result["qualification"]=qualification;result["technical_outcome"]="FAILED";rows[0]["result"]=result;p["records"]=rows;raw["packet"]=p
        XCTAssertThrowsError(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q))
        result["technical_outcome"]="COMPLETE";rows[0]["result"]=result;p["records"]=rows;raw["packet"]=p
        XCTAssertEqual(try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q).packet.records[0].result.qualification.run_qualification,"QUALIFIED")
    }
    @MainActor func testSameRunDifferentAttemptIsNeverPublished() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=ExecutionSource(),state=ExecutionProgressState(transport:peer,root:root),q=try ExecutionFixture.query();defer{state.reset()}
        await state.activate(q,current:{q.connection});await state.choose("mission");XCTAssertEqual(state.status,"ready")
        await peer.set("wrong");await state.select("sub")
        XCTAssertEqual(state.status,"invalid");XCTAssertNil(state.detail);XCTAssertNil(state.overview)
        XCTAssertEqual(state.navigation.submission,"sub");XCTAssertEqual(state.navigation.run,"run")
    }
    @MainActor func testOriginalSelectionReopensAndExplicitEmptyChoicePersistsWithoutRead() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=ExecutionSource(),q=try ExecutionFixture.query(),state=ExecutionProgressState(transport:peer,root:root)
        await state.activate(q,current:{q.connection});await state.choose("mission");await state.select("sub");XCTAssertEqual(state.detail?.run_id,"run")
        state.expanded(false);XCTAssertFalse(state.navigation.expanded);state.expanded(true)
        let selected=state.navigation;state.reset()
        let reopened=ExecutionProgressState(transport:peer,root:root);defer{reopened.reset()}
        await reopened.activate(q,current:{q.connection});XCTAssertEqual(reopened.navigation,selected);XCTAssertEqual(reopened.detail?.id,"sub")
        let before=await peer.calls.count;await reopened.choose("");XCTAssertEqual(reopened.status,"choose");XCTAssertNil(reopened.overview);XCTAssertNil(reopened.detail);let after=await peer.calls.count;XCTAssertEqual(after,before)
        reopened.reset();await reopened.activate(q,current:{q.connection});XCTAssertEqual(reopened.status,"choose");XCTAssertEqual(reopened.navigation,ExecutionNavigation())
        // Navigation persists identifiers only, never protected source packets.
        for file in try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) where file.pathExtension=="json" {
            let text=try String(contentsOf:file,encoding:.utf8);XCTAssertFalse(text.contains("technical_outcome"));XCTAssertFalse(text.contains("source_updated_at"))
        }
    }
    @MainActor func testDistinctFailuresHideProtectedDataAndRecoverByExplicitFullRead() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=ExecutionSource(),q=try ExecutionFixture.query(),state=ExecutionProgressState(transport:peer,root:root);defer{state.reset()}
        await state.activate(q,current:{q.connection});await state.choose("mission")
        for mode in ["snapshot","unavailable","unbound","notFound","unsupported","corrupt","invalid"] {
            await peer.set(mode);await state.refresh();XCTAssertEqual(state.status,mode);XCTAssertNil(state.overview);XCTAssertNil(state.detail)
            await peer.set("normal");await state.refresh();XCTAssertEqual(state.status,"ready")
        }
        await peer.set("denied");await state.refresh();XCTAssertEqual(state.status,"denied");XCTAssertNil(state.overview)
    }
    @MainActor func testLateReplyAfterHideAndChangedAuthorityCannotPublish() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=ExecutionSource(),q=try ExecutionFixture.query(),state=ExecutionProgressState(transport:peer,root:root);defer{state.reset()}
        await state.activate(q,current:{q.connection});await peer.slow(true)
        let request=Task {await state.choose("mission")};try await Task.sleep(for:.milliseconds(30));state.hide();await request.value
        XCTAssertNil(state.overview);XCTAssertNil(state.detail);XCTAssertFalse(state.busy)
        await state.activate(q,current:{nil});await state.choose("mission");XCTAssertEqual(state.status,"denied")
    }
    @MainActor func testHiddenNaturalExpiryStillEnforcesDeniedAndClearsSelection() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let q=try ExecutionFixture.query(),peer=ExecutionSource(),state=ExecutionProgressState(transport:peer,root:root);defer{state.reset()}
        let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        await peer.expire(formatter.string(from:Date().addingTimeInterval(0.9)))
        await state.activate(q,current:{q.connection});await state.choose("mission");XCTAssertNotNil(state.overview)
        state.hide();try await Task.sleep(for:.milliseconds(1400))
        XCTAssertEqual(state.status,"denied");XCTAssertNil(state.overview);XCTAssertNil(state.detail);XCTAssertTrue(state.navigation.mission.isEmpty)
    }
    @MainActor func testSelectionChangeRejectsLateMissionReplyAndCoalescesRefresh() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let q=try ExecutionFixture.query(),peer=ExecutionSource(),state=ExecutionProgressState(transport:peer,root:root);defer{state.reset()}
        await state.activate(q,current:{q.connection});await peer.slow(true)
        let first=Task {await state.choose("mission")};try await Task.sleep(for:.milliseconds(25))
        let before=await peer.calls.count;await state.refresh();let after=await peer.calls.count;XCTAssertEqual(before,after)
        await state.choose("second-mission");await first.value
        XCTAssertEqual(state.navigation.mission,"second-mission");XCTAssertEqual(state.overview?.packet.selected_mission_id,"second-mission")
        XCTAssertFalse(state.busy)
    }
    @MainActor func testMissingOriginalSelectionIsNotSilentlyReplacedByEmptyResult() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let q=try ExecutionFixture.query(),peer=ExecutionSource(),state=ExecutionProgressState(transport:peer,root:root);defer{state.reset()}
        await state.activate(q,current:{q.connection});await state.choose("mission");await state.select("sub");let original=state.navigation
        await peer.set("empty");await state.refresh();XCTAssertEqual(state.status,"notFound");XCTAssertNil(state.detail);XCTAssertEqual(state.navigation,original)
        await peer.set("normal");await state.refresh();XCTAssertEqual(state.status,"ready");XCTAssertEqual(state.detail?.id,"sub")
    }
    func testLegalReservedSubmissionIDsRetainSeparateFocusAndOriginalAnchors() throws {
        let q=try ExecutionFixture.query()
        for original in ["detail","refresh","mission"] {
            var raw=try ExecutionFixture.raw(q);var packet=raw["packet"] as! [String:Any];var rows=packet["records"] as! [[String:Any]];rows[0]["submission_id"]=original;packet["records"]=rows;raw["packet"]=packet
            let admitted=try ExecutionWire.decode(JSONSerialization.data(withJSONObject:raw),q).packet.records[0]
            let run=ExecutionFocus.run(admitted.id)
            XCTAssertNotEqual(run,.detail);XCTAssertNotEqual(run,.refresh);XCTAssertNotEqual(run,.mission)
            XCTAssertEqual(run.anchor,"execution-run-"+original);XCTAssertNotEqual(run.anchor,ExecutionFocus.detail.anchor);XCTAssertNotEqual(run.anchor,ExecutionFocus.refresh.anchor);XCTAssertNotEqual(run.anchor,ExecutionFocus.mission.anchor)
        }
    }
    func testAllFiveLanguageLabelsHaveCompleteEntries() {
        for (key,values) in ExecutionProgressCopy.table {XCTAssertEqual(values.count,5,key);XCTAssertTrue(values.allSatisfy{!$0.isEmpty})}
        for language in ["en","nl","de","fr","es"] {XCTAssertEqual(ExecutionProgressCopy.text("NEW_FUTURE_PHASE",language),ExecutionProgressCopy.text("UNAVAILABLE",language))}
        XCTAssertEqual(ExecutionProgressCopy.text("title","unknown"),"Execution")
        XCTAssertNotEqual(ExecutionProgressCopy.text("COMPLETE","nl"),"Missie geaccepteerd")
    }
}

private final class ExecutionURLProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var reply:((URLRequest)throws->(Int,Data,[String:String]))?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {
            let (code,data,headers)=try Self.reply!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:headers)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
extension ExecutionProgressTests {
    func testTransportOnlyOwnGETAndOriginalRunSnapshotHeaders() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ExecutionURLProtocol.self]
        let transport=ExecutionProgressTransport(session:URLSession(configuration:config)),q=try ExecutionFixture.query()
        ExecutionURLProtocol.reply={request in
            XCTAssertEqual(request.httpMethod,"GET");XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+q.connection.bearer)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),q.connection.draftGrant)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Activity-Grant"),q.activity.token)
            XCTAssertNil(request.value(forHTTPHeaderField:"EP-Progress-Contract"));XCTAssertNil(request.value(forHTTPHeaderField:"EP-Audience"))
            XCTAssertTrue(request.url!.path.hasPrefix("/v1/execution-progress/"+q.workset))
            return (200,try JSONSerialization.data(withJSONObject:ExecutionFixture.raw(q)),["Content-Type":"application/json","Cache-Control":"no-store"])
        }
        let value=try await transport.read(q);XCTAssertEqual(value.packet.records.count,1)
        var detail=q;detail.run="run";detail.binding="binding";detail.expectedSnapshot=String(repeating:"a",count:64)
        let frozen=detail
        ExecutionURLProtocol.reply={request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Execution-Binding"),"binding")
            XCTAssertTrue(request.url!.path.hasSuffix("/runs/run"));XCTAssertTrue(request.url!.query!.contains("expected_snapshot="+String(repeating:"a",count:64)))
            return (200,try JSONSerialization.data(withJSONObject:ExecutionFixture.raw(frozen)),["Content-Type":"application/json","Cache-Control":"no-store"])
        }
        let original=try await transport.read(detail);XCTAssertEqual(original.packet.selected_run_id,"run")
    }
    func testTransportErrorsAreDistinctAndNeverUnsupportedBy404OrAuth() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ExecutionURLProtocol.self]
        let transport=ExecutionProgressTransport(session:URLSession(configuration:config)),q=try ExecutionFixture.query()
        for (code,name) in [(503,"UNBOUND"),(404,"RUN_NOT_FOUND"),(409,"SNAPSHOT_CONFLICT"),(422,"UNSUPPORTED"),(503,"SOURCE_CORRUPT"),(409,"SOURCE_CORRUPT"),(409,"UNAVAILABLE"),(503,"UNAVAILABLE"),(404,"UNSUPPORTED"),(401,"UNSUPPORTED"),(403,"UNSUPPORTED")] {
            ExecutionURLProtocol.reply={_ in (code,Data(("{\"error\":\"EXECUTION_PROGRESS_"+name+"\"}").utf8),["Content-Type":"application/json","Cache-Control":"no-store"])}
            do {_=try await transport.read(q);XCTFail("must reject "+name)} catch {
                switch (code,name,error) {
                case (503,"UNBOUND",ExecutionError.unbound),(404,"RUN_NOT_FOUND",ExecutionError.notFound),(409,"SNAPSHOT_CONFLICT",ExecutionError.snapshot),(422,"UNSUPPORTED",ExecutionError.unsupported),(503,"SOURCE_CORRUPT",ExecutionError.corrupt),(409,"SOURCE_CORRUPT",ExecutionError.corrupt),(409,"UNAVAILABLE",ExecutionError.unavailable),(503,"UNAVAILABLE",ExecutionError.unavailable),(404,"UNSUPPORTED",ExecutionError.invalid),(401,_,ExecutionError.denied),(403,_,ExecutionError.denied):break
                default:XCTFail("wrong classification: \(code) \(error)")
                }
            }
        }
        for headers in [["Content-Type":"text/html","Cache-Control":"no-store"],["Content-Type":"application/json","Cache-Control":"public"]] {
            ExecutionURLProtocol.reply={_ in (200,Data(),headers)}
            do {_=try await transport.read(q);XCTFail()}catch ExecutionError.invalid {}
        }
    }
    @MainActor func testSourceRenderFiveLanguagesThemesAndCompactWideLayouts() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let q=try ExecutionFixture.query(),state=ExecutionProgressState(transport:ExecutionSource(),root:root);defer{state.reset()}
        await state.activate(q,current:{q.connection});await state.choose("mission");await state.select("sub")
        XCTAssertEqual(state.detail?.id,"sub")
        let page=try ActivityWire.page(ActivityTests.data("page"),access:q.activity,workset:q.workset)
        for language in ["en","nl","de","fr","es"] {
            for width in [520.0,1150.0] {
                for scheme in [ColorScheme.light,.dark] {
                    let v=ExecutionProgressView(state:state,access:q.activity,workset:q.workset,missions:page.current,connection:{q.connection}).environment(\.locale,Locale(identifier:language)).environment(\.colorScheme,scheme).frame(width:width)
                    let host=NSHostingView(rootView:v);host.setFrameSize(NSSize(width:width,height:1800));host.layoutSubtreeIfNeeded()
                    XCTAssertEqual(host.frame.width,width);XCTAssertGreaterThan(host.fittingSize.height,0)
                }
            }
        }
    }
}
