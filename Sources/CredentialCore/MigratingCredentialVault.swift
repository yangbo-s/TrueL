import Foundation

public protocol CredentialBackend {
    func read(service: String, account: String, allowInteraction: Bool) throws -> String?
    func write(_ key: String, service: String, account: String, allowInteraction: Bool) throws
    func insert(_ key: String, service: String, account: String, allowInteraction: Bool) throws -> Bool
}

public struct MigratingCredentialVault<Backend: CredentialBackend> {
    private let backend: Backend
    public init(backend: Backend) { self.backend = backend }

    public func read(account: String, allowInteraction: Bool) throws -> String? {
        guard CredentialContract.accounts.contains(account) else { throw CredentialStoreError(status: -50) }
        if let key = try backend.read(service: CredentialContract.service, account: account, allowInteraction: allowInteraction) {
            guard CredentialContract.validKey(key) else { throw CredentialStoreError(status: -26275) }
            return key
        }
        guard let legacy = try backend.read(service: CredentialContract.legacyService, account: account,
                                            allowInteraction: allowInteraction) else { return nil }
        guard CredentialContract.validKey(legacy) else { throw CredentialStoreError(status: -26275) }
        let inserted = try backend.insert(legacy, service: CredentialContract.service, account: account, allowInteraction: allowInteraction)
        guard let stored = try backend.read(service: CredentialContract.service, account: account, allowInteraction: false),
              CredentialContract.validKey(stored), !inserted || stored == legacy else {
            throw CredentialStoreError(status: -26275)
        }
        return stored
    }

    public func save(_ key: String, account: String) throws {
        guard CredentialContract.accounts.contains(account), CredentialContract.validKey(key) else {
            throw CredentialStoreError(status: -50)
        }
        try backend.write(key, service: CredentialContract.service, account: account, allowInteraction: true)
    }
}
