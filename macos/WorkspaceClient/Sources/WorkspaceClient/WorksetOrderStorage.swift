import Foundation
import CryptoKit
import Security

protocol OrderCredentials: Sendable {
    func load() throws -> OrderAccess?
    func save(_ access: OrderAccess) throws
    func forget() throws
}
struct OrderKeychain: OrderCredentials {
    let operations: DraftKeychainOperations
    init(operations: DraftKeychainOperations = .live) { self.operations = operations }
    private var query: [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.pcvantol.workspace.native-client.workset-order.v1",
         kSecAttrAccount: "order-grant", kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }
    func load() throws -> OrderAccess? {
        var q = query; q[kSecReturnData] = true; q[kSecMatchLimit] = kSecMatchLimitOne
        let (status, data) = operations.copy(q as CFDictionary)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data else { throw CredentialError.keychain(status) }
        let access = try JSONDecoder().decode(OrderAccess.self, from: data)
        guard access.valid else { throw CredentialError.corruptBinding }; return access
    }
    func save(_ access: OrderAccess) throws {
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


struct OrderIntentStore: Sendable {
    let records:PrivateLocalRecordStore
    init(root:URL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Workspace/OrderIntents")) { records=PrivateLocalRecordStore(root:root,namespace:"workset-order") }
    private struct Journal:Codable {
        var entries:[OrderIntent] = []
        var operations:[String] = []
        var rejected:[String:String] = [:]
        enum CodingKeys:String,CodingKey {case entries,operations,rejected}
        init(entries:[OrderIntent]=[],operations:[String]=[],rejected:[String:String]=[:]) {self.entries=entries;self.operations=operations;self.rejected=rejected}
        init(from decoder:any Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            entries=try c.decodeIfPresent([OrderIntent].self,forKey:.entries) ?? []
            operations=try c.decodeIfPresent([String].self,forKey:.operations) ?? []
            rejected=try c.decodeIfPresent([String:String].self,forKey:.rejected) ?? [:]
        }
    }
    private func recordKey(_ scope:String,_ operation:String) -> String { SHA256.hash(data:Data((scope+"\n"+operation).utf8)).map{String(format:"%02x",$0)}.joined() }
    private func journal(_ key:String) throws -> Journal {
        guard ActivityWire.matches(key,"^[0-9a-f]{64}$") else {throw AdvisoryError.invalid}
        guard let data=try records.load(key) else {return Journal()}
        var value=try JSONDecoder().decode(Journal.self,from:data)
        guard value.entries.isEmpty || value.operations.isEmpty else {throw AdvisoryError.invalid}
        if !value.operations.isEmpty {
            value.entries=try value.operations.map {operation in
                guard ActivityWire.identifier(operation),let bytes=try records.load(recordKey(key,operation)) else {throw AdvisoryError.invalid}
                return try JSONDecoder().decode(OrderIntent.self,from:bytes)
            }
        }
        guard value.entries.count<=80,Set(value.entries.map(\.operation)).count==value.entries.count,
            value.rejected.count<=64,value.entries.filter({value.rejected[$0.operation]==nil}).count<=16,
            value.rejected.keys.allSatisfy({operation in value.entries.contains(where:{$0.operation==operation})}) else {throw AdvisoryError.invalid}
        for entry in value.entries {
            guard entry.scopeKey==key,ActivityWire.identifier(entry.operation),ActivityWire.identifier(entry.workset) else {throw AdvisoryError.invalid}
            let raw=try OrderWire.object(entry.request);try OrderWire.validate(raw,"request")
            guard raw["operation_id"] as? String==entry.operation,raw["workset_id"] as? String==entry.workset else {throw AdvisoryError.invalid}
        }
        return value
    }
    private func commit(_ value:Journal,_ key:String) throws {
        for entry in value.entries {
            let record=recordKey(key,entry.operation),bytes=try JSONEncoder().encode(entry)
            if let existing=try records.load(record) {guard try JSONDecoder().decode(OrderIntent.self,from:existing)==entry else {throw AdvisoryError.invalid}}
            else {try records.save(bytes,key:record)}
        }
        try records.save(JSONEncoder().encode(Journal(operations:value.entries.map(\.operation),rejected:value.rejected)),key:key)
    }
    func load(_ key:String) throws -> OrderIntent? {try journal(key).entries.last}
    func save(_ intent:OrderIntent) throws {
        try OrderWire.validate(OrderWire.object(intent.request),"request")
        var value=try journal(intent.scopeKey)
        if let original=value.entries.first(where:{$0.operation==intent.operation}) {guard original==intent else {throw AdvisoryError.invalid};return}
        guard value.entries.count<80,value.entries.filter({value.rejected[$0.operation]==nil}).count<16 else {throw AdvisoryError.invalid}
        value.entries.append(intent);try commit(value,intent.scopeKey)
    }
    func rejectionCode(_ intent:OrderIntent) throws -> String? {try journal(intent.scopeKey).rejected[intent.operation]}
    func isRejected(_ intent:OrderIntent) throws -> Bool {try rejectionCode(intent) != nil}
    func markRejected(_ intent:OrderIntent,code:String) throws {
        var value=try journal(intent.scopeKey)
        guard value.entries.contains(intent),value.rejected[intent.operation] != nil || value.rejected.count<64 else {throw AdvisoryError.invalid}
        value.rejected[intent.operation]=code;try commit(value,intent.scopeKey)
    }
}
