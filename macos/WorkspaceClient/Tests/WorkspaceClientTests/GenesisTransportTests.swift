import XCTest
import Foundation
@testable import WorkspaceClient

private final class GenesisURLProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var reply:((URLRequest)throws->(Int,Data,String))?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {
            let (code,data,type)=try Self.reply!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":type])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
@MainActor final class GenesisTransportTests:XCTestCase {
    func fixture()throws->[String:Any] {
        let url=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/genesis-source-only.json")
        return try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
    }
    func transport()->GenesisTransport {let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[GenesisURLProtocol.self];return GenesisTransport(configuration:c)}
    func testActualOwnHeadersClosedRoutesAndCanonicalOriginalPlanAndDecisionDigests()async throws {
        let fixture=try fixture();let peer=try GenesisFixture();let c=peer.connection;let t=transport();let concept=peer.concept.id;let op=String(repeating:"b",count:32)
        for name in ["access","result","decision_result"] {
            let data=try CanonicalJSON.data(fixture[name]!,ascii:false)
            GenesisURLProtocol.reply={req in
                XCTAssertEqual(req.value(forHTTPHeaderField:"Authorization"),"Bearer "+c.bearer);XCTAssertEqual(req.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),c.access.token);XCTAssertEqual(req.value(forHTTPHeaderField:"X-Workspace-Instance"),c.access.instanceID)
                XCTAssertNil(req.value(forHTTPHeaderField:"X-Forge-Bootstrap-Audience"));XCTAssertTrue(req.url!.path.hasPrefix("/v1/concept-genesis/"+concept+"/"));return (200,data,"application/json; charset=utf-8")
            }
            if name=="access" {_=try await t.access(c,concept:concept,source:peer.source.operation_id)}
            else {_=try await t.result(c,concept:concept,action:"operations",operation:op,body:nil)}
        }
        GenesisURLProtocol.reply={req in XCTAssertEqual(req.httpMethod,"POST");XCTAssertEqual(req.value(forHTTPHeaderField:"Content-Type"),"application/json");return (200,try CanonicalJSON.data(fixture["result"]!,ascii:false),"application/json")}
        _=try await t.result(c,concept:concept,action:"plans",operation:nil,body:Data("{}".utf8))
    }
    func testAuthConflictsUnknownAndMalformedErrorsNeverHealthyMissing()async throws {
        let peer=try GenesisFixture();let c=peer.connection;let t=transport()
        for status in [401,403,404,409,503] {
            let code=status==404 ? "GENESIS_NOT_FOUND":status==409 ? "GENESIS_CONFLICT":"GENESIS_STORAGE_UNAVAILABLE"
            GenesisURLProtocol.reply={_ in (status,Data(("{\"error\":\""+code+"\"}").utf8),"application/json")}
            do {_=try await t.result(c,concept:peer.concept.id,action:"operations",operation:String(repeating:"b",count:32),body:nil);XCTFail("Expected refusal")}
            catch let error as ConceptError {
                switch status {case 401,403:if case .denied=error {} else {XCTFail("denial required")}
                case 404:if case .notFound=error {} else {XCTFail("original missing required")}
                case 409:if case .conflict=error {} else {XCTFail("conflict required")}
                default:if case .unavailable=error {} else {XCTFail("unavailable required")}}
            }
        }
        for (status,body,type) in [(404,"{}","application/json"),(409,"{\"error\":\"WRONG_INSTANCE\"}","application/json"),(200,"{}","text/html"),(200,"{}","application/json")] {
            GenesisURLProtocol.reply={_ in (status,Data(body.utf8),type)}
            do {_=try await t.result(c,concept:peer.concept.id,action:"operations",operation:String(repeating:"b",count:32),body:nil);XCTFail("Malformed/foreign reply accepted")} catch {}
        }
        do {_=try await t.result(c,concept:"invalid",action:"apply",operation:nil,body:nil);XCTFail("Unknown effect route accepted")} catch {}
    }
    func testRehashedDocumentMutationAndPlanOrDecisionDigestMismatchRejected()async throws {
        let peer=try GenesisFixture();let t=transport();let raw=try fixture()
        for name in ["result","decision_result"] {
            var object=raw[name] as! [String:Any];var result=object["result"] as! [String:Any]
            if name=="result" {var p=result["plan"] as! [String:Any];p["plan_digest"]=String(repeating:"0",count:64);result["plan"]=p}
            else {var history=result["effect_history"] as! [[String:Any]];history[0]["decision_digest"]=String(repeating:"0",count:64);result["effect_history"]=history}
            object["result"]=result;let data=try CanonicalJSON.data(object,ascii:false);GenesisURLProtocol.reply={_ in (200,data,"application/json")}
            do {_=try await t.result(peer.connection,concept:peer.concept.id,action:"operations",operation:String(repeating:"b",count:32),body:nil);XCTFail("Corrupt original digest accepted")} catch {}
        }
        XCTAssertEqual(GenesisCopy.text("unknown_reason","nl"),GenesisCopy.text("unavailable","nl"))
    }
}
