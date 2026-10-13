import Foundation
import Security

protocol ActivityCredentials: Sendable {
    func load() throws -> ActivityAccess?
    func save(_ access: ActivityAccess) throws
    func forget() throws
}
struct ActivityKeychain: ActivityCredentials {
    let operations: DraftKeychainOperations
    init(operations: DraftKeychainOperations = .live) { self.operations = operations }
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.pcvantol.workspace.native-client.workset-activity.v1",
         kSecAttrAccount: "activity-read-grant", kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }
    func load() throws -> ActivityAccess? {
        var q = query; q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(q as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        let access = try JSONDecoder().decode(ActivityAccess.self, from: data)
        guard access.valid else { throw CredentialError.corruptBinding }; return access
    }
    func save(_ access: ActivityAccess) throws {
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

struct ActivityJournal: Codable, Sendable {
    var pageKeys: [String] = []
    var cursor: String?
    var complete = false
    var lastViewedIDs: [String] = []
    var previousCursor: String?
    var comparisonKnown = false
    var historicalKeys: [String] = []
}
struct ActivityLocalStore: Sendable {
    let records: PrivateLocalRecordStore
    init(root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/ActivityViews")) {
        records=PrivateLocalRecordStore(root:root,namespace:"workset-activity")
    }
    init(records:PrivateLocalRecordStore) { self.records=records }
    private func scoped(_ key:String) throws -> PrivateLocalRecordStore {
        guard ActivityWire.matches(key,"^[0-9a-f]{64}$") else { throw AdvisoryError.invalid }
        return PrivateLocalRecordStore(root:records.root.appendingPathComponent(key),namespace:"workset-activity",synchronizeDirectory:records.synchronizeDirectory)
    }
    private struct Envelope: Codable {
        let version: Int
        var journal: ActivityJournal
        let cursorKey: String?
        let previousCursorKey: String?
    }
    private func cursor(_ value:String?,scope:String,label:String,records:PrivateLocalRecordStore) throws -> String? {
        guard let value else { return nil }
        guard ActivityWire.matches(value,"^[A-Za-z0-9_.-]{1,32768}$") else { throw AdvisoryError.invalid }
        let key=ActivityWire.hash(Data((scope+"/"+label+"/"+value).utf8))
        try records.save(Data(value.utf8),key:key);return key
    }
    private func restored(_ key:String?,scope:String,label:String,records:PrivateLocalRecordStore) throws -> String? {
        guard let key else { return nil }
        guard let data=try records.load(key),let value=String(data:data,encoding:.utf8),
            ActivityWire.matches(value,"^[A-Za-z0-9_.-]{1,32768}$"),
            ActivityWire.hash(Data((scope+"/"+label+"/"+value).utf8))==key else { throw AdvisoryError.invalid }
        return value
    }
    func load(_ key:String) throws -> ActivityJournal {
        let records=try scoped(key)
        guard let data=try records.load(key) else { return .init() }
        let envelope=try JSONDecoder().decode(Envelope.self,from:data)
        guard envelope.version==1,envelope.journal.cursor==nil,envelope.journal.previousCursor==nil else { throw AdvisoryError.invalid }
        var value=envelope.journal
        value.cursor=try restored(envelope.cursorKey,scope:key,label:"current",records:records)
        value.previousCursor=try restored(envelope.previousCursorKey,scope:key,label:"previous",records:records)
        try validate(value);return value
    }
    private func validate(_ value:ActivityJournal) throws {
        guard value.historicalKeys.count<=8,value.historicalKeys.allSatisfy({ActivityWire.matches($0,"^[0-9a-f]{64}$")}),value.pageKeys.count<=8,Set(value.pageKeys).count==value.pageKeys.count,value.lastViewedIDs.count<=128,
            value.pageKeys.allSatisfy({ActivityWire.matches($0,"^[0-9a-f]{64}$")}),
            Set(value.lastViewedIDs).count==value.lastViewedIDs.count,
            value.lastViewedIDs.allSatisfy({ActivityWire.matches($0,"^[0-9a-f]{64}$")}),
            [value.cursor,value.previousCursor].compactMap({$0}).allSatisfy({ActivityWire.matches($0,"^[A-Za-z0-9_.-]{1,32768}$")}) else { throw AdvisoryError.invalid }
    }
    private func save(_ value:ActivityJournal,_ key:String,records:PrivateLocalRecordStore,dir:Int32) throws {
        try validate(value)
        let current=try cursor(value.cursor,scope:key,label:"current",records:records),previous=try cursor(value.previousCursor,scope:key,label:"previous",records:records)
        var metadata=value;metadata.cursor=nil;metadata.previousCursor=nil
        try records.save(JSONEncoder().encode(Envelope(version:1,journal:metadata,cursorKey:current,previousCursorKey:previous)),key:key)
        try records.prune(Set(value.pageKeys+value.historicalKeys+[key]+[current,previous].compactMap{$0}),directory:dir)
    }
    func save(_ value:ActivityJournal,_ key:String) throws {
        let records=try scoped(key)
        try records.transaction { dir in try save(value,key,records:records,dir:dir) }
    }
    func commit(_ value:ActivityJournal,_ key:String,page:Data,pageKey:String) throws {
        guard page.count<=32768,value.pageKeys.contains(pageKey) else { throw AdvisoryError.invalid }
        let records=try scoped(key)
        try records.transaction { dir in
            try records.save(page,key:pageKey)
            try save(value,key,records:records,dir:dir)
        }
    }
    func pages(_ journal:ActivityJournal,_ key:String) throws -> [Data] {
        let records=try scoped(key)
        return try records.transaction { _ in
            try journal.pageKeys.map { guard let value=try records.load($0) else { throw AdvisoryError.unavailable };return value }
        }
    }
}
