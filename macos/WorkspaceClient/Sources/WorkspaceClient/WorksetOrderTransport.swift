import Foundation

protocol OrderServing: Sendable {
    func probe(_ connection:AdvisoryConnection,token:String) async throws -> OrderAccess
    func read(_ connection:AdvisoryConnection,access:OrderAccess,workset:String) async throws -> OrderCurrent
    func preview(_ connection:AdvisoryConnection,access:OrderAccess,workset:String,proposed:[String]) async throws -> OrderPreview
    func operation(_ connection:AdvisoryConnection,access:OrderAccess,intent:OrderIntent,confirm:Bool) async throws -> Data
}
struct OrderTransport: OrderServing {
    let session:URLSession
    init(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=10;configuration.timeoutIntervalForResource=20
        session=URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    func request(_ connection:AdvisoryConnection,token:String,suffix:String,body:Data?=nil) async throws -> Data {
        guard ActivityWire.matches(token,"^[A-Za-z0-9_-]{43}$") else { throw AdvisoryError.denied }
        let url=try ServerEndpoint(connection.endpoint).route("/v1/workset-orders"+suffix)
        var request=URLRequest(url:url);request.httpMethod=body == nil ? "GET":"POST";request.httpBody=body
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(connection.workspaceInstanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(connection.draftGrant,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        request.setValue(token,forHTTPHeaderField:"X-Workspace-Order-Grant")
        try Task.checkCancellation();let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.url==url,data.count<=1_000_000,
            http.value(forHTTPHeaderField:"Content-Type")?.lowercased().hasPrefix("application/json")==true else { throw AdvisoryError.invalid }
        if http.statusCode==401 || http.statusCode==403 { throw AdvisoryError.denied }
        guard http.statusCode==200 else {
            let raw=try OrderWire.object(data)
            guard Set(raw.keys)==["error"],let code=raw["error"] as? String else { throw AdvisoryError.invalid }
            throw AdvisoryError.state(code)
        }
        return data
    }
    func probe(_ connection:AdvisoryConnection,token:String) async throws -> OrderAccess {
        var raw=try OrderWire.object(await request(connection,token:token,suffix:""))
        guard raw["consumer_contract"] as? String=="workspace-workset-order-access/v1",
            raw["producer_source"] as? String==ActivityWire.pin,raw["producer_version"] as? String=="2.15.0",
            raw["actor_id"] as? String==connection.actorID,raw["workspace_project_id"] as? String==connection.workspaceProjectID else { throw AdvisoryError.denied }
        let binding=ActivityAccess(endpoint:connection.endpoint,workspaceInstanceID:connection.workspaceInstanceID,actorID:connection.actorID,workspaceProjectID:connection.workspaceProjectID,token:token,binding_id:raw["binding_id"] as? String ?? "",scope:try AdvisoryWire.decode(raw["scope"] as Any,as:ActivityScope.self),installation_id:raw["installation_id"] as? String ?? "",worksets:try AdvisoryWire.decode(raw["worksets"] as Any,as:[ActivitySubject].self),expires_at:raw["expires_at"] as? String ?? "")
        let access=OrderAccess(binding:binding,permissions:raw["permissions"] as? [String] ?? [],maximumAmendments:raw["maximum_amendments"] as? Int ?? 0)
        for key in ["consumer_contract","producer_source","producer_version","actor_id","workspace_project_id","binding_id","installation_id"] { raw.removeValue(forKey:key) }
        try OrderWire.validate(raw,"capability")
        guard access.valid,(WorksetReleaseWire.date(binding.expires_at).map{$0>Date()} ?? false) else { throw AdvisoryError.denied }
        return access
    }
    func read(_ connection:AdvisoryConnection,access:OrderAccess,workset:String) async throws -> OrderCurrent {
        guard ActivityWire.identifier(workset) else { throw AdvisoryError.invalid }
        return try OrderWire.current(await request(connection,token:access.binding.token,suffix:"/"+workset),access,workset)
    }
    func preview(_ connection:AdvisoryConnection,access:OrderAccess,workset:String,proposed:[String]) async throws -> OrderPreview {
        guard ActivityWire.identifier(workset) else { throw AdvisoryError.invalid }
        let body=try JSONSerialization.data(withJSONObject:["contract_version":OrderWire.contract,"proposed_order":proposed])
        return try OrderWire.preview(await request(connection,token:access.binding.token,suffix:"/"+workset+"/preview",body:body),access,workset,proposed)
    }
    func operation(_ connection:AdvisoryConnection,access:OrderAccess,intent:OrderIntent,confirm:Bool) async throws -> Data {
        guard ActivityWire.identifier(intent.workset),ActivityWire.identifier(intent.operation),intent.scopeKey==access.key(intent.workset,draft:connection.draftGrant) else { throw AdvisoryError.denied }
        let rawRequest=try OrderWire.object(intent.request);try OrderWire.validate(rawRequest,"request");try OrderWire.scope(rawRequest,access)
        guard rawRequest["operation_id"] as? String==intent.operation,rawRequest["workset_id"] as? String==intent.workset else { throw AdvisoryError.invalid }
        let suffix="/"+intent.workset+(confirm ? "/confirm":"/operations/"+intent.operation)
        let data=try await request(connection,token:access.binding.token,suffix:suffix,body:confirm ? intent.request:nil)
        let raw=try OrderWire.object(data);try OrderWire.validate(raw,"operation")
        guard raw["operation_id"] as? String==intent.operation,
            let original=raw["original_request"] as? [String:Any],NSDictionary(dictionary:original).isEqual(to:rawRequest) else { throw AdvisoryError.invalid }
        if raw["state"] as? String=="APPLIED" {
            guard let receipt=raw["original_receipt"] as? [String:Any],let package=rawRequest["package"] as? [String:Any],
                receipt["operation_id"] as? String==intent.operation,receipt["workset_id"] as? String==intent.workset,
                receipt["package_digest"] as? String==rawRequest["package_digest"] as? String,
                receipt["original_order"] as? [String]==package["current_order"] as? [String],
                receipt["applied_order"] as? [String]==package["proposed_order"] as? [String],
                receipt["fixed_prefix"] as? Int==package["fixed_prefix"] as? Int,
                receipt["order_revision"] as? Int==(package["order_revision"] as? Int).map{$0+1},
                receipt["consumed_activations"] as? Int==package["consumed_activations"] as? Int,
                let decisions=receipt["decisions"] as? [String:String],Set(decisions.keys)==["business","architecture"],
                decisions==raw["canonical_decisions_observed"] as? [String:String] else { throw AdvisoryError.invalid }
        }
        _ = try OrderWire.current(JSONSerialization.data(withJSONObject:raw["current"]!),access,intent.workset)
        return data
    }
}
