import Foundation
import Testing
@testable import TrueL

@MainActor
struct CredentialRecoveryTests {
    @Test func startupDoesNotPromptAndExplicitRetryRestoresSavedKey() async throws {
        let credentials = DelayedCredentials()
        let service = ServiceConfiguration(persist: false, credentialStore: credentials)
        await credentials.waitForReads(1)
        #expect(credentials.interactions == [false])
        credentials.complete(0, .failure(CredentialStoreError(status: -25293)))
        await until { service.needsCredentialAccess }
        #expect(service.draftKey.isEmpty)
        service.switchProvider(.glm)
        await credentials.waitForReads(2)
        credentials.complete(1, .failure(CredentialStoreError(status: -25308)))
        await until { service.needsCredentialAccess }
        service.authorizeSavedKey()
        await credentials.waitForReads(3)
        #expect(credentials.interactions == [false, false, true])
        credentials.complete(2, .success("restored-fixture"))
        await until { service.isKeyVerified }
        #expect(service.draftKey == "restored-fixture")
        #expect(!service.needsCredentialAccess)
    }

    @Test func lateRestoreCannotOverwriteTypedKeyOrAnotherProvider() async {
        let credentials = DelayedCredentials()
        let service = ServiceConfiguration(persist: false, credentialStore: credentials)
        await credentials.waitForReads(1)
        service.draftKey = "user-entered"
        credentials.complete(0, .success("stale-fixture"))
        for _ in 0..<20 { await Task.yield() }
        #expect(service.draftKey == "user-entered")
        service.switchProvider(.glm)
        #expect(service.draftKey.isEmpty)
        await credentials.waitForReads(2)
        service.switchProvider(.openAI)
        await credentials.waitForReads(3)
        credentials.complete(1, .success("glm-fixture"))
        credentials.complete(2, .success(nil))
        await until { !service.isRestoringKey }
        #expect(service.selectedProvider == .openAI)
        #expect(service.draftKey.isEmpty)
        #expect(!service.isKeyVerified)
    }

    @Test func cancelledAuthorizationRemainsRetryableWithoutLosingSelections() async {
        let credentials = DelayedCredentials()
        let service = ServiceConfiguration(persist: false, credentialStore: credentials)
        await credentials.waitForReads(1)
        credentials.complete(0, .failure(CredentialStoreError(status: -25293)))
        await until { service.needsCredentialAccess }
        service.authorizeSavedKey()
        await credentials.waitForReads(2)
        credentials.complete(1, .failure(CredentialStoreError(status: -128)))
        await until { !service.isRestoringKey }
        #expect(service.needsCredentialAccess)
        #expect(service.isError)
        #expect(!service.isKeyVerified)
        #expect(service.draftKey.isEmpty)
    }

    @Test func missingBrokerFailsClosedWithoutCallingKeychainDirectly() async {
        let client = CredentialBrokerClient(bundle: Bundle(for: DelayedCredentials.self))
        await #expect(throws: CredentialStoreError.self) { try await client.read(account: "gemini", allowInteraction: false) }
        await #expect(throws: CredentialStoreError.self) { try await client.read(account: "../bad", allowInteraction: false) }
    }
}

@MainActor
private final class DelayedCredentials: NSObject, CredentialStore {
    var interactions: [Bool] = []
    var replies: [CheckedContinuation<String?, any Error>?] = []
    func key(for provider: AIProvider, allowInteraction: Bool) async throws -> String? {
        interactions.append(allowInteraction)
        return try await withCheckedThrowingContinuation { replies.append($0) }
    }
    func save(_ key: String, for provider: AIProvider) throws {}
    func complete(_ index: Int, _ result: Result<String?, any Error>) {
        replies[index]?.resume(with: result); replies[index] = nil
    }
    func waitForReads(_ count: Int) async { await until { replies.count >= count } }
}

@MainActor
private func until(_ check: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !check(), ContinuousClock.now < deadline { await Task.yield() }
    #expect(check())
}
