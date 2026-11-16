import AppKit
import Foundation
import Observation

enum WorkMode: String, CaseIterable, Identifiable, Sendable {
    case grammar
    case translation

    var id: String { rawValue }
    var title: String { self == .grammar ? "语法检查" : "翻译" }
}

enum GrammarOutcome: Equatable, Sendable {
    case edited
    case unchanged
    case unverified
}

struct Correction: Identifiable, Sendable {
    let id = UUID()
    let original: String
    let replacement: String
    let explanation: String
    let pattern: String

    init(original: String, replacement: String, explanation: String, pattern: String = "语法调整") {
        self.original = original
        self.replacement = replacement
        self.explanation = explanation
        self.pattern = pattern
    }
}

/// Editing state shared by live requests and explicitly isolated preview fixtures.
@MainActor
@Observable
final class DemoModel {
    // A selection belongs to one editing session, even if text is changed back.
    private(set) var inputRevision = UUID()
    var input = "Haha, enjoy~\n\nYou not the last one." {
        didSet { if input != oldValue { inputChanged() } }
    }
    var mode: WorkMode = .grammar {
        didSet { if mode != oldValue { modeChanged() } }
    }
    private(set) var output = ""
    private(set) var corrections: [Correction] = []
    private(set) var grammarOutcome: GrammarOutcome = .unverified
    private(set) var grammarTranslation = ""
    private(set) var tip = ""
    private(set) var isProcessing = false
    private(set) var copied = false
    private(set) var accepted = false
    private(set) var errorMessage: String?
    var targetLanguage = "简体中文" { didSet { if targetLanguage != oldValue { invalidateAndClear() } } }
    var sourceLanguage = TextLanguage.automatic { didSet { if sourceLanguage != oldValue { invalidateAndClear() } } }
    private(set) var detectedLanguage: TextLanguage? = .english
    var translationStyle = "standard" { didSet { if translationStyle != oldValue && mode == .translation { invalidateAndClear() } } }
    var writingStyle = "standard" { didSet { if writingStyle != oldValue && mode == .grammar { invalidateAndClear() } } }

    var resolvedSourceLanguage: TextLanguage? { TextLanguage(rawValue: sourceLanguage) ?? detectedLanguage }
    var sourceLanguageTitle: String {
        sourceLanguage == TextLanguage.automatic ? detectedLanguage.map { "检测 · \($0.rawValue)" } ?? TextLanguage.automatic : sourceLanguage
    }
    var resolvedTargetLanguage: TextLanguage {
        let target = TextLanguage(rawValue: targetLanguage) ?? .simplifiedChinese
        return target == resolvedSourceLanguage ? target.alternate : target
    }
    var currentStyle: TextStyle { TextStyle.resolve(mode == .translation ? translationStyle : writingStyle, for: mode) }
    var canSwapLanguages: Bool { mode == .translation && hasResult && resolvedSourceLanguage != nil }

    func swapLanguages() {
        guard canSwapLanguages, let source = resolvedSourceLanguage else { return }
        let result = output
        let target = resolvedTargetLanguage
        input = result
        sourceLanguage = target.rawValue
        targetLanguage = source.rawValue
    }

    var hasResult: Bool { !output.isEmpty && !isProcessing }
    var canSubmit: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing }

    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var copyReset: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private let processingDelay: Duration
    @ObservationIgnored private let streamDelay: Duration
    @ObservationIgnored private let engine: (any LanguageEngine)?
    @ObservationIgnored private let copyText: @MainActor (String) -> Void

    init(
        engine: (any LanguageEngine)? = nil,
        processingDelay: Duration = .milliseconds(650),
        streamDelay: Duration = .milliseconds(24),
        copyText: @escaping @MainActor (String) -> Void = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.engine = engine
        self.processingDelay = processingDelay
        self.streamDelay = streamDelay
        self.copyText = copyText
    }

    func inputChanged() {
        detectedLanguage = TextLanguage.detect(input)
        inputRevision = UUID()
        invalidateAndClear()
    }
    func modeChanged() {
        inputRevision = UUID()
        invalidateAndClear()
    }

    func reportInputError(_ message: String) {
        input = ""
        invalidateAndClear()
        errorMessage = message
    }

    func submit() {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            invalidateAndClear()
            errorMessage = "先输入一点文字，再试试看。"
            return
        }
        guard !isProcessing else { return }
        if engine != nil {
            beginRequest(LanguageRequest(source: source, mode: mode,
                targetLanguage: mode == .translation ? resolvedTargetLanguage.rawValue : targetLanguage,
                writingStyle: currentStyle.id, sourceLanguage: resolvedSourceLanguage?.rawValue))
        } else {
            begin(Self.fixture(source: source, mode: mode, targetLanguage: resolvedTargetLanguage))
        }
    }

    func cancel() {
        guard isProcessing else { return }
        invalidateAndClear()
    }

    func reset() {
        sourceLanguage = TextLanguage.automatic
        inputRevision = UUID()
        invalidateAndClear()
        input = ""
    }

    func applyResult() {
        guard hasResult else { return }
        let result = output
        invalidateAndClear()
        input = result
        accepted = true
    }

    func copyResult() {
        guard hasResult else { return }
        copyText(output)
        copied = true
        copyReset?.cancel()
        copyReset = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1_250)) }
            catch { return }
            self?.copied = false
        }
    }

    func loadSample(_ index: Int = 0) {
        sourceLanguage = TextLanguage.automatic
        inputRevision = UUID()
        invalidateAndClear()
        switch index {
        case 1: input = "I has a idea. It help people write better."
        case 2: input = "把复杂的想法，写得清楚一点。"
        default: input = "Haha, enjoy~\n\nYou not the last one."
        }
    }

    func showPreviewResult() {
        invalidateAndClear()
        let result = Self.fixture(source: input.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode, targetLanguage: resolvedTargetLanguage)
        output = result.text
        corrections = result.corrections
        grammarOutcome = result.outcome
        grammarTranslation = result.grammarTranslation
        tip = result.tip
    }

    func showPreviewError(_ message: String) {
        invalidateAndClear()
        errorMessage = message
    }

    func showPreviewPendingResult() {
        invalidateAndClear()
        output = Self.fixture(source: input.trimmingCharacters(in: .whitespacesAndNewlines),
                              mode: mode, targetLanguage: resolvedTargetLanguage).text
        isProcessing = true
    }

    private func invalidateAndClear() {
        generation = UUID()
        work?.cancel()
        work = nil
        copyReset?.cancel()
        copyReset = nil
        isProcessing = false
        output = ""
        corrections = []
        grammarOutcome = .unverified
        grammarTranslation = ""
        tip = ""
        copied = false
        accepted = false
        errorMessage = nil
    }

    private func beginRequest(_ request: LanguageRequest) {
        guard let engine else { return }
        invalidateAndClear()
        isProcessing = true
        let token = generation
        work = Task { [weak self] in
            do {
                let result = try await engine.perform(request) { [weak self] text in
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { throw CancellationError() }
                    self.output = text
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.output = result.text
                self.corrections = result.corrections
                self.grammarOutcome = result.outcome
                self.grammarTranslation = result.translation
                self.tip = result.tip
                self.isProcessing = false
                self.work = nil
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                // An unverified preview must never become an actionable result.
                self.output = ""
                self.isProcessing = false
                self.work = nil
                self.errorMessage = error is CancellationError ? nil : error.localizedDescription
            }
        }
    }

    private func begin(_ result: DemoResult) {
        invalidateAndClear()
        isProcessing = true
        let token = generation
        let delay = processingDelay
        let interval = streamDelay
        work = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                for character in result.text {
                    try Task.checkCancellation()
                    guard let self, self.generation == token else { return }
                    self.output.append(character)
                    try await Task.sleep(for: interval)
                }
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.corrections = result.corrections
                self.grammarOutcome = result.outcome
                self.grammarTranslation = result.grammarTranslation
                self.tip = result.tip
                self.isProcessing = false
                self.work = nil
            } catch {
                // Cancellation is expected when the text or mode changes.
            }
        }
    }

    private struct DemoResult {
        let text: String
        let corrections: [Correction]
        let grammarTranslation: String
        let tip: String
        let outcome: GrammarOutcome

        init(text: String, corrections: [Correction], grammarTranslation: String, tip: String, outcome: GrammarOutcome = .unverified) {
            self.text = text
            self.corrections = corrections
            self.grammarTranslation = grammarTranslation
            self.tip = tip
            self.outcome = outcome
        }
    }

    private static func fixture(source: String, mode: WorkMode, targetLanguage: TextLanguage) -> DemoResult {
        if mode == .translation {
            let text: String
            if targetLanguage == .english, source.contains("阅读是一种缓慢的理解过程") {
                let paragraph = "Reading is a gradual process of understanding. A good translation preserves meaning and connects sentences naturally. The source and translation need a clear hierarchy so you can keep reading."
                text = Array(repeating: paragraph, count: source.components(separatedBy: "阅读是一种缓慢的理解过程").count - 1).joined(separator: "\n\n")
            } else if targetLanguage == .english, source.contains("你不是最后一个") {
                text = "Haha, enjoy~\n\nYou are not the last one."
            } else if source.contains("last one") {
                text = "哈哈，玩得开心～\n\n你不是最后一个。"
            } else if source.contains("I has a idea") {
                text = "我有一个想法。它能帮助大家写得更好。"
            } else if source == "把复杂的想法，写得清楚一点。" {
                text = "Make complex ideas a little clearer."
            } else {
                text = "这是一段用于预览界面的模拟译文。\n\n原文：\(source)"
            }
            return DemoResult(text: text, corrections: [], grammarTranslation: "", tip: "")
        }
        if source.contains("You not the last one.") {
            return DemoResult(
                text: source.replacingOccurrences(of: "You not the last one.", with: "You are not the last one."),
                corrections: [Correction(original: "You not", replacement: "You are not", explanation: "在英语句子中，谓语动词是必不可少的。这里缺少了系动词 are，加上它句子才完整。", pattern: "缺少系动词")],
                grammarTranslation: "哈哈，玩得开心～\n\n你不是最后一个。",
                tip: "英语句子里通常需要一个动词。下次写句子时，先找找动词在哪里；如果没有动作，就用 am、is 或 are 来连接。",
                outcome: .edited
            )
        }
        if source == "I has a idea. It help people write better." {
            return DemoResult(text: "I have an idea. It helps people write better.", corrections: [
                Correction(original: "has", replacement: "have", explanation: "主语是 I，动词要用 have。", pattern: "主谓一致"),
                Correction(original: "a idea", replacement: "an idea", explanation: "idea 以元音音素开头，前面使用 an。", pattern: "不定冠词"),
                Correction(original: "help", replacement: "helps", explanation: "主语 It 是第三人称单数，动词使用 helps。", pattern: "第三人称单数")
            ], grammarTranslation: "我有一个想法。它能帮助大家写得更好。", tip: "让主语和动词保持一致，句子就会更自然。", outcome: .edited)
        }
        if source == "Your sentence is already clear." {
            return DemoResult(
                text: source,
                corrections: [],
                grammarTranslation: "",
                tip: "",
                outcome: .unchanged
            )
        }
        return DemoResult(text: source, corrections: [], grammarTranslation: "", tip: "当前为模拟检查，原文已保留。使用示例可以体验逐词高亮与修改解释。")
    }
}
