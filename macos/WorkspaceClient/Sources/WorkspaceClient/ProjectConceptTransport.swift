import Foundation

struct ProjectConceptTransport: ConceptServing {
    let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration:configuration,delegate:RejectRedirects(),delegateQueue:nil)
    }
    private func request<T: Decodable>(_ type:T.Type, _ connection:ConceptConnection, path:String, method:String="GET", body:Data?=nil) async throws -> T {
        let endpoint = try ServerEndpoint(connection.access.endpoint)
        let url = endpoint.route(path)
        var request = URLRequest(url:url); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer "+connection.bearer,forHTTPHeaderField:"Authorization")
        request.setValue(connection.access.instanceID,forHTTPHeaderField:"X-Workspace-Instance")
        request.setValue(connection.access.token,forHTTPHeaderField:"X-Workspace-Draft-Grant")
        if body != nil { request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, http.url == url else { throw ConceptError.invalid }
        switch http.statusCode {
        case 200,201: break
        case 401,403: throw ConceptError.denied
        case 404: throw ConceptError.notFound
        case 409: throw ConceptError.conflict
        case 400: throw ConceptError.invalid
        default: throw ConceptError.unavailable
        }
        guard data.count <= 2_000_000, http.value(forHTTPHeaderField:"Content-Type")?.hasPrefix("application/json") == true,
              let value = try? JSONDecoder().decode(T.self,from:data) else { throw ConceptError.invalid }
        return value
    }
    private struct List: Decodable { let actor_id:String; let context_id:String; let concepts:[ProjectConceptSummary] }
    func list(_ connection:ConceptConnection) async throws -> [ProjectConceptSummary] {
        let result = try await request(List.self,connection,path:"/v1/project-concepts")
        guard result.context_id == connection.access.projectID, result.concepts.count <= 500,
              result.concepts.allSatisfy({$0.actor_id == result.actor_id}) else { throw ConceptError.invalid }
        return result.concepts
    }
    func get(_ connection:ConceptConnection,id:String) async throws -> ProjectConcept {
        guard id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) != nil else { throw ConceptError.invalid }
        let result = try await request(ProjectConcept.self,connection,path:"/v1/project-concepts/"+id)
        guard result.id == id else { throw ConceptError.invalid }; return result
    }
    func save(_ connection:ConceptConnection,id:String?,command:ConceptCommand) async throws -> ProjectConcept {
        if let id, id.range(of:"^[0-9a-f]{32}$",options:.regularExpression) == nil { throw ConceptError.invalid }
        return try await request(ProjectConcept.self,connection,path:"/v1/project-concepts"+(id.map {"/"+$0} ?? ""),method:id == nil ? "POST" : "PATCH",body:JSONEncoder().encode(command))
    }
}
