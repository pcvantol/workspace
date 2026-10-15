import XCTest
@testable import WorkspaceClient

@MainActor final class ProposalCompareStateTests:XCTestCase {
    func root()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func wait(_ predicate:@escaping @MainActor ()->Bool)async throws {
        let deadline=ContinuousClock.now + .seconds(2)
        while !predicate(),ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(5))}
        XCTAssertTrue(predicate())
    }
    func testReadOnlyDefaultExactSavedReverseAndStateRestart()async throws {
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer(),state=ProposalCompareState(transport:peer,root:url),c=CompareFixture.connection
        await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"comparable");XCTAssertEqual(state.choice?.before,CompareFixture.first);XCTAssertEqual(state.choice?.after,CompareFixture.second)
        XCTAssertEqual(state.comparison?.before.source_product.name,"Original 1");XCTAssertEqual(state.comparison?.after.source_product.name,"Original 2")
        let reverse=ProposalCompareState.Choice(before:CompareFixture.second,after:CompareFixture.first)
        await state.compare(reverse,concept:CompareFixture.concept,current:{c});XCTAssertEqual(state.comparison?.before.operation_id,CompareFixture.second);state.conceal()
        let restarted=ProposalCompareState(transport:peer,root:url);await restarted.load(CompareFixture.concept,current:{c});XCTAssertEqual(restarted.choice,reverse);XCTAssertEqual(restarted.comparison?.after.operation_id,CompareFixture.first);XCTAssertEqual(peer.posts,0);restarted.conceal()
    }
    func testLatestCompletePairSurvivesManyNewerIncompleteIntentsWithoutPrepare()async throws {
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        peer.ids += (10...21).map{String(format:"%032x",$0)}
        await state.load(CompareFixture.concept,current:{c})
        XCTAssertEqual(state.phase,"comparable");XCTAssertTrue(state.partialHistory)
        XCTAssertEqual(state.choice,.init(before:CompareFixture.first,after:CompareFixture.second))
        XCTAssertEqual(state.comparison?.after.operation_id,CompareFixture.second);XCTAssertEqual(peer.posts,0);state.conceal()
    }
    func testMissingOneIdenticalAndIncompleteHistoryAreDistinctWithoutPrepare()async throws {
        for (ids,expected) in [([],"none"),([CompareFixture.first],"single"),([CompareFixture.first,CompareFixture.third],"partial")] {
            let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();peer.ids=ids;let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
            await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,expected);XCTAssertNil(state.comparison);XCTAssertEqual(peer.posts,0);state.conceal()
        }
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();peer.results[CompareFixture.second]=try CompareFixture.result(CompareFixture.second);let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"identical");XCTAssertEqual(state.comparison?.changedDocuments,0)
        await state.compare(.init(before:CompareFixture.first,after:CompareFixture.first),concept:CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"chooseDifferent");XCTAssertNil(state.comparison);state.conceal()
    }
    func testFreshAccessDenialAndRebindingAfterWorkerCannotPublishBeforeMonitor()async throws {
        for rebind in [false,true] {
            let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
            await state.load(CompareFixture.concept,current:{c});XCTAssertNotNil(state.comparison)
            peer.blockAccessAt=peer.accesses+2
            let task=Task {await state.compare(.init(before:CompareFixture.second,after:CompareFixture.first),concept:CompareFixture.concept,current:{c})}
            try await wait{peer.waitingAccess != nil};XCTAssertNil(state.comparison)
            let continuation=peer.waitingAccess;peer.waitingAccess=nil
            if rebind {peer.binding="different-current-pair";continuation?.resume(returning:peer.capability())}
            else {peer.revoked=true;continuation?.resume(throwing:ConceptError.denied)}
            await task.value;XCTAssertNil(state.comparison);XCTAssertEqual(state.phase,"denied");XCTAssertTrue(state.history.isEmpty);XCTAssertEqual(peer.posts,0);state.conceal()
        }
    }
    func testLateOwnContextReadCannotPublishOrOverwriteNewerSelection()async throws {
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        await state.load(CompareFixture.concept,current:{c});peer.blockAccessAt=peer.accesses+1
        let old=Task {await state.compare(.init(before:CompareFixture.second,after:CompareFixture.first),concept:CompareFixture.concept,current:{c})}
        try await wait{peer.waitingAccess != nil};let held=peer.waitingAccess;peer.waitingAccess=nil;peer.blockAccessAt=nil;state.conceal()
        await state.load(CompareFixture.concept,current:{c});let latest=ProposalCompareState.Choice(before:CompareFixture.first,after:CompareFixture.second);await state.compare(latest,concept:CompareFixture.concept,current:{c})
        held?.resume(returning:peer.capability());await old.value
        XCTAssertEqual(state.choice,latest);XCTAssertEqual(try JSONDecoder().decode(ProposalCompareState.Choice.self,from:XCTUnwrap(state.records.load(state.key(c,CompareFixture.concept)))),latest);XCTAssertEqual(state.comparison?.before.operation_id,CompareFixture.first);state.conceal()
    }
    func testLateMissingReadCannotMarkNewLoadAsPartial()async throws {
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();peer.blockNextRead=true;let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        let old=Task {await state.load(CompareFixture.concept,current:{c})};try await wait{peer.waitingRead != nil};let held=peer.waitingRead;peer.waitingRead=nil;state.conceal();await state.load(CompareFixture.concept,current:{c});XCTAssertFalse(state.partialHistory)
        held?.resume(throwing:ConceptError.notFound);await old.value;XCTAssertFalse(state.partialHistory);XCTAssertNotNil(state.comparison);state.conceal()
    }
    func testDeniedUnavailableCorruptExpiryAndSourceRevisionFailClosed()async throws {
        for (error,phase) in [(ConceptError.denied,"denied"),(.unavailable,"unavailable"),(.invalid,"invalid"),(.conflict,"sourceChanged"),(.notFound,"partial")] {
            let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();peer.failure=error;let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
            await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,phase);XCTAssertNil(state.comparison);state.conceal()
        }
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        peer.sourceRevision=4;await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"sourceChanged");peer.sourceRevision=3
        peer.results[CompareFixture.second]=try CompareFixture.result(CompareFixture.second,profile:"future/2");await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"incompatible");XCTAssertNil(state.comparison)
        peer.results[CompareFixture.second]=try CompareFixture.result(CompareFixture.second,revision:2);peer.expiry=ISO8601DateFormatter().string(from:Date().addingTimeInterval(1.5));await state.load(CompareFixture.concept,current:{c});XCTAssertNotNil(state.comparison);try await wait{state.phase=="denied"};XCTAssertNil(state.comparison);XCTAssertTrue(state.history.isEmpty);state.conceal()
    }
    func testOneInaccessibleOriginalAndSavedChoiceLossNeverCreatesReplacement()async throws {
        let url=root();defer{try? FileManager.default.removeItem(at:url)};let peer=try ComparePeer();let state=ProposalCompareState(transport:peer,root:url);let c=CompareFixture.connection
        await state.load(CompareFixture.concept,current:{c});peer.results[CompareFixture.second]=nil
        await state.compare(.init(before:CompareFixture.first,after:CompareFixture.second),concept:CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"partial");XCTAssertNil(state.comparison);state.conceal()
        await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"partial");XCTAssertNil(state.comparison);XCTAssertEqual(peer.posts,0);state.conceal()
        try state.records.saveBounded(Data("corrupt".utf8),key:state.key(c,CompareFixture.concept));await state.load(CompareFixture.concept,current:{c});XCTAssertEqual(state.phase,"invalid");XCTAssertNil(state.comparison);state.conceal()
    }
}
