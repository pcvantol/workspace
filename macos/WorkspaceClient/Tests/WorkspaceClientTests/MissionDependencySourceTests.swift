import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionDependencySourceTests:XCTestCase {
    func fixture(_ name:String) throws -> [String:Any] {
        let p=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mission-dependency-source/"+name+".json")
        return try AdvisoryWire.object(Data(contentsOf:p))
    }
    func sourceAccess() throws -> AdvisoryAccess {
        let p=try fixture("prepared-dependent")["package"] as! [String:Any],s=p["source"] as! [String:Any],a=p["authority"] as! [String:Any]
        return .init(endpoint:"http://127.0.0.1:12345/",workspaceInstanceID:String(repeating:"a",count:32),workspaceProjectID:"own-project",actorID:(a["principal_reference"] as! String).components(separatedBy:":").last!,forgeInstanceID:s["instance_id"] as! String,forgeProjectID:s["project_id"] as! String,repositoryID:s["repository_id"] as! String,conversationIDs:["foundation","portal"],token:String(repeating:"C",count:43))
    }
    func testActualTypedDirectedDependencyFrozenBindingAndFocusedContext() throws {
        let access=try sourceAccess(),raw=try fixture("catalog-directed-dependency")
        let catalog=try MissionConceptWire.catalog(JSONSerialization.data(withJSONObject:raw),access:access)
        let edge=try XCTUnwrap(catalog.items.last?.edges.first)
        XCTAssertEqual(edge.source_object_id,catalog.items.first?.object_id)
        XCTAssertEqual(edge.target_object_id,catalog.items.last?.object_id)
        XCTAssertEqual(edge.state,"APPROVED_DEFINITION")
        let packet=try MissionApprovalWire.prepared(JSONSerialization.data(withJSONObject:fixture("prepared-dependent")),access:access,conversation:"portal")
        XCTAssertEqual(packet.definition.dependency_reasons[edge.candidate_id],edge.reason)
        let actual=try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:fixture("compound-dependent")),access:access,conversation:"portal",frozenData:packet.packageData)
        XCTAssertTrue(try XCTUnwrap(actual.readiness).blockers.contains("DEPENDENCY_NOT_PROVEN"))
        XCTAssertFalse(try XCTUnwrap(actual.readiness).execution_ready)
        var foreignReadiness=try fixture("compound-dependent"),r=foreignReadiness["current"] as! [String:Any]
        r["subject_revision"]="sha256:"+String(repeating:"0",count:64);foreignReadiness["current"]=r
        XCTAssertThrowsError(try MissionApprovalWire.compound(JSONSerialization.data(withJSONObject:foreignReadiness),access:access,conversation:"portal",frozenData:packet.packageData))
        for language in ["en","nl","de","fr","es"] {
            for code in ["DEPENDENCY_NOT_PROVEN","NOT_RELEASED","WORKSET_HELD","ACTIVATION_INPUTS_UNAVAILABLE","unknown"] {
                XCTAssertNotEqual(MissionWorkspaceCopy.blocker(code,language:language),code)
            }
        }
        let context=try MissionConceptWire.context(JSONSerialization.data(withJSONObject:fixture("context-with-predecessor")),access:access,conversation:"portal")
        XCTAssertEqual(context.context.concept_dependency_catalog.first?.subject_revision,edge.subject_revision)
        for field in ["target_object_id","reason","candidate_id"] {
            var bad=raw,items=bad["items"] as! [[String:Any]],edges=items[1]["edges"] as! [[String:Any]]
            edges[0][field]=field=="reason" ? "A different and unapproved explanation.":"foreign"
            items[1]["edges"]=edges;bad["items"]=items;bad["snapshot_revision"]=try AdvisoryWire.digest(items)
            XCTAssertThrowsError(try MissionConceptWire.catalog(JSONSerialization.data(withJSONObject:bad),access:access))
        }
        var changed=try fixture("prepared-dependent"),p=changed["package"] as! [String:Any],bindings=p["dependency_bindings"] as! [[String:Any]]
        bindings[0]["reason"]="A different and unapproved explanation.";p["dependency_bindings"]=bindings
        changed["package"]=p;changed["package_digest"]=try AdvisoryWire.digest(p)
        XCTAssertThrowsError(try MissionApprovalWire.prepared(JSONSerialization.data(withJSONObject:changed),access:access,conversation:"portal"))
    }
    @MainActor func testFullSnapshotDisplaysOnlyBoundRealEdgesAndRejectsForeignPredecessor() async throws {
        let original=try sourceAccess(),ids=[String(repeating:"a",count:32),String(repeating:"b",count:32)]
        let access=AdvisoryAccess(endpoint:original.endpoint,workspaceInstanceID:original.workspaceInstanceID,workspaceProjectID:original.workspaceProjectID,actorID:original.actorID,forgeInstanceID:original.forgeInstanceID,forgeProjectID:original.forgeProjectID,repositoryID:original.repositoryID,conversationIDs:ids,token:original.token)
        let credentials=AdviceMemory();credentials.access=access
        var catalog=try fixture("catalog-directed-dependency"),items=catalog["items"] as! [[String:Any]]
        // Explicit Workspace namespace replay; candidate/edge IDs and human meaning unchanged.
        for i in items.indices { items[i]["conversation_id"]=ids[i] }
        catalog["items"]=items;catalog["snapshot_revision"]=try AdvisoryWire.digest(items)
        var calls:[URLRequest]=[]
        StubProtocol.handler = { request in
            calls.append(request)
            if request.url!.path.hasSuffix("/catalog") { return (200,try JSONSerialization.data(withJSONObject:catalog)) }
            if request.url!.path.hasSuffix("/capability") {
                var cap=try MissionConceptWireTests().fixture("capability");cap["instance_id"]=access.forgeInstanceID;cap["project_id"]=access.forgeProjectID;cap["repository_id"]=access.repositoryID;cap["conversation_ids"]=ids
                var context=cap["context"] as! [String:Any];context["instance_id"]=access.forgeInstanceID;context["project_id"]=access.forgeProjectID;context["repository_id"]=access.repositoryID
                cap["context"]=context;cap["context_revision"]=try AdvisoryWire.digest(context)
                return (200,try JSONSerialization.data(withJSONObject:cap))
            }
            return (404,Data("{}".utf8))
        }
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[StubProtocol.self]
        let state=MissionConceptState(credentials:credentials,store:MissionIntentMemory(),transport:MissionConceptTransport(http:AdvisoryTransport(configuration:config)))
        let c=AdvisoryConnection(endpoint:access.endpoint,workspaceInstanceID:access.workspaceInstanceID,actorID:access.actorID,workspaceProjectID:access.workspaceProjectID,conversationID:ids[1],bearer:"synthetic-root",draftGrant:String(repeating:"D",count:43))
        await state.refresh(c)
        let shown=try XCTUnwrap(state.presentation(project:"Own"))
        XCTAssertEqual(shown.cards.count,2);XCTAssertEqual(shown.relations.count,1)
        XCTAssertFalse(shown.relations[0].proposed)
        XCTAssertEqual(shown.visibleRelations[0].predecessor,shown.cards[0].id)
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod=="GET" })
        var edges=items[1]["edges"] as! [[String:Any]];edges[0]["source_object_id"]="foreign-object";items[1]["edges"]=edges
        catalog["items"]=items;catalog["snapshot_revision"]=try AdvisoryWire.digest(items)
        await state.refresh(c)
        XCTAssertEqual(state.phase,"invalid");XCTAssertNil(state.presentation(project:"No leak"))
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod=="GET" })
    }
}
