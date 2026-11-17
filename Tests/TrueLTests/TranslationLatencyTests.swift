import Foundation
import Testing
@testable import TrueL

@MainActor
struct TranslationLatencyTests {
    @Test(arguments: [false, true])
    func sourceEnvelopeNeverReachesTheVisibleOrCopiedResult(_ fails: Bool) async throws {
        let gate = TranslationGate()
        let client = makeClient { request, receive in
            try await receive(.response(streamResponse(request)))
            try await receive(.line(chunk(#"{"source":"你好"#)))
            await gate.pause()
            if fails { throw URLError(.networkConnectionLost) }
            try await receive(.line(chunk(#"\n第二段。"}"#)))
            try await endStream(receive)
        }
        let service = await configuredService(client)
        var copied: [String] = []
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client), copyText: { copied.append($0) })
        model.mode = .translation
        model.input = "Hello.\nSecond paragraph."
        model.submit()
        await gate.waitUntilPaused()
        #expect(model.output.isEmpty)
        #expect(model.isProcessing && !model.hasResult)
        model.copyResult()
        model.applyResult()
        #expect(copied.isEmpty && model.input == "Hello.\nSecond paragraph.")
        await gate.resume()
        await waitForCompletion(model)
        #expect(model.output == (fails ? "" : "你好\n第二段。"))
        #expect(model.hasResult == !fails)
        model.copyResult()
        if fails {
            #expect(copied.isEmpty)
            #expect(model.errorMessage == AIClientError.network.errorDescription)
            model.applyResult()
            #expect(model.input == "Hello.\nSecond paragraph.")
        } else {
            #expect(copied == ["你好\n第二段。"])
            model.applyResult()
            #expect(model.input == "你好\n第二段。")
        }
    }

    @Test func lunaTranslationRequestsStreamingWithoutExtraReasoning() async throws {
        let recorder = TranslationRequestRecorder()
        let client = AIClient(transport: { request in
            await recorder.append(request)
            let json = request.httpMethod == "GET"
                ? #"{"data":[{"id":"gpt-6-luna"}]}"#
                : #"{"choices":[{"message":{"content":"你好"},"finish_reason":"stop"}]}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }, streamingTransport: { request, receive in
            await recorder.append(request)
            try await receive(.response(streamResponse(request)))
            try await receive(.line(chunk("你好")))
            try await endStream(receive)
        })
        let service = ServiceConfiguration(persist: false, client: client)
        service.switchProvider(.openAI)
        service.draftKey = "test-key"
        await service.saveKey()
        #expect(service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-6-luna"), for: .translation))
        let engine = ProviderLanguageEngine(service: service, client: client)
        #expect(try await engine.perform(LanguageRequest(source: "Hello", mode: .translation)).text == "你好")
        let request = try #require(await recorder.requests.last)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(body["reasoning_effort"] as? String == "none")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.timeoutInterval == 120)
    }

    @Test func firstTextIsVisibleWhileCompletionIsHeldAndActionsStayDisabled() async throws {
        let gate = TranslationGate()
        let client = makeClient { request, receive in
            try await receive(.response(streamResponse(request)))
            try await receive(.line(#"data: {"choices":[{"index":0,"delta":{"role":"assistant","reasoning_content":"hidden"},"finish_reason":null}]}"#))
            try await receive(.line(chunk("你好 🌍")))
            await gate.pause()
            try await receive(.line(chunk("\n第二段。")))
            try await endStream(receive)
        }
        let service = await configuredService(client)
        var copied: [String] = []
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client), copyText: { copied.append($0) })
        model.mode = .translation
        model.input = "Hello world.\nSecond paragraph."
        model.submit()
        await gate.waitUntilPaused()
        #expect(model.output == "你好 🌍")
        #expect(model.isProcessing)
        #expect(!model.hasResult)
        model.copyResult()
        model.applyResult()
        #expect(copied.isEmpty)
        #expect(model.input == "Hello world.\nSecond paragraph.")
        await gate.resume()
        await waitForCompletion(model)
        #expect(model.output == "你好 🌍\n第二段。")
        #expect(model.hasResult)
        model.copyResult()
        #expect(copied == ["你好 🌍\n第二段。"])
    }

    @Test(arguments: ["cancel", "input", "model", "modelRoundTrip", "otherTask"])
    func staleStreamsCannotOverwriteCurrentSession(_ change: String) async throws {
        let gate = TranslationGate()
        let client = makeClient { request, receive in
            try await receive(.response(streamResponse(request)))
            try await receive(.line(chunk("首段")))
            await gate.pause()
            defer { Task { await gate.markFinished() } }
            try await receive(.line(chunk("过时尾段")))
            try await endStream(receive)
        }
        let service = await configuredService(client)
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client))
        model.mode = .translation
        model.input = "Original text"
        model.submit()
        await gate.waitUntilPaused()
        switch change {
        case "cancel": model.cancel()
        case "input": model.input = "New text"
        case "model", "modelRoundTrip":
            service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-4.1-mini"), for: .translation)
            if change == "modelRoundTrip" {
                service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-6-luna"), for: .translation)
            }
        default: service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-4.1-mini"), for: .grammar)
        }
        await gate.resume()
        await gate.waitUntilFinished()
        await waitForCompletion(model)
        #expect(model.output == (change == "otherTask" ? "首段过时尾段" : ""))
        #expect(model.hasResult == (change == "otherTask"))
        #expect(model.errorMessage == nil)
    }

    @Test func failureAfterFirstTextClearsThePartialResult() async throws {
        let gate = TranslationGate()
        let client = makeClient { request, receive in
            try await receive(.response(streamResponse(request)))
            try await receive(.line(chunk("未完成译文")))
            await gate.pause()
            throw URLError(.networkConnectionLost)
        }
        let service = await configuredService(client)
        var copies: [String] = []
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client), copyText: { copies.append($0) })
        model.mode = .translation
        model.input = "Original text"
        model.submit()
        await gate.waitUntilPaused()
        #expect(model.output == "未完成译文")
        await gate.resume()
        await waitForCompletion(model)
        #expect(model.output.isEmpty)
        #expect(!model.hasResult)
        #expect(model.errorMessage == AIClientError.network.errorDescription)
        model.copyResult()
        model.applyResult()
        #expect(copies.isEmpty)
        #expect(model.input == "Original text")
    }

    @Test func otherOpenAIModelsAndRewritingKeepTheirReasoningPolicy() async throws {
        let recorder = TranslationRequestRecorder()
        let client = AIClient(transport: { request in
            await recorder.append(request)
            return (Data(#"{"choices":[{"message":{"content":"正文"},"finish_reason":"stop"}]}"#.utf8), streamResponse(request))
        }, streamingTransport: { request, receive in
            await recorder.append(request)
            try await receive(.response(streamResponse(request)))
            try await receive(.line(chunk("正文")))
            try await endStream(receive)
        })
        _ = try await client.generateTranslation(configuration: config(model: "gpt-4.1-mini"), system: "system", user: "text", onUpdate: { _ in })
        _ = try await client.generate(configuration: config(), system: "Rewrite", user: "text")
        let requests = await recorder.requests
        #expect(requests.count == 2)
        for (index, request) in requests.enumerated() {
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["reasoning_effort"] == nil)
            #expect(body["stream"] as? Bool == (index == 0))
        }
    }

    @Test(arguments: AIProvider.allCases.filter { $0 != .openAI }, WorkMode.allCases)
    func otherProvidersKeepTheirExistingGenerationPath(_ provider: AIProvider, mode: WorkMode) async throws {
        let client = AIClient(transport: { request in
            let json: String
            switch provider {
            case .claude: json = #"{"content":[{"type":"text","text":"正文"}],"stop_reason":"end_turn"}"#
            case .gemini: json = #"{"candidates":[{"content":{"parts":[{"text":"正文"}]},"finishReason":"STOP"}]}"#
            default: json = #"{"choices":[{"message":{"content":"正文"},"finish_reason":"stop"}]}"#
            }
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["stream"] as? Bool != true)
            #expect(body["reasoning_effort"] == nil)
            return (Data(json.utf8), streamResponse(request))
        }, streamingTransport: { _, _ in Issue.record("Unexpected streaming request") })
        let onUpdate: AITextUpdate = { _ in
            Issue.record("Unexpected partial result")
        }
        let result = if mode == .translation {
            try await client.generateTranslation(configuration: config(provider: provider), system: "system", user: "source", onUpdate: onUpdate)
        } else {
            try await client.generateRewrite(configuration: config(provider: provider), system: "system", user: "source", onUpdate: onUpdate)
        }
        #expect(result == "正文")
    }

    @Test(arguments: [401, 403, 429, 500])
    func streamHTTPFailuresStaySanitized(_ status: Int) async throws {
        let client = makeClient { request, receive in
            try await receive(.response(streamResponse(request, status: status)))
            try await receive(.line("data: private-key private-source"))
        }
        let expected: AIClientError = switch status {
        case 401: .unauthorized
        case 403: .forbidden
        case 429: .rateLimited
        default: .http(status)
        }
        await #expect(throws: expected) {
            try await client.generateTranslation(configuration: config(), system: "system", user: "text", onUpdate: { _ in })
        }
    }

    @Test func malformedIncompleteAndRejectedStreamsCannotSucceed() async throws {
        let cases: [([String], AIClientError)] = [
            (["data: not json"], .invalidResponse),
            ([#"data: {"error":{"message":"private-key private-source"}}"#], .invalidResponse),
            ([chunk("正文")], .invalidResponse),
            ([chunk("正文"), stopChunk], .invalidResponse),
            ([chunk("正文"), "data: [DONE]"], .invalidResponse),
            ([stopChunk, "data: [DONE]"], .emptyResponse),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#], .truncated),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}"#], .blocked),
            ([#"data: {"choices":[{"index":0,"delta":{"refusal":"no"},"finish_reason":null}]}"#], .blocked),
            ([#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#], .invalidResponse),
            ([String(repeating: "x", count: 10_000_001)], .invalidResponse)
        ]
        for (lines, expected) in cases {
            let client = makeClient { request, receive in
                try await receive(.response(streamResponse(request)))
                for line in lines { try await receive(.line(line)) }
            }
            await #expect(throws: expected) {
                try await client.generateTranslation(configuration: config(), system: "system", user: "text", onUpdate: { _ in })
            }
        }
    }

    @Test func streamTimeoutCancellationAndWrongContentTypeStayDistinct() async throws {
        for (code, expected) in [(URLError.timedOut, AIClientError.timedOut), (.notConnectedToInternet, .network)] {
            let client = makeClient { _, _ in throw URLError(code) }
            await #expect(throws: expected) {
                try await client.generateTranslation(configuration: config(), system: "system", user: "text", onUpdate: { _ in })
            }
        }
        let cancelled = makeClient { _, _ in throw URLError(.cancelled) }
        await #expect(throws: CancellationError.self) {
            try await cancelled.generateTranslation(configuration: config(), system: "system", user: "text", onUpdate: { _ in })
        }
        let wrongType = makeClient { request, receive in
            try await receive(.response(streamResponse(request, contentType: "application/json")))
        }
        await #expect(throws: AIClientError.invalidResponse) {
            try await wrongType.generateTranslation(configuration: config(), system: "system", user: "text", onUpdate: { _ in })
        }
    }

    private func configuredService(_ client: AIClient) async -> ServiceConfiguration {
        let service = ServiceConfiguration(persist: false, client: client)
        service.switchProvider(.openAI)
        service.draftKey = "test-key"
        await service.saveKey()
        #expect(service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-6-luna"), for: .translation))
        return service
    }

    private func waitForCompletion(_ model: DemoModel) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isProcessing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isProcessing)
    }
}

private actor TranslationRequestRecorder {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

private func config(provider: AIProvider = .openAI, model: String = "gpt-6-luna") -> AIConfiguration {
    AIConfiguration(provider: provider, apiKey: "test-key", modelID: model)
}

private func makeClient(streaming: @escaping AIClient.StreamingTransport) -> AIClient {
    AIClient(transport: { request in
        #expect(request.httpMethod == "GET")
        return (Data(#"{"data":[{"id":"gpt-6-luna"},{"id":"gpt-4.1-mini"}]}"#.utf8), streamResponse(request))
    }, streamingTransport: streaming)
}

private func streamResponse(_ request: URLRequest, status: Int = 200, contentType: String = "text/event-stream") -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!
}

private func chunk(_ text: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: ["choices": [["index": 0, "delta": ["content": text], "finish_reason": NSNull()]]])
    return "data: " + String(decoding: data, as: UTF8.self)
}

private let stopChunk = #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#

private func endStream(_ receive: @Sendable (AIStreamEvent) async throws -> Void) async throws {
    try await receive(.line(stopChunk))
    try await receive(.line("data: [DONE]"))
}

private actor TranslationGate {
    private var paused = false
    private var finished = false
    private var release: CheckedContinuation<Void, Never>?
    private var pausedWaiter: CheckedContinuation<Void, Never>?
    private var finishedWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation
            paused = true
            pausedWaiter?.resume()
            pausedWaiter = nil
        }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { pausedWaiter = $0 }
    }

    func resume() { release?.resume(); release = nil }

    func markFinished() {
        finished = true
        finishedWaiter?.resume()
        finishedWaiter = nil
    }

    func waitUntilFinished() async {
        if finished { return }
        await withCheckedContinuation { finishedWaiter = $0 }
    }
}
