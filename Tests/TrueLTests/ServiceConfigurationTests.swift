import Foundation
import Testing
@testable import TrueL

@MainActor
struct ServiceConfigurationTests {
    @Test func freshConfigurationHasNoCredentialsModelsOrReadyState() {
        let service = ServiceConfiguration(persist: false)
        #expect(service.draftKey.isEmpty)
        #expect(service.models.isEmpty)
        #expect(service.availableSelections.isEmpty)
        for mode in WorkMode.allCases {
            #expect(!service.isReady(for: mode))
            #expect(!service.canSaveModel(for: mode))
            #expect(throws: ServiceConfigurationError.self) { try service.configuration(for: mode) }
        }
        #expect(!service.canSaveKey)
    }

    @Test func savingKeyAndEachTaskModelAreSeparateOperations() async throws {
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: false, client: FixedClient(), credentialStore: credentials)
        service.draftKey = "  test-key  "
        await service.saveKey()
        #expect(service.isKeyVerified)
        #expect(try credentials.key(for: .gemini) == "test-key")
        let selected = ModelSelection(provider: .gemini, modelID: "gemini-text")
        service.setDraftModel(selected, for: .translation)
        #expect(service.canSaveModel(for: .translation))
        #expect(!service.isReady(for: .translation))
        service.saveModel(for: .translation)
        #expect(service.isReady(for: .translation))
        #expect(!service.isReady(for: .grammar))
        let configuration = try service.configuration(for: .translation)
        #expect(configuration.modelID == "gemini-text")
        #expect(configuration.apiKey == "test-key")
        #expect(!String(describing: configuration).contains("test-key"))
        #expect(!String(reflecting: configuration).contains("test-key"))
    }

    @Test func editingKeyKeepsSavedTaskButSavingReplacementRequiresNewModelChoice() async throws {
        let service = ServiceConfiguration(persist: false, client: FixedClient())
        service.draftKey = "first-key"
        await service.saveKey()
        let selected = ModelSelection(provider: .gemini, modelID: "gemini-text")
        service.selectModel(selected, for: .translation)
        let before = service.configurationRevision(for: .translation)
        service.draftKey = "replacement-key"
        #expect(service.models.isEmpty)
        #expect(!service.isKeyVerified)
        #expect(service.isReady(for: .translation))
        #expect(service.configurationRevision(for: .translation) == before)
        #expect(try service.configuration(for: .translation).apiKey == "first-key")
        await service.saveKey()
        #expect(service.isKeyVerified)
        #expect(!service.isReady(for: .translation))
        #expect(service.configurationRevision(for: .translation) > before)
        service.selectModel(selected, for: .translation)
        #expect(try service.configuration(for: .translation).apiKey == "replacement-key")
    }

    @Test func unsavedModelDraftKeepsActiveChoiceAndUnknownModelIsRejected() async throws {
        let service = ServiceConfiguration(persist: false, client: FixedClient())
        service.draftKey = "test-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .gemini, modelID: "gemini-text"), for: .translation)
        service.setDraftModel(ModelSelection(provider: .gemini, modelID: "gemini-second"), for: .translation)
        #expect(try service.configuration(for: .translation).modelID == "gemini-text")
        service.saveModel(for: .translation)
        #expect(try service.configuration(for: .translation).modelID == "gemini-second")
        #expect(!service.selectModel(ModelSelection(provider: .gemini, modelID: "unknown"), for: .translation))
        #expect(try service.configuration(for: .translation).modelID == "gemini-second")
        #expect(service.modelError)
    }

    @Test func taskModelsPersistAcrossProvidersWithoutSecretsInDefaults() async throws {
        let suite = "TrueLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        service.draftKey = "gemini-secret"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .gemini, modelID: "gemini-text"), for: .translation)
        let revision = service.configurationRevision(for: .translation)
        service.switchProvider(.openAI)
        #expect(service.isReady(for: .translation))
        service.draftKey = "openai-secret"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .openAI, modelID: "openAI-second"), for: .grammar)
        #expect(service.configurationRevision(for: .translation) == revision)
        #expect(try service.configuration(for: .translation).apiKey == "gemini-secret")
        #expect(try service.configuration(for: .grammar).apiKey == "openai-secret")
        let reopened = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        let deadline = ContinuousClock.now + .seconds(2)
        while (!reopened.isReady(for: .translation) || !reopened.isReady(for: .grammar)), ContinuousClock.now < deadline { await Task.yield() }
        #expect(try reopened.configuration(for: .translation).modelID == "gemini-text")
        #expect(try reopened.configuration(for: .grammar).modelID == "openAI-second")
        #expect(!defaults.dictionaryRepresentation().description.contains("gemini-secret"))
        #expect(!defaults.dictionaryRepresentation().description.contains("openai-secret"))
    }

    @Test func oldSingleModelMigratesToBothTasksOnlyOnce() async throws {
        let suite = "TrueLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("glm", forKey: "TrueL.ai.selectedProvider")
        defaults.set(["glm": "glm-4.7-flash"], forKey: "TrueL.ai.savedModels")
        let credentials = MemoryCredentialStore(keys: [.glm: "old-key"])
        let service = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        await waitForRestore(service)
        for mode in WorkMode.allCases { #expect(try service.configuration(for: mode).modelID == "glm-4.7-flash") }
        // Explicit new preferences take precedence over legacy entries on all later launches.
        defaults.set(try JSONEncoder().encode([String: ModelSelection]()), forKey: "TrueL.ai.taskModels.v1")
        let reopened = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        #expect(reopened.selection(for: .translation) == nil)
        #expect(reopened.selection(for: .grammar) == nil)
    }

    @Test func configuredButUnusedAccountRemainsInMenuAfterRestart() async throws {
        let suite = "TrueLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        service.draftKey = "gemini-key"
        await service.saveKey()
        service.switchProvider(.openAI)
        service.draftKey = "openai-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .openAI, modelID: "openAI-text"), for: .translation)
        let reopened = ServiceConfiguration(persist: true, client: FixedClient(), credentialStore: credentials, defaults: defaults)
        let deadline = ContinuousClock.now + .seconds(2)
        while reopened.availableSelections.count < 4, ContinuousClock.now < deadline { await Task.yield() }
        #expect(Set(reopened.availableSelections.map(\.provider)) == Set([.gemini, .openAI]))
    }

    @Test func savedKeyIsAutomaticallyRevalidatedBeforeUse() async throws {
        let client = GateClient()
        let service = ServiceConfiguration(persist: false, client: client,
                                           credentialStore: MemoryCredentialStore(keys: [.gemini: "saved-key"]))
        #expect(!service.isKeyVerified)
        #expect(!service.isReady(for: .translation))
        #expect(await client.waitForRequests(1))
        await client.complete(0, models: [AIModelInfo(id: "gemini-text", displayName: "Text")])
        for _ in 0..<100 where !service.isKeyVerified { await Task.yield() }
        #expect(service.isKeyVerified)
        #expect(!service.isReady(for: .translation))
    }

    @Test func failedKeychainWriteCannotLookSavedOrExposeModels() async {
        let service = ServiceConfiguration(persist: false, client: FixedClient(), credentialStore: FailingCredentialStore())
        service.draftKey = "test-key"
        await service.saveKey()
        #expect(service.isError)
        #expect(service.status?.contains("无法保存") == true)
        #expect(service.models.isEmpty)
        #expect(!service.isKeyVerified)
        #expect(!service.isReady(for: .translation))
    }

    @Test func restoringGLMUsesPriorVerificationWithoutBackgroundInference() async throws {
        let suite = "TrueLTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("glm", forKey: "TrueL.ai.selectedProvider")
        defaults.set(["glm": "glm-4.7-flash"], forKey: "TrueL.ai.savedModels")
        let client = GateClient()
        let service = ServiceConfiguration(persist: true, client: client,
            credentialStore: MemoryCredentialStore(keys: [.glm: "previously-verified-key"]), defaults: defaults)
        await waitForRestore(service)
        #expect(service.isKeyVerified)
        #expect(service.isReady(for: .translation))
        #expect(service.status == "已载入 API Key")
        service.switchProvider(.gemini)
        service.switchProvider(.glm)
        await waitForRestore(service)
        #expect(service.isReady(for: .translation))
        await Task.yield()
        #expect(await client.requestCount == 0)

        let verification = Task { await service.saveKey() }
        #expect(await client.waitForRequests(1))
        await client.complete(0, models: AIProvider.glmCatalog)
        await verification.value
        #expect(service.isReady(for: .translation))
        #expect(service.status == "API Key 已保存")
        #expect(await client.requestCount == 1)
    }

    @Test func invalidKeyDoesNotOverwritePreviouslySavedKey() async throws {
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: false, client: FixedClient(), credentialStore: credentials)
        service.draftKey = "valid-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: service.selectedProvider, modelID: service.models[0].id), for: .translation)
        service.draftKey = "invalid-key"
        await service.saveKey()
        #expect(service.isError)
        #expect(service.models.isEmpty)
        #expect(service.isReady(for: .translation))
        #expect(try service.configuration(for: .translation).apiKey == "valid-key")
        #expect(try credentials.key(for: .gemini) == "valid-key")
    }

    @Test func staleProviderCompletionCannotReplaceCurrentProviderConfiguration() async throws {
        let client = GateClient()
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: false, client: client, credentialStore: credentials)
        service.draftKey = "old-key"
        let old = Task { await service.saveKey() }
        #expect(await client.waitForRequests(1))
        service.switchProvider(.openAI)
        service.draftKey = "new-key"
        let current = Task { await service.saveKey() }
        #expect(await client.waitForRequests(2))
        await client.complete(1, models: [AIModelInfo(id: "gpt-text", displayName: "Current")])
        await current.value
        service.selectModel(ModelSelection(provider: service.selectedProvider, modelID: service.models[0].id), for: .translation)
        await client.complete(0, models: [AIModelInfo(id: "gemini-stale", displayName: "Stale")])
        await old.value
        #expect(service.selectedProvider == .openAI)
        #expect(service.models.map(\.id) == ["gpt-text"])
        #expect(service.isReady(for: .translation))
        #expect(try credentials.key(for: .gemini) == nil)
        #expect(try service.configuration(for: .translation).apiKey == "new-key")
    }

    @Test func editedKeyRejectsOldCompletionEvenWhenProviderIsUnchanged() async throws {
        let client = GateClient()
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: false, client: client, credentialStore: credentials)
        service.draftKey = "old-key"
        let old = Task { await service.saveKey() }
        #expect(await client.waitForRequests(1))
        service.draftKey = "new-key"
        await client.complete(0, models: [AIModelInfo(id: "old-model", displayName: "Old")])
        await old.value
        #expect(service.models.isEmpty)
        #expect(!service.isVerifying)
        #expect(!service.isKeyVerified)
        #expect(service.draftKey == "new-key")
        #expect(try credentials.key(for: .gemini) == nil)
    }

    @Test func cancellingCallerCannotSaveLateResponse() async throws {
        let client = GateClient()
        let credentials = MemoryCredentialStore()
        let service = ServiceConfiguration(persist: false, client: client, credentialStore: credentials)
        service.draftKey = "test-key"
        let pending = Task { await service.saveKey() }
        #expect(await client.waitForRequests(1))
        pending.cancel()
        await client.complete(0, models: [AIModelInfo(id: "late-model", displayName: "Late")])
        await pending.value
        #expect(!service.isVerifying)
        #expect(!service.isReady(for: .translation))
        #expect(service.models.isEmpty)
        #expect(try credentials.key(for: .gemini) == nil)
        #expect(service.status == "验证已取消")
    }
}

private struct FixedClient: AIClientProtocol {
    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        if apiKey == "invalid-key" { throw AIClientError.unauthorized }
        return [AIModelInfo(id: "\(provider.rawValue)-text", displayName: "Text"),
                AIModelInfo(id: "\(provider.rawValue)-second", displayName: "Second")]
    }
    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String { "result" }
}

/// Intentionally ignores cancellation so state tests exercise stale-result guards.
private actor GateClient: AIClientProtocol {
    private var requests: [CheckedContinuation<[AIModelInfo], any Error>?] = []
    var requestCount: Int { requests.count }
    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String { "result" }
    func complete(_ index: Int, models: [AIModelInfo]) {
        guard requests.indices.contains(index) else { return }
        requests[index]?.resume(returning: models)
        requests[index] = nil
    }
    func waitForRequests(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while requests.count < count, ContinuousClock.now < deadline { await Task.yield() }
        return requests.count >= count
    }
}

@MainActor
private final class FailingCredentialStore: CredentialStore {
    func key(for provider: AIProvider, allowInteraction: Bool) throws -> String? { nil }
    func save(_ key: String, for provider: AIProvider) throws { throw CredentialStoreError(status: -25293) }
}

@MainActor
private func waitForRestore(_ service: ServiceConfiguration) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while service.isRestoringKey, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!service.isRestoringKey)
}
