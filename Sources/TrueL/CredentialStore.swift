import Foundation
import CredentialCore

typealias CredentialStoreError = CredentialCore.CredentialStoreError

@MainActor
protocol CredentialStore {
    func key(for provider: AIProvider, allowInteraction: Bool) async throws -> String?
    func save(_ key: String, for provider: AIProvider) async throws
}

@MainActor
final class MemoryCredentialStore: CredentialStore {
    private var keys: [AIProvider: String]

    init(keys: [AIProvider: String] = [:]) { self.keys = keys }
    func key(for provider: AIProvider, allowInteraction: Bool = false) throws -> String? { keys[provider] }
    func save(_ key: String, for provider: AIProvider) throws { keys[provider] = key }
}

@MainActor
final class KeychainCredentialStore: CredentialStore {
    private let client = CredentialBrokerClient()
    func key(for provider: AIProvider, allowInteraction: Bool = false) async throws -> String? {
        try await client.read(account: provider.rawValue, allowInteraction: allowInteraction)
    }

    func save(_ key: String, for provider: AIProvider) async throws {
        try await client.save(key, account: provider.rawValue)
    }
}
