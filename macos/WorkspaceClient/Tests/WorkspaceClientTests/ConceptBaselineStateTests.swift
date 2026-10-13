import XCTest
import CryptoKit
import SwiftUI
import AppKit
@testable import WorkspaceClient

// Source-only protocol double. Installed R52/native qualification is separate.
private final class BaselineFixture:ConceptBaselineServing,@unchecked Sendable {
    let concept:ProjectConcept
    var fail:ConceptError?
    var prepareFailure:Error?
    var expiry="2099-01-01T00:00:00Z"
    var permission=true
    var paths=["README.md"]
    var summary="Source-only template proposal"
    var binding="own-pairing"
    var created:[String:ConceptBaselineResult]=[:]
    var posts:[ConceptBaselineCommand]=[]
    var lose=false
    var hold=false
    var waiting:CheckedContinuation<ConceptBaselineResult,Error>?
    init(_ concept:ProjectConcept) {self.concept=concept}
    func access(_ c:ConceptConnection,concept:String) async throws -> ConceptBaselineAccess {
        if let fail {throw fail}
        return .init(contract_version:"workspace-concept-baseline/1",actor_id:self.concept.actor_id,context_id:c.access.projectID,concept_id:concept,binding_id:binding,producer_source:String(repeating:"a",count:40),source_revision:self.concept.revision,document_language:"en",can_prepare:permission,expires_at:expiry)
    }
    func history(_ c:ConceptConnection,concept:String) async throws -> ConceptBaselineHistory {
        if let fail {throw fail}
        return .init(contract_version:"workspace-concept-baseline/1",actor_id:self.concept.actor_id,context_id:c.access.projectID,concept_id:concept,binding_id:binding,producer_source:String(repeating:"a",count:40),operations:created.keys.sorted().map{.init(operation_id:$0,source_revision:1)})
    }
    func result(_ operation:String)->ConceptBaselineResult {
        let content="# Source-only fixture\n";let sha=SHA256.hash(data:Data(content.utf8)).map{String(format:"%02x",$0)}.joined()
        return .init(contract_version:"workspace-concept-baseline/1",actor_id:concept.actor_id,context_id:concept.context_id,concept_id:concept.id,operation_id:operation,source_revision:1,current_revision:concept.revision,source_digest:String(repeating:"a",count:64),producer_source:String(repeating:"a",count:40),binding_id:binding,unknown_fields:["users"],source_product:.init(name:concept.title,purpose:concept.notes,users:"Not supplied",non_goals:"Not supplied",constraints:"Not supplied",open_questions:["Who should this serve?"]),proposal:.init(contract_version:"forge-project-proposal-http/v1",instance_id:"producer",principal_id:"limited-actor",audience:"workspace",dossier_id:"private-dossier",operation_id:operation,plan_id:"proposal-source-only",proposal_kind:"pb-render/1.0",request_digest:String(repeating:"a",count:64),record_digest:String(repeating:"a",count:64),result:.init(state:"PROPOSED_NOT_APPROVED",original_contract_version:"pb-render/1.0",summary:summary,artifacts:paths.sorted().map{.init(path:$0,mode:420,sha256:sha,content:content)},observations:"SUPPLIED_UNVERIFIED",repository_quality:"NOT_ASSESSED"),read_only_result:true,approval:"NOT_PERFORMED",registration:"NOT_PERFORMED"),status:"PROPOSAL_PROJECT_NOT_CONFIGURED")
    }
    func prepare(_ c:ConceptConnection,concept:String,command:ConceptBaselineCommand) async throws -> ConceptBaselineResult {
        posts.append(command);if let prepareFailure {throw prepareFailure};if let fail {throw fail};let value=result(command.operation_id);created[command.operation_id]=value
        if lose {throw ConceptError.unavailable};return value
    }
    func read(_ c:ConceptConnection,concept:String,operation:String) async throws -> ConceptBaselineResult {
        if hold {return try await withCheckedThrowingContinuation{waiting=$0}}
        if let fail {throw fail};guard let value=created[operation] else {throw ConceptError.notFound};return value
    }
}
final class ConceptBaselineStateTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"context",token:String(repeating:"c",count:43)),bearer:"source-only")
    func source()->ProjectConcept {ConceptBaselineTests().concept()}
    func testNilDescriptionIsExplicitNullAndOriginalBytesRoundtrip() throws {
        let command=ConceptBaselineCommand(operation_id:String(repeating:"a",count:32),expected_revision:1,description:nil)
        let data=try JSONEncoder().encode(command);let object=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(Set(object.keys),["operation_id","expected_revision","description"]);XCTAssertTrue(object["description"] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(ConceptBaselineCommand.self,from:data),command)
    }
    @MainActor func testLostResponseSameOperationAfterStateRestartAndOriginalRead() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});XCTAssertEqual(state.phase,"ready")
        let draft=try ConceptBaselineDraftSource.capture(concept,choice:nil,dirty:false);fixture.lose=true
        await state.prepare(draft,concept:concept,current:{active});let original=try XCTUnwrap(state.pending)
        XCTAssertEqual(state.phase,"offline");XCTAssertNil(state.result);XCTAssertEqual(fixture.posts.count,1);state.conceal()
        let restarted=ConceptBaselineState(transport:fixture,root:root);await restarted.load(concept,current:{active})
        XCTAssertEqual(restarted.pending?.command,original.command);fixture.lose=false
        await restarted.prepare(original.source,concept:concept,current:{active})
        XCTAssertEqual(restarted.result?.operation_id,original.command.operation_id);XCTAssertEqual(fixture.posts.count,1);XCTAssertNil(restarted.pending)
        restarted.conceal();await restarted.load(concept,current:{active});XCTAssertNil(restarted.pending)
        await restarted.open(original.command.operation_id,concept:concept,current:{active});XCTAssertEqual(restarted.result?.operation_id,original.command.operation_id);restarted.conceal()
    }
    @MainActor func testSelectionChangedWhileOriginalReadWaitsCannotPostOrPublish() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});fixture.hold=true;let draft=try ConceptBaselineDraftSource.capture(concept,choice:nil,dirty:false)
        let task=Task{await state.prepare(draft,concept:concept,current:{active})}
        for _ in 0..<100 {if fixture.waiting != nil {break};await Task.yield()}
        XCTAssertNotNil(fixture.waiting);state.conceal();fixture.waiting?.resume(throwing:ConceptError.notFound);await task.value
        XCTAssertEqual(fixture.posts.count,0);XCTAssertNil(state.pending);XCTAssertNil(state.result)
    }
    @MainActor func testExpiryAndChangedOwnConnectionConceal() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        fixture.expiry=ISO8601DateFormatter().string(from:Date().addingTimeInterval(2))
        await state.load(concept,current:{active});XCTAssertNotNil(state.access)
        try await Task.sleep(for:.seconds(2.2));XCTAssertNil(state.access);XCTAssertNil(state.result)
        fixture.expiry="2099-01-01T00:00:00Z";var current=active
        await state.load(concept,current:{current});current=ConceptConnection(access:active.access,bearer:"changed")
        await state.open(String(repeating:"f",count:32),concept:concept,current:{current});XCTAssertNil(state.result)
        try await Task.sleep(for:.seconds(3.2));XCTAssertNil(state.access);state.conceal()
    }
    @MainActor func testFailuresReadonlyAndInvalidJournalStaySafe() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        for error in [ConceptError.denied,.invalid,.unavailable,.notFound,.conflict] {
            fixture.fail=error;await state.load(concept,current:{active});XCTAssertNil(state.result)
        }
        fixture.fail=nil;fixture.permission=false;await state.load(concept,current:{active})
        let draft=try ConceptBaselineDraftSource.capture(concept,choice:nil,dirty:false);await state.prepare(draft,concept:concept,current:{active});XCTAssertEqual(fixture.posts.count,0)
        fixture.permission=true;try state.records.save(Data("corrupt".utf8),key:state.key(active,concept));await state.load(concept,current:{active});XCTAssertEqual(state.phase,"invalid");state.conceal()
    }
    @MainActor func testDefinitiveSourceRejectionRetainsOriginalAndExplicitFreshRequest() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});let draft=try ConceptBaselineDraftSource.capture(concept,choice:nil,dirty:false)
        fixture.prepareFailure=ConceptBaselineError.sourceRejected
        await state.prepare(draft,concept:concept,current:{active});let original=try XCTUnwrap(state.pending)
        XCTAssertEqual(state.phase,"sourceRejected");XCTAssertEqual(fixture.created.count,0)
        await state.retireRejected(concept:concept,current:{active});XCTAssertNil(state.pending);XCTAssertEqual(state.phase,"ready")
        let archiveKey=SHA256.hash(data:Data((original.key+"\n"+original.command.operation_id).utf8)).map{String(format:"%02x",$0)}.joined()
        let saved=try JSONDecoder().decode(ConceptBaselineState.Journal.self,from:XCTUnwrap(state.records.load(archiveKey)))
        XCTAssertEqual(saved.command,original.command);XCTAssertFalse(saved.completed)
        fixture.prepareFailure=nil;await state.prepare(draft,concept:concept,current:{active})
        XCTAssertNotEqual(state.result?.operation_id,original.command.operation_id);XCTAssertEqual(fixture.created.count,1);state.conceal()
    }
    @MainActor func testUncertainRequestCannotBeRetiredAsRejected() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});fixture.lose=true
        await state.prepare(try .capture(concept,choice:nil,dirty:false),concept:concept,current:{active});let original=try XCTUnwrap(state.pending)
        await state.retireRejected(concept:concept,current:{active});XCTAssertEqual(state.pending?.command,original.command);XCTAssertEqual(fixture.posts.count,1);state.conceal()
    }

    @MainActor func testActualResultPresentationGroupsAndOriginalRecoveryAtNarrowWideWidths() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source();let fixture=BaselineFixture(concept);fixture.paths=["README.md","docs/product/VISION.md","docs/architecture/ARCHITECTURE.md","docs/roadmap/ROADMAP.md","AGENTS.md","BOOTSTRAP.md","engineering/project-contract.json"]
        fixture.summary="Source-only long ledger\n"+(0..<37).map{"file-\($0) sha256:"+String(repeating:"a",count:64)}.joined(separator:"\n")
        let state=ConceptBaselineState(transport:fixture,root:root);let active=connection
        await state.load(concept,current:{active});let draft=try ConceptBaselineDraftSource.capture(concept,choice:nil,dirty:false)
        await state.prepare(draft,concept:concept,current:{active});XCTAssertNotNil(state.result)
        XCTAssertEqual(state.result?.proposal.result.summary,fixture.summary)
        let compact=NSHostingView(rootView:ConceptBaselinePanel(state:state,concept:concept,dirty:false,current:{active}))
        compact.frame=NSRect(x:0,y:0,width:520,height:900);compact.layoutSubtreeIfNeeded()
        XCTAssertLessThan(compact.fittingSize.height,900,"Authentic long ledger must not displace primary questions/documents by default")
        for language in ConceptBaselineCopy.languages {
            for width in [520.0,900.0] {
                let host=NSHostingView(rootView:ScrollView {ConceptBaselinePanel(state:state,concept:concept,dirty:false,current:{active})}.environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:width,height:900);host.layoutSubtreeIfNeeded();_=host.fittingSize
                XCTAssertEqual(host.frame.width,width)
            }
        }
        state.conceal();let recoveryFixture=BaselineFixture(concept);recoveryFixture.prepareFailure=ConceptBaselineError.sourceRejected
        let recovery=ConceptBaselineState(transport:recoveryFixture,root:root.appendingPathComponent("recovery"))
        await recovery.load(concept,current:{active})
        await recovery.prepare(draft,concept:concept,current:{active});XCTAssertNotNil(recovery.pending)
        for phase in ["capacity","sourceRejected","offline","conflict","invalid","notFound","unavailable"] {
            recovery.phase=phase
            let host=NSHostingView(rootView:ConceptBaselinePanel(state:recovery,concept:concept,dirty:false,current:{active}))
            host.frame=NSRect(x:0,y:0,width:520,height:900);host.layoutSubtreeIfNeeded();_=host.fittingSize
        }
        recovery.conceal();state.conceal()
    }

    @MainActor func testOriginalLossAfterLostSuccessFailsClosedWithoutAnotherPost() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source(),active=connection;let fixture=BaselineFixture(concept)
        let state=ConceptBaselineState(transport:fixture,root:root)
        await state.load(concept,current:{active});fixture.lose=true
        await state.prepare(try .capture(concept,choice:nil,dirty:false),concept:concept,current:{active})
        let original=try XCTUnwrap(state.pending);state.conceal()
        try FileManager.default.removeItem(at:root.appendingPathComponent("concept-baseline-"+original.key+".json"))
        let restarted=ConceptBaselineState(transport:fixture,root:root)
        await restarted.load(concept,current:{active});XCTAssertEqual(restarted.phase,"unavailable");XCTAssertNil(restarted.access)
        await restarted.prepare(original.source,concept:concept,current:{active});XCTAssertEqual(fixture.posts.count,1)
        XCTAssertNotNil(try restarted.records.load(restarted.allocationKey(original.key)));restarted.conceal()
    }
    func testBoundedPrivatePublicationPreservesOriginalAndHandlesLargeValidSource() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let store=PrivateLocalRecordStore(root:root,namespace:"concept-baseline")
        let first=String(repeating:"a",count:64),second=String(repeating:"b",count:64)
        try store.saveBounded(Data("original".utf8),key:first,maximumRecords:1,maximumBytes:8)
        XCTAssertThrowsError(try store.saveBounded(Data("second".utf8),key:second,maximumRecords:1,maximumBytes:8))
        XCTAssertThrowsError(try store.saveBounded(Data(repeating:0,count:9),key:first,maximumRecords:1,maximumBytes:8))
        XCTAssertEqual(try store.load(first),Data("original".utf8));XCTAssertNil(try store.load(second))
        let notes=String(repeating:"😀",count:10000),purpose=String(repeating:"😀",count:4096)
        let source=ConceptBaselineDraftSource(conceptID:String(repeating:"a",count:32),revision:1,title:"Source",originalNotes:notes,chosenPurpose:purpose)
        let journal=ConceptBaselineState.Journal(key:first,concept_id:source.conceptID,command:.init(operation_id:String(repeating:"c",count:32),expected_revision:1,description:purpose),source:source,binding_id:"binding",producer_source:String(repeating:"d",count:40),completed:false)
        let encoded=try JSONEncoder().encode(journal);XCTAssertGreaterThan(encoded.count,65536)
        try store.saveBounded(encoded,key:first);XCTAssertEqual(try store.load(first),encoded)
        XCTAssertEqual(try JSONDecoder().decode(ConceptBaselineState.Journal.self,from:encoded).source.originalNotes,notes)
        XCTAssertThrowsError(try store.saveBounded(Data(repeating:0,count:131073),key:second))
    }
    @MainActor func testPeerMonitorConcealsButPreservesUnavailableErrorClassification() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source(),active=connection;let fixture=BaselineFixture(concept)
        let state=ConceptBaselineState(transport:fixture,root:root)
        await state.load(concept,current:{active});fixture.fail = .unavailable
        try await Task.sleep(for:.seconds(3.3));XCTAssertNil(state.access);XCTAssertEqual(state.phase,"unavailable");state.conceal()
    }

    @MainActor func testFullNativeAdmissionReportsLocalCapacityBeforeAnyPost() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let concept=source(),active=connection;let fixture=BaselineFixture(concept)
        let state=ConceptBaselineState(transport:fixture,root:root)
        await state.load(concept,current:{active})
        for index in 0..<256 {try state.records.saveBounded(Data("retained".utf8),key:String(format:"%064x",index))}
        await state.prepare(try .capture(concept,choice:nil,dirty:false),concept:concept,current:{active})
        XCTAssertEqual(state.phase,"capacity");XCTAssertEqual(fixture.posts.count,0);XCTAssertNil(state.pending)
        for index in 0..<256 {XCTAssertEqual(try state.records.load(String(format:"%064x",index)),Data("retained".utf8))}
        state.failure(AdvisoryError.state("UNKNOWN"));XCTAssertEqual(state.phase,"unavailable");state.conceal()
    }

}
