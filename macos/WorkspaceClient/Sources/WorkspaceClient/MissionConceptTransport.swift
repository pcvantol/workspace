import Foundation

// Composition over the existing pinned, ephemeral, redirect-rejecting own HTTP transport.
final class MissionConceptTransport: @unchecked Sendable {
    private let http: AdvisoryTransport
    init(http: AdvisoryTransport = AdvisoryTransport()) { self.http = http }
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> AdvisoryAccess {
        try await http.probe(connection: connection, token: token, concept: true)
    }
    func resolve(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,workspaceDraftID:String,operationID:String) async throws -> MissionResolvedBinding {
        try http.bound(access,connection)
        guard workspaceDraftID.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid }
        let request:[String:Any]=["contract_version":MissionConceptWire.contract,"operation_id":operationID,"workspace_conversation_id":connection.conversationID,"workspace_draft_id":workspaceDraftID]
        try MissionConceptWire.validate(request,kind:"resolve_request")
        let body=try JSONSerialization.data(withJSONObject:request)
        return try MissionConceptWire.resolution(await http.request(connection,token:access.token,path:"/v1/mission-concepts/resolve",body:body),access:access,request:request)
    }
    func capability(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, sources: [AdvisorySource] = []) async throws -> AdvisoryCapability {
        try http.bound(access, connection); guard sources.count <= 2 else { throw AdvisoryError.invalid }
        var parts=URLComponents();parts.queryItems=sources.flatMap { [URLQueryItem(name:"source_id",value:$0.source_id),URLQueryItem(name:"source_version",value:$0.version)] }
        let query=parts.percentEncodedQuery.map { "?"+$0 } ?? ""
        return try MissionConceptWire.capability(await http.request(connection,token:access.token,path:"/v1/mission-concepts/capability"+query),access:access)
    }
    func history(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, cursor: Int = 0) async throws -> MissionConceptHistory {
        try http.bound(access, connection);guard (0...8).contains(cursor) else { throw AdvisoryError.invalid }
        return try MissionConceptWire.history(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"?cursor=\(cursor)&limit=4"),access:access,conversation:connection.conversationID)
    }
    func turn(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, request: AdvisoryRequest) async throws -> MissionConceptObservation {
        try http.bound(access, connection)
        return try MissionConceptWire.observation(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/turns/"+request.turn_id),kind:"turn",access:access,conversation:connection.conversationID,expected:request)
    }
    func submit(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, request: AdvisoryRequest) async throws -> MissionConceptObservation {
        try http.bound(access, connection)
        let data=try JSONEncoder().encode(request)
        _ = try MissionConceptWire.request(AdvisoryWire.object(data),access:access,conversation:connection.conversationID)
        return try MissionConceptWire.observation(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/turns",body:data),kind:"submit",access:access,conversation:connection.conversationID,expected:request)
    }
    func cancel(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, request: AdvisoryRequest, cancel: AdvisoryCancelRequest) async throws -> MissionConceptObservation {
        try http.bound(access, connection)
        let data=try JSONEncoder().encode(cancel);try MissionConceptWire.validate(AdvisoryWire.object(data),kind:"cancel_request")
        return try MissionConceptWire.observation(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/turns/"+request.turn_id+"/cancel",body:data),kind:"cancel",access:access,conversation:connection.conversationID,expected:request)
    }
    func catalog(_ access: AdvisoryAccess, _ connection: AdvisoryConnection, cursor: Int = 0, snapshot: String? = nil) async throws -> MissionConceptCatalog {
        try http.bound(access, connection)
        guard (0...access.conversationIDs.count).contains(cursor) else { throw AdvisoryError.invalid }
        if let snapshot { guard snapshot.range(of:"^sha256:[0-9a-f]{64}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid } }
        var parts=URLComponents();parts.queryItems=[URLQueryItem(name:"cursor",value:String(cursor)),URLQueryItem(name:"limit",value:"4")]
        if let snapshot { parts.queryItems?.append(URLQueryItem(name:"snapshot_revision",value:snapshot)) }
        return try MissionConceptWire.catalog(await http.request(connection,token:access.token,path:"/v1/mission-concepts/catalog?"+parts.percentEncodedQuery!),access:access,cursor:cursor,expectedSnapshot:snapshot)
    }
    func package(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,revision:Int?=nil) async throws -> MissionPreparedPacket {
        try http.bound(access,connection)
        if let revision { guard (1...8).contains(revision) else { throw AdvisoryError.invalid } }
        let query=revision.map { "?revision="+String($0) } ?? ""
        return try MissionApprovalWire.prepared(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/package"+query),access:access,conversation:connection.conversationID,revision:revision)
    }
    func approve(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,body:Data,packet:MissionPreparedPacket) async throws -> MissionCompoundReadback {
        try http.bound(access,connection)
        let request=try AdvisoryWire.object(body);try MissionConceptWire.validate(request,kind:"approve_request")
        guard request["revision"] as? Int==packet.revision,request["package_digest"] as? String==packet.digest,packet.packageData != nil else { throw AdvisoryError.invalid }
        let reply=try await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/approve",body:body)
        return try MissionApprovalWire.compound(reply,access:access,conversation:connection.conversationID,expectedDigest:packet.digest,frozenData:packet.packageData)
    }
    func operation(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,id:String,expectedDigest:String?=nil) async throws -> MissionCompoundReadback {
        try http.bound(access,connection)
        guard id.range(of:"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid }
        return try MissionApprovalWire.compound(await http.request(connection,token:access.token,path:"/v1/mission-concepts/"+connection.conversationID+"/operations/"+id),access:access,conversation:connection.conversationID,expectedDigest:expectedDigest,operation:id)
    }

}
