import Foundation
import Security

// Compiled together with CredentialCore, then sealed once. Ordinary app builds
// must embed the signed artifact unchanged, rather than compiling this file.
struct FileKeychain: CredentialBackend {
    func read(service: String, account: String, allowInteraction: Bool) throws -> String? {
        try withInteraction(allowInteraction) {
            var query = identity(service, account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw CredentialStoreError(status: errSecDecode)
            }
            return key
        }
    }

    func write(_ key: String, service: String, account: String, allowInteraction: Bool) throws {
        try withInteraction(allowInteraction) {
            let query = identity(service, account)
            let value = [kSecValueData as String: Data(key.utf8)]
            var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
            if status == errSecItemNotFound {
                var item = query.merging(value) { _, new in new }
                item[kSecAttrLabel as String] = service == CredentialContract.validationService ? "TrueL storage check" : "TrueL API Key (\(account))"
                status = SecItemAdd(item as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
        }
    }

    func removeValidation(_ ticket: String) throws {
        try withInteraction(false) {
            let status = SecItemDelete(identity(CredentialContract.validationService, ticket) as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound].contains(status) else { throw CredentialStoreError(status: status) }
        }
    }

    func insert(_ key: String, service: String, account: String, allowInteraction: Bool) throws -> Bool {
        try withInteraction(allowInteraction) {
            var item = identity(service, account)
            item[kSecValueData as String] = Data(key.utf8)
            item[kSecAttrLabel as String] = "TrueL API Key (\(account))"
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecDuplicateItem { return false }
            guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
            return true
        }
    }

    private func identity(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    private func withInteraction<T>(_ allowed: Bool, _ operation: () throws -> T) throws -> T {
        // This switch applies to the process. All calls run on the single broker
        // queue so a background read cannot enable UI for another request.
        let status = SecKeychainSetUserInteractionAllowed(allowed)
        guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
        defer { SecKeychainSetUserInteractionAllowed(false) }
        return try operation()
    }
}

final class Broker: NSObject, CredentialBrokerProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.truel.credentials", qos: .userInitiated)

    func readKey(for account: String, allowInteraction: Bool, reply: @escaping @Sendable (String?, Int32) -> Void) {
        queue.async {
            do { reply(try MigratingCredentialVault(backend: FileKeychain()).read(account: account, allowInteraction: allowInteraction), 0) }
            catch { reply(nil, (error as? CredentialStoreError)?.status ?? errSecInternalError) }
        }
    }

    func saveKey(_ key: String, for account: String, reply: @escaping @Sendable (Int32) -> Void) {
        queue.async {
            do { try MigratingCredentialVault(backend: FileKeychain()).save(key, account: account); reply(0) }
            catch { reply((error as? CredentialStoreError)?.status ?? errSecInternalError) }
        }
    }

    func checkStorage(_ ticket: String, operation: String, reply: @escaping @Sendable (Bool, Int32) -> Void) {
        guard UUID(uuidString: ticket) != nil, ["create", "read", "delete"].contains(operation) else {
            reply(false, errSecParam); return
        }
        queue.async {
            let backend = FileKeychain()
            do {
                switch operation {
                case "create":
                    try backend.write(ticket, service: CredentialContract.validationService, account: ticket, allowInteraction: false)
                    reply(true, 0)
                case "read":
                    let matches = try backend.read(service: CredentialContract.validationService, account: ticket, allowInteraction: false) == ticket
                    reply(matches, matches ? 0 : errSecItemNotFound)
                default: try backend.removeValidation(ticket); reply(true, 0)
                }
            } catch { reply(false, (error as? CredentialStoreError)?.status ?? errSecInternalError) }
        }
    }
}

final class Listener: NSObject, NSXPCListenerDelegate {
    let broker = Broker()
    let clientRequirement: String
    init(requirement: String) { clientRequirement = requirement }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == geteuid() else { return false }
        // NSXPC applies this requirement to the peer's audit token, not a PID
        // lookup. An ID alone or a caller-supplied path is never authentication.
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: CredentialBrokerProtocol.self)
        connection.exportedObject = broker
        connection.resume()
        return true
    }
}

guard let requirement = Bundle.main.object(forInfoDictionaryKey: "TrueLClientRequirement") as? String else { exit(78) }
var parsed: SecRequirement?
guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else { exit(78) }
let delegate = Listener(requirement: requirement)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
