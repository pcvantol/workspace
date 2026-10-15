import XCTest
import Foundation
@testable import WorkspaceClient

@MainActor final class ProposalContentStateTests:XCTestCase {
    func temporary()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func stage(_ state:ProposalContentState,role:String="BUSINESS",choice:String="APPROVE_CONTENT") {state.stage(role:role,choice:choice,reason:"Synthetic explicit reason",acknowledged:true,concept:CompareFixture.concept)}
    func testSeparateRoleConfirmationsNoApprovalOrGenerationFromReadAndRestartRecovery()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c});XCTAssertEqual(state.result?.decision.state,"DECISION_NEEDED");XCTAssertEqual(peer.posts.count,0)
        stage(state);XCTAssertNotNil(state.confirmation);state.cancelConfirmation();XCTAssertEqual(peer.posts.count,0)
        stage(state);peer.lost=true;await state.confirm(peer.source,concept:concept,current:{c});XCTAssertEqual(peer.posts.count,1);let original=try XCTUnwrap(state.pending);XCTAssertNil(state.result);state.conceal()
        let restarted=ProposalContentState(transport:peer,root:root);await restarted.load(peer.source,concept:concept,current:{c});XCTAssertEqual(restarted.pending?.command,original.command)
        await restarted.recover(peer.source,concept:concept,current:{c});XCTAssertNil(restarted.pending);XCTAssertEqual(peer.posts.count,1);XCTAssertEqual(restarted.result?.decision.state,"DECISION_NEEDED")
        stage(restarted,role:"ARCHITECTURE");await restarted.confirm(peer.source,concept:concept,current:{c});XCTAssertEqual(peer.posts.count,2);XCTAssertEqual(restarted.result?.decision.state,"CONTENT_APPROVED");XCTAssertFalse(try XCTUnwrap(restarted.result).decision.effects_authorized);restarted.conceal()
    }
    func testStaleCASRequiresNewExplicitReviewAndRetainsOriginal()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c});stage(state);peer.stale=true;await state.confirm(peer.source,concept:concept,current:{c});let rejected=try XCTUnwrap(state.pending?.command.operation_id);XCTAssertEqual(state.phase,"conflict");XCTAssertEqual(peer.posts.count,0)
        peer.stale=false;await state.load(peer.source,concept:concept,current:{c});XCTAssertNil(state.pending);XCTAssertNil(state.confirmation);stage(state,choice:"REQUEST_CHANGES");XCTAssertNotEqual(state.confirmation?.operation_id,rejected)
        await state.confirm(peer.source,concept:concept,current:{c});XCTAssertEqual(state.result?.decision.state,"CHANGES_REQUESTED");state.conceal()
    }
    func testRoleAcknowledgementReasonAndSelectionFences()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c})
        for (role,choice,reason,ack) in [("OWNER","APPROVE_CONTENT","Reason",true),("BUSINESS","NO","Reason",true),("BUSINESS","APPROVE_CONTENT","",true),("BUSINESS","APPROVE_CONTENT","Reason",false),("BUSINESS","APPROVE_CONTENT",String(repeating:"x",count:2001),true)] {state.stage(role:role,choice:choice,reason:reason,acknowledged:ack,concept:concept);XCTAssertNil(state.confirmation)}
        stage(state);peer.binding="changed";await state.confirm(peer.source,concept:concept,current:{c});XCTAssertEqual(peer.posts.count,0);XCTAssertNil(state.confirmation);XCTAssertEqual(state.phase,"conflict");state.conceal()
    }
    func testLateSelectionAndAuthorityCannotPublishOrSend()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        peer.wait=true;let task=Task {await state.load(peer.source,concept:concept,current:{c})}
        while peer.waiting==nil {await Task.yield()};state.conceal();peer.waiting?.resume(returning:try peer.result());await task.value;XCTAssertNil(state.result)
        await state.load(peer.source,concept:concept,current:{c});stage(state);peer.failure=ConceptError.denied;await state.confirm(peer.source,concept:concept,current:{c});XCTAssertEqual(state.phase,"access");XCTAssertNil(state.result);XCTAssertEqual(peer.posts.count,0);state.conceal()
    }
    func testErrorStatesAllocationLossAndExpiry()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        for (error,phase) in [(ConceptError.invalid as Error,"invalid"),(ConceptError.unavailable,"unavailable"),(ProposalContentError.capacity,"capacity"),(ProposalContentError.unsupportedProfile,"unsupported")] {peer.failure=error;await state.load(peer.source,concept:concept,current:{c});XCTAssertEqual(state.phase,phase)}
        peer.failure=nil;peer.expires=ISO8601DateFormatter().string(from:Date().addingTimeInterval(1.5));await state.load(peer.source,concept:concept,current:{c});XCTAssertNotNil(state.result);try await Task.sleep(for:.seconds(2));XCTAssertNil(state.result);XCTAssertEqual(state.phase,"access")
        peer.expires="2099-01-01T00:00:00Z";let key=state.key(c,concept,peer.source);try state.records.saveBounded(Data(key.utf8),key:state.witnessKey(key));await state.load(peer.source,concept:concept,current:{c});XCTAssertNil(state.result);XCTAssertEqual(state.phase,"unavailable");state.conceal()
    }
    func testCompletedJournalCannotMaskNewServerOriginalAfterClientReopen()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c});stage(state);await state.confirm(peer.source,concept:concept,current:{c});XCTAssertNil(state.pending)
        let command=ProposalContentCommand(operation_id:CompareFixture.second,source_operation_id:peer.source.operation_id,expected_concept_revision:3,selection_digest:String(repeating:"1",count:64),role:"ARCHITECTURE",decision:"APPROVE_CONTENT",reason:"Original server-captured role decision",acknowledged_open_points:peer.source.source_product.open_questions)
        peer.pending=[["operation_id":command.operation_id,"command":try JSONSerialization.jsonObject(with:JSONEncoder().encode(command))]];state.conceal()
        let reopened=ProposalContentState(transport:peer,root:root);await reopened.load(peer.source,concept:concept,current:{c});XCTAssertEqual(reopened.pending?.command,command)
        await reopened.recover(peer.source,concept:concept,current:{c});XCTAssertNil(reopened.pending);XCTAssertEqual(peer.posts.count,2);XCTAssertEqual(peer.posts.last,command);XCTAssertEqual(reopened.result?.decision.state,"CONTENT_APPROVED");reopened.conceal()
    }
    func testBoundedMonitorInvalidatesConfirmationAndConcealsRevocation()async throws {
        let root=temporary();defer{try? FileManager.default.removeItem(at:root)};let peer=try ContentFixture();let state=ProposalContentState(transport:peer,root:root);let c=CompareFixture.connection;let concept=CompareFixture.concept
        await state.load(peer.source,concept:concept,current:{c});stage(state);XCTAssertNotNil(state.confirmation)
        let other=ProposalContentCommand(operation_id:CompareFixture.second,source_operation_id:peer.source.operation_id,expected_concept_revision:3,selection_digest:String(repeating:"0",count:64),role:"ARCHITECTURE",decision:"REQUEST_CHANGES",reason:"Independent synthetic role changed during review",acknowledged_open_points:peer.source.source_product.open_questions)
        _=try await peer.decide(c,concept:concept.id,command:other)
        try await Task.sleep(for:.seconds(5.3));XCTAssertNil(state.confirmation);XCTAssertEqual(state.result?.decision.state,"CHANGES_REQUESTED")
        peer.failure=ConceptError.denied;try await Task.sleep(for:.seconds(5.3));XCTAssertNil(state.result);XCTAssertEqual(state.phase,"access");state.conceal()
    }
}
