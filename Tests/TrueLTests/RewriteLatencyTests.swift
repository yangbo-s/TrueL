import Foundation
import Testing
@testable import TrueL

@MainActor
struct RewriteLatencyTests {
    @Test func terraRewriteRequestsStreamingWithLowReasoning() async throws {
        let recorder = RewriteRequestRecorder()
        let client = AIClient(transport: { request in
            await recorder.append(request)
            let json = request.httpMethod == "GET"
                ? #"{"data":[{"id":"gpt-6.1-terra"}]}"#
                : #"{"choices":[{"message":{"content":"{\"output\":\"I have an idea.\",\"corrections\":[]}"},"finish_reason":"stop"}]}"#
            return (Data(json.utf8), rewriteResponse(request, contentType: "application/json"))
        }, streamingTransport: { request, receive in
            await recorder.append(request)
            try await receive(.response(rewriteResponse(request)))
            try await receive(.line(rewriteChunk(#"{"output":"I have an idea.","corrections":[]}"#)))
            try await endRewriteStream(receive)
        })
        let service = await configuredService(client)
        let engine = ProviderLanguageEngine(service: service, client: client)
        #expect(try await engine.perform(LanguageRequest(source: "I has an idea.", mode: .grammar)).text == "I have an idea.")
        let request = try #require(await recorder.requests.last)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect(body["reasoning_effort"] as? String == "low")
        #expect(body["max_completion_tokens"] as? Int == 8192)
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.first?["content"]?.contains("Emit output as the first field") == true)
    }

    @Test func completedBodyAppearsBeforeCorrectionsAndCannotBeAppliedEarly() async throws {
        let gate = RewriteGate()
        let client = makeRewriteClient { request, receive in
            try await receive(.response(rewriteResponse(request)))
            try await receive(.line(rewriteChunk(#"{"output":"I have"#)))
            try await receive(.line(rewriteChunk(#" an idea.","#)))
            await gate.pause()
            try await receive(.line(rewriteChunk(rewriteMetadata)))
            try await endRewriteStream(receive)
        }
        let service = await configuredService(client)
        var copies: [String] = []
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client), copyText: { copies.append($0) })
        model.input = "I has an idea."
        model.submit()
        defer { model.cancel() }
        #expect(await gate.waitUntilPaused())
        #expect(model.output == "I have an idea.")
        #expect(model.isProcessing)
        #expect(!model.hasResult)
        #expect(model.corrections.isEmpty && model.tip.isEmpty)
        model.copyResult()
        model.applyResult()
        #expect(copies.isEmpty && model.input == "I has an idea.")
        await gate.resume()
        await waitForCompletion(model)
        #expect(model.output == "I have an idea.")
        #expect(model.hasResult)
        #expect(model.corrections.count == 1)
        #expect(model.corrections.first?.original == "has")
        #expect(model.corrections.first?.replacement == "have")
        #expect(model.corrections.first?.explanation == "主语 I 使用 have。")
        #expect(model.tip == "注意主谓一致。")
        model.copyResult()
        #expect(copies == ["I have an idea."])
    }

    @Test(arguments: ["cancel", "input", "style", "model", "modelRoundTrip", "otherTask"])
    func changedSessionRejectsLateRewriteMetadata(_ change: String) async throws {
        let gate = RewriteGate()
        let client = makeRewriteClient { request, receive in
            try await receive(.response(rewriteResponse(request)))
            try await receive(.line(rewriteChunk(#"{"output":"I have an idea.","#)))
            await gate.pause()
            defer { Task { await gate.markFinished() } }
            try await receive(.line(rewriteChunk(rewriteMetadata)))
            try await endRewriteStream(receive)
        }
        let service = await configuredService(client)
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client))
        model.input = "I has an idea."
        model.submit()
        defer { model.cancel() }
        #expect(await gate.waitUntilPaused())
        switch change {
        case "cancel": model.cancel()
        case "input": model.input = "New source."
        case "style": model.writingStyle = "professional"
        case "model", "modelRoundTrip":
            service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-4.1-mini"), for: .grammar)
            if change == "modelRoundTrip" {
                service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-6.1-terra"), for: .grammar)
            }
        default: service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-4.1-mini"), for: .translation)
        }
        await gate.resume()
        #expect(await gate.waitUntilFinished())
        await waitForCompletion(model)
        #expect(model.output == (change == "otherTask" ? "I have an idea." : ""))
        #expect(model.corrections.count == (change == "otherTask" ? 1 : 0))
        #expect(model.hasResult == (change == "otherTask"))
        #expect(model.errorMessage == nil)
    }

    @Test(arguments: ["network", "invalidJSON", "truncated", "blocked", "missingEnd"])
    func failedMetadataClearsBodyAndNeverEnablesReplacement(_ failure: String) async throws {
        let gate = RewriteGate()
        let client = makeRewriteClient { request, receive in
            try await receive(.response(rewriteResponse(request)))
            try await receive(.line(rewriteChunk(#"{"output":"I have an idea.","#)))
            await gate.pause()
            switch failure {
            case "network": throw URLError(.networkConnectionLost)
            case "invalidJSON": try await endRewriteStream(receive)
            case "truncated":
                try await receive(.line(#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#))
            case "blocked":
                try await receive(.line(#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"content_filter"}]}"#))
            default: break
            }
        }
        let service = await configuredService(client)
        var copies: [String] = []
        let model = DemoModel(engine: ProviderLanguageEngine(service: service, client: client), copyText: { copies.append($0) })
        model.input = "I has an idea."
        model.submit()
        defer { model.cancel() }
        #expect(await gate.waitUntilPaused())
        #expect(model.output == "I have an idea.")
        await gate.resume()
        await waitForCompletion(model)
        #expect(model.output.isEmpty && model.corrections.isEmpty && model.tip.isEmpty)
        #expect(!model.hasResult && model.errorMessage != nil)
        model.copyResult()
        model.applyResult()
        #expect(copies.isEmpty && model.input == "I has an idea.")
    }

    @Test(arguments: [false, true])
    func unchangedAndReorderedResponsesRemainValid(_ reordered: Bool) async throws {
        let raw = reordered ? #"{"corrections":[],"output":"Clear.","tip":"ignored"}"#
            : #"{"output":"Clear.","corrections":[],"tip":"ignored"}"#
        let client = makeRewriteClient { request, receive in
            try await receive(.response(rewriteResponse(request)))
            try await receive(.line(rewriteChunk(raw)))
            try await endRewriteStream(receive)
        }
        let service = await configuredService(client)
        var updates: [String] = []
        let result = try await ProviderLanguageEngine(service: service, client: client).perform(
            LanguageRequest(source: "Clear.", mode: .grammar), onUpdate: { updates.append($0) })
        #expect(result.text == "Clear.")
        #expect(result.outcome == .unchanged && result.corrections.isEmpty && result.tip.isEmpty)
        #expect(updates == (reordered ? [] : ["Clear."]))
    }

    @Test(arguments: [WorkMode.grammar, .translation], ["gpt-6.1-terra", "gpt-6-luna", "gpt-4.1-mini"])
    func effortRemainsSpecificToModelAndTask(_ mode: WorkMode, model: String) async throws {
        let recorder = RewriteRequestRecorder()
        let client = makeRewriteClient { request, receive in
            await recorder.append(request)
            try await receive(.response(rewriteResponse(request)))
            let content = mode == .grammar ? #"{"output":"Clear.","corrections":[]}"# : "译文"
            try await receive(.line(rewriteChunk(content)))
            try await endRewriteStream(receive)
        }
        let config = AIConfiguration(provider: .openAI, apiKey: "test-key", modelID: model)
        if mode == .grammar {
            _ = try await client.generateRewrite(configuration: config, system: "system", user: "text", onUpdate: { _ in })
        } else {
            _ = try await client.generateTranslation(configuration: config, system: "system", user: "text", onUpdate: { _ in })
        }
        let request = try #require(await recorder.requests.last)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let expected: String? = mode == .grammar && model == "gpt-6.1-terra" ? "low"
            : mode == .translation && model == "gpt-6-luna" ? "none" : nil
        #expect(body["reasoning_effort"] as? String == expected)
        #expect(body["stream"] as? Bool == true)
    }

    private func configuredService(_ client: AIClient) async -> ServiceConfiguration {
        let service = ServiceConfiguration(persist: false, client: client)
        service.switchProvider(.openAI)
        service.draftKey = "test-key"
        await service.saveKey()
        #expect(service.selectModel(ModelSelection(provider: .openAI, modelID: "gpt-6.1-terra"), for: .grammar))
        return service
    }

    private func waitForCompletion(_ model: DemoModel) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isProcessing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isProcessing)
    }
}

private actor RewriteRequestRecorder {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

private func rewriteResponse(_ request: URLRequest, contentType: String = "text/event-stream") -> HTTPURLResponse {
    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": contentType])!
}

private func makeRewriteClient(streaming: @escaping AIClient.StreamingTransport) -> AIClient {
    AIClient(transport: { request in
        #expect(request.httpMethod == "GET")
        return (Data(#"{"data":[{"id":"gpt-6.1-terra"},{"id":"gpt-4.1-mini"}]}"#.utf8), rewriteResponse(request))
    }, streamingTransport: streaming)
}

private let rewriteMetadata = #""corrections":[{"original":"has","replacement":"have","explanation":"主语 I 使用 have。","pattern":"主谓一致"}],"tip":"注意主谓一致。"}"#

private func rewriteChunk(_ text: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: ["choices": [["index": 0, "delta": ["content": text], "finish_reason": NSNull()]]])
    return "data: " + String(decoding: data, as: UTF8.self)
}

private func endRewriteStream(_ receive: @Sendable (AIStreamEvent) async throws -> Void) async throws {
    try await receive(.line(#"data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#))
    try await receive(.line("data: [DONE]"))
}

private actor RewriteGate {
    private var paused = false
    private var finished = false
    private var release: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation
            paused = true
        }
    }

    func waitUntilPaused() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !paused, ContinuousClock.now < deadline { await Task.yield() }
        return paused
    }

    func resume() { release?.resume(); release = nil }
    func markFinished() { finished = true }

    func waitUntilFinished() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while !finished, ContinuousClock.now < deadline { await Task.yield() }
        return finished
    }
}
