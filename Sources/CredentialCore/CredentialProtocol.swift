import Foundation

@objc(TrueLCredentialBrokerProtocol)
public protocol CredentialBrokerProtocol {
    func readKey(for account: String, allowInteraction: Bool,
                 reply: @escaping @Sendable (String?, Int32) -> Void)
    func saveKey(_ key: String, for account: String,
                 reply: @escaping @Sendable (Int32) -> Void)
    /// A bounded diagnostic namespace, never a production API key.
    func checkStorage(_ ticket: String, operation: String,
                      reply: @escaping @Sendable (Bool, Int32) -> Void)
}

public enum CredentialContract {
    public static let serviceID = "com.truel.CredentialBroker"
    public static let accounts: Set<String> = ["openAI", "claude", "gemini", "grok", "deepSeek", "kimi", "glm"]
    public static let service = "com.truel.credentials.v1"
    public static let legacyService = "com.truel.provider-api-key"
    public static let validationService = "com.truel.credential-broker.validation"
    public static let maximumKeyBytes = 16 * 1024
    public static func validKey(_ key: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && key.utf8.count <= maximumKeyBytes
    }
}

public struct CredentialStoreError: Error, LocalizedError, Sendable {
    public let status: Int32
    public init(status: Int32) { self.status = status }
    public var needsAuthorization: Bool { [-25293, -25308, -128].contains(status) }
    public var errorDescription: String? {
        if needsAuthorization { return "请允许 TrueL 读取已保存的 API Key。" }
        return "无法访问凭据组件（\(status)），请重试。"
    }
}
