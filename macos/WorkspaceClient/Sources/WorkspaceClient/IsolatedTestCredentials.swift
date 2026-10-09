#if WORKSPACE_ISOLATED_TEST
import Darwin
import Foundation

struct IsolatedTestDocument: Decodable {
    let endpoint: String
    let instance_id: String
    let read_token: String
    let project_id: String
    let draft_grant: String
    let local_root: String
    let review_grant: String?
    let review_actor: String?
    let review_forge_instance: String?
    let review_mission_ids: [String]?

    let worklist_grant: String?
    let worklist_actor: String?
    let worklist_forge_instance: String?
    let worklist_workset_ids: [String]?

    let advisory_access: AdvisoryAccess?
    let mission_access:AdvisoryAccess?
    let candidate_access: CandidateAccess?

    let control_grant: String?
    let control_actor: String?
    let control_forge_instance: String?
    let control_workset_ids: [String]?

    static func load() throws -> IsolatedTestDocument {
        guard let path = ProcessInfo.processInfo.environment["WORKSPACE_ISOLATED_CREDENTIALS_FILE"],
              path.hasPrefix("/"), !path.contains("/../") else {
            throw ConversationError.invalidResponse
        }
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              attributes[.ownerAccountID] as? Int == Int(getuid()),
              ((attributes[.posixPermissions] as? Int) ?? 0o777) & 0o077 == 0 else {
            throw ConversationError.invalidResponse
        }
        guard let data = FileManager.default.contents(atPath: path), data.count <= 4096 else {
            throw ConversationError.invalidResponse
        }
        let document = try JSONDecoder().decode(Self.self, from: data)
        let endpoint = try ServerEndpoint(document.endpoint)
        guard endpoint.url.absoluteString == document.endpoint, endpoint.url.scheme == "http",
              ["127.0.0.1", "localhost", "::1"].contains(endpoint.url.host ?? ""),
              document.instance_id.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil,
              !document.read_token.isEmpty, document.read_token.count <= 256,
              document.draft_grant.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              !document.project_id.isEmpty, document.project_id.count <= 120,
              document.local_root.hasPrefix("/"), !document.local_root.contains("/../") else {
            throw ConversationError.invalidResponse
        }
        let reviewFields = [document.review_grant != nil, document.review_actor != nil,
                            document.review_forge_instance != nil, document.review_mission_ids != nil]
        if reviewFields.contains(true) {
            guard reviewFields.allSatisfy({ $0 }),
                  document.review_grant?.range(of: "^[A-Za-z0-9_-]{43}$",
                                               options: .regularExpression) != nil,
                  document.review_actor?.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$",
                                               options: .regularExpression) != nil,
                  document.review_forge_instance?.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$",
                                                        options: .regularExpression) != nil,
                  let missions = document.review_mission_ids, (1...32).contains(missions.count),
                  Set(missions).count == missions.count,
                  missions.allSatisfy({ $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$",
                                                  options: .regularExpression) != nil }) else {
                throw ConversationError.invalidResponse
            }
        }
        let worklistFields = [document.worklist_grant != nil, document.worklist_actor != nil,
                              document.worklist_forge_instance != nil, document.worklist_workset_ids != nil]
        if worklistFields.contains(true) {
            guard worklistFields.allSatisfy({ $0 }),
                  WorklistAccess(endpoint: document.endpoint, workspaceInstanceID: document.instance_id,
                    forgeInstanceID: document.worklist_forge_instance ?? "", actorID: document.worklist_actor ?? "",
                    worksetIDs: document.worklist_workset_ids ?? [], token: document.worklist_grant ?? "").valid else {
                throw ConversationError.invalidResponse
            }
        }
        let controlFields = [document.control_grant != nil, document.control_actor != nil,
                             document.control_forge_instance != nil, document.control_workset_ids != nil]
        if controlFields.contains(true) {
            guard controlFields.allSatisfy({ $0 }),
                  WorklistAccess(endpoint: document.endpoint, workspaceInstanceID: document.instance_id,
                    forgeInstanceID: document.control_forge_instance ?? "", actorID: document.control_actor ?? "",
                    worksetIDs: document.control_workset_ids ?? [], token: document.control_grant ?? "").valid else {
                throw ConversationError.invalidResponse
            }
        }
        if let advisory=document.advisory_access {
            guard advisory.valid,advisory.endpoint==document.endpoint,advisory.workspaceInstanceID==document.instance_id,
                  advisory.workspaceProjectID==document.project_id else { throw ConversationError.invalidResponse }
        }
        if let mission=document.mission_access {
            guard mission.validForMission,mission.endpoint==document.endpoint,mission.workspaceInstanceID==document.instance_id,
                  mission.workspaceProjectID==document.project_id else { throw ConversationError.invalidResponse }
        }
        if let candidate=document.candidate_access {
            guard candidate.valid,candidate.endpoint==document.endpoint,candidate.workspaceInstanceID==document.instance_id,
                  candidate.workspaceProjectID==document.project_id else { throw ConversationError.invalidResponse }
        }
        return document
    }
}

final class IsolatedServerCredentials: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBinding: ServerBinding?
    private var storedToken: String?

    init(_ document: IsolatedTestDocument) {
        storedBinding = ServerBinding(endpoint: document.endpoint, instanceID: document.instance_id)
        storedToken = document.read_token
    }

    func binding() throws -> ServerBinding? { lock.withLock { storedBinding } }
    func token() throws -> String? { lock.withLock { storedToken } }
    func save(binding: ServerBinding, token: String) throws {
        lock.withLock { storedBinding = binding; storedToken = token }
    }
    func forget() throws { lock.withLock { storedBinding = nil; storedToken = nil } }
}

final class IsolatedDraftGrant: DraftGrantStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DraftAccess?
    init(_ document: IsolatedTestDocument) {
        stored = DraftAccess(endpoint: document.endpoint, instanceID: document.instance_id,
                             projectID: document.project_id, token: document.draft_grant)
    }
    func load() throws -> DraftAccess? { lock.withLock { stored } }
    func save(_ access: DraftAccess) throws { lock.withLock { stored = access } }
    func forget() throws { lock.withLock { stored = nil } }
}

final class IsolatedReviewGrant: ReviewCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var access: ReviewAccess?
    private var intent: MissionReviewIntent?

    init(_ document: IsolatedTestDocument) {
        if let token = document.review_grant,
           let actor = document.review_actor,
           let forge = document.review_forge_instance,
           let missions = document.review_mission_ids {
            access = ReviewAccess(endpoint: document.endpoint,
                                  workspaceInstanceID: document.instance_id,
                                  forgeInstanceID: forge, actorID: actor,
                                  missionIDs: missions, token: token)
        }
    }

    func loadAccess() throws -> ReviewAccess? { lock.withLock { access } }
    func saveAccess(_ value: ReviewAccess) throws { lock.withLock { access = value } }
    func forgetAccess() throws { lock.withLock { access = nil } }
    func loadIntent() throws -> MissionReviewIntent? { lock.withLock { intent } }
    func saveIntent(_ value: MissionReviewIntent) throws { lock.withLock { intent = value } }
    func forgetIntent() throws { lock.withLock { intent = nil } }
}
final class IsolatedWorklistGrant: WorklistCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var access: WorklistAccess?
    init(_ document: IsolatedTestDocument) {
        if let token = document.worklist_grant, let actor = document.worklist_actor,
           let forge = document.worklist_forge_instance, let ids = document.worklist_workset_ids {
            access = WorklistAccess(endpoint: document.endpoint, workspaceInstanceID: document.instance_id,
                forgeInstanceID: forge, actorID: actor, worksetIDs: ids, token: token)
        }
    }
    func loadAccess() throws -> WorklistAccess? { lock.withLock { access } }
    func saveAccess(_ value: WorklistAccess) throws { lock.withLock { access = value } }
    func forgetAccess() throws { lock.withLock { access = nil } }
}
final class IsolatedWorklistControlGrant: WorklistControlCredentials, @unchecked Sendable {
    private let lock = NSLock()
    private var access: WorklistAccess?
    private let pendingStore: PrivateLocalDraftCache
    private let key = String(repeating: "c", count: 64)
    init(_ document: IsolatedTestDocument) {
        pendingStore = PrivateLocalDraftCache(root: URL(fileURLWithPath: document.local_root).appendingPathComponent("control-intent"))
        if let token = document.control_grant, let actor = document.control_actor,
           let forge = document.control_forge_instance, let ids = document.control_workset_ids {
            access = WorklistAccess(endpoint: document.endpoint, workspaceInstanceID: document.instance_id,
                forgeInstanceID: forge, actorID: actor, worksetIDs: ids, token: token)
        }
    }
    func loadAccess() throws -> WorklistAccess? { lock.withLock { access } }
    func saveAccess(_ value: WorklistAccess) throws { lock.withLock { access = value } }
    func forgetAccess() throws { lock.withLock { access = nil } }
    func loadIntent() throws -> WorklistControlIntent? {
        try lock.withLock {
            guard let value = try pendingStore.load(scopeHash: key) else { return nil }
            let intent = try JSONDecoder().decode(WorklistControlIntent.self, from: Data(value.draft.utf8))
            guard intent.request.valid else { throw CredentialError.corruptBinding }
            return intent
        }
    }
    func saveIntent(_ value: WorklistControlIntent) throws {
        try lock.withLock {
            let data = try JSONEncoder().encode(value)
            let record = LocalDraftSnapshot(scopeHash: key, selectedID: nil, title: "", focus: "", mode: "BUSINESS",
                draft: String(decoding: data, as: UTF8.self), savedRevision: nil, requestID: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
            try pendingStore.save(record)
        }
    }
    func forgetIntent() throws { try lock.withLock { try pendingStore.remove(scopeHash: key) } }
}
final class IsolatedAdvisoryCredentials: AdvisoryCredentials, @unchecked Sendable {
    private let lock=NSLock()
    private var access:AdvisoryAccess?
    private let cache:PrivateLocalDraftCache
    private let key=String(repeating:"a",count:64)
    init(_ document:IsolatedTestDocument,mission:Bool=false) {
        access=mission ? document.mission_access:document.advisory_access
        cache=PrivateLocalDraftCache(root:URL(fileURLWithPath:document.local_root).appendingPathComponent("advisory-intent"))
    }
    func loadAccess() throws -> AdvisoryAccess? { lock.withLock { access } }
    func saveAccess(_ value:AdvisoryAccess) throws { lock.withLock { access=value } }
    func forgetAccess() throws { lock.withLock { access=nil } }
    func loadIntent() throws -> AdvisoryIntent? {
        try lock.withLock {
            guard let record=try cache.load(scopeHash:key) else { return nil }
            let intent=try JSONDecoder().decode(AdvisoryIntent.self,from:Data(record.draft.utf8));_=try intent.request.data();return intent
        }
    }
    func saveIntent(_ value:AdvisoryIntent) throws {
        try lock.withLock {
            let record=LocalDraftSnapshot(scopeHash:key,selectedID:nil,title:"",focus:"",mode:"BUSINESS",
                draft:String(decoding:try JSONEncoder().encode(value),as:UTF8.self),savedRevision:nil,
                requestID:UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased())
            try cache.save(record)
        }
    }
    func forgetIntent() throws { try lock.withLock { try cache.remove(scopeHash:key) } }
}
final class IsolatedCandidateCredentials:CandidateCredentials,@unchecked Sendable {
    private let lock=NSLock()
    private var access:CandidateAccess?
    init(_ document:IsolatedTestDocument) { access=document.candidate_access }
    func load() throws -> CandidateAccess? { lock.withLock { access } }
    func save(_ value:CandidateAccess) throws { lock.withLock { access=value } }
    func forget() throws { lock.withLock { access=nil } }
}
#endif
