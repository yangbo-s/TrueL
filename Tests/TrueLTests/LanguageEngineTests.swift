import Foundation
import Testing
@testable import TrueL

@MainActor
private final class DelayedLanguageEngine: LanguageEngine {
    var requests: [LanguageRequest] = []
    var fail = false
    func perform(_ request: LanguageRequest) async throws -> LanguageResult {
        requests.append(request)
        // Deliberately ignores cancellation to prove generation isolation.
        try? await Task.sleep(for: .milliseconds(50))
        if fail { throw LanguageResponseError.empty }
        return LanguageResult(text: "Live: " + request.source, outcome: .edited)
    }
}

enum RequestConfigurationChange: CaseIterable, Sendable {
    case key, provider, model, modelRoundTrip
}

/// Changes configuration synchronously on the same actor, before the awaiting
/// engine can return. No timing sleeps or App observation callback are involved.
@MainActor
private final class ConfigurationMutatingClient: AIClientProtocol {
    var onGenerate: @MainActor () -> Void = {}
    var fail = false
    var lastConfiguration: AIConfiguration?
    var lastSystem = ""
    var lastUser = ""
    var response = "译文"
    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        [AIModelInfo(id: "model-a", displayName: "A"), AIModelInfo(id: "model-b", displayName: "B")]
    }
    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String {
        lastConfiguration = configuration
        lastSystem = system
        lastUser = user
        onGenerate()
        if fail { throw AIClientError.unauthorized }
        return response
    }
}

@MainActor
private struct CancelledLanguageEngine: LanguageEngine {
    func perform(_ request: LanguageRequest) async throws -> LanguageResult { throw CancellationError() }
}

@MainActor
struct LanguageEngineTests {
    private func waitForCompletion(_ model: DemoModel) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isProcessing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isProcessing)
    }

    @Test(arguments: RequestConfigurationChange.allCases, [false, true])
    func savedConfigurationChangesRejectLateResponsesWhileDraftEditsStayIndependent(_ change: RequestConfigurationChange, responseFails: Bool) async throws {
        let client = ConfigurationMutatingClient()
        let service = ServiceConfiguration(persist: false, client: client)
        service.draftKey = "test-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .gemini, modelID: "model-a"), for: .translation)
        let before = service.configurationRevision(for: .translation)
        client.fail = responseFails
        client.onGenerate = {
            switch change {
            case .key: service.draftKey = "replacement-key"
            case .provider: service.switchProvider(.openAI)
            case .model: service.selectModel(ModelSelection(provider: .gemini, modelID: "model-b"), for: .translation)
            case .modelRoundTrip:
                service.selectModel(ModelSelection(provider: .gemini, modelID: "model-b"), for: .translation)
                service.selectModel(ModelSelection(provider: .gemini, modelID: "model-a"), for: .translation)
            }
        }
        let engine = ProviderLanguageEngine(service: service, client: client)
        if change == .key || change == .provider {
            if responseFails {
                await #expect(throws: AIClientError.unauthorized) {
                    try await engine.perform(LanguageRequest(source: "Hello", mode: .translation))
                }
            } else {
                #expect(try await engine.perform(LanguageRequest(source: "Hello", mode: .translation)).text == "译文")
            }
            #expect(service.configurationRevision(for: .translation) == before)
        } else {
            await #expect(throws: CancellationError.self) {
                try await engine.perform(LanguageRequest(source: "Hello", mode: .translation))
            }
            #expect(service.configurationRevision(for: .translation) > before)
        }
        #expect(client.lastConfiguration?.modelID == "model-a")
        if change == .modelRoundTrip {
            #expect(service.isReady(for: .translation))
            #expect(try service.configuration(for: .translation) == client.lastConfiguration)
        }
    }

    @Test func otherTaskModelChangeDoesNotCancelCurrentTranslation() async throws {
        let client = ConfigurationMutatingClient()
        let service = ServiceConfiguration(persist: false, client: client)
        service.draftKey = "test-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .gemini, modelID: "model-a"), for: .translation)
        client.onGenerate = {
            service.selectModel(ModelSelection(provider: .gemini, modelID: "model-b"), for: .grammar)
        }
        let engine = ProviderLanguageEngine(service: service, client: client)
        #expect(try await engine.perform(LanguageRequest(source: "Hello", mode: .translation)).text == "译文")
        #expect(client.lastConfiguration?.modelID == "model-a")
        #expect(try service.configuration(for: .grammar).modelID == "model-b")
    }

    @Test func unchangedConfigurationReturnsLiveResponse() async throws {
        let client = ConfigurationMutatingClient()
        let service = ServiceConfiguration(persist: false, client: client)
        service.draftKey = "test-key"
        await service.saveKey()
        service.selectModel(ModelSelection(provider: .gemini, modelID: "model-a"), for: .translation)
        let engine = ProviderLanguageEngine(service: service, client: client)
        let result = try await engine.perform(LanguageRequest(source: "Hello", mode: .translation))
        #expect(result.text == "译文")
        #expect(client.lastConfiguration?.provider == .gemini)
        client.fail = true
        await #expect(throws: AIClientError.unauthorized) {
            try await engine.perform(LanguageRequest(source: "Hello", mode: .translation))
        }
    }

    @Test func presetsReachProviderPromptAndRewriteStaysInSourceLanguage() async throws {
        let client = ConfigurationMutatingClient()
        let service = ServiceConfiguration(persist: false, client: client)
        service.draftKey = "test-key"
        await service.saveKey()
        for mode in WorkMode.allCases {
            service.selectModel(ModelSelection(provider: .gemini, modelID: "model-a"), for: mode)
        }
        let engine = ProviderLanguageEngine(service: service, client: client)
        _ = try await engine.perform(LanguageRequest(source: "A source sentence.", mode: .translation,
            targetLanguage: "日本語", writingStyle: "literal", sourceLanguage: "English"))
        #expect(client.lastSystem.contains("Source language: English"))
        #expect(client.lastSystem.contains("Translate only the value of its \"source\" field"))
        #expect(client.lastSystem.contains("Do not include the request's outer JSON object"))
        #expect(client.lastSystem.contains(TextStyle.resolve("literal", for: .translation).instruction))
        let payload = try #require(JSONSerialization.jsonObject(with: Data(client.lastUser.utf8)) as? [String: String])
        #expect(payload == ["source": "A source sentence."])
        client.response = #"{"output":"A source sentence.","corrections":[]}"#
        _ = try await engine.perform(LanguageRequest(source: "A source sentence.", mode: .grammar,
            writingStyle: "professional", sourceLanguage: "English"))
        #expect(client.lastSystem.contains("Do not translate the source."))
        #expect(client.lastSystem.contains(TextStyle.resolve("professional", for: .grammar).instruction))
        #expect(!client.lastSystem.contains("translation ("))
    }

    @Test func engineCancellationExitsLoadingWithoutResultOrError() async throws {
        let model = DemoModel(engine: CancelledLanguageEngine())
        model.input = "Source"
        model.submit()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isProcessing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isProcessing)
        #expect(!model.hasResult)
        #expect(model.output.isEmpty)
        #expect(model.errorMessage == nil)
    }

    @Test func missingNewSourceCannotRetryStaleText() async throws {
        let engine = DelayedLanguageEngine()
        let model = DemoModel(engine: engine)
        model.input = "Earlier selection"
        model.submit()
        await waitForCompletion(model)
        model.reportInputError("No new selection")
        #expect(model.input.isEmpty)
        #expect(!model.hasResult)
        model.submit()
        #expect(engine.requests.count == 1)
        #expect(!model.isProcessing)
    }
    @Test func realEngineReplacesFixturesAndCarriesLanguageAndStyle() async throws {
        let engine = DelayedLanguageEngine()
        let model = DemoModel(engine: engine)
        model.targetLanguage = "日本語"
        model.writingStyle = "professional"
        model.input = "Arbitrary source"
        model.submit()
        await waitForCompletion(model)
        #expect(model.output == "Live: Arbitrary source")
        #expect(engine.requests.first?.targetLanguage == "日本語")
        #expect(engine.requests.first?.writingStyle == "professional")
        #expect(!model.isProcessing)
    }

    @Test func editingAndCancellationRejectOldNetworkCompletion() async throws {
        let engine = DelayedLanguageEngine()
        let model = DemoModel(engine: engine)
        model.submit()
        try await Task.sleep(for: .milliseconds(10))
        model.input = "New source"
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.output.isEmpty)
        model.submit()
        try await Task.sleep(for: .milliseconds(10))
        model.cancel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.output.isEmpty)
        #expect(!model.isProcessing)
    }

    @Test func styleRegenerationUsesOriginalSourceAndTaskSpecificStyle() async throws {
        let engine = DelayedLanguageEngine()
        let model = DemoModel(engine: engine)
        model.input = "Original sentence in English."
        model.submit()
        await waitForCompletion(model)
        model.writingStyle = "concise"
        model.submit()
        await waitForCompletion(model)
        #expect(engine.requests.last?.source == "Original sentence in English.")
        #expect(engine.requests.last?.writingStyle == "concise")
        #expect(model.output == "Live: Original sentence in English.")
        model.mode = .translation
        model.translationStyle = "literal"
        model.targetLanguage = "English"
        model.submit()
        await waitForCompletion(model)
        #expect(engine.requests.last?.writingStyle == "literal")
        #expect(engine.requests.last?.targetLanguage == "简体中文")
        #expect(engine.requests.last?.sourceLanguage == "English")
    }

    @Test func providerFailureDoesNotFallBackToFakeSuccess() async throws {
        let engine = DelayedLanguageEngine()
        engine.fail = true
        let model = DemoModel(engine: engine)
        model.submit()
        await waitForCompletion(model)
        #expect(model.errorMessage != nil)
        #expect(!model.hasResult)
        #expect(!model.isProcessing)
    }

    @Test func grammarParsingDropsInventedCorrectionsAndRejectsMissingOutput() throws {
        let valid = """
        {"output":"I have an idea.","corrections":[{"original":"has","replacement":"have","explanation":"Subject agreement"},{"original":"missing","replacement":"have","explanation":"invented"}],"translation":"我有一个想法。"}
        """
        let result = try ProviderLanguageEngine.parseGrammar(valid, source: "I has an idea.")
        #expect(result.corrections.count == 1)
        #expect(result.outcome == .edited)
        #expect(result.translation == "我有一个想法。")
        #expect(throws: LanguageResponseError.self) {
            try ProviderLanguageEngine.parseGrammar("{\"corrections\":[]}", source: "test")
        }
        #expect(throws: LanguageResponseError.self) {
            try ProviderLanguageEngine.parseGrammar("not JSON", source: "test")
        }
    }

    @Test func unchangedOutputDoesNotPublishSpuriousLearningContent() throws {
        let response = """
        ```json
        {"output":"Clear.","corrections":[],"translation":"ignored","tip":"ignored"}
        ```
        """
        let result = try ProviderLanguageEngine.parseGrammar(response, source: "Clear.")
        #expect(result.outcome == .unchanged)
        #expect(result.tip.isEmpty)
        #expect(result.translation.isEmpty)
    }
}
