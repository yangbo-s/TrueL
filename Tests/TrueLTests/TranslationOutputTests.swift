import Foundation
import Testing
@testable import TrueL

@MainActor
struct TranslationOutputTests {
    @Test func reportedPackageTextLosesOnlyItsTransportWrapper() async throws {
        let translation = """
        B. 器件封装
        说明（请删除此框）：封装焊盘由微带线段和阶梯结构构成，尺寸与数据手册中的焊盘尺寸一致；原理图中已接入 .s3p 文件（它与布局无关）。说明你如何处理两个发射极焊盘（手册中将较大的焊盘布线连接，并将较小的焊盘接到它上面）。手册现已列出 SOT343 的焊盘几何尺寸（间距 1.3 mm；基极、集电极和较小的发射极焊盘均为 0.5 × 0.58 mm；较大的发射极焊盘宽 0.8 mm）——请对照检查你的封装线条，并说明检查结果。
        [待办：封装原理图和布局，以及一句关于发射极焊盘处理方式的说明。]
        """
        let client = TranslationFixtureClient(response: try envelope(translation))
        let engine = await configuredEngine(client)
        let result = try await engine.perform(LanguageRequest(source: "B. Device package\nDescription (delete this box).", mode: .translation))
        #expect(result.text == translation)
    }

    @Test(arguments: ["", "json", "unlabeled"])
    func wrappedTextDecodesEscapesAndUnicode(_ fence: String) async throws {
        let expected = "## 标题\n\n**正文**：\"你好\" 🌍 e\u{0301}\n路径 C:\\folder\t0.5 × 0.58 mm"
        let object = try envelope(expected)
        let response = fence.isEmpty ? object : "```\(fence == "unlabeled" ? "" : fence)\n\(object)\n```"
        let engine = await configuredEngine(TranslationFixtureClient(response: response))
        #expect(try await engine.perform(LanguageRequest(source: "A paragraph with formatting.", mode: .translation)).text == expected)
    }

    @Test func surrogatePairsAndPrettyPrintedEnvelopeUseJSONDecoding() async throws {
        let response = #"{ "source" : "\u4f60\u597d \ud83d\ude00\nnext" }"#
        let engine = await configuredEngine(TranslationFixtureClient(response: response))
        #expect(try await engine.perform(LanguageRequest(source: "Hello 😀\nnext", mode: .translation)).text == "你好 😀\nnext")
    }

    @Test(arguments: [
        "普通译文\n\n第二段。", "`source` 是字段名。", "## 标题\n\n**强调**和 [链接](https://example.com)。",
        #"{"source":"原文","translation":"译文"}"#, #"{"translation":"译文"}"#,
        #"{"outer":{"source":"嵌套正文"}}"#, #"{"source":42}"#,
        #"{"source":"第一段","source":"第二段"}"#,
        "```swift\nlet source = \"正文\"\n```"
    ])
    func ordinaryTextAndOtherStructuresAreNotRewritten(_ response: String) async throws {
        let engine = await configuredEngine(TranslationFixtureClient(response: response))
        #expect(try await engine.perform(LanguageRequest(source: "Original paragraph.", mode: .translation)).text == response)
    }

    @Test(arguments: [
        #"{"source":"Hello"}"#, #"[{"source":"Hello"}]"#,
        "```json\n{\"source\":\"Hello\"}\n```", "```\n{\"source\":\"Hello\"}\n```"
    ])
    func structuredSourceKeepsItsOwnStructureInPreviewAndFinalResult(_ source: String) async throws {
        let response = source.replacingOccurrences(of: "Hello", with: "你好")
        let client = TranslationFixtureClient(response: response, updates: [String(response.prefix(1)), response])
        let engine = await configuredEngine(client)
        var updates: [String] = []
        let result = try await engine.perform(LanguageRequest(source: source, mode: .translation), onUpdate: { updates.append($0) })
        #expect(result.text == response)
        #expect(updates == client.updates)
        #expect(client.system.contains("Keep every JSON key unchanged, including any key named source"))
    }

    @Test(arguments: [false, true])
    func noFragmentOfAnAccidentalEnvelopeEntersThePreview(_ fenced: Bool) async throws {
        let expected = "你好 🌍\n第二行 \"引号\"。"
        let object = try envelope(expected)
        let response = fenced ? "```json\n\(object)\n```" : object
        let prefixes = response.indices.map { String(response[...$0]) }
        let engine = await configuredEngine(TranslationFixtureClient(response: response, updates: prefixes))
        var updates: [String] = []
        let result = try await engine.perform(LanguageRequest(source: "Hello world.\nSecond line.", mode: .translation), onUpdate: { updates.append($0) })
        #expect(updates.allSatisfy { $0 == expected })
        #expect(result.text == expected)
    }

    @Test func ordinaryTranslationStillStreamsImmediately() async throws {
        let client = TranslationFixtureClient(response: "你好。\n第二段。", updates: ["你好。", "你好。\n第二段。"])
        let engine = await configuredEngine(client)
        var updates: [String] = []
        let result = try await engine.perform(LanguageRequest(source: "Hello.\nSecond paragraph.", mode: .translation), onUpdate: { updates.append($0) })
        #expect(updates == client.updates)
        #expect(result.text == client.response)
    }

    @Test(arguments: [#"{"source":""}"#, #"{"source":" \n\t "}"#,
                      #"{"source":"unfinished"#, #"{"source":"bad\q"}"#,
                      "```json\n{\"source\":\"正文\"}"])
    func emptyOrMalformedEnvelopesCannotBecomeSuccessfulTranslations(_ response: String) async throws {
        let engine = await configuredEngine(TranslationFixtureClient(response: response))
        await #expect(throws: LanguageResponseError.self) {
            try await engine.perform(LanguageRequest(source: "Hello", mode: .translation))
        }
    }

    @Test func onlyOneEnvelopeIsRemoved() async throws {
        let expected = #"{"source":"这是正文中的示例"}"#
        let engine = await configuredEngine(TranslationFixtureClient(response: try envelope(expected)))
        #expect(try await engine.perform(LanguageRequest(source: "An example object.", mode: .translation)).text == expected)
    }

    private func configuredEngine(_ client: TranslationFixtureClient) async -> ProviderLanguageEngine {
        let service = ServiceConfiguration(persist: false, client: client)
        service.draftKey = "test-key"
        await service.saveKey()
        #expect(service.selectModel(ModelSelection(provider: .gemini, modelID: "fixture-model"), for: .translation))
        return ProviderLanguageEngine(service: service, client: client)
    }

    private func envelope(_ text: String) throws -> String {
        String(decoding: try JSONEncoder().encode(["source": text]), as: UTF8.self)
    }
}

@MainActor
private final class TranslationFixtureClient: AIClientProtocol {
    let response: String
    let updates: [String]
    private(set) var system = ""

    init(response: String, updates: [String] = []) {
        self.response = response
        self.updates = updates
    }

    func listModels(provider: AIProvider, apiKey: String) async throws -> [AIModelInfo] {
        [AIModelInfo(id: "fixture-model", displayName: "Fixture")]
    }

    func generate(configuration: AIConfiguration, system: String, user: String) async throws -> String { response }

    func generateTranslation(configuration: AIConfiguration, system: String, user: String,
                             onUpdate: @escaping AITextUpdate) async throws -> String {
        self.system = system
        for update in updates { try onUpdate(update) }
        return response
    }
}
