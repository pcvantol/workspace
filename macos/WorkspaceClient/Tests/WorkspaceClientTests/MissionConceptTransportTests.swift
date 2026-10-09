import Foundation
import XCTest
@testable import WorkspaceClient

final class MissionConceptTransportTests: XCTestCase, @unchecked Sendable {
    let wire=MissionConceptWireTests()
    var connection: AdvisoryConnection { .init(endpoint:wire.access.endpoint,workspaceInstanceID:wire.access.workspaceInstanceID,actorID:wire.access.actorID,workspaceProjectID:wire.access.workspaceProjectID,conversationID:wire.conversation,bearer:"synthetic-read-root",draftGrant:String(repeating:"D",count:43)) }
    var calls:[URLRequest]=[]
    var dropSubmit=false
    var deny=false
    var absentHistory=false
    var absentTurn=false
    var recorded:[String:Any]?
    func transport() -> MissionConceptTransport {
        StubProtocol.handler = { request in
            self.calls.append(request)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Instance"),self.wire.access.workspaceInstanceID)
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Draft-Grant"),String(repeating:"D",count:43))
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Workspace-Advisory-Grant"),self.wire.access.token)
            if self.deny { return (403,Data("{}".utf8)) }
            let path=request.url!.path
            let raw:[String:Any]
            if path.hasSuffix("/access") {
                raw=["contract_version":"workspace-advisory-access/v1","actor_id":"alice","workspace_project_id":"ws-project","instance_id":"forge-one","project_id":"project-one","repository_id":"repo-one","conversation_ids":[self.wire.conversation]]
            } else if path.hasSuffix("/capability") { raw=try self.wire.fixture("capability") }
            else if path.hasSuffix("/context") {
                let cap=try self.wire.fixture("capability")
                raw=["contract_version":MissionConceptWire.contract,"conversation_id":self.wire.conversation,"context":cap["context"]!,"context_revision":cap["context_revision"]!,"read_only":true,"additional_model_calls":0]
            }
            else if path.hasSuffix("/catalog") {
                var catalog=try self.wire.fixture("catalog")
                if let record=self.recorded {
                    var items=catalog["items"] as! [[String:Any]],item=items[0]
                    let request=record["request"] as! [String:Any],revision=(request["expected_revision"] as! Int)+1
                    item["revision"]=revision;item["conversation_revision"]=revision;item["source_turn_id"]=request["turn_id"]
                    items[0]=item;catalog["items"]=items;catalog["snapshot_revision"]=try AdvisoryWire.digest(items)
                }
                raw=catalog
            }
            else if path.hasSuffix("/resolve") {
                var body=request.httpBody
                if body == nil,let stream=request.httpBodyStream {
                    stream.open();defer { stream.close() };var buffer=[UInt8](repeating:0,count:4096),bytes=Data()
                    while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 { break };bytes.append(buffer,count:n) };body=bytes
                }
                let submitted=try AdvisoryWire.object(body!),scope:[String:Any]=["instance_id":self.wire.access.forgeInstanceID,"project_id":self.wire.access.forgeProjectID,"repository_id":self.wire.access.repositoryID]
                let principal=self.wire.access.forgeInstanceID+":"+self.wire.access.actorID
                let key=try AdvisoryWire.digest([principal,scope,submitted["workspace_conversation_id"]!,submitted["workspace_draft_id"]!])
                raw=["contract_version":MissionConceptWire.contract,"operation_id":submitted["operation_id"]!,"binding":["scope":scope,"principal_reference":principal,"workspace_conversation_id":submitted["workspace_conversation_id"]!,"workspace_draft_id":submitted["workspace_draft_id"]!,"conversation_id":self.wire.conversation,"binding_key":key],"additional_model_calls":0,"grant_issued":false,"budget_reset":false]
            }
            else if path.hasSuffix("/cancel") {
                raw=["contract_version":MissionConceptWire.contract,"original_turn":try self.wire.fixture("record"),"current_revision":1,"provider_stopped":false,"cancel_request_recorded":true]
            } else if request.httpMethod=="POST" {
                var body=request.httpBody
                if body == nil, let stream=request.httpBodyStream {
                    stream.open();defer { stream.close() };var buffer=[UInt8](repeating:0,count:4096);var bytes=Data()
                    while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 { break };bytes.append(buffer,count:count) };body=bytes
                }
                let submitted=try AdvisoryWire.object(body!)
                var record=try self.wire.fixture("record");record["request"]=submitted;record["request_digest"]=try AdvisoryWire.digest(submitted)
                var outcome=record["outcome"] as! [String:Any],output=outcome["output"] as! [String:Any]
                output["request_digest"]=record["request_digest"];outcome["output"]=output;outcome["result_digest"]=try AdvisoryWire.digest(output);record["outcome"]=outcome
                self.recorded=record
                if self.dropSubmit { throw URLError(.networkConnectionLost) }
                raw=["contract_version":MissionConceptWire.contract,"original_turn":record,"current_revision":(submitted["expected_revision"] as! Int)+1,"recorded":true]
            } else if path.contains("/turns/") {
                if self.absentTurn && self.recorded == nil { return (404,Data("{}".utf8)) }
                if let record=self.recorded { raw=["contract_version":MissionConceptWire.contract,"original_turn":record,"current_revision":((record["request"] as! [String:Any])["expected_revision"] as! Int)+1,"read_only":true] }
                else { raw=try self.wire.fixture("turn") }
            }
            else {
                if self.absentHistory { return (404,Data("{}".utf8)) }
                var history=try self.wire.fixture("history")
                if let record=self.recorded { history["turns"]=[record];history["revision"]=((record["request"] as! [String:Any])["expected_revision"] as! Int)+1 }
                raw=history
            }
            return (200,try self.wire.data(raw))
        }
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[StubProtocol.self]
        return MissionConceptTransport(http:AdvisoryTransport(configuration:configuration))
    }
    func testReadAndExplicitRefinementUseOnlyOwnBoundedRoutes() async throws {
        let t=transport(),access=wire.access
        let observed=try await t.probe(connection,token:access.token);XCTAssertEqual(observed,access)
        _ = try await t.capability(access,connection)
        _ = try await t.capability(access,connection,sources:[.init(source_id:"Vision",version:"sha256:"+String(repeating:"a",count:64))])
        _ = try await t.context(access,connection)
        _ = try await t.history(access,connection)
        let request=try MissionConceptWire.request(wire.fixture("request"),access:access,conversation:wire.conversation)
        _ = try await t.turn(access,connection,request:request)
        _ = try await t.catalog(access,connection)
        let snapshot=try MissionConceptWire.catalog(wire.data(wire.fixture("catalog")),access:access).snapshot_revision
        _ = try await t.catalog(access,connection,snapshot:snapshot)
        XCTAssertTrue(calls.allSatisfy { $0.httpMethod=="GET" && $0.url!.path.hasPrefix("/v1/mission-concepts/") })
        _ = try await t.submit(access,connection,request:request)
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,1)
        _ = try await t.cancel(access,connection,request:request,cancel:.init(contract_version:MissionConceptWire.contract,expected_revision:1,request_digest:AdvisoryWire.digest(wire.fixture("request"))))
        XCTAssertEqual(calls.filter { $0.httpMethod=="POST" }.count,2)
    }
    func testForeignScopeAndInvalidBoundsTransmitNothing() async throws {
        let t=transport(),access=wire.access
        do { _ = try await t.catalog(access,connection,cursor:2);XCTFail() } catch {}
        do { _ = try await t.catalog(access,connection,snapshot:"bad");XCTFail() } catch {}
        do { _ = try await t.history(access,connection,cursor:9);XCTFail() } catch {}
        do { _ = try await t.capability(access,connection,sources:Array(repeating:.init(source_id:"same",version:"sha256:"+String(repeating:"a",count:64)),count:3));XCTFail() } catch {}
        var foreign=connection;foreign=AdvisoryConnection(endpoint:foreign.endpoint,workspaceInstanceID:foreign.workspaceInstanceID,actorID:"bob",workspaceProjectID:foreign.workspaceProjectID,conversationID:foreign.conversationID,bearer:foreign.bearer,draftGrant:foreign.draftGrant)
        do { _ = try await t.catalog(access,foreign);XCTFail() } catch {}
        XCTAssertTrue(calls.isEmpty)
    }
    func testResolutionKeepsWorkspaceAndProducerReferencesSeparateWithoutGeneration() async throws {
        let t=transport(),draft=String(repeating:"b",count:32)
        let first=try await t.resolve(wire.access,connection,workspaceDraftID:draft,operationID:"resolve-one")
        let replay=try await t.resolve(wire.access,connection,workspaceDraftID:draft,operationID:"resolve-one")
        XCTAssertEqual(first,replay);XCTAssertEqual(first.workspaceDraftID,draft)
        XCTAssertEqual(first.producerConversationID,wire.conversation);XCTAssertNil(recorded)
        XCTAssertTrue(calls.allSatisfy { $0.url!.path=="/v1/mission-concepts/resolve" })
        let before=calls.count
        do { _ = try await t.resolve(wire.access,connection,workspaceDraftID:"foreign",operationID:"resolve-other");XCTFail() } catch {}
        XCTAssertEqual(calls.count,before)
    }

}
