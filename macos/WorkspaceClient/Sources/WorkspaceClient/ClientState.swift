import Foundation
import Security

struct ServerBinding: Codable, Equatable, Sendable {
    let endpoint: String
    let instanceID: String
}

enum CredentialError: Error, LocalizedError {
    case keychain(OSStatus), corruptBinding, incompleteBinding

    var errorDescription: String? {
        switch self {
        case .keychain: "The Mac Keychain could not store or read this Workspace binding."
        case .corruptBinding: "The saved Workspace binding is invalid. Forget it explicitly to start again."
        case .incompleteBinding: "A token was saved without a Server binding. Forget it explicitly before pairing again."
        }
    }
}

protocol CredentialStore {
    func binding() throws -> ServerBinding?
    func token() throws -> String?
    func save(binding: ServerBinding, token: String) throws
    func forget() throws
}

struct ClientKeychain: CredentialStore {
    private let service = "com.pcvantol.workspace.native-client.v1"

    private func query(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
         kSecAttrAccount: account, kSecAttrSynchronizable: kCFBooleanFalse as Any]
    }

    private func read(_ account: String) throws -> Data? {
        var request = query(account)
        request[kSecReturnData] = true
        request[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialError.keychain(status)
        }
        return data
    }

    private func save(_ data: Data, account: String) throws {
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw CredentialError.keychain(status) }
        var item = query(account)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw CredentialError.keychain(added) }
    }

    func binding() throws -> ServerBinding? {
        guard let data = try read("server-binding") else { return nil }
        guard let binding = try? JSONDecoder().decode(ServerBinding.self, from: data),
              let endpoint = try? ServerEndpoint(binding.endpoint),
              endpoint.url.absoluteString == binding.endpoint,
              binding.instanceID.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
            throw CredentialError.corruptBinding
        }
        return binding
    }

    func token() throws -> String? {
        guard let data = try read("server-token") else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(binding: ServerBinding, token: String) throws {
        try save(Data(token.utf8), account: "server-token")
        try save(JSONEncoder().encode(binding), account: "server-binding")
    }

    func forget() throws {
        for account in ["server-binding", "server-token"] {
            let status = SecItemDelete(query(account) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialError.keychain(status)
            }
        }
    }
}

@MainActor
final class ClientState: ObservableObject {
    @Published private(set) var phase = "UNCONFIGURED"
    @Published private(set) var detail = "Set a Server address and token in Settings."
    @Published private(set) var snapshot: ServerSnapshot?
    @Published private(set) var savedEndpoint = ""
    @Published private(set) var savedInstance = ""
    @Published private(set) var canForgetBinding = false

    private let keychain: any CredentialStore
    private let transport = ServerTransport()
    private var activeTask: Task<Void, Never>?
    private var attempt = 0

    init(keychain: any CredentialStore = ClientKeychain()) {
        self.keychain = keychain
        do {
            if let binding = try keychain.binding() {
                savedEndpoint = binding.endpoint
                savedInstance = binding.instanceID
                canForgetBinding = true
                phase = "DISCONNECTED"
                detail = "Saved Server binding; reconnect to read current data."
            } else if try keychain.token() != nil {
                canForgetBinding = true
                phase = "UNAVAILABLE"
                detail = CredentialError.incompleteBinding.localizedDescription
            }
        } catch {
            canForgetBinding = true
            phase = "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func connect(address: String, enteredToken: String = "") {
        activeTask?.cancel()
        attempt += 1
        let current = attempt
        do {
            let endpoint = try ServerEndpoint(address)
            let binding = try keychain.binding()
            let storedToken = try keychain.token()
            if binding == nil && storedToken != nil {
                throw CredentialError.incompleteBinding
            }
            if let binding, binding.endpoint != endpoint.url.absoluteString {
                throw ClientError.bindingChanged
            }
            let token = enteredToken.isEmpty ? storedToken ?? "" : enteredToken
            guard !token.isEmpty else { throw ClientError.noToken }
            phase = "CONNECTING"
            detail = "Reading the Server identity and current status."
            activeTask = Task {
                do {
                    let result = try await transport.connect(endpoint: endpoint, token: token,
                                                             pinnedInstance: binding?.instanceID)
                    guard !Task.isCancelled, current == attempt else { return }
                    let newBinding = ServerBinding(endpoint: endpoint.url.absoluteString,
                                                   instanceID: result.identity.instance_id)
                    try keychain.save(binding: newBinding, token: token)
                    savedEndpoint = newBinding.endpoint
                    savedInstance = newBinding.instanceID
                    canForgetBinding = true
                    snapshot = result
                    phase = "CONNECTED"
                    detail = "Fresh Server read at \(result.observedAt.formatted(date: .abbreviated, time: .standard))."
                } catch {
                    guard !Task.isCancelled, current == attempt else { return }
                    if error is CredentialError { canForgetBinding = true }
                    phase = "UNAVAILABLE"
                    let prior = snapshot.map { " Last successful read: \($0.observedAt.formatted(date: .abbreviated, time: .standard)); displayed data is cached." } ?? ""
                    detail = error.localizedDescription + prior
                }
            }
        } catch {
            phase = "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }

    func reconnect() {
        guard !savedEndpoint.isEmpty, phase != "CONNECTING" else { return }
        connect(address: savedEndpoint)
    }

    func cancel() {
        activeTask?.cancel()
        attempt += 1
        phase = "DISCONNECTED"
        detail = "Connection cancelled. Previous data, if shown, is cached."
    }

    func forget() {
        activeTask?.cancel()
        attempt += 1
        do {
            try keychain.forget()
            savedEndpoint = ""
            savedInstance = ""
            canForgetBinding = false
            snapshot = nil
            phase = "UNCONFIGURED"
            detail = "Server binding removed."
        } catch {
            phase = "UNAVAILABLE"
            detail = error.localizedDescription
        }
    }
}
