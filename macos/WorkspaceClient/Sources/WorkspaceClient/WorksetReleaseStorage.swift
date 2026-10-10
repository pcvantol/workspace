import Foundation
import Security

protocol WorksetReleaseCredentials: Sendable {
    func load() throws -> WorksetReleaseAccess?
    func save(_ access: WorksetReleaseAccess) throws
    func forget() throws
}
struct WorksetReleaseKeychain: WorksetReleaseCredentials {
    let operations: DraftKeychainOperations
    init(operations: DraftKeychainOperations = .live) { self.operations = operations }
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.pcvantol.workspace.native-client.workset-release.v1",
         kSecAttrAccount: "project-subject-grant", kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }
    func load() throws -> WorksetReleaseAccess? {
        var q = query; q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(q as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        let access = try JSONDecoder().decode(WorksetReleaseAccess.self, from: data)
        guard access.valid else { throw CredentialError.corruptBinding }; return access
    }
    func save(_ access: WorksetReleaseAccess) throws {
        guard access.valid else { throw CredentialError.corruptBinding }
        let data = try JSONEncoder().encode(access)
        let status = operations.update(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var entry = query; entry[kSecValueData] = data; entry[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = operations.add(entry as CFDictionary)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }
    func forget() throws {
        let status = operations.delete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.keychain(status) }
    }
}
struct WorksetReleaseJournal: Codable, Equatable, Sendable {
    var pending: WorksetReleaseIntent?
    var history: [WorksetReleaseIntent] = []
    func validate(key: String) throws {
        guard history.count <= 16, Set(history.map { $0.command.operation_id }).count == history.count else { throw AdvisoryError.invalid }
        for intent in history + (pending.map { [$0] } ?? []) {
            guard intent.scopeKey == key, intent.accessFingerprint.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw AdvisoryError.invalid }
            _ = try intent.command.data()
        }
    }
}
protocol WorksetReleaseIntentStorage: Sendable {
    func load(_ key: String) throws -> WorksetReleaseJournal
    func save(_ journal: WorksetReleaseJournal, key: String) throws
}
struct PrivateWorksetReleaseStore: WorksetReleaseIntentStorage {
    let records: PrivateLocalRecordStore
    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Workspace/WorksetReleaseIntents")) {
        records = PrivateLocalRecordStore(root: root, namespace: "workset-release")
    }
    func load(_ key: String) throws -> WorksetReleaseJournal {
        guard let data = try records.load(key) else { return .init() }
        let journal = try JSONDecoder().decode(WorksetReleaseJournal.self, from: data)
        try journal.validate(key: key); return journal
    }
    func save(_ journal: WorksetReleaseJournal, key: String) throws {
        try journal.validate(key: key); try records.save(JSONEncoder().encode(journal), key: key)
    }
}
