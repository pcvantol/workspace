import XCTest
import Foundation
@testable import WorkspaceClient

private final class ContentURLProtocol:URLProtocol,@unchecked Sendable {
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
@MainActor final class ProposalContentTransportTests:XCTestCase {
    func transport()->ProposalContentTransport {let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[ContentURLProtocol.self];return ProposalContentTransport(configuration:c)}
    func testExactOwnHeadersOriginalEndpointsAndNoPeerCredentialInClient()async throws {
        let peer=try ContentFixture();let data=try JSONSerialization.data(withJSONObject:peer.object());let c=CompareFixture.connection;let id=CompareFixture.concept.id;let t=transport();let op=CompareFixture.second
        ContentURLProtocol.reply={request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+c.bearer);XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),c.access.token);XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Instance"),c.access.instanceID)
            XCTAssertNil(request.value(forHTTPHeaderField:"X-Forge-Content-Audience"));XCTAssertTrue(request.url!.path.hasPrefix("/v1/proposal-content/"+id+"/"));return (200,data,"application/json")
        }
        _=try await t.proposal(c,concept:id,source:peer.source.operation_id)
        _=try await t.original(c,concept:id,operation:op)
        let command=ProposalContentCommand(operation_id:op,source_operation_id:peer.source.operation_id,expected_concept_revision:3,selection_digest:String(repeating:"a",count:64),role:"BUSINESS",decision:"REQUEST_CHANGES",reason:"Original synthetic reason",acknowledged_open_points:peer.source.source_product.open_questions)
        _=try await t.decide(c,concept:id,command:command)
        do {_=try await t.proposal(c,concept:"../bad",source:op);XCTFail()}catch ConceptError.invalid {}
        do {_=try await t.original(c,concept:id,operation:"bad");XCTFail()}catch ConceptError.invalid {}
    }
    func testActualStatusAndClosedErrorMeaningNo401403UnsupportedOr503NotFound()async throws {
        let t=transport();let c=CompareFixture.connection;let id=CompareFixture.concept.id;let op=CompareFixture.first
        for status in [401,403] {
            ContentURLProtocol.reply={_ in (status,Data("{\"error\":\"CONTENT_PROFILE_UNSUPPORTED\"}".utf8),"application/json")}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ConceptError.denied {}
        }
        for code in ["CONTENT_NOT_FOUND","CONTENT_OWN_NOT_FOUND"] {
            ContentURLProtocol.reply={_ in (404,Data(("{\"error\":\""+code+"\"}").utf8),"application/json")}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ConceptError.notFound {}
        }
        for (status,code) in [(503,"CONTENT_NOT_FOUND"),(404,"CONTENT_ROUTE_UNSUPPORTED"),(500,"OTHER")] {
            ContentURLProtocol.reply={_ in (status,Data(("{\"error\":\""+code+"\"}").utf8),"application/json")}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ConceptError.unavailable {}
        }
        for code in ["CONTENT_DECISION_STALE","CONTENT_SUBJECT_CHANGED"] {
            ContentURLProtocol.reply={_ in (409,Data(("{\"error\":\""+code+"\"}").utf8),"application/json")}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ConceptError.conflict {}
        }
        ContentURLProtocol.reply={_ in (409,Data("{\"error\":\"CONTENT_PROFILE_UNSUPPORTED\"}".utf8),"application/json")}
        do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ProposalContentError.unsupportedProfile {}
        for code in ["CONTENT_DECISION_CAPACITY","CONTENT_STORAGE_CAPACITY"] {
            ContentURLProtocol.reply={_ in (409,Data(("{\"error\":\""+code+"\"}").utf8),"application/json")}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ProposalContentError.capacity {}
        }
        for (data,type) in [(Data("{}".utf8),"text/html"),(Data(repeating:32,count:1150001),"application/json")] {
            ContentURLProtocol.reply={_ in (200,data,type)}
            do {_=try await t.original(c,concept:id,operation:op);XCTFail()}catch ConceptError.invalid {}
        }
    }
    func testExactProposalOriginalNullRevisionHumanAndEffectsCannotBeSubstituted()throws {
        let peer=try ContentFixture();let c=CompareFixture.connection;let concept=CompareFixture.concept;let source=peer.source
        try peer.result().validate(c,concept:concept,source:source)
        for (key,bad) in [("actor_id","bob" as Any),("source_operation_id",CompareFixture.second),("current_revision",4),("roles",["OWNER"])] {
            var object=peer.object();object[key]=bad
            XCTAssertThrowsError(try peer.decode(object).validate(c,concept:concept,source:source))
        }
        for (key,bad) in [("effects_authorized",true as Any),("execution_readiness","READY"),("open_points",[String]()),("state","APPROVED"),("concept_revision_qualification","SUPPLIED")] {
            var object=peer.object();var decision=object["decision"] as! [String:Any];decision[key]=bad;object["decision"]=decision
            XCTAssertThrowsError(try peer.decode(object).validate(c,concept:concept,source:source))
        }
        var object=peer.object();var decision=object["decision"] as! [String:Any];var subject=decision["subject"] as! [String:Any];subject["concept_revision"]=3;decision["subject"]=subject;object["decision"]=decision
        XCTAssertThrowsError(try peer.decode(object).validate(c,concept:concept,source:source))
    }
}
