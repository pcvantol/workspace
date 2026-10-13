import XCTest
import SwiftUI
import AppKit
import Security
@testable import WorkspaceClient

final class WorksetOrderTests: XCTestCase {
    func testMovementFocusPreservesDirectionUntilBoundary() {
        XCTAssertEqual(OrderMovementFocus.target(index:2,fixed:1,count:5,delta:1),":down")
        XCTAssertEqual(OrderMovementFocus.target(index:2,fixed:1,count:5,delta:-1),":up")
        XCTAssertEqual(OrderMovementFocus.target(index:1,fixed:1,count:5,delta:-1),":down")
        XCTAssertEqual(OrderMovementFocus.target(index:4,fixed:1,count:5,delta:1),":up")
        XCTAssertNil(OrderMovementFocus.target(index:1,fixed:1,count:2,delta:1))
        XCTAssertNil(OrderMovementFocus.target(index:0,fixed:1,count:5,delta:1))
        XCTAssertNil(OrderMovementFocus.target(index:5,fixed:1,count:5,delta:1))
        XCTAssertNil(OrderMovementFocus.target(index:2,fixed:1,count:5,delta:0))
        XCTAssertNil(OrderMovementFocus.target(index:2,fixed:-1,count:5,delta:1))
    }
    private func fixture() throws -> [String:Any] {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try OrderWire.object(Data(contentsOf:root.appendingPathComponent("tests/fixtures/workset-order-wire.json")))
    }
    func testActualRecordedCurrentAndPreview() throws {
        let fixture=try fixture();let cap=fixture["capability"] as! [String:Any];let current=fixture["current"] as! [String:Any];let projection=current["current"] as! [String:Any];let scope=projection["scope"] as! [String:Any]
        let binding=ActivityAccess(endpoint:"http://127.0.0.1:8765/",workspaceInstanceID:String(repeating:"a",count:32),actorID:scope["principal_id"] as! String,workspaceProjectID:"order-project",token:String(repeating:"x",count:43),binding_id:"own-order",scope:try AdvisoryWire.decode(cap["scope"] as Any,as:ActivityScope.self),installation_id:projection["installation_id"] as! String,worksets:try AdvisoryWire.decode(cap["worksets"] as Any,as:[ActivitySubject].self),expires_at:cap["expires_at"] as! String)
        let access=OrderAccess(binding:binding,permissions:cap["permissions"] as! [String],maximumAmendments:cap["maximum_amendments"] as! Int)
        XCTAssertTrue(access.valid)
        XCTAssertNoThrow(try OrderWire.validate(current,"current"))
        let key=current["workset_id"] as! String
        let decoded=try OrderWire.current(JSONSerialization.data(withJSONObject:current),access,key)
        XCTAssertEqual(decoded.fixed,1)
        let preview=fixture["preview"] as! [String:Any];let package=preview["package"] as! [String:Any]
        let shown=try OrderWire.preview(JSONSerialization.data(withJSONObject:preview),access,key,package["proposed_order"] as! [String])
        XCTAssertTrue(shown.supported)
        let command=try OrderWire.command(shown,operation:"same-original",workset:key,reason:"Own synthetic choice")
        XCTAssertNoThrow(try OrderWire.validate(OrderWire.object(command),"request"))
    }
    func testOriginalIntentPrivateStoreAndConflictGuard() throws {
        let fixture=try fixture();let shown=fixture["preview"] as! [String:Any];let package=shown["package"] as! [String:Any]
        let request:[String:Any]=["contract_version":OrderWire.contract,"operation_id":"order-original","instance_id":package["instance_id"]!,"project_id":package["project_id"]!,"repository_id":package["repository_id"]!,"workset_id":package["workset_id"]!,"package_digest":shown["package_digest"]!,"package":package,"reason":"Own synthetic choice","confirm":true]
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=OrderIntentStore(root:root)
        let key=String(repeating:"a",count:64)
        XCTAssertNil(try store.load(key))
        let intent=OrderIntent(scopeKey:key,operation:"order-original",workset:package["workset_id"] as! String,request:try JSONSerialization.data(withJSONObject:request))
        try store.save(intent);XCTAssertEqual(try store.load(key),intent)
        try store.save(intent);XCTAssertEqual(try store.load(key),intent)
        var conflicting=request;conflicting["reason"]="Different choice"
        XCTAssertThrowsError(try store.save(OrderIntent(scopeKey:key,operation:intent.operation,workset:intent.workset,request:JSONSerialization.data(withJSONObject:conflicting))))
        XCTAssertEqual(try store.load(key),intent)
    }

}

private struct OrderSamples: Sendable {
    let access:OrderAccess
    let current:OrderCurrent
    let preview:OrderPreview
    let applied:Data
    var key:String { access.binding.worksets[0].workset_id }
    var connection:AdvisoryConnection { AdvisoryConnection(endpoint:access.binding.endpoint,workspaceInstanceID:access.binding.workspaceInstanceID,actorID:access.binding.actorID,workspaceProjectID:access.binding.workspaceProjectID,conversationID:"",bearer:"own-read",draftGrant:String(repeating:"d",count:43)) }
    static func make() throws -> Self {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture=try OrderWire.object(Data(contentsOf:root.appendingPathComponent("tests/fixtures/workset-order-wire.json")))
        let cap=fixture["capability"] as! [String:Any],raw=fixture["current"] as! [String:Any],projection=raw["current"] as! [String:Any],scoped=projection["scope"] as! [String:Any]
        let date=ISO8601DateFormatter().string(from:Date().addingTimeInterval(3600))
        let binding=ActivityAccess(endpoint:"http://127.0.0.1:8765/",workspaceInstanceID:String(repeating:"a",count:32),actorID:scoped["principal_id"] as! String,workspaceProjectID:"order-project",token:String(repeating:"x",count:43),binding_id:"order-own",scope:try AdvisoryWire.decode(cap["scope"] as Any,as:ActivityScope.self),installation_id:projection["installation_id"] as! String,worksets:try AdvisoryWire.decode(cap["worksets"] as Any,as:[ActivitySubject].self),expires_at:date)
        let access=OrderAccess(binding:binding,permissions:cap["permissions"] as! [String],maximumAmendments:2),key=binding.worksets[0].workset_id
        let preview=fixture["preview"] as! [String:Any],package=preview["package"] as! [String:Any]
        return Self(access:access,current:try OrderWire.current(JSONSerialization.data(withJSONObject:raw),access,key),preview:try OrderWire.preview(JSONSerialization.data(withJSONObject:preview),access,key,package["proposed_order"] as! [String]),applied:try Data(contentsOf:root.appendingPathComponent("tests/fixtures/workset-order-applied.json")))
    }
}
private final class OrderMemory:OrderCredentials,@unchecked Sendable {
    let lock=NSLock();var value:OrderAccess?
    init(_ value:OrderAccess?) { self.value=value }
    func load() throws -> OrderAccess? { lock.withLock{value} }
    func save(_ access:OrderAccess) throws { lock.withLock{value=access} }
    func forget() throws { lock.withLock{value=nil} }
}
@MainActor private final class OrderOwnContext { var value:AdvisoryConnection?;init(_ value:AdvisoryConnection?) {self.value=value} }
private actor OrderScripted:OrderServing {
    let sample:OrderSamples
    var mode="normal"
    var confirmed=0
    var applied=false
    var held=false
    var waiting:CheckedContinuation<Void,Never>?
    init(_ sample:OrderSamples) { self.sample=sample }
    func configure(_ mode:String) { self.mode=mode }
    func holdPreview() { held=true }
    func release() { held=false;waiting?.resume();waiting=nil }
    func probe(_ connection:AdvisoryConnection,token:String) async throws -> OrderAccess {
        if mode=="denied" { throw AdvisoryError.denied };if mode=="unavailable" { throw AdvisoryError.state("ORDER_UNAVAILABLE") }
        return sample.access
    }
    func read(_ connection:AdvisoryConnection,access:OrderAccess,workset:String) async throws -> OrderCurrent {
        if applied { let raw=try OrderWire.object(sample.applied);return try OrderWire.current(JSONSerialization.data(withJSONObject:raw["current"]!),access,workset) }
        return sample.current
    }
    func preview(_ connection:AdvisoryConnection,access:OrderAccess,workset:String,proposed:[String]) async throws -> OrderPreview {
        if held { await withCheckedContinuation{waiting=$0} }
        return sample.preview
    }
    func operation(_ connection:AdvisoryConnection,access:OrderAccess,intent:OrderIntent,confirm:Bool) async throws -> Data {
        if confirm {
            confirmed+=1
            if mode=="stale" { throw AdvisoryError.state("ORDER_PREVIEW_STALE") }
            applied=true
            if mode=="lost" { mode="normal";throw URLError(.networkConnectionLost) }
        } else if !applied && mode != "pending" { throw AdvisoryError.state("ORDER_OPERATION_UNKNOWN") }
        var raw=try OrderWire.object(sample.applied)
        raw["operation_id"]=intent.operation;raw["original_request"]=try OrderWire.object(intent.request)
        var receipt=raw["original_receipt"] as! [String:Any];receipt["operation_id"]=intent.operation
        raw["original_receipt"]=receipt
        if !applied {
            raw["state"]="PENDING";raw["original_receipt"]=NSNull();raw["canonical_decisions_observed"]=[String:String]()
            raw["current"]=try OrderWire.object(sample.current.data)
        }
        return try JSONSerialization.data(withJSONObject:raw)
    }
}

extension WorksetOrderTests {
    @MainActor func testNativeOneEffectLostReplyRecoveryAndPrivateOriginalIntent() async throws {
        let sample=try OrderSamples.make(),peer=OrderScripted(sample),memory=OrderMemory(sample.access),context=OrderOwnContext(sample.connection)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let state=OrderState(credentials:memory,store:OrderIntentStore(root:root),transport:peer);state.authority={context.value}
        await state.connect(sample.connection);await state.choose(sample.key)
        state.move(sample.current.order[0],1);XCTAssertEqual(state.proposed,sample.current.order)
        state.move(sample.current.order[2],-1);await state.showPreview();XCTAssertNotNil(state.preview)
        state.cancel();XCTAssertNil(state.preview)
        state.move(sample.current.order[2],-1);await state.showPreview();await peer.configure("lost")
        await state.confirm(reason:"Own explicit native unit choice");XCTAssertEqual(state.status,"unavailable")
        let original=try XCTUnwrap(state.intent);XCTAssertEqual(try OrderIntentStore(root:root).load(original.scopeKey),original)
        await state.recover(replay:false);XCTAssertEqual(state.status,"applied");let count1=await peer.confirmed;XCTAssertEqual(count1,1)
        await state.recover(replay:true);let count2=await peer.confirmed;XCTAssertEqual(count2,1)
        await state.refresh();XCTAssertEqual(state.status,"applied");state.newProposal();XCTAssertNil(state.intent);XCTAssertNotNil(state.result)
        state.invalidate();await state.connect(sample.connection);await state.choose(sample.key)
        XCTAssertEqual(state.intent,original);XCTAssertEqual(state.status,"applied");let count3=await peer.confirmed;XCTAssertEqual(count3,1)
        state.forget();XCTAssertNil(try memory.load());XCTAssertNil(state.access)
    }
    @MainActor func testLateOldAuthorityCannotPublishPreviewAndCanceledTimerCannotClearNewConnection() async throws {
        let sample=try OrderSamples.make(),peer=OrderScripted(sample),memory=OrderMemory(sample.access),context=OrderOwnContext(sample.connection)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let state=OrderState(credentials:memory,store:OrderIntentStore(root:root),transport:peer);state.authority={context.value}
        await state.connect(sample.connection);state.invalidate();await state.connect(sample.connection)
        try await Task.sleep(for:.milliseconds(20));XCTAssertNotNil(state.access)
        await state.choose(sample.key);state.move(sample.current.order[2],-1);await peer.holdPreview()
        let work=Task{await state.showPreview()};try await Task.sleep(for:.milliseconds(20));context.value=nil;await peer.release();await work.value
        XCTAssertNil(state.preview);XCTAssertNil(state.access);XCTAssertEqual(state.status,"denied");state.invalidate()
    }
    @MainActor func testNativePendingReplayAndDefinitiveRejectedIntentRemainDistinct() async throws {
        let sample=try OrderSamples.make(),peer=OrderScripted(sample),memory=OrderMemory(sample.access),context=OrderOwnContext(sample.connection)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=OrderIntentStore(root:root),state=OrderState(credentials:memory,store:store,transport:peer);state.authority={context.value}
        await state.connect(sample.connection);await state.choose(sample.key);state.move(sample.current.order[2],-1);await state.showPreview()
        await peer.configure("stale");await state.confirm(reason:"Stale explicit choice")
        XCTAssertEqual(state.status,"rejected");XCTAssertEqual(state.rejectionCode,"ORDER_PREVIEW_STALE");let rejected=try XCTUnwrap(state.intent);XCTAssertTrue(try store.isRejected(rejected));state.newProposal();XCTAssertNil(state.intent)
        state.move(sample.current.order[2],-1);await state.showPreview();await peer.configure("pending");await state.confirm(reason:"Resume supported original pending")
        XCTAssertEqual(state.status,"applied");let count=await peer.confirmed;XCTAssertEqual(count,2);state.invalidate()
    }
}

private final class OrderHTTPProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var handler:((URLRequest)throws->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        do {
            let (code,data)=try Self.handler!(request)
            let response=HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
private struct OrderEmptyDraft:DraftGrantStore {
    func load() throws -> DraftAccess? {nil}
    func save(_ value:DraftAccess) throws {}
    func forget() throws {}
}
private struct OrderEmptyServer:CredentialStore {
    func binding() throws -> ServerBinding? {nil}
    func token() throws -> String? {nil}
    func save(binding:ServerBinding,token:String) throws {}
    func forget() throws {}
}
extension WorksetOrderTests {
    func testTransportPreservesExactOriginalBytesAndRejectsAuthorizationAndReceiptConflicts() async throws {
        let sample=try OrderSamples.make(),configuration=URLSessionConfiguration.ephemeral
        configuration.protocolClasses=[OrderHTTPProtocol.self];let transport=OrderTransport(configuration:configuration)
        defer{OrderHTTPProtocol.handler=nil}
        var applied=try OrderWire.object(sample.applied)
        let original=applied["original_request"] as! [String:Any],operation=original["operation_id"] as! String
        let intent=OrderIntent(scopeKey:sample.access.key(sample.key,draft:sample.connection.draftGrant),operation:operation,workset:sample.key,request:try JSONSerialization.data(withJSONObject:original))
        OrderHTTPProtocol.handler={ request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Order-Grant"),sample.access.binding.token)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),sample.connection.draftGrant)
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+sample.connection.bearer)
            var data=request.httpBody ?? Data();if let stream=request.httpBodyStream {stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable {let count=stream.read(&buffer,maxLength:buffer.count);if count<=0{break};data.append(contentsOf:buffer.prefix(count))}};XCTAssertEqual(data,intent.request);XCTAssertEqual(request.url?.path,"/v1/workset-orders/"+sample.key+"/confirm")
            return (200,sample.applied)
        }
        let confirmed=try await transport.operation(sample.connection,access:sample.access,intent:intent,confirm:true);XCTAssertEqual(confirmed,sample.applied)
        OrderHTTPProtocol.handler={ request in
            XCTAssertEqual(request.httpMethod,"GET");XCTAssertNil(request.httpBody)
            return (200,sample.current.data)
        }
        let read=try await transport.read(sample.connection,access:sample.access,workset:sample.key);XCTAssertEqual(read.order,sample.current.order)
        OrderHTTPProtocol.handler={ request in
            var data=request.httpBody ?? Data();if let stream=request.httpBodyStream {stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096);while stream.hasBytesAvailable {let count=stream.read(&buffer,maxLength:buffer.count);if count<=0{break};data.append(contentsOf:buffer.prefix(count))}};let raw=try OrderWire.object(data);XCTAssertEqual(raw["proposed_order"] as? [String],(try OrderWire.object(sample.preview.package))["proposed_order"] as? [String])
            return (200,sample.preview.data)
        }
        let shown=try await transport.preview(sample.connection,access:sample.access,workset:sample.key,proposed:(try OrderWire.object(sample.preview.package))["proposed_order"] as! [String]);XCTAssertEqual(shown.digest,sample.preview.digest)
        var cap=try fixture()["capability"] as! [String:Any]
        cap["expires_at"]=sample.access.binding.expires_at
        cap.merge(["consumer_contract":"workspace-workset-order-access/v1","producer_source":ActivityWire.pin,"producer_version":"2.15.0","actor_id":sample.connection.actorID,"workspace_project_id":sample.connection.workspaceProjectID,"binding_id":sample.access.binding.binding_id,"installation_id":sample.access.binding.installation_id]){_,new in new}
        let capData=try JSONSerialization.data(withJSONObject:cap);OrderHTTPProtocol.handler={_ in (200,capData)}
        let access=try await transport.probe(sample.connection,token:sample.access.binding.token);XCTAssertEqual(access,sample.access)
        for status in [401,403,404,409,503] {
            OrderHTTPProtocol.handler={_ in (status,Data("{\"error\":\"ORDER_PREVIEW_STALE\"}".utf8))}
            do{_=try await transport.read(sample.connection,access:sample.access,workset:sample.key);XCTFail("Accepted denied response") }catch{}
        }
        var wrongRevision=applied;var wrongReceipt=wrongRevision["original_receipt"] as! [String:Any];wrongReceipt["order_revision"]=2;wrongRevision["original_receipt"]=wrongReceipt
        let wrongBytes=try JSONSerialization.data(withJSONObject:wrongRevision);OrderHTTPProtocol.handler={_ in (200,wrongBytes)}
        do{_=try await transport.operation(sample.connection,access:sample.access,intent:intent,confirm:false);XCTFail("Accepted receipt revision unrelated to original package") }catch{}
        applied["canonical_decisions_observed"]=["business":"foreign","architecture":"foreign"]
        let conflicting=try JSONSerialization.data(withJSONObject:applied);OrderHTTPProtocol.handler={_ in (200,conflicting)}
        do{_=try await transport.operation(sample.connection,access:sample.access,intent:intent,confirm:false);XCTFail("Accepted conflicting original decisions") }catch{}
        OrderHTTPProtocol.handler={_ in (200,Data(repeating:32,count:1_000_001))}
        do{_=try await transport.read(sample.connection,access:sample.access,workset:sample.key);XCTFail("Accepted oversized response") }catch{}
        do{_=try await transport.read(sample.connection,access:sample.access,workset:"../foreign");XCTFail("Accepted path injection") }catch{}
        do{_=try await transport.probe(sample.connection,token:"bad");XCTFail("Accepted malformed grant") }catch{}
    }
    @MainActor func testTranslatedPreviewOriginalAndCurrentPresentationKeepsFixedPositions() async throws {
        let sample=try OrderSamples.make(),peer=OrderScripted(sample),memory=OrderMemory(sample.access)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let state=OrderState(credentials:memory,store:OrderIntentStore(root:root),transport:peer);state.authority={sample.connection}
        let client=ClientState(keychain:OrderEmptyServer());await state.connect(sample.connection);await state.choose(sample.key)
        state.move(sample.current.order[2],-1);await state.showPreview()
        for language in ["en","nl","de","fr","es"] {
            for key in ["title","grant","choose","current","proposed","fixed","moveable","up","down","preview","confirm","reason","cancel","original","roles","consequences","stale","denied","readonly","allowance"] {XCTAssertFalse(OrderCopy.text(key,language).isEmpty)}
            XCTAssertNotEqual(OrderCopy.text("ORDER_UNCHANGED",language),"ORDER_UNCHANGED")
            for width in [560.0,1180.0] {
                let host=NSHostingView(rootView:WorksetOrderView(state:state,client:client,grants:OrderEmptyDraft()).environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:width,height:900);host.layoutSubtreeIfNeeded();XCTAssertEqual(host.frame.width,width)
            }
        }
        let appliedState=OrderState(credentials:OrderMemory(sample.access),store:OrderIntentStore(root:root.appendingPathComponent("applied")),transport:OrderScripted(sample));appliedState.authority={sample.connection}
        await appliedState.connect(sample.connection);await appliedState.choose(sample.key);appliedState.move(sample.current.order[2],-1);await appliedState.showPreview();await appliedState.confirm(reason:"Own deliberate source presentation case")
        XCTAssertEqual(appliedState.status,"applied");XCTAssertEqual(appliedState.current?.fixed,1)
        let appliedHost=NSHostingView(rootView:WorksetOrderView(state:appliedState,client:client,grants:OrderEmptyDraft()));appliedHost.frame=NSRect(x:0,y:0,width:560,height:900);appliedHost.layoutSubtreeIfNeeded()
        XCTAssertEqual(sample.current.fixed,1)
        let original=NSHostingView(rootView:WorksetOrderView(state:state,client:client,grants:OrderEmptyDraft()));original.frame=NSRect(x:0,y:0,width:560,height:900);original.layoutSubtreeIfNeeded()
        state.invalidate();let unavailable=NSHostingView(rootView:WorksetOrderView(state:state,client:client,grants:OrderEmptyDraft()));unavailable.frame=NSRect(x:0,y:0,width:560,height:900);unavailable.layoutSubtreeIfNeeded()
    }
}
private final class OrderKeychainBackend:@unchecked Sendable {
    let lock=NSLock();var stored:Data?;var failure:OSStatus?;var services:[String]=[]
    var operations:DraftKeychainOperations {
        .init(copy:{ q in self.lock.withLock {
            self.services.append((q as! [CFString:Any])[kSecAttrService] as! String)
            if let failure=self.failure{return(failure,nil)};return self.stored.map{(errSecSuccess,$0)} ?? (errSecItemNotFound,nil)
        }},update:{_,a in self.lock.withLock{
            if let failure=self.failure{return failure};guard self.stored != nil else{return errSecItemNotFound};self.stored=(a as! [CFString:Any])[kSecValueData] as? Data;return errSecSuccess
        }},add:{q in self.lock.withLock{
            if let failure=self.failure{return failure};self.stored=(q as! [CFString:Any])[kSecValueData] as? Data;return errSecSuccess
        }},delete:{_ in self.lock.withLock{
            if let failure=self.failure{return failure};self.stored=nil;return errSecSuccess
        }})
    }
}
extension WorksetOrderTests {
    func testSeparatePrivateKeychainAndRejectionJournalAreFailClosed() throws {
        let sample=try OrderSamples.make(),backend=OrderKeychainBackend(),keychain=OrderKeychain(operations:backend.operations)
        XCTAssertNil(try keychain.load());try keychain.save(sample.access);XCTAssertEqual(try keychain.load(),sample.access);try keychain.save(sample.access)
        XCTAssertEqual(Set(backend.services),["com.pcvantol.workspace.native-client.workset-order.v1"])
        backend.failure=errSecInteractionNotAllowed;XCTAssertThrowsError(try keychain.load());XCTAssertThrowsError(try keychain.save(sample.access));XCTAssertThrowsError(try keychain.forget())
        backend.failure=nil;backend.stored=Data("corrupt".utf8);XCTAssertThrowsError(try keychain.load());try keychain.forget();XCTAssertNil(try keychain.load())
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=OrderIntentStore(root:root),raw=try OrderWire.object(sample.applied),request=try JSONSerialization.data(withJSONObject:raw["original_request"]!),intent=OrderIntent(scopeKey:sample.access.key(sample.key,draft:sample.connection.draftGrant),operation:raw["operation_id"] as! String,workset:sample.key,request:request)
        XCTAssertThrowsError(try store.markRejected(intent,code:"ORDER_PREVIEW_STALE"));try store.save(intent);XCTAssertFalse(try store.isRejected(intent));try store.markRejected(intent,code:"ORDER_PREVIEW_STALE");XCTAssertTrue(try store.isRejected(intent));XCTAssertEqual(try store.load(intent.scopeKey),intent)
        XCTAssertThrowsError(try store.load("../foreign"))
    }
}
extension WorksetOrderTests {
    func testRejectedArchiveCannotConsumeSixteenFiniteAmendmentSlots() throws {
        let sample=try OrderSamples.make(),root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=OrderIntentStore(root:root),scope=sample.access.key(sample.key,draft:sample.connection.draftGrant)
        var command=try OrderWire.object(OrderWire.command(sample.preview,operation:"rejected-original",workset:sample.key,reason:"Own exact finite recovery guard"))
        let rejected=OrderIntent(scopeKey:scope,operation:"rejected-original",workset:sample.key,request:try JSONSerialization.data(withJSONObject:command));try store.save(rejected);try store.markRejected(rejected,code:"ORDER_PREVIEW_STALE")
        for index in 1...16 {
            let operation="approved-original-"+String(index);command["operation_id"]=operation
            try store.save(OrderIntent(scopeKey:scope,operation:operation,workset:sample.key,request:JSONSerialization.data(withJSONObject:command)))
        }
        XCTAssertEqual(try store.load(scope)?.operation,"approved-original-16");XCTAssertEqual(try store.rejectionCode(rejected),"ORDER_PREVIEW_STALE")
        command["operation_id"]="seventeenth-active"
        XCTAssertThrowsError(try store.save(OrderIntent(scopeKey:scope,operation:"seventeenth-active",workset:sample.key,request:JSONSerialization.data(withJSONObject:command))))
        XCTAssertEqual(try store.load(scope)?.operation,"approved-original-16")
    }
}
