import Foundation
import Testing
import CredentialCore

struct CredentialVaultTests {
    @Test func migrationCopiesOnceAndKeepsLegacyForRollback() throws {
        let backend = VaultBackend()
        backend.values[CredentialContract.legacyService] = "legacy-test-value"
        let vault = MigratingCredentialVault(backend: backend)
        #expect(try vault.read(account: "gemini", allowInteraction: true) == "legacy-test-value")
        #expect(backend.values[CredentialContract.legacyService] == "legacy-test-value")
        backend.failLegacyRead = true
        #expect(try vault.read(account: "gemini", allowInteraction: false) == "legacy-test-value")
        #expect(backend.insertions == 1)
    }

    @Test func deniedMigrationAndFailedCopyLeaveOldValueIntact() {
        for failsRead in [false, true] {
            let backend = VaultBackend()
            backend.values[CredentialContract.legacyService] = "legacy-test-value"
            backend.failLegacyRead = failsRead
            backend.failWrite = !failsRead
            #expect(throws: CredentialStoreError.self) {
                try MigratingCredentialVault(backend: backend).read(account: "gemini", allowInteraction: false)
            }
            #expect(backend.values[CredentialContract.legacyService] == "legacy-test-value")
            #expect(backend.values[CredentialContract.service] == nil)
        }
    }

    @Test func aConcurrentSaveWinsOverLegacyMigration() throws {
        let backend = VaultBackend()
        backend.values[CredentialContract.legacyService] = "old-test-value"
        backend.concurrentValue = "new-test-value"
        #expect(try MigratingCredentialVault(backend: backend).read(account: "gemini", allowInteraction: true) == "new-test-value")
        #expect(backend.values[CredentialContract.service] == "new-test-value")
    }

    @Test func migrationRequiresReadbackToMatch() {
        let backend = VaultBackend()
        backend.values[CredentialContract.legacyService] = "old-test-value"
        backend.corruptWrite = true
        #expect(throws: CredentialStoreError.self) {
            try MigratingCredentialVault(backend: backend).read(account: "gemini", allowInteraction: true)
        }
        #expect(backend.values[CredentialContract.legacyService] == "old-test-value")
    }

    @Test func saveReplacesOnlyManagedValueAndDoesNotRequireLegacyRead() throws {
        let backend = VaultBackend()
        backend.values[CredentialContract.legacyService] = "old-test-value"
        backend.failLegacyRead = true
        let vault = MigratingCredentialVault(backend: backend)
        try vault.save("new-test-value", account: "gemini")
        try vault.save("new-test-value", account: "gemini")
        #expect(try vault.read(account: "gemini", allowInteraction: false) == "new-test-value")
        #expect(backend.values[CredentialContract.legacyService] == "old-test-value")
    }

    @Test func missingIsNilAndInvalidRequestsDoNotReachStorage() throws {
        let backend = VaultBackend()
        let vault = MigratingCredentialVault(backend: backend)
        #expect(try vault.read(account: "gemini", allowInteraction: false) == nil)
        #expect(throws: CredentialStoreError.self) { try vault.read(account: "../other", allowInteraction: true) }
        for key in ["", "  \n", String(repeating: "a", count: 16385)] {
            #expect(throws: CredentialStoreError.self) { try vault.save(key, account: "gemini") }
        }
        #expect(backend.values.isEmpty)
        #expect(backend.insertions == 0)
    }
}

private final class VaultBackend: CredentialBackend {
    var values: [String: String] = [:]
    var failLegacyRead = false
    var failWrite = false
    var corruptWrite = false
    var concurrentValue: String?
    var insertions = 0

    func read(service: String, account: String, allowInteraction: Bool) throws -> String? {
        if service == CredentialContract.legacyService, failLegacyRead { throw CredentialStoreError(status: -25293) }
        return values[service]
    }
    func write(_ key: String, service: String, account: String, allowInteraction: Bool) throws {
        if failWrite { throw CredentialStoreError(status: -25308) }
        values[service] = corruptWrite ? "corrupt-test-value" : key
    }
    func insert(_ key: String, service: String, account: String, allowInteraction: Bool) throws -> Bool {
        insertions += 1
        if let concurrentValue { values[service] = concurrentValue }
        if values[service] != nil { return false }
        try write(key, service: service, account: account, allowInteraction: allowInteraction)
        return true
    }
}
