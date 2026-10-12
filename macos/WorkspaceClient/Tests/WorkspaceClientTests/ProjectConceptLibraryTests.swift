import XCTest
import Foundation
import SwiftUI
import AppKit
@testable import WorkspaceClient

private final class LibraryFixture: ConceptServing, @unchecked Sendable {
    var items:[ProjectConcept] = []
    var moves:[ConceptLifecycleCommand] = []
    var receipts:[String:ProjectConcept] = [:]
    var fail:ConceptError?
    var drop = false
    var drift = false
    var readHeld = false
    var hold:CheckedContinuation<[ProjectConceptSummary],Error>?
    func list(_ c:ConceptConnection) async throws -> [ProjectConceptSummary] {
        if let fail {throw fail};if readHeld {return try await withCheckedThrowingContinuation{hold=$0}}
        return items.map(\.summary)
    }
    func get(_ c:ConceptConnection,id:String) async throws -> ProjectConcept {
        if let fail {throw fail};guard let item=items.first(where:{$0.id==id}) else {throw ConceptError.notFound};return item
    }
    func save(_ c:ConceptConnection,id:String?,command:ConceptCommand) async throws -> ProjectConcept {throw ConceptError.invalid}
    func move(_ c:ConceptConnection,id:String,command:ConceptLifecycleCommand) async throws -> ProjectConcept {
        moves.append(command);if let fail {throw fail}
        if let old=receipts[command.operation_id] {return old}
        guard let old=items.first(where:{$0.id==id}),old.revision==command.expected_revision else {throw ConceptError.conflict}
        var next=old;next=ProjectConcept(id:old.id,actor_id:old.actor_id,context_id:old.context_id,title:old.title,notes:old.notes,revision:old.revision+1,created_at:old.created_at,updated_at:"2026-10-12T01:00:00Z",state:old.state,lifecycle:command.lifecycle,library_version:"project-concept-library/1")
        receipts[command.operation_id]=next;items.removeAll{$0.id==id};items.append(next)
        if drift {items[items.count-1]=ProjectConcept(id:next.id,actor_id:next.actor_id,context_id:next.context_id,title:next.title,notes:next.notes,revision:next.revision+1,created_at:next.created_at,updated_at:next.updated_at,state:next.state,lifecycle:next.lifecycle=="ACTIVE" ? "ARCHIVED" : "ACTIVE",library_version:next.library_version)}
        if drop {throw ConceptError.unavailable};return next
    }
}
final class ProjectConceptLibraryTests:XCTestCase {
    let connection=ConceptConnection(access:.init(endpoint:"http://127.0.0.1:8888/",instanceID:String(repeating:"b",count:32),projectID:"own-context",token:String(repeating:"c",count:43)),bearer:"synthetic")
    func record(_ digit:String="a",title:String="Café ideeën 🌱",life:String="ACTIVE") -> ProjectConcept {
        .init(id:String(repeating:digit,count:32),actor_id:"alice",context_id:"own-context",title:title,notes:"Protected long notes 日本語",revision:1,created_at:"2026-10-12T00:00:00Z",updated_at:"2026-10-12T00:00:00Z",state:"CONCEPT_NOT_CONFIGURED",lifecycle:life,library_version:"project-concept-library/1")
    }
    @MainActor func testMetadataSearchFilterDirtyAndLateListKeepSelectionAndContent() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=LibraryFixture();peer.items=[record(),record("d"),record("e",life:"ARCHIVED")]
        let s=ProjectConceptState(transport:peer,root:root),c=connection
        await s.refresh(current:{c});s.searchQuery="CAFÉ";XCTAssertEqual(s.visibleItems.count,2)
        await s.open(peer.items[0].id,current:{c});let id=s.selected?.id;s.notes="Unsaved own text"
        s.libraryTab="ARCHIVED";XCTAssertEqual(s.visibleItems.count,1);XCTAssertEqual(s.selected?.id,id);XCTAssertEqual(s.notes,"Unsaved own text")
        await s.move(current:{c});XCTAssertTrue(peer.moves.isEmpty)
        s.searchQuery="No title";XCTAssertEqual(s.libraryEmptyMessage,"noTitles")
        s.searchQuery="";s.libraryTab="ACTIVE";peer.readHeld=true
        let read=Task {await s.refresh(current:{c})};for _ in 0..<100 where peer.hold==nil {await Task.yield()}
        s.searchQuery="Missing";s.libraryTab="ARCHIVED";peer.hold?.resume(returning:peer.items.map(\.summary));await read.value
        XCTAssertEqual(s.selected?.id,id);XCTAssertEqual(s.notes,"Unsaved own text");XCTAssertEqual(s.libraryEmptyMessage,"noTitles")
        peer.readHeld=false;peer.items=[];s.searchQuery="";await s.refresh(current:{c});XCTAssertEqual(s.libraryEmptyMessage,"archiveEmpty")
        s.libraryTab="ACTIVE";XCTAssertEqual(s.libraryEmptyMessage,"activeEmpty")
        s.concealAuthorization();XCTAssertNil(s.libraryEmptyMessage);XCTAssertEqual(s.searchQuery,"");XCTAssertEqual(s.notes,"")
    }
    @MainActor func testDurableLifecycleLostReplyRestartReplayRestoreSameIdentity() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=LibraryFixture();peer.items=[record()];let c=connection,s=ProjectConceptState(transport:peer,root:root)
        await s.refresh(current:{c});await s.open(peer.items[0].id,current:{c})
        peer.drop=true;await s.move(current:{c});XCTAssertEqual(s.phase,"lifecycleOffline");XCTAssertNotNil(s.pendingLifecycle)
        let original=try XCTUnwrap(s.pendingLifecycle);XCTAssertEqual(peer.items[0].lifecycle,"ARCHIVED")
        let reopened=ProjectConceptState(transport:peer,root:root);await reopened.refresh(current:{c})
        XCTAssertEqual(reopened.phase,"lifecycleRetry");XCTAssertEqual(reopened.pendingLifecycle?.command,original.command)
        peer.drop=false;await reopened.move(current:{c});XCTAssertEqual(peer.moves,[original.command,original.command]);XCTAssertEqual(peer.items[0].revision,2)
        XCTAssertEqual(reopened.libraryTab,"ARCHIVED");XCTAssertEqual(reopened.selected?.id,original.identity);XCTAssertEqual(reopened.notes,original.snapshot.notes)
        await reopened.save(current:{c});XCTAssertEqual(reopened.selected?.revision,2) // archived cannot edit
        await reopened.move(current:{c});XCTAssertEqual(reopened.libraryTab,"ACTIVE");XCTAssertEqual(reopened.selected?.revision,3);XCTAssertEqual(reopened.selected?.id,original.identity)
        let again=ProjectConceptState(transport:peer,root:root);await again.refresh(current:{c});XCTAssertNil(again.pendingLifecycle)
        XCTAssertEqual(peer.receipts.count,2)
    }
    @MainActor func testConflictDriftDenialInvalidAndDurableFailureBoundaries() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
        let peer=LibraryFixture();peer.items=[record()];let c=connection,s=ProjectConceptState(transport:peer,root:root)
        await s.refresh(current:{c});await s.open(peer.items[0].id,current:{c})
        peer.fail = .conflict;await s.move(current:{c});XCTAssertEqual(s.phase,"conflict");XCTAssertNil(s.pendingLifecycle);XCTAssertEqual(s.notes,peer.items[0].notes)
        peer.fail=nil;await s.open(peer.items[0].id,discard:true,current:{c});peer.drift=true;await s.move(current:{c});XCTAssertEqual(s.phase,"conflict");XCTAssertNil(s.pendingLifecycle);XCTAssertEqual(s.selected?.revision,1)
        await s.open(peer.items[0].id,discard:true,current:{c});XCTAssertEqual(s.selected?.revision,3)
        peer.fail = .denied;await s.move(current:{c});XCTAssertEqual(s.phase,"denied");XCTAssertNil(s.selected);XCTAssertEqual(s.notes,"")
        peer.fail = .incompatible;await s.refresh(current:{c});XCTAssertEqual(s.phase,"incompatible")
        peer.fail=nil;s.busy=true;await s.move(current:{c});s.busy=false;await s.move(current:{c});XCTAssertNil(s.selected)
        var invalid=record();invalid.lifecycle="DELETED";XCTAssertThrowsError(try invalid.validate("own-context"))
        let broken=root.appendingPathComponent("file");try Data().write(to:broken)
        let b=ProjectConceptState(transport:peer,root:broken);await b.refresh(current:{c});XCTAssertEqual(b.phase,"offline")
    }
    @MainActor func testFiveLanguageLibraryViewActiveArchiveConflictAndNarrow() throws {
        let peer=LibraryFixture();peer.items=[record(),record("d",life:"ARCHIVED")]
        let s=ProjectConceptState(transport:peer),client=ClientState(keychain:LibraryEmptyServer());s.items=peer.items.map(\.summary);s.inventoryLoaded=true
        for language in ["en","nl","de","fr","es"] {
            for life in ["ACTIVE","ARCHIVED"] {
                s.selected=peer.items.first{$0.lifecycle==life};s.title=s.selected!.title;s.notes=s.selected!.notes;s.libraryTab=life;s.phase="conflict"
                let host=NSHostingView(rootView:ProjectConceptView(state:s,client:client,grants:LibraryEmptyGrant()).environment(\.locale,Locale(identifier:language)))
                host.frame=NSRect(x:0,y:0,width:560,height:780);host.layoutSubtreeIfNeeded();_=host.fittingSize
                XCTAssertTrue(host.frame.width.isFinite);XCTAssertEqual(ProjectConceptCopy.values["search"]?.count,5)
            }
        }
        s.items=[];s.phase="ready";let host=NSHostingView(rootView:ProjectConceptView(state:s,client:client,grants:LibraryEmptyGrant()));host.frame=NSRect(x:0,y:0,width:560,height:780);host.layoutSubtreeIfNeeded()
    }
}
private struct LibraryEmptyServer:CredentialStore {
    func binding() throws -> ServerBinding? {nil};func token() throws -> String? {nil};func save(binding:ServerBinding,token:String)throws{};func forget()throws{}
}
private struct LibraryEmptyGrant:DraftGrantStore {
    func load()throws->DraftAccess?{nil};func save(_ access:DraftAccess)throws{};func forget()throws{}
}
