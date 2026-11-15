import Foundation
import Observation

struct ModelSelection: Codable, Equatable, Hashable, Sendable, Identifiable {
    let provider: AIProvider
    let modelID: String
    var id: String { provider.rawValue + ":" + modelID }
}

@MainActor
@Observable
final class ServiceConfiguration {
    private(set) var selectedProvider: AIProvider
    var draftKey = "" {
        didSet { if draftKey != oldValue { invalidateVerification() } }
    }
    private(set) var models: [AIModelInfo] = []
    private(set) var catalogs: [AIProvider: [AIModelInfo]] = [:]
    private(set) var selections: [String: ModelSelection] = [:]
    private(set) var drafts: [String: ModelSelection] = [:]
    private(set) var revisions: [String: UInt64] = [:]
    private(set) var isVerifying = false
    private(set) var isKeyVerified = false
    private(set) var status: String?
    private(set) var modelStatus: String?
    private(set) var isError = false
    private(set) var modelError = false

    var canSaveKey: Bool { !normalizedKey.isEmpty && !isVerifying }
    var availableSelections: [ModelSelection] {
        AIProvider.allCases.flatMap { provider in
            (catalogs[provider] ?? []).map { ModelSelection(provider: provider, modelID: $0.id) }
        }
    }

    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let client: any AIClientProtocol
    @ObservationIgnored private let credentialStore: any CredentialStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var configuredProviders: Set<AIProvider> = []
    @ObservationIgnored private var verifiedKeys: [AIProvider: String] = [:]
    @ObservationIgnored private var providerGenerations: [AIProvider: UUID] = [:]
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var verificationTask: Task<[AIModelInfo], any Error>?

    private var normalizedKey: String { draftKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static let providerPreference = "TrueL.ai.selectedProvider"
    private static let selectionsPreference = "TrueL.ai.taskModels.v1"

    init(persist: Bool = true, client: any AIClientProtocol = AIClient(),
         credentialStore: (any CredentialStore)? = nil, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.client = client
        self.defaults = defaults
        self.credentialStore = credentialStore ?? (persist ? KeychainCredentialStore() : MemoryCredentialStore())
        selectedProvider = persist ? (defaults.string(forKey: Self.providerPreference).flatMap(AIProvider.init(rawValue:)) ?? .gemini) : .gemini
        if persist, let data = defaults.data(forKey: Self.selectionsPreference) {
            selections = (try? JSONDecoder().decode([String: ModelSelection].self, from: data)) ?? [:]
        } else if persist {
            // Migrate only once. An intentionally unconfigured task stays unconfigured on restart.
            let legacy = defaults.dictionary(forKey: "TrueL.ai.savedModels") as? [String: String] ?? [:]
            if let modelID = legacy[selectedProvider.rawValue], !modelID.isEmpty {
                let selection = ModelSelection(provider: selectedProvider, modelID: modelID)
                for mode in WorkMode.allCases { selections[mode.rawValue] = selection }
            }
            persistSelections()
        }
        if persist {
            let saved = defaults.stringArray(forKey: "TrueL.ai.configuredProviders") ?? []
            let legacy = defaults.dictionary(forKey: "TrueL.ai.savedModels") ?? [:]
            configuredProviders = Set((saved + Array(legacy.keys)).compactMap(AIProvider.init(rawValue:)))
        }
        drafts = selections
        restoreProvider()
        let savedProviders = configuredProviders.union(selections.values.map(\.provider)).subtracting([selectedProvider])
        for provider in savedProviders { restoreCatalog(provider) }
    }

    func selection(for mode: WorkMode) -> ModelSelection? { selections[mode.rawValue] }
    func draftSelection(for mode: WorkMode) -> ModelSelection? { drafts[mode.rawValue] }
    func configurationRevision(for mode: WorkMode) -> UInt64 { revisions[mode.rawValue, default: 0] }
    func isAvailable(_ selection: ModelSelection) -> Bool {
        verifiedKeys[selection.provider] != nil && catalogs[selection.provider]?.contains(where: { $0.id == selection.modelID }) == true
    }
    func isReady(for mode: WorkMode) -> Bool { selection(for: mode).map(isAvailable) ?? false }
    func canSaveModel(for mode: WorkMode) -> Bool { draftSelection(for: mode).map(isAvailable) ?? false }

    func setDraftModel(_ selection: ModelSelection, for mode: WorkMode) {
        guard isAvailable(selection) else { return }
        drafts[mode.rawValue] = selection
        modelStatus = nil
        modelError = false
    }

    @discardableResult
    func selectModel(_ selection: ModelSelection, for mode: WorkMode) -> Bool {
        guard isAvailable(selection) else {
            modelStatus = "请先保存并验证对应的 API Key。"
            modelError = true
            return false
        }
        if selections[mode.rawValue] != selection { revisions[mode.rawValue, default: 0] &+= 1 }
        selections[mode.rawValue] = selection
        drafts[mode.rawValue] = selection
        persistSelections()
        modelStatus = "\(mode == .translation ? "翻译" : "改写")模型已保存"
        modelError = false
        return true
    }

    func saveModel(for mode: WorkMode) {
        guard let selection = draftSelection(for: mode) else { return }
        selectModel(selection, for: mode)
    }

    func configuration(for mode: WorkMode) throws -> AIConfiguration {
        guard let selection = selection(for: mode), isAvailable(selection),
              let key = verifiedKeys[selection.provider] else { throw ServiceConfigurationError.notReady }
        return AIConfiguration(provider: selection.provider, apiKey: key, modelID: selection.modelID)
    }

    func switchProvider(_ provider: AIProvider) {
        guard provider != selectedProvider else { return }
        invalidateVerification()
        selectedProvider = provider
        if persist { defaults.set(provider.rawValue, forKey: Self.providerPreference) }
        restoreProvider()
    }

    func saveKey() async { await verifyKey(save: true) }

    func cancelVerification() {
        guard isVerifying else { return }
        invalidateVerification()
        status = "验证已取消"
    }

    private func restoreProvider() {
        do {
            draftKey = try credentialStore.key(for: selectedProvider) ?? ""
            guard !draftKey.isEmpty else { return }
            if verifiedKeys[selectedProvider] == normalizedKey, let available = catalogs[selectedProvider] {
                models = available
                isKeyVerified = true
                status = "已载入 API Key"
            } else if selectedProvider == .glm {
                // Restoring a saved GLM key must not start billable inference.
                publishModels(AIProvider.glmCatalog, provider: .glm, key: normalizedKey)
                status = "已载入 API Key"
            } else {
                let expectedRevision = revision
                Task { [weak self] in
                    guard let self, self.revision == expectedRevision else { return }
                    await self.verifyKey(save: false)
                }
            }
        } catch {
            draftKey = ""
            status = "无法读取钥匙串，请解锁后重新保存 API Key。"
            isError = true
        }
    }

    private func restoreCatalog(_ provider: AIProvider) {
        guard let key = try? credentialStore.key(for: provider), !key.isEmpty else { return }
        if provider == .glm {
            publishModels(AIProvider.glmCatalog, provider: provider, key: key)
            return
        }
        let generation = UUID()
        providerGenerations[provider] = generation
        Task { [weak self, client] in
            do {
                let available = try await client.listModels(provider: provider, apiKey: key)
                guard let self, self.providerGenerations[provider] == generation, !available.isEmpty else { return }
                self.publishModels(available, provider: provider, key: key)
            } catch {
                // Keep saved choices so a transient outage cannot erase preferences.
                // An unverified account stays unavailable until the user retries in Settings.
            }
        }
    }

    private func verifyKey(save: Bool) async {
        invalidateVerification()
        let key = normalizedKey
        guard !key.isEmpty else { status = AIClientError.invalidKey.errorDescription; isError = true; return }
        let provider = selectedProvider
        let expectedRevision = revision
        providerGenerations[provider] = UUID()
        isVerifying = true
        status = "正在验证 API Key…"
        let client = client
        let task = Task { try await client.listModels(provider: provider, apiKey: key) }
        verificationTask = task
        defer {
            if revision == expectedRevision { isVerifying = false; verificationTask = nil }
        }
        do {
            let available = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard revision == expectedRevision, selectedProvider == provider, normalizedKey == key else { return }
            guard !available.isEmpty else { throw AIClientError.noModels }
            if save {
                let previousKey: String?
                do {
                    previousKey = try credentialStore.key(for: provider)
                    try credentialStore.save(key, for: provider)
                } catch {
                    status = "API Key 验证通过，但无法保存到钥匙串。请解锁钥匙串后重试。"
                    isError = true
                    return
                }
                configuredProviders.insert(provider)
                if persist { defaults.set(configuredProviders.map(\.rawValue).sorted(), forKey: "TrueL.ai.configuredProviders") }
                if previousKey != nil, previousKey != key {
                    for mode in WorkMode.allCases where selection(for: mode)?.provider == provider { clearSelection(for: mode) }
                    persistSelections()
                }
            }
            publishModels(available, provider: provider, key: key)
            status = save ? "API Key 已保存" : "API Key 已验证"
            isError = false
        } catch is CancellationError {
            guard revision == expectedRevision else { return }
            status = "验证已取消"
        } catch {
            guard revision == expectedRevision else { return }
            status = AIClientError.safeMessage(for: error)
            isError = true
        }
    }

    private func publishModels(_ available: [AIModelInfo], provider: AIProvider, key: String) {
        catalogs[provider] = available
        verifiedKeys[provider] = key
        for mode in WorkMode.allCases {
            if let selected = selection(for: mode), selected.provider == provider,
               !available.contains(where: { $0.id == selected.modelID }) { clearSelection(for: mode) }
        }
        persistSelections()
        if selectedProvider == provider, normalizedKey == key { models = available; isKeyVerified = true }
    }

    private func clearSelection(for mode: WorkMode) {
        selections.removeValue(forKey: mode.rawValue)
        drafts.removeValue(forKey: mode.rawValue)
        revisions[mode.rawValue, default: 0] &+= 1
    }

    private func invalidateVerification() {
        revision = UUID()
        verificationTask?.cancel()
        verificationTask = nil
        isVerifying = false
        isKeyVerified = false
        models = []
        status = nil
        isError = false
    }

    private func persistSelections() {
        guard persist, let data = try? JSONEncoder().encode(selections) else { return }
        defaults.set(data, forKey: Self.selectionsPreference)
    }
}

enum ServiceConfigurationError: LocalizedError {
    case notReady
    var errorDescription: String? { "请在设置中验证 API Key，并为当前任务选择模型。" }
}
