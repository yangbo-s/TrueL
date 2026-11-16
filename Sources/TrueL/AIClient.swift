import Foundation

typealias AITextUpdate = @MainActor @Sendable (String) throws -> Void

protocol AIClientProtocol: Sendable {
    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo]
    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String
    func generateTranslation(configuration: AIConfiguration, system: String, user: String,
                             onUpdate: @escaping AITextUpdate) async throws -> String
    func generateRewrite(configuration: AIConfiguration, system: String, user: String,
                         onUpdate: @escaping AITextUpdate) async throws -> String
}

extension AIClientProtocol {
    func generateTranslation(configuration: AIConfiguration, system: String, user: String,
                             onUpdate: @escaping AITextUpdate) async throws -> String {
        try await generate(configuration: configuration, system: system, user: user)
    }

    func generateRewrite(configuration: AIConfiguration, system: String, user: String,
                         onUpdate: @escaping AITextUpdate) async throws -> String {
        try await generate(configuration: configuration, system: system, user: user)
    }
}

enum AIClientError: Error, LocalizedError, Equatable, Sendable {
    case invalidKey, invalidModel, noModels, unauthorized, forbidden, rateLimited
    case http(Int), network, timedOut, invalidResponse, emptyResponse, truncated, blocked

    var errorDescription: String? {
        switch self {
        case .invalidKey: "请输入有效的 API Key。"
        case .invalidModel: "请选择并保存可用模型。"
        case .noModels: "此 Key 未返回可用于文本生成的模型。"
        case .unauthorized: "API Key 无效或已失效，请检查后重试。"
        case .forbidden: "此 Key 没有访问权限，请检查服务商账号、区域或模型权限。"
        case .rateLimited: "服务商额度不足或请求过于频繁，请稍后重试。"
        case .http(let code): "服务商请求失败（HTTP \(code)）。请检查账号和模型后重试。"
        case .network: "无法连接服务商，请检查网络后重试。"
        case .timedOut: "服务商响应超时，请重试。"
        case .invalidResponse: "服务商返回了无法识别的数据。"
        case .emptyResponse: "服务商没有返回文本，请重试或更换模型。"
        case .truncated: "输出达到模型长度限制，请缩短输入后重试。"
        case .blocked: "服务商未返回此内容，请调整输入后重试。"
        }
    }

    static func safeMessage(for error: any Error) -> String {
        // Provider error bodies and URLSession errors can contain input or secrets.
        // Only errors we created are eligible for display.
        (error as? AIClientError)?.errorDescription ?? "服务请求失败，请重试。"
    }
}

struct AIClient: AIClientProtocol {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias StreamingTransport = @Sendable (URLRequest, @escaping @Sendable (AIStreamEvent) async throws -> Void) async throws -> Void
    private let transport: Transport
    private let streamingTransport: StreamingTransport

    init(transport: @escaping Transport = AIClient.send) {
        self.init(transport: transport, streamingTransport: AIClient.sendStream)
    }

    init(transport: @escaping Transport, streamingTransport: @escaping StreamingTransport) {
        self.transport = transport
        self.streamingTransport = streamingTransport
    }

    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        try validateKey(apiKey)
        if provider == .glm {
            // GLM publishes a catalog, not a documented authenticated list API.
            // Probe its free text model with a bounded, non-user prompt first.
            let request = try generationRequest(
                configuration: AIConfiguration(provider: .glm, apiKey: apiKey, modelID: "glm-4.7-flash"),
                system: "Reply with OK only.", user: "OK", validating: true
            )
            _ = try output(from: await object(for: request), provider: .glm)
            return AIProvider.glmCatalog
        }

        guard let baseURL = provider.modelsURL else { throw AIClientError.invalidResponse }
        var collected: [AIModelInfo] = []
        var pageToken: String?
        var seenPages = Set<String>()
        for _ in 0..<50 {
            try Task.checkCancellation()
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            switch provider {
            case .claude:
                components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
                if let pageToken { components.queryItems?.append(URLQueryItem(name: "after_id", value: pageToken)) }
            case .gemini:
                components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            default: break
            }
            guard let url = components.url else { throw AIClientError.invalidResponse }
            let response = try await object(for: request(url: url, provider: provider, apiKey: apiKey))
            let arrayKey = (provider == .gemini || provider == .grok) ? "models" : "data"
            guard let rows = response[arrayKey] as? [[String: Any]] else { throw AIClientError.invalidResponse }
            collected.append(contentsOf: rows.compactMap { model(from: $0, provider: provider) })
            switch provider {
            case .claude:
                if response["has_more"] as? Bool == true {
                    guard let next = response["last_id"] as? String, !next.isEmpty else { throw AIClientError.invalidResponse }
                    pageToken = next
                } else { pageToken = nil }
            case .gemini: pageToken = (response["nextPageToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            default: pageToken = nil
            }
            if pageToken == nil {
                var seenModels = Set<String>()
                let models = collected.filter { seenModels.insert($0.id).inserted }
                    .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
                guard !models.isEmpty else { throw AIClientError.noModels }
                return models
            }
            guard seenPages.insert(pageToken!).inserted else { throw AIClientError.invalidResponse }
        }
        throw AIClientError.invalidResponse
    }

    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String {
        try validateKey(configuration.apiKey)
        guard AIProvider.isSafeModelID(configuration.modelID) else { throw AIClientError.invalidModel }
        let request = try generationRequest(configuration: configuration, system: system, user: user)
        return try output(from: await object(for: request), provider: configuration.provider)
    }

    func generateTranslation(configuration: AIConfiguration, system: String, user: String,
                             onUpdate: @escaping AITextUpdate) async throws -> String {
        try await generateStream(configuration: configuration, system: system, user: user, mode: .translation, onUpdate: onUpdate)
    }

    func generateRewrite(configuration: AIConfiguration, system: String, user: String,
                         onUpdate: @escaping AITextUpdate) async throws -> String {
        try await generateStream(configuration: configuration, system: system, user: user, mode: .grammar, onUpdate: onUpdate)
    }

    private func generateStream(configuration: AIConfiguration, system: String, user: String, mode: WorkMode,
                                onUpdate: @escaping AITextUpdate) async throws -> String {
        guard configuration.provider == .openAI else {
            return try await generate(configuration: configuration, system: system, user: user)
        }
        try validateKey(configuration.apiKey)
        guard AIProvider.isSafeModelID(configuration.modelID) else { throw AIClientError.invalidModel }
        let request = try generationRequest(configuration: configuration, system: system, user: user, streamingMode: mode)
        let stream = OpenAITextStream(mode: mode, onUpdate: onUpdate)
        do {
            try Task.checkCancellation()
            try await streamingTransport(request) { event in try await stream.receive(event) }
            try Task.checkCancellation()
            return try await stream.finish()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AIClientError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw AIClientError.timedOut
        } catch {
            throw AIClientError.network
        }
    }

    private func request(url: URL, provider: AIProvider, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if provider == .gemini {
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if provider == .claude { request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version") }
        return request
    }

    private func generationRequest(configuration: AIConfiguration, system: String, user: String,
                                   validating: Bool = false, streamingMode: WorkMode? = nil) throws -> URLRequest {
        let provider = configuration.provider
        var request = request(url: try provider.generationURL(modelID: configuration.modelID), provider: provider, apiKey: configuration.apiKey)
        request.httpMethod = "POST"
        request.timeoutInterval = validating ? 30 : 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        switch provider {
        case .claude:
            body = ["model": configuration.modelID, "system": system,
                    "messages": [["role": "user", "content": user]], "max_tokens": 8192, "stream": false]
        case .gemini:
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": user]]]],
                    "generationConfig": ["maxOutputTokens": 8192]]
        default:
            var chat: [String: Any] = ["model": configuration.modelID,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]], "stream": streamingMode != nil]
            let tokenField = (provider == .openAI || provider == .kimi) ? "max_completion_tokens" : "max_tokens"
            chat[tokenField] = validating ? 16 : 8192
            if validating { chat["thinking"] = ["type": "disabled"] }
            // Effort compatibility is model-specific. Keep other models on their
            // existing policy and preserve some reasoning for grammar analysis.
            if provider == .openAI {
                if streamingMode == .translation, configuration.modelID == "gpt-6-luna" {
                    chat["reasoning_effort"] = "none"
                } else if streamingMode == .grammar, configuration.modelID == "gpt-6.1-terra" {
                    chat["reasoning_effort"] = "low"
                }
            }
            body = chat
        }
        if streamingMode != nil { request.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func object(for request: URLRequest) async throws -> [String: Any] {
        try Task.checkCancellation()
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw AIClientError.timedOut
        } catch {
            throw AIClientError.network
        }
        try Task.checkCancellation()
        try Self.validateStatus(response)
        guard data.count <= 10_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil else { throw AIClientError.invalidResponse }
        return object
    }

    static func validateStatus(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: break
        case 401: throw AIClientError.unauthorized
        case 403: throw AIClientError.forbidden
        case 429: throw AIClientError.rateLimited
        default: throw AIClientError.http(response.statusCode)
        }
    }

    private func model(from row: [String: Any], provider: AIProvider) -> AIModelInfo? {
        let id: String
        if provider == .gemini {
            guard let name = row["name"] as? String, name.hasPrefix("models/"),
                  let methods = row["supportedGenerationMethods"] as? [String], methods.contains("generateContent") else { return nil }
            id = String(name.dropFirst("models/".count))
        } else {
            guard let modelID = row["id"] as? String else { return nil }
            id = modelID
        }
        guard AIProvider.isSafeModelID(id) else { return nil }
        if let input = row["input_modalities"] as? [String], !input.contains("text") { return nil }
        if let output = row["output_modalities"] as? [String], !output.contains("text") { return nil }
        if let lifecycle = row["lifecycle"] as? String, ["retired", "shutdown"].contains(lifecycle) { return nil }
        let lower = id.lowercased()
        switch provider {
        case .openAI:
            // /models exposes no endpoint capability field. Keep established chat
            // families and exclude task-specific / Responses-only model variants.
            let textFamily = lower.hasPrefix("gpt-") || lower.hasPrefix("chatgpt-")
                || lower.range(of: "^o[0-9]", options: .regularExpression) != nil
            let excluded = ["audio", "realtime", "transcrib", "tts", "image", "codex", "-pro", "deep-research", "search", "instruct"]
            guard textFamily, !excluded.contains(where: lower.contains) else { return nil }
        case .gemini:
            guard !["image", "tts", "audio", "robotics", "computer-use"].contains(where: lower.contains) else { return nil }
        default: break
        }
        let name = row["display_name"] as? String ?? row["displayName"] as? String ?? row["name"] as? String
        return AIModelInfo(id: id, displayName: name.flatMap { $0.isEmpty ? nil : $0 } ?? id)
    }

    private func output(from object: [String: Any], provider: AIProvider) throws -> String {
        let text: String
        switch provider {
        case .claude:
            let stop = object["stop_reason"] as? String
            if stop == "max_tokens" { throw AIClientError.truncated }
            if stop == "refusal" { throw AIClientError.blocked }
            guard let blocks = object["content"] as? [[String: Any]] else { throw AIClientError.invalidResponse }
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .gemini:
            if let feedback = object["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil { throw AIClientError.blocked }
            guard let candidate = (object["candidates"] as? [[String: Any]])?.first else { throw AIClientError.emptyResponse }
            let finish = candidate["finishReason"] as? String
            if finish == "MAX_TOKENS" { throw AIClientError.truncated }
            if let finish, !["STOP", "FINISH_REASON_UNSPECIFIED"].contains(finish) { throw AIClientError.blocked }
            guard let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else { throw AIClientError.emptyResponse }
            text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        default:
            guard let choice = (object["choices"] as? [[String: Any]])?.first,
                  let message = choice["message"] as? [String: Any] else { throw AIClientError.invalidResponse }
            let finish = choice["finish_reason"] as? String
            if finish == "length" { throw AIClientError.truncated }
            if finish == "content_filter" || (message["refusal"] as? String)?.isEmpty == false { throw AIClientError.blocked }
            if let content = message["content"] as? String { text = content }
            else if let parts = message["content"] as? [[String: Any]] {
                text = parts.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            } else { throw AIClientError.emptyResponse }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIClientError.emptyResponse }
        return trimmed
    }

    private func validateKey(_ key: String) throws {
        guard !key.isEmpty, key.count <= 4096,
              key.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e }) else { throw AIClientError.invalidKey }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        return (data, http)
    }

    private static func sendStream(_ request: URLRequest,
                                   receive: @escaping @Sendable (AIStreamEvent) async throws -> Void) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        // End the connection on cancellation, parse errors, and early rejection.
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        try await receive(.response(http))
        for try await line in bytes.lines {
            try Task.checkCancellation()
            try await receive(.line(line))
            // The protocol ends at DONE; do not wait for the server to close a
            // connection after a complete answer. receive validates the marker.
            if line.hasPrefix("data:"), line.dropFirst(5).trimmingCharacters(in: .whitespaces) == "[DONE]" { break }
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Fixed API endpoints should not redirect an Authorization header elsewhere.
        completionHandler(nil)
    }
}
