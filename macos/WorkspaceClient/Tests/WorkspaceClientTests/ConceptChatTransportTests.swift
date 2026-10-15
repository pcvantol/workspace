import XCTest
@testable import WorkspaceClient

private final class ChatURLProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var reply:(URLRequest)throws->(Int,Data,String) = {_ in (503,Data(),"application/json")}
    nonisolated(unsafe) static var last:URLRequest?
    nonisolated(unsafe) static var lastBody:Data?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        Self.last=request;Self.lastBody=request.httpBody
        if Self.lastBody==nil,let stream=request.httpBodyStream {
            stream.open();defer{stream.close()};var bytes=[UInt8](repeating:0,count:65536)
            let count=stream.read(&bytes,maxLength:bytes.count);if count>=0 {Self.lastBody=Data(bytes.prefix(count))}
        }
        do {
            let (code,data,type)=try Self.reply(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:"HTTP/1.1",headerFields:["Content-Type":type])!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        } catch {client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
final class ConceptChatTransportTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"own-context",token:String(repeating:"c",count:43)),bearer:String(repeating:"d",count:43))
    func testRealTransportUsesOnlyOwningRoutesAndSeparatePinnedCredentials() async throws {
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[ChatURLProtocol.self];let transport=ConceptChatTransport(configuration:config)
        let seed=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("concept-chat-wire-fixture.json"))) as! [String:Any]
        let concept=try JSONDecoder().decode(ProjectConcept.self,from:JSONSerialization.data(withJSONObject:seed["concept"]!))
        let id=concept.id,c=connection
        ChatURLProtocol.reply={r in
            let value:Any
            if r.url!.path.hasSuffix("/access") {value=seed["access"]!}
            else if r.url!.path.hasSuffix("/briefing") {value=seed["briefing"]!}
            else if r.url!.path.hasSuffix("/history") {value=seed["history"]!}
            else if r.url!.path.hasSuffix("/adopt") {value=seed["adopted"]!}
            else {value=seed["result"]!}
            return (200,try JSONSerialization.data(withJSONObject:value),"application/json; charset=utf-8")
        }
        let cap=try await transport.access(c,concept:id);try cap.validate(c,concept)
        _=try await transport.briefing(c,concept:id);_=try await transport.history(c,concept:id)
        let command=ConceptChatCommand(operation_id:String(repeating:"b",count:32),turn_id:String(repeating:"c",count:32),expected_concept_revision:1,role:"BUSINESS",language:"nl",message:"Before sending, explicit user review")
        _=try await transport.send(c,concept:id,command:command)
        XCTAssertEqual(ChatURLProtocol.last?.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),c.access.token)
        XCTAssertEqual(ChatURLProtocol.last?.value(forHTTPHeaderField:"Authorization"),"Bearer "+c.bearer)
        XCTAssertEqual(ChatURLProtocol.last?.value(forHTTPHeaderField:"X-Workspace-Instance"),c.access.instanceID)
        XCTAssertEqual(ChatURLProtocol.last?.url?.path,"/v1/concept-chats/"+id+"/turns")
        XCTAssertEqual(try JSONDecoder().decode(ConceptChatCommand.self,from:try XCTUnwrap(ChatURLProtocol.lastBody)),command)
        _=try await transport.read(c,concept:id,operation:command.operation_id)
        _=try await transport.adopt(c,concept:id,command:.init(operation_id:String(repeating:"d",count:32),expected_revision:1,result_reference:command.operation_id,displayed_change_digest:String(repeating:"e",count:64)))
        for code in [401,403,404,409,503] {
            ChatURLProtocol.reply={_ in (code,Data("{\"error\":\"CHAT_NOT_FOUND\"}".utf8),"application/json")}
            do {_=try await transport.access(c,concept:id);XCTFail("accepted \(code)")}catch is ConceptError {}catch ConceptChatError.ownOriginalNotCaptured {}
        }
        ChatURLProtocol.reply={_ in (404,Data("{\"error\":\"OTHER\"}".utf8),"application/json")}
        do {_=try await transport.read(c,concept:id,operation:command.operation_id);XCTFail()}catch ConceptError.unavailable {}
        ChatURLProtocol.reply={_ in (400,Data("{\"error\":\"CHAT_INVALID_OR_UNAVAILABLE\"}".utf8),"application/json")}
        do {_=try await transport.send(c,concept:id,command:command);XCTFail()}catch ConceptChatError.inputRejected {}
        ChatURLProtocol.reply={_ in (400,Data("{\"error\":\"OTHER\"}".utf8),"application/json")}
        do {_=try await transport.send(c,concept:id,command:command);XCTFail()}catch ConceptError.unavailable {}
        for (data,type) in [(Data("bad".utf8),"application/json"),(Data(),"text/html"),(Data(repeating:120,count:1150001),"application/json")] {
            ChatURLProtocol.reply={_ in (200,data,type)}
            do {_=try await transport.access(c,concept:id);XCTFail()}catch ConceptError.invalid {}
        }
        do {_=try await transport.access(c,concept:"../other");XCTFail()}catch ConceptError.invalid {}
        do {_=try await transport.read(c,concept:id,operation:"../other");XCTFail()}catch ConceptError.invalid {}
    }
}
