import Foundation

struct ExecutionProgressTransport:ExecutionServing {
    let session:URLSession
    init(session:URLSession?=nil) {
        let c=URLSessionConfiguration.ephemeral;c.httpCookieStorage=nil;c.urlCredentialStorage=nil;c.urlCache=nil
        c.httpMaximumConnectionsPerHost=1;c.timeoutIntervalForRequest=12;c.timeoutIntervalForResource=15
        self.session=session ?? URLSession(configuration:c,delegate:RejectRedirects(),delegateQueue:nil)
    }
    func read(_ query:ExecutionQuery) async throws->ExecutionEnvelope {
        try query.validate();try Task.checkCancellation()
        let suffix=query.run.map {"runs/"+$0} ?? "overview"
        let route=try ServerEndpoint(query.connection.endpoint).route("/v1/execution-progress/"+query.workset+"/"+suffix)
        guard var components=URLComponents(url:route,resolvingAgainstBaseURL:false) else {throw ExecutionError.invalid}
        var items=[URLQueryItem(name:"mission_id",value:query.mission)]
        if let snapshot=query.expectedSnapshot {items.append(URLQueryItem(name:"expected_snapshot",value:snapshot))}
        components.queryItems=items
        guard let url=components.url else {throw ExecutionError.invalid}
        var request=URLRequest(url:url);request.httpMethod="GET"
        request.setValue("Bearer "+query.connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(query.connection.workspaceInstanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(query.connection.draftGrant,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        request.setValue(query.activity.token,forHTTPHeaderField:"X-Workspace-Activity-Grant")
        if let binding=query.binding {request.setValue(binding,forHTTPHeaderField:"X-Workspace-Execution-Binding")}
        let (bytes,response)=try await session.bytes(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url,http.expectedContentLength<=600000,http.value(forHTTPHeaderField:"Content-Type")?.lowercased().hasPrefix("application/json")==true,http.value(forHTTPHeaderField:"Cache-Control")?.lowercased()=="no-store" else {throw ExecutionError.invalid}
        if [401,403].contains(http.statusCode) {throw ExecutionError.denied}
        var data=Data()
        for try await byte in bytes {guard data.count<600000 else {throw ExecutionError.invalid};data.append(byte)}
        try Task.checkCancellation()
        guard http.statusCode==200 else {throw try failure(data,http.statusCode)}
        return try ExecutionWire.decode(data,query)
    }
    private func failure(_ data:Data,_ status:Int) throws->ExecutionError {
        guard data.count<=2048,let raw=try JSONSerialization.jsonObject(with:data) as? [String:String],Set(raw.keys)==["error"],let code=raw["error"],ActivityWire.matches(code,"^EXECUTION_PROGRESS_[A-Z_]{1,64}$") else {return .invalid}
        switch (status,code) {
        case (503,"EXECUTION_PROGRESS_UNBOUND"):return .unbound
        case (404,"EXECUTION_PROGRESS_RUN_NOT_FOUND"):return .notFound
        case (409,"EXECUTION_PROGRESS_SNAPSHOT_CONFLICT"):return .snapshot
        case (422,"EXECUTION_PROGRESS_UNSUPPORTED"):return .unsupported
        case (409,"EXECUTION_PROGRESS_SOURCE_CORRUPT"),(500,"EXECUTION_PROGRESS_SOURCE_CORRUPT"),(503,"EXECUTION_PROGRESS_SOURCE_CORRUPT"):return .corrupt
        case (409,"EXECUTION_PROGRESS_UNAVAILABLE"),(503,"EXECUTION_PROGRESS_UNAVAILABLE"):return .unavailable
        default:return .invalid
        }
    }
}
