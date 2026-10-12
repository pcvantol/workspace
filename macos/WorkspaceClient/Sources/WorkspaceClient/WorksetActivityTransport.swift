import Foundation

protocol ActivityServing: Sendable {
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> ActivityAccess
    func page(_ connection: AdvisoryConnection, access: ActivityAccess, workset: String, cursor: String?) async throws -> ActivityPage
    func detail(_ connection: AdvisoryConnection, access: ActivityAccess, workset: String, id: String) async throws -> ActivityEvent
}
struct ActivityTransport: ActivityServing {
    let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=20
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request(_ connection: AdvisoryConnection, token: String, suffix: String) async throws -> Data {
        guard ActivityWire.matches(token,"^[A-Za-z0-9_-]{43}$") else { throw AdvisoryError.denied }
        let url=try ServerEndpoint(connection.endpoint).route("/v1/workset-activity"+suffix)
        var request=URLRequest(url:url);request.httpMethod="GET"
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(connection.workspaceInstanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(connection.draftGrant,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        request.setValue(token,forHTTPHeaderField:"X-Workspace-Activity-Grant")
        try Task.checkCancellation()
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url,data.count<=32768,
            http.value(forHTTPHeaderField:"Content-Type")?.lowercased().hasPrefix("application/json")==true else { throw AdvisoryError.invalid }
        switch http.statusCode {
        case 200:return data
        case 401,403:throw AdvisoryError.denied
        case 409:
            let raw=try ActivityWire.object(data)
            if raw["error"] as? String == "ACTIVITY_RESYNC_REQUIRED" { throw AdvisoryError.state("RESYNC_REQUIRED") }
            throw AdvisoryError.denied
        case 404:
            let raw=try ActivityWire.object(data)
            throw AdvisoryError.state(raw["error"] as? String == "ACTIVITY_UNSUPPORTED" ? "UNSUPPORTED":"EVENT_UNAVAILABLE")
        case 503:
            let raw=try ActivityWire.object(data)
            guard Set(raw.keys)==["error"],let code=raw["error"] as? String,code.range(of:"^[A-Z][A-Z0-9_]{0,127}$",options:.regularExpression) != nil else { throw AdvisoryError.invalid }
            throw AdvisoryError.state(code)
        default:throw AdvisoryError.invalid
        }
    }
    func probe(_ connection: AdvisoryConnection, token: String) async throws -> ActivityAccess {
        try ActivityWire.access(await request(connection,token:token,suffix:""),connection:connection,token:token,now:Date())
    }
    private func allowed(_ access: ActivityAccess, _ connection: AdvisoryConnection, _ workset: String) throws {
        guard access.matches(connection),access.worksets.contains(where:{$0.workset_id==workset}),
            let expiry=WorksetReleaseWire.date(access.expires_at),expiry>Date() else { throw AdvisoryError.denied }
    }
    func page(_ connection: AdvisoryConnection, access: ActivityAccess, workset: String, cursor: String?) async throws -> ActivityPage {
        try allowed(access,connection,workset)
        if let cursor { guard cursor != ".",cursor != "..",ActivityWire.matches(cursor,"^[A-Za-z0-9_.-]{1,32768}$") else { throw AdvisoryError.invalid } }
        let suffix="/"+workset+"/pages"+(cursor.map { "/"+$0 } ?? "")
        let result=try ActivityWire.page(await request(connection,token:access.token,suffix:suffix),access:access,workset:workset)
        try allowed(access,connection,workset);return result
    }
    func detail(_ connection: AdvisoryConnection, access: ActivityAccess, workset: String, id: String) async throws -> ActivityEvent {
        try allowed(access,connection,workset)
        guard ActivityWire.matches(id,"^[0-9a-f]{64}$") else { throw AdvisoryError.invalid }
        let result=try ActivityWire.detail(await request(connection,token:access.token,suffix:"/"+workset+"/events/"+id),workset:workset,id:id)
        try allowed(access,connection,workset);return result
    }
}
