import Foundation
import Security

@MainActor
protocol CredentialStore {
    func key(for provider: AIProvider) throws -> String?
    func save(_ key: String, for provider: AIProvider) throws
}

@MainActor
final class MemoryCredentialStore: CredentialStore {
    private var keys: [AIProvider: String]

    init(keys: [AIProvider: String] = [:]) { self.keys = keys }
    func key(for provider: AIProvider) throws -> String? { keys[provider] }
    func save(_ key: String, for provider: AIProvider) throws { keys[provider] = key }
}

@MainActor
final class KeychainCredentialStore: CredentialStore {
    private let service = "com.truel.provider-api-key"

    func key(for provider: AIProvider) throws -> String? {
        var query = identity(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError(status: status)
        }
        return key
    }

    func save(_ key: String, for provider: AIProvider) throws {
        let query = identity(for: provider)
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CredentialStoreError(status: status) }
    }

    private func identity(for provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue,
         kSecAttrSynchronizable as String: false]
    }
}

struct CredentialStoreError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "无法读取或保存钥匙串（\(status)）。请解锁钥匙串后重试。" }
}
