import Foundation

final class AdvisoryTransport: @unchecked Sendable {
    private let session: URLSession
    private let redirects=RejectRedirects()
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session=URLSession(configuration:configuration,delegate:redirects,delegateQueue:nil)
    }
    func request(_ connection:AdvisoryConnection, token:String,path:String,body:Data?=nil) async throws -> Data {
        guard token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil,
              (path.hasPrefix("/v1/advisory/") || path.hasPrefix("/v1/mission-concepts/")) else { throw AdvisoryError.denied }
        let endpoint=try ServerEndpoint(connection.endpoint)
        guard let url=URL(string:path,relativeTo:endpoint.url)?.absoluteURL else { throw AdvisoryError.invalid }
        var request=URLRequest(url:url);request.timeoutInterval=65;request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(connection.workspaceInstanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(connection.draftGrant,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        request.setValue(token,forHTTPHeaderField:"X-Workspace-Advisory-Grant")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,data.count<=65536,
              http.value(forHTTPHeaderField:"Content-Type")?.lowercased().hasPrefix("application/json")==true else { throw AdvisoryError.invalid }
        switch http.statusCode {
        case 200:return data
        case 401,403:throw AdvisoryError.denied
        case 404:throw AdvisoryError.missing
        case 400,409,503:
            if let error=try? AdvisoryWire.object(data)["error"] as? String { throw AdvisoryError.state(error) }
            throw AdvisoryError.unavailable
        default:throw AdvisoryError.unavailable
        }
    }
    func probe(connection:AdvisoryConnection,token:String,concept:Bool=false) async throws -> AdvisoryAccess {
        let raw=try AdvisoryWire.object(await request(connection,token:token,path:concept ? "/v1/mission-concepts/access":"/v1/advisory/access"))
        guard Set(raw.keys)==["contract_version","actor_id","workspace_project_id","instance_id","project_id","repository_id","conversation_ids"],
              raw["contract_version"] as? String=="workspace-advisory-access/v1",
              let actor=raw["actor_id"] as? String,let project=raw["workspace_project_id"] as? String,
              let forge=raw["instance_id"] as? String,let forgeProject=raw["project_id"] as? String,
              let repository=raw["repository_id"] as? String,let conversations=raw["conversation_ids"] as? [String],
              actor==connection.actorID,project==connection.workspaceProjectID,(concept || conversations.contains(connection.conversationID)) else { throw AdvisoryError.denied }
        let value=AdvisoryAccess(endpoint:connection.endpoint,workspaceInstanceID:connection.workspaceInstanceID,workspaceProjectID:project,
            actorID:actor,forgeInstanceID:forge,forgeProjectID:forgeProject,repositoryID:repository,conversationIDs:conversations,token:token)
        guard concept ? value.validForMission:value.valid else { throw AdvisoryError.invalid };return value
    }
    func bound(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,concept:Bool=false) throws {
        guard (concept ? access.validForMission:access.valid),access.endpoint==connection.endpoint,access.workspaceInstanceID==connection.workspaceInstanceID,
              access.actorID==connection.actorID,access.workspaceProjectID==connection.workspaceProjectID,
              access.conversationIDs.contains(connection.conversationID) else { throw AdvisoryError.denied }
    }
    func capability(_ access:AdvisoryAccess,_ connection:AdvisoryConnection, sources:[AdvisorySource]) async throws -> AdvisoryCapability {
        try bound(access,connection);guard sources.count<=2 else { throw AdvisoryError.invalid }
        var parts=URLComponents();parts.queryItems=sources.flatMap { [URLQueryItem(name:"source_id",value:$0.source_id),URLQueryItem(name:"source_version",value:$0.version)] }
        let query=parts.percentEncodedQuery.map{"?"+$0} ?? ""
        return try AdvisoryWire.capability(await request(connection,token:access.token,path:"/v1/advisory/capability"+query),access:access)
    }
    func history(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,cursor:Int=0) async throws -> AdvisoryHistory {
        try bound(access,connection);guard (0...8).contains(cursor) else { throw AdvisoryError.invalid }
        return try AdvisoryWire.history(await request(connection,token:access.token,path:"/v1/advisory/"+connection.conversationID+"?cursor=\(cursor)&limit=4"),access:access,conversation:connection.conversationID)
    }
    func turn(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,request body:AdvisoryRequest) async throws -> AdvisoryObservation {
        try bound(access,connection)
        let value=try AdvisoryWire.observation(await request(connection,token:access.token,path:"/v1/advisory/"+connection.conversationID+"/turns/"+body.turn_id),kind:"turn",access:access,conversation:connection.conversationID,expected:body)
        return value
    }
    func submit(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,body:AdvisoryRequest) async throws -> AdvisoryObservation {
        try bound(access,connection)
        guard body.conversation_id==connection.conversationID,body.instance_id==access.forgeInstanceID,
              body.project_id==access.forgeProjectID,body.repository_id==access.repositoryID else { throw AdvisoryError.denied }
        return try AdvisoryWire.observation(await request(connection,token:access.token,path:"/v1/advisory/"+connection.conversationID+"/turns",body:body.data()),kind:"submit",access:access,conversation:connection.conversationID,expected:body)
    }
    func cancel(_ access:AdvisoryAccess,_ connection:AdvisoryConnection,request body:AdvisoryRequest,cancel:AdvisoryCancelRequest) async throws -> AdvisoryObservation {
        try bound(access,connection)
        let data=try JSONEncoder().encode(cancel);try AdvisoryWire.validate(AdvisoryWire.object(data),kind:"cancel_request")
        return try AdvisoryWire.observation(await request(connection,token:access.token,path:"/v1/advisory/"+connection.conversationID+"/turns/"+body.turn_id+"/cancel",body:data),kind:"cancel",access:access,conversation:connection.conversationID,expected:body)
    }
}
