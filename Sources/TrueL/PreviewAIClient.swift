import Foundation

/// Explicit snapshot dependency; never selected during ordinary application startup.
struct PreviewAIClient: AIClientProtocol {
    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        [AIModelInfo(id: "preview-model", displayName: "Preview model"),
         AIModelInfo(id: "preview-model-with-a-deliberately-long-context-window-name", displayName: "Preview model with a deliberately long context-window name")]
    }
    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String {
        "把复杂的想法，写得清楚一点。"
    }
}

@MainActor
final class PreviewLockedCredentialStore: CredentialStore {
    func key(for provider: AIProvider, allowInteraction: Bool) throws -> String? {
        guard allowInteraction else { throw CredentialStoreError(status: -25293) }
        return "snapshot-only-placeholder"
    }
    func save(_ key: String, for provider: AIProvider) throws {}
}
