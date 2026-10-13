import XCTest
import Foundation
@testable import WorkspaceClient

private final class BaselineURLProtocol:URLProtocol,@unchecked Sendable {
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
final class ConceptBaselineTransportTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"context",token:String(repeating:"c",count:43)),bearer:"own-synthetic")
    let identity=String(repeating:"a",count:32)
    func transport()->ConceptBaselineTransport {let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[BaselineURLProtocol.self];return ConceptBaselineTransport(configuration:configuration)}
    func cap()->[String:Any] {[
        "contract_version":"workspace-concept-baseline/1","actor_id":"alice","context_id":"context","concept_id":identity,"binding_id":"own-pairing","producer_source":String(repeating:"a",count:40),"source_revision":1,"document_language":"en","can_prepare":true,"expires_at":"2099-01-01T00:00:00Z"]}
    func testScopedAccessHistoryAndClosedPrepareOriginalRead() async throws {
        let transport=transport();let id=identity;let active=connection
        BaselineURLProtocol.reply={request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer "+active.bearer)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),active.access.token)
            XCTAssertNil(request.value(forHTTPHeaderField:"X-Forge-Proposal-Audience"))
            var object=self.cap()
            if request.url!.path.hasSuffix("operations") {object.removeValue(forKey:"can_prepare");object.removeValue(forKey:"source_revision");object.removeValue(forKey:"document_language");object.removeValue(forKey:"expires_at");object["operations"]=[]}
            if request.httpMethod=="POST" {
                let data:Data
                if let body=request.httpBody {data=body} else {let stream=try XCTUnwrap(request.httpBodyStream);stream.open();defer{stream.close()};var bytes=[UInt8](repeating:0,count:4096);let count=stream.read(&bytes,maxLength:bytes.count);data=Data(bytes.prefix(count))}
                let command=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any]);XCTAssertTrue(command["description"] is NSNull);XCTAssertEqual(Set(command.keys),["operation_id","expected_revision","description"])
                return (503,Data(),"application/json")
            }
            return (200,try JSONSerialization.data(withJSONObject:object),"application/json")
        }
        let access=try await transport.access(active,concept:id);XCTAssertEqual(access.concept_id,id)
        let history=try await transport.history(active,concept:id);XCTAssertEqual(history.operations.count,0)
        do {_=try await transport.prepare(active,concept:id,command:.init(operation_id:id,expected_revision:1,description:nil));XCTFail()}catch ConceptError.unavailable {}
        BaselineURLProtocol.reply={_ in (404,Data("{\"error\":\"PROPOSAL_NOT_FOUND\"}".utf8),"application/json")}
        do {_=try await transport.read(active,concept:id,operation:id);XCTFail()}catch ConceptError.notFound {}
        do {_=try await transport.read(active,concept:id,operation:"../other");XCTFail()}catch ConceptError.invalid {}
        do {_=try await transport.access(active,concept:"other");XCTFail()}catch ConceptError.invalid {}
    }
    func testDenialsConflictsInvalidJsonAndUnknown404StayDistinct() async throws {
        let transport=transport();let active=connection;let id=identity
        for code in [401,403] {
            BaselineURLProtocol.reply={_ in (code,Data(),"application/json")}
            do {_=try await transport.access(active,concept:id);XCTFail()}catch ConceptError.denied {}
        }
        for error in ["WRONG_INSTANCE","OTHER"] {
            BaselineURLProtocol.reply={_ in (409,Data(("{\"error\":\""+error+"\"}").utf8),"application/json")}
            do {_=try await transport.access(active,concept:id);XCTFail()}catch ConceptError.denied {}
        }
        BaselineURLProtocol.reply={_ in (409,Data("{\"error\":\"BASELINE_CONFLICT\"}".utf8),"application/json")}
        do {_=try await transport.prepare(active,concept:id,command:.init(operation_id:id,expected_revision:1,description:nil));XCTFail()}catch ConceptBaselineError.sourceRejected {}
        BaselineURLProtocol.reply={_ in (409,Data("{\"error\":\"PROPOSAL_IDEMPOTENCY_CONFLICT\"}".utf8),"application/json")}
        do {_=try await transport.prepare(active,concept:id,command:.init(operation_id:id,expected_revision:1,description:"Exact choice"));XCTFail()}catch ConceptError.conflict {}
        BaselineURLProtocol.reply={_ in (404,Data("{\"error\":\"OTHER\"}".utf8),"application/json")}
        do {_=try await transport.access(active,concept:id);XCTFail()}catch ConceptError.unavailable {}
        for (code,data,type) in [(400,Data(),"application/json"),(200,Data("corrupt".utf8),"application/json"),(200,Data(),"text/html"),(200,Data(repeating:120,count:1150001),"application/json")] {
            BaselineURLProtocol.reply={_ in (code,data,type)}
            do {_=try await transport.access(active,concept:id);XCTFail()}catch ConceptError.invalid {}
        }
        BaselineURLProtocol.reply={_ in throw URLError(.timedOut)}
        do {_=try await transport.access(active,concept:id);XCTFail()}catch is URLError {}
    }
}
