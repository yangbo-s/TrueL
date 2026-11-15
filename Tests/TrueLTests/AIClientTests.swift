import Foundation
import Testing
@testable import TrueL

struct AIClientTests {
    @Test(arguments: AIProvider.allCases)
    func modelListingUsesOfficialEndpointAndAuthentication(_ provider: AIProvider) async throws {
        let recorder = RequestRecorder()
        let client = AIClient { request in
            await recorder.append(request)
            return response(request, json: modelFixture(provider))
        }
        let models = try await client.listModels(provider: provider, apiKey: "test-key")
        #expect(!models.isEmpty)
        let request = try #require(await recorder.requests.first)
        #expect(request.url?.absoluteString.contains("test-key") == false)
        if provider == .gemini {
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        } else {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        }
        if provider == .claude { #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21") }
        if provider == .glm {
            #expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/paas/v4/chat/completions")
            #expect(request.httpMethod == "POST")
            let body = try jsonBody(request)
            #expect(body["model"] as? String == "glm-4.7-flash")
            #expect(body["max_tokens"] as? Int == 16)
            #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
            #expect(models.contains { $0.id == "glm-4.7-flash" })
        } else {
            #expect(request.httpMethod == "GET")
            #expect(request.url?.host == provider.modelsURL?.host)
            #expect(request.url?.path == provider.modelsURL?.path)
        }
    }

    @Test(arguments: AIProvider.allCases)
    func generationPreservesPromptsAndDecodesOnlyVisibleText(_ provider: AIProvider) async throws {
        let recorder = RequestRecorder()
        let client = AIClient { request in
            await recorder.append(request)
            let json: String
            switch provider {
            case .claude: json = #"{"content":[{"type":"thinking","thinking":"private reasoning"},{"type":"text","text":"译文"}],"stop_reason":"end_turn"}"#
            case .gemini: json = #"{"candidates":[{"content":{"parts":[{"thought":true,"text":"private reasoning"},{"text":"译文"}]},"finishReason":"STOP"}]}"#
            default: json = #"{"choices":[{"message":{"content":"译文","reasoning_content":"private reasoning"},"finish_reason":"stop"}]}"#
            }
            return response(request, json: json)
        }
        let config = AIConfiguration(provider: provider, apiKey: "test-key", modelID: "text-model")
        let output = try await client.generate(configuration: config, system: "Translate only.", user: "你好\n🌍")
        #expect(output == "译文")
        let request = try #require(await recorder.requests.first)
        #expect(request.url?.absoluteString == expectedGenerationURL(provider))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try jsonBody(request)
        switch provider {
        case .claude:
            #expect(body["system"] as? String == "Translate only.")
            #expect((body["messages"] as? [[String: String]])?.first?["content"] == "你好\n🌍")
            #expect(body["max_tokens"] as? Int == 8192)
        case .gemini:
            #expect(((body["systemInstruction"] as? [String: Any])?["parts"] as? [[String: String]])?.first?["text"] == "Translate only.")
            let contents = try #require(body["contents"] as? [[String: Any]])
            #expect((contents.first?["parts"] as? [[String: String]])?.first?["text"] == "你好\n🌍")
        default:
            #expect((body["messages"] as? [[String: String]]) == [
                ["role": "system", "content": "Translate only."], ["role": "user", "content": "你好\n🌍"]])
            let tokenField = (provider == .openAI || provider == .kimi) ? "max_completion_tokens" : "max_tokens"
            #expect(body[tokenField] as? Int == 8192)
        }
        #expect(body["temperature"] == nil)
    }

    @Test func paginatedGeminiListFiltersUnsupportedModelsAndDeduplicates() async throws {
        let recorder = RequestRecorder()
        let client = AIClient { request in
            await recorder.append(request)
            if request.url?.query?.contains("pageToken=second") == true {
                return response(request, json: #"{"models":[{"name":"models/gemini-text","displayName":"Text","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-tts","supportedGenerationMethods":["generateContent"]}]}"#)
            }
            return response(request, json: #"{"models":[{"name":"models/gemini-text","displayName":"Text","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding","supportedGenerationMethods":["embedContent"]}],"nextPageToken":"second"}"#)
        }
        let models = try await client.listModels(provider: .gemini, apiKey: "test-key")
        #expect(models == [AIModelInfo(id: "gemini-text", displayName: "Text")])
        #expect(await recorder.requests.count == 2)
    }

    @Test func claudePaginationUsesLastID() async throws {
        let recorder = RequestRecorder()
        let client = AIClient { request in
            await recorder.append(request)
            if request.url?.query?.contains("after_id=claude-a") == true {
                return response(request, json: #"{"data":[{"id":"claude-b","display_name":"B"}],"has_more":false}"#)
            }
            return response(request, json: #"{"data":[{"id":"claude-a","display_name":"A"}],"has_more":true,"last_id":"claude-a"}"#)
        }
        #expect(try await client.listModels(provider: .claude, apiKey: "test-key").map(\.id) == ["claude-a", "claude-b"])
        #expect(await recorder.requests.count == 2)
    }

    @Test func repeatedPageTokenFailsRatherThanLooping() async throws {
        let client = AIClient { request in response(request, json: #"{"models":[],"nextPageToken":"same"}"#) }
        await #expect(throws: AIClientError.invalidResponse) {
            try await client.listModels(provider: .gemini, apiKey: "test-key")
        }
    }

    @Test func openAIListExcludesNonChatModels() async throws {
        let client = AIClient { request in
            response(request, json: #"{"data":[{"id":"gpt-4.1-mini"},{"id":"text-embedding-3-small"},{"id":"gpt-image-1"},{"id":"gpt-audio"},{"id":"gpt-5-pro"},{"id":"gpt-5-codex"},{"id":"gpt-3.5-turbo-instruct"}]}"#)
        }
        #expect(try await client.listModels(provider: .openAI, apiKey: "test-key").map(\.id) == ["gpt-4.1-mini"])
    }

    @Test(arguments: [401, 403, 429, 500])
    func serverFailuresNeverExposeResponseBody(_ status: Int) async {
        let client = AIClient { request in response(request, status: status, json: #"{"error":{"message":"test-secret-key private user text"}}"#) }
        do {
            _ = try await client.listModels(provider: .openAI, apiKey: "test-secret-key")
            Issue.record("Expected provider failure")
        } catch {
            let expected: AIClientError = switch status {
            case 401: .unauthorized
            case 403: .forbidden
            case 429: .rateLimited
            default: .http(status)
            }
            #expect(error as? AIClientError == expected)
            #expect(!AIClientError.safeMessage(for: error).contains("test-secret-key"))
            #expect(!AIClientError.safeMessage(for: error).contains("private user text"))
        }
    }

    @Test func timeoutAndCancellationRemainDistinct() async {
        let timeout = AIClient { _ in throw URLError(.timedOut) }
        await #expect(throws: AIClientError.timedOut) { try await timeout.listModels(provider: .openAI, apiKey: "test-key") }
        let cancelled = AIClient { _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) { try await cancelled.listModels(provider: .openAI, apiKey: "test-key") }
    }

    @Test func rejectsEmptyMalformedTruncatedAndBlockedResponses() async {
        for (json, expected) in [
            ("not json", AIClientError.invalidResponse),
            (#"{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}"#, .emptyResponse),
            (#"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#, .truncated),
            (#"{"choices":[{"message":{"content":"blocked"},"finish_reason":"content_filter"}]}"#, .blocked)
        ] {
            let client = AIClient { request in response(request, json: json) }
            await #expect(throws: expected) {
                try await client.generate(configuration: AIConfiguration(provider: .openAI, apiKey: "test-key", modelID: "gpt-test"), system: "system", user: "text")
            }
        }
    }

    @Test func invalidCredentialsAndPathNeverReachTransport() async {
        let recorder = RequestRecorder()
        let client = AIClient { request in await recorder.append(request); return response(request, json: "{}") }
        await #expect(throws: AIClientError.invalidKey) { try await client.listModels(provider: .openAI, apiKey: "key\r\ninjected") }
        await #expect(throws: AIClientError.invalidModel) {
            try await client.generate(configuration: AIConfiguration(provider: .gemini, apiKey: "test-key", modelID: "../other?key=leak"), system: "", user: "text")
        }
        #expect(await recorder.requests.isEmpty)
    }
}

private actor RequestRecorder {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

private func response(_ request: URLRequest, status: Int = 200, json: String) -> (Data, HTTPURLResponse) {
    (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
}

private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    let data = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func modelFixture(_ provider: AIProvider) -> String {
    switch provider {
    case .openAI: #"{"data":[{"id":"gpt-4.1-mini"}]}"#
    case .claude: #"{"data":[{"id":"claude-test","display_name":"Claude Test"}],"has_more":false}"#
    case .gemini: #"{"models":[{"name":"models/gemini-test","displayName":"Gemini Test","supportedGenerationMethods":["generateContent"]}]}"#
    case .grok: #"{"models":[{"id":"grok-test","input_modalities":["text"],"output_modalities":["text"]}]}"#
    case .deepSeek: #"{"data":[{"id":"deepseek-test","name":"DeepSeek Test"}]}"#
    case .kimi: #"{"data":[{"id":"kimi-test"}]}"#
    case .glm: #"{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}"#
    }
}

private func expectedGenerationURL(_ provider: AIProvider) -> String {
    switch provider {
    case .openAI: "https://api.openai.com/v1/chat/completions"
    case .claude: "https://api.anthropic.com/v1/messages"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta/models/text-model:generateContent"
    case .grok: "https://api.x.ai/v1/chat/completions"
    case .deepSeek: "https://api.deepseek.com/chat/completions"
    case .kimi: "https://api.moonshot.cn/v1/chat/completions"
    case .glm: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    }
}
