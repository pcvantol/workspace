import Foundation

// Own request and exact consent snapshot only. Never an authority or canonical history store.
struct MissionTransportIntent: Codable, Equatable, Sendable {
    let key: String
    let connectionScope: [String]
    let kind: String
    let refine: AdvisoryRequest?
    let approvalBody: Data?
    let frozenPackage: Data?
    func matches(_ connection: AdvisoryConnection) -> Bool {
        key == CandidateLocal.scopeKey(connection) && connectionScope == Self.scope(connection)
    }
    static func scope(_ connection: AdvisoryConnection) -> [String] {
        [connection.endpoint, connection.workspaceInstanceID, connection.workspaceProjectID, connection.actorID, connection.conversationID]
    }
    func validate() throws {
        guard key.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil, connectionScope.count == 5 else { throw AdvisoryError.invalid }
        switch kind {
        case "refine":
            guard let refine, approvalBody == nil, frozenPackage == nil, refine.conversation_id == connectionScope[4] else { throw AdvisoryError.invalid }
            try MissionConceptWire.validate(AdvisoryWire.object(JSONEncoder().encode(refine)),kind:"request")
        case "approve":
            guard refine == nil, let approvalBody else { throw AdvisoryError.invalid }
            let request=try AdvisoryWire.object(approvalBody)
            try MissionConceptWire.validate(request,kind:"approve_request")
            if let frozenPackage {
                let package=try AdvisoryWire.object(frozenPackage)
                try MissionConceptWire.validate(package,kind:"frozen_package")
                guard try AdvisoryWire.digest(package) == request["package_digest"] as? String,
                      (package["source"] as? [String:Any])?["conversation_id"] as? String == connectionScope[4] else { throw AdvisoryError.invalid }
            }
        default: throw AdvisoryError.invalid
        }
    }
}
protocol MissionIntentStore: Sendable {
    func load(_ key: String) throws -> MissionTransportIntent?
    func save(_ intent: MissionTransportIntent) throws
    func clear(_ key: String) throws
}
struct PrivateMissionIntentStore: MissionIntentStore {
    let records: PrivateLocalRecordStore
    init(root: URL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/MissionIntents")) {
        records = PrivateLocalRecordStore(root:root,namespace:"mission")
    }
    func load(_ key: String) throws -> MissionTransportIntent? {
        guard let data=try records.load(key) else { return nil }
        let raw=try AdvisoryWire.object(data)
        if raw["cleared"] as? Bool == true, Set(raw.keys)==["cleared","key"], raw["key"] as? String == key { return nil }
        let intent=try JSONDecoder().decode(MissionTransportIntent.self,from:data)
        guard intent.key==key else { throw AdvisoryError.invalid }
        try intent.validate();return intent
    }
    func save(_ intent: MissionTransportIntent) throws {
        try intent.validate();try records.save(JSONEncoder().encode(intent),key:intent.key)
    }
    func clear(_ key: String) throws {
        // Durable tombstone uses the same pinned-directory atomic write and sync as an intent.
        try records.save(JSONSerialization.data(withJSONObject:["cleared":true,"key":key]),key:key)
    }
}
