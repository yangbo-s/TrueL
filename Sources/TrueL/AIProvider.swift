import Foundation

enum AIProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case openAI, claude, gemini, grok, deepSeek, kimi, glm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "GPT"
        case .claude: "Claude"
        case .gemini: "Gemini"
        case .grok: "Grok"
        case .deepSeek: "DeepSeek"
        case .kimi: "Kimi"
        case .glm: "GLM"
        }
    }

    /// Provider-owned URLs only. Neither credentials nor model IDs can change the host.
    var modelsURL: URL? {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/models")
        case .claude: URL(string: "https://api.anthropic.com/v1/models")
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")
        case .grok: URL(string: "https://api.x.ai/v1/language-models")
        case .deepSeek: URL(string: "https://api.deepseek.com/models")
        case .kimi: URL(string: "https://api.moonshot.cn/v1/models")
        case .glm: nil
        }
    }

    func generationURL(modelID: String) throws -> URL {
        let address: String
        switch self {
        case .openAI: address = "https://api.openai.com/v1/chat/completions"
        case .claude: address = "https://api.anthropic.com/v1/messages"
        case .gemini:
            // A model resource is one path component, never an arbitrary URL or path.
            guard Self.isSafeModelID(modelID) else { throw AIClientError.invalidModel }
            address = "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent"
        case .grok: address = "https://api.x.ai/v1/chat/completions"
        case .deepSeek: address = "https://api.deepseek.com/chat/completions"
        case .kimi: address = "https://api.moonshot.cn/v1/chat/completions"
        case .glm: address = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        }
        guard let url = URL(string: address) else { throw AIClientError.invalidModel }
        return url
    }

    static func isSafeModelID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 200 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:").contains($0)
        }
    }

    /// The public GLM API does not document a models-list operation. Updated from its
    /// official text-model catalog on 2026-11-13; availability remains account-specific.
    static let glmCatalog: [AIModelInfo] = [
        "glm-4.7-flash", "glm-5.3", "glm-5.3-flash", "glm-5.3-flashx",
        "glm-5.2", "glm-5.1", "glm-5", "glm-5-turbo", "glm-4.7",
        "glm-4.7-flashx", "glm-4.6", "glm-4.5-air", "glm-4.5-airx",
        "glm-4.5-flash"
    ].map { AIModelInfo(id: $0, displayName: $0) }
}

struct AIModelInfo: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
}

/// An in-memory request snapshot. Deliberately not Codable: the key must never be
/// serialized with preference metadata or included in a diagnostic description.
struct AIConfiguration: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let provider: AIProvider
    let apiKey: String
    let modelID: String

    var description: String { "AIConfiguration(\(provider.rawValue), \(modelID), key: <redacted>)" }
    var debugDescription: String { description }
}
