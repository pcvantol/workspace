import Foundation

final class CandidateTransport: @unchecked Sendable {
    private let session:URLSession
    private let redirects=RejectRedirects()
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session=URLSession(configuration:configuration,delegate:redirects,delegateQueue:nil)
    }
    private func request(_ c:AdvisoryConnection,token:String,path:String,body:Data?=nil) async throws -> Data {
        guard token.range(of:"^[A-Za-z0-9_-]{43}$",options:.regularExpression) != nil,path.hasPrefix("/v1/advisory-candidates/") else { throw AdvisoryError.denied }
        let endpoint=try ServerEndpoint(c.endpoint)
        guard let url=URL(string:path,relativeTo:endpoint.url)?.absoluteURL else { throw AdvisoryError.invalid }
        var r=URLRequest(url:url);r.timeoutInterval=65;r.httpMethod=body==nil ? "GET":"POST";r.httpBody=body
        r.setValue("Bearer "+c.bearer,forHTTPHeaderField:"Authorization");r.setValue(c.workspaceInstanceID,forHTTPHeaderField:"X-Workspace-Instance")
        r.setValue(c.draftGrant,forHTTPHeaderField:"X-Workspace-Draft-Grant");r.setValue(token,forHTTPHeaderField:"X-Workspace-Candidate-Grant")
        r.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response)=try await session.data(for:r)
        guard let http=response as? HTTPURLResponse,data.count<=65536,http.value(forHTTPHeaderField:"Content-Type")?.lowercased().hasPrefix("application/json")==true else { throw AdvisoryError.invalid }
        switch http.statusCode {
        case 200:return data
        case 401,403:throw AdvisoryError.denied
        case 404:throw AdvisoryError.missing
        case 400,409,503:
            if let code=try? AdvisoryWire.object(data)["error"] as? String { throw AdvisoryError.state(code) }
            throw AdvisoryError.unavailable
        default:throw AdvisoryError.unavailable
        }
    }
    func probe(_ c:AdvisoryConnection,token:String) async throws -> CandidateAccess {
        let raw=try AdvisoryWire.object(await request(c,token:token,path:"/v1/advisory-candidates/access"))
        guard Set(raw.keys)==["contract_version","actor_id","workspace_project_id","instance_id","project_id","repository_id","conversation_id","proposal_ids","maximum_registrations"],
              raw["contract_version"] as? String=="workspace-candidate-access/v1",
              let actor=raw["actor_id"] as? String,let wsProject=raw["workspace_project_id"] as? String,
              let instance=raw["instance_id"] as? String,let project=raw["project_id"] as? String,
              let repo=raw["repository_id"] as? String,let conv=raw["conversation_id"] as? String,
              let ids=raw["proposal_ids"] as? [String],let max=raw["maximum_registrations"] as? Int else { throw AdvisoryError.invalid }
        let a=CandidateAccess(endpoint:c.endpoint,workspaceInstanceID:c.workspaceInstanceID,workspaceProjectID:wsProject,actorID:actor,
            forgeInstanceID:instance,forgeProjectID:project,repositoryID:repo,conversationID:conv,proposalIDs:ids,maximumRegistrations:max,token:token)
        guard a.matches(c) else { throw AdvisoryError.denied };return a
    }
    private func read(_ a:CandidateAccess,_ c:AdvisoryConnection,path:String,body:Data?=nil) async throws -> Data {
        guard a.matches(c) else { throw AdvisoryError.denied }
        return try await request(c,token:a.token,path:path,body:body)
    }
    func capability(_ a:CandidateAccess,_ c:AdvisoryConnection) async throws -> CandidateCapability {
        try CandidateWire.capability(await read(a,c,path:"/v1/advisory-candidates/capability"),access:a)
    }
    func source(_ a:CandidateAccess,_ c:AdvisoryConnection,turn:String) async throws -> CandidateSource {
        guard WorklistWire.identifier(turn) else { throw AdvisoryError.invalid }
        return try CandidateWire.source(await read(a,c,path:"/v1/advisory-candidates/"+c.conversationID+"/source/"+turn),turn:turn)
    }
    func preview(_ a:CandidateAccess,_ c:AdvisoryConnection,id:String,revision:Int) async throws -> CandidatePreview {
        guard a.proposalIDs.contains(id),(1...8).contains(revision) else { throw AdvisoryError.denied }
        return try CandidateWire.preview(await read(a,c,path:"/v1/advisory-candidates/"+c.conversationID+"/proposals/"+id+"?revision=\(revision)"),access:a,id:id,revision:revision)
    }
    func save(_ a:CandidateAccess,_ c:AdvisoryConnection,body:CandidateSaveRequest) async throws -> CandidateProposal {
        let data=try CandidateWire.data(body,kind:"proposal_request");try CandidateWire.bound(AdvisoryWire.object(data),access:a);try CandidateWire.fields(body.fields)
        guard a.proposalIDs.contains(body.proposal_id),WorklistWire.identifier(body.turn_id) else { throw AdvisoryError.denied }
        return try CandidateWire.saved(await read(a,c,path:"/v1/advisory-candidates/"+c.conversationID+"/proposals",body:data),access:a,request:body)
    }
    func register(_ a:CandidateAccess,_ c:AdvisoryConnection,body:CandidateRegistrationRequest) async throws -> CandidateRegistration {
        let data=try CandidateWire.data(body,kind:"registration_request");try CandidateWire.bound(AdvisoryWire.object(data),access:a)
        guard a.proposalIDs.contains(body.proposal_id),WorklistWire.identifier(body.operation_id) else { throw AdvisoryError.denied }
        return try CandidateWire.registration(AdvisoryWire.object(await read(a,c,path:"/v1/advisory-candidates/"+c.conversationID+"/proposals/"+body.proposal_id+"/registrations",body:data)),access:a,id:body.proposal_id,expected:body)
    }
    func operation(_ a:CandidateAccess,_ c:AdvisoryConnection,body:CandidateRegistrationRequest) async throws -> CandidateRegistration? {
        try CandidateWire.bound(AdvisoryWire.object(CandidateWire.data(body,kind:"registration_request")),access:a)
        guard a.proposalIDs.contains(body.proposal_id),WorklistWire.identifier(body.operation_id) else { throw AdvisoryError.denied }
        let raw=try AdvisoryWire.object(await read(a,c,path:"/v1/advisory-candidates/"+c.conversationID+"/proposals/"+body.proposal_id+"/registrations/"+body.operation_id))
        if raw["state"] as? String=="PENDING" {
            try CandidateWire.validate(raw,kind:"pending")
            guard raw["operation_id"] as? String==body.operation_id else { throw AdvisoryError.invalid };return nil
        }
        return try CandidateWire.registration(raw,access:a,id:body.proposal_id,expected:body)
    }
}
