import XCTest
import Foundation
import SwiftUI
@testable import WorkspaceClient

private final class AdoptionURLProtocol:URLProtocol,@unchecked Sendable {
    nonisolated(unsafe) static var reply:((URLRequest)throws->(Int,Data,String))?
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading() {
        do {let(code,data,type)=try Self.reply!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:["Content-Type":type])!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading() {}
}
final class ConceptAdoptionContractTests:XCTestCase {
    let connection=ConceptBaselineTransportTests().connection
    let concept=ConceptBaselineTests().concept()
    let source=String(repeating:"e",count:32)
    func observed() throws->[String:Any] {try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/inspection-adoption-observed.json"))) as! [String:Any]}
    func scopedRaw() throws->[String:Any] {var raw=try observed();raw["actor_id"]=concept.actor_id;raw["context_id"]=concept.context_id;raw["concept_id"]=concept.id;raw["binding_id"]=source;return raw}
    func scoped() throws->ConceptAdoptionResult {try JSONDecoder().decode(ConceptAdoptionResult.self,from:JSONSerialization.data(withJSONObject:scopedRaw()))}
    @MainActor func testObservedOriginalContentsAndIntegrityRejectTampering() throws {
        let value=try scoped();try value.validate(connection,concept:concept,source:source,operation:value.operation_id)
        XCTAssertTrue(value.document!.entries.contains{$0.mapping_source.content?.contains("Bestaande Nederlandse productrichting") == true})
        XCTAssertTrue(value.document!.entries.contains{$0.operation=="PROPOSE_ADDITION"});XCTAssertTrue(value.document!.entries.contains{$0.operation=="INSUFFICIENT_INFORMATION"})
        for (key,replacement) in [("actor_id","foreign"),("producer_source",String(repeating:"0",count:40)),("binding_id","foreign")] {var raw=try scopedRaw();raw[key]=replacement;let bad=try JSONDecoder().decode(ConceptAdoptionResult.self,from:JSONSerialization.data(withJSONObject:raw));XCTAssertThrowsError(try bad.validate(connection,concept:concept,source:source,operation:bad.operation_id))}
        for path in ["../private","/private","docs/../private","docs//file", "docs\\file", String(repeating:"a",count:257)] {XCTAssertFalse(ConceptAdoptionState.safeReference(path))}
    }
    func transport()->ConceptAdoptionTransport {let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[AdoptionURLProtocol.self];return .init(configuration:c)}
    func testOwnHeadersClosedPathsAndOriginalRead() async throws {
        let t=transport();let active=connection;let id=concept.id;let src=source;let packet=try scoped()
        AdoptionURLProtocol.reply={req in
            XCTAssertEqual(req.value(forHTTPHeaderField:"Authorization"),"Bearer "+active.bearer);XCTAssertEqual(req.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),active.access.token);XCTAssertNil(req.value(forHTTPHeaderField:"X-Forge-Inspection-Audience"))
            let path=req.url!.path;let object:[String:Any]
            if path.hasSuffix("/sources") {object=["contract_version":"workspace-concept-adoption/1","actor_id":"alice","context_id":"context","concept_id":id,"sources":[]]}
            else if path.hasSuffix("/access") {object=["contract_version":"workspace-concept-adoption/1","actor_id":"alice","context_id":"context","concept_id":id,"binding_id":src,"producer_source":ConceptAdoptionResult.pin,"source_revision":1,"can_prepare":true,"expires_at":"2099-01-01T00:00:00Z"]}
            else if path.hasSuffix("/operations") {object=["operations":[]]}
            else {return(200,try JSONSerialization.data(withJSONObject:self.observed()),"application/json")}
            return(200,try JSONSerialization.data(withJSONObject:object),"application/json")
        }
        _=try await t.sources(active,concept:id);_=try await t.access(active,concept:id,source:src);_=try await t.history(active,concept:id,source:src);_=try await t.read(active,concept:id,source:src,operation:packet.operation_id)
        do {_=try await t.read(active,concept:id,source:src,operation:"../foreign");XCTFail()}catch ConceptError.invalid {}
        do {_=try await t.sources(active,concept:"foreign");XCTFail()}catch ConceptError.invalid {}
    }
    func testDefinitiveRejectionNeverInferredFrom404OrOther409() async throws {
        let t=transport();let command=ConceptAdoptionCommand(operation_id:concept.id,expected_revision:1,requested_artifacts:["docs/product/VISION.md"],mappings:[])
        AdoptionURLProtocol.reply={_ in (409,Data("{\"error\":\"ADOPTION_SOURCE_REJECTED_BEFORE_CAPTURE\"}".utf8),"application/json")}
        do {_=try await t.prepare(connection,concept:concept.id,source:source,command:command);XCTFail()}catch ConceptAdoptionError.sourceRejected {}
        do {_=try await t.read(connection,concept:concept.id,source:source,operation:concept.id);XCTFail()}catch ConceptError.conflict {}
        AdoptionURLProtocol.reply={_ in (403,Data("{\"error\":\"DENIED\",\"reason\":\"ADOPTION_SOURCE_ARCHIVED_BEFORE_CAPTURE\"}".utf8),"application/json")}
        do {_=try await t.prepare(connection,concept:concept.id,source:source,command:command);XCTFail()}catch ConceptAdoptionError.sourceRejected {}
        do {_=try await t.read(connection,concept:concept.id,source:source,operation:concept.id);XCTFail()}catch ConceptError.denied {}
        for code in ["ADOPTION_CAPACITY","INSPECTION_ADOPTION_CAPACITY_EXHAUSTED"] {
            AdoptionURLProtocol.reply={_ in (409,try JSONSerialization.data(withJSONObject:["error":code]),"application/json")}
            do {_=try await t.prepare(connection,concept:concept.id,source:source,command:command);XCTFail()}catch ConceptAdoptionError.capacity {}
            AdoptionURLProtocol.reply={_ in (503,try JSONSerialization.data(withJSONObject:["error":code]),"application/json")}
            do {_=try await t.prepare(connection,concept:concept.id,source:source,command:command);XCTFail()}catch ConceptError.unavailable {}
        }
        for code in [401,403,404,400,409,503] {
            AdoptionURLProtocol.reply={_ in (code,Data("{}".utf8),"application/json")}
            do {_=try await t.access(connection,concept:concept.id,source:source);XCTFail()}catch ConceptError.denied {XCTAssertTrue([401,403].contains(code))}catch ConceptError.notFound {XCTAssertEqual(code,404)}catch ConceptError.invalid {XCTAssertEqual(code,400)}catch ConceptError.conflict {XCTAssertEqual(code,409)}catch ConceptError.unavailable {XCTAssertEqual(code,503)}
        }
        for (data,type) in [(Data(),"text/html"),(Data(repeating:120,count:1150001),"application/json")] {AdoptionURLProtocol.reply={_ in (200,data,type)};do{_=try await t.sources(connection,concept:concept.id);XCTFail()}catch ConceptError.invalid {}}
    }
    @MainActor func testHonestCategoriesAndFiveLanguageLayoutsAtBothWidths() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let fixture=AdoptionFixture(concept);let state=ConceptAdoptionState(transport:fixture,root:root);let result=try scoped();let active=connection
        state.sources=[.init(id:source,label:"Synthetic owner setup",source_options:["docs/RICHTING.md"],setup_metadata_not_observed:true,can_prepare:true,expires_at:"2099-01-01T00:00:00Z")];state.source=source;state.result=result
        state.history=[.init(operation_id:result.operation_id,source_revision:1)]
        for (key,values) in ConceptAdoptionCopy.values {XCTAssertEqual(values.count,5);XCTAssertTrue(values.allSatisfy{!$0.isEmpty},key)}
        for language in ["en","nl","de","fr","es"] {
            XCTAssertFalse(ConceptAdoptionCopy.text("unknown",language).isEmpty)
            for code in ["EXCLUDED_OR_UNCOVERED","NOT_OBSERVED","R51_DOCUMENT_CONTENT_LIMIT_EXCEEDED","SOURCE_BYTES_NOT_SUPPLIED","MAPPING_SOURCE_NOT_COMPARABLE","EXISTING_IDENTITY_CONFLICT","IDENTITY_REFERENCE_CONFLICT","CANONICAL_AND_MAPPING_DOCUMENT_CONFLICT","UNRECOGNIZED_REASON"] {XCTAssertFalse(ConceptAdoptionCopy.reason(code,language).isEmpty)}
            XCTAssertNotEqual(ConceptAdoptionCopy.text("referenceNone",language),ConceptAdoptionCopy.text("choose",language))
            for width in [520.0,900.0] {for entry in result.document!.entries {state.expandedDocument=entry.id
                let host=NSHostingView(rootView:ConceptAdoptionPanel(state:state,concept:concept,dirty:false,current:{active}).environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:width,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize;XCTAssertEqual(host.frame.width,width)
            }}
        }
        // The Server can know revision2 while this selected Client still holds revision1.
        // Render that real contract case in every UI language, including its honest warning.
        var newer=try scopedRaw();newer["current_revision"]=concept.revision+1
        state.result=try JSONDecoder().decode(ConceptAdoptionResult.self,from:JSONSerialization.data(withJSONObject:newer))
        XCTAssertEqual(state.result?.source_revision,concept.revision)
        XCTAssertEqual(state.result?.current_revision,concept.revision+1)
        for language in ["en","nl","de","fr","es"] {
            let host=NSHostingView(rootView:ConceptAdoptionPanel(state:state,concept:concept,dirty:false,current:{active}).environment(\.locale,Locale(identifier:language)))
            host.frame=NSRect(x:0,y:0,width:520,height:780);host.layoutSubtreeIfNeeded();XCTAssertGreaterThan(host.fittingSize.height,0)
        }
        for phase in ["empty","access","unavailable","conflict","invalid","notFound","pending","sourceRejected","capacity"] {
            state.phase=phase;state.pending = .init(key:"rejected",concept:concept.id,source:source,command:.init(operation_id:concept.id,expected_revision:1,requested_artifacts:["docs/product/VISION.md"],mappings:[]),complete:false,rejected:true)
            let host=NSHostingView(rootView:ConceptAdoptionPanel(state:state,concept:concept,dirty:true,current:{active}));host.frame=NSRect(x:0,y:0,width:520,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
        }
        XCTAssertEqual(ConceptAdoptionCopy.text("missing-copy-key","nl"),"")
        XCTAssertEqual(ConceptAdoptionCopy.text("title","unknown"),ConceptAdoptionCopy.text("title","en"));state.conceal()
    }
}
