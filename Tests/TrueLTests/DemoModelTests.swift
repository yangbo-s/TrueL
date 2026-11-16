import Testing
@testable import TrueL

@MainActor
struct DemoModelTests {
    private func model() -> DemoModel {
        DemoModel(processingDelay: .milliseconds(10), streamDelay: .milliseconds(1))
    }

    private func waitForResult(_ model: DemoModel) async throws {
        for _ in 0..<200 {
            if !model.isProcessing { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Demo operation did not complete within the test budget")
    }

    @Test func grammarProducesCorrectionAndAppliesToEditor() async throws {
        let subject = model()
        subject.submit()
        #expect(subject.isProcessing)
        try await waitForResult(subject)
        #expect(subject.hasResult)
        #expect(subject.grammarOutcome == .edited)
        #expect(subject.output == "Haha, enjoy~\n\nYou are not the last one.")
        #expect(subject.corrections.count == 1)
        #expect(subject.corrections.first?.original == "You not")
        #expect(subject.corrections.first?.replacement == "You are not")
        #expect(subject.corrections.first?.pattern == "缺少系动词")
        #expect(subject.corrections.first?.explanation == "在英语句子中，谓语动词是必不可少的。这里缺少了系动词 are，加上它句子才完整。")
        #expect(subject.grammarTranslation == "哈哈，玩得开心～\n\n你不是最后一个。")
        #expect(subject.tip == "英语句子里通常需要一个动词。下次写句子时，先找找动词在哪里；如果没有动作，就用 am、is 或 are 来连接。")
        subject.applyResult()
        #expect(subject.input == "Haha, enjoy~\n\nYou are not the last one.")
        #expect(subject.accepted)
        #expect(!subject.hasResult)
        #expect(subject.grammarOutcome == .unverified)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
    }

    @Test func emptyInputIsRejectedWithoutStartingWork() {
        let subject = model()
        subject.input = " \n\t "
        subject.submit()
        #expect(!subject.isProcessing)
        #expect(!subject.hasResult)
        #expect(subject.errorMessage != nil)
    }

    @Test func editedInputCannotReceiveOldCompletion() async throws {
        let subject = model()
        subject.submit()
        try await Task.sleep(for: .milliseconds(20))
        subject.input = "A new sentence."
        try await Task.sleep(for: .milliseconds(100))
        #expect(subject.output.isEmpty)
        #expect(subject.corrections.isEmpty)
        #expect(subject.grammarOutcome == .unverified)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        #expect(!subject.isProcessing)
    }

    @Test func cancellationClearsPartialStreamingOutput() async throws {
        let subject = model()
        subject.submit()
        try await Task.sleep(for: .milliseconds(20))
        subject.cancel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!subject.isProcessing)
        #expect(subject.output.isEmpty)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        #expect(!subject.hasResult)
        #expect(subject.grammarOutcome == .unverified)
    }

    @Test func modeSwitchCancelsGrammarAndStreamsTranslation() async throws {
        let subject = model()
        subject.submit()
        subject.mode = .translation
        #expect(subject.grammarOutcome == .unverified)
        #expect(subject.grammarTranslation.isEmpty)
        subject.submit()
        try await waitForResult(subject)
        #expect(subject.output == "哈哈，玩得开心～\n\n你不是最后一个。")
        #expect(subject.corrections.isEmpty)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        #expect(subject.hasResult)
    }

    @Test func changingStyleClearsResultWithoutChangingSourceRevision() {
        let subject = model()
        subject.showPreviewResult()
        let revision = subject.inputRevision
        let source = subject.input
        subject.writingStyle = "concise"
        #expect(!subject.hasResult)
        #expect(subject.input == source)
        #expect(subject.inputRevision == revision)
        #expect(subject.currentStyle.id == "concise")
    }

    @Test func grammarAuxiliaryContentAppearsOnlyAfterStreamingCompletes() async throws {
        let subject = DemoModel(processingDelay: .zero, streamDelay: .milliseconds(2))
        subject.showPreviewResult()
        #expect(!subject.grammarTranslation.isEmpty)
        subject.submit()
        for _ in 0..<100 {
            if !subject.output.isEmpty { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(subject.isProcessing)
        #expect(!subject.output.isEmpty)
        #expect(subject.corrections.isEmpty)
        #expect(subject.grammarOutcome == .unverified)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        try await waitForResult(subject)
        #expect(!subject.grammarTranslation.isEmpty)
        #expect(!subject.tip.isEmpty)
        #expect(subject.corrections.count == 1)
        #expect(subject.grammarOutcome == .edited)
    }

    @Test func knownCorrectFixtureIsUnchangedWithoutStaleAuxiliaryContent() async throws {
        let subject = model()
        subject.showPreviewResult()
        subject.input = "Your sentence is already clear."
        #expect(subject.grammarTranslation.isEmpty)
        subject.submit()
        try await waitForResult(subject)
        #expect(subject.hasResult)
        #expect(subject.output == subject.input)
        #expect(subject.corrections.isEmpty)
        #expect(subject.grammarOutcome == .unchanged)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        subject.reset()
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.tip.isEmpty)
        #expect(subject.grammarOutcome == .unverified)
    }

    @Test func restyledResultSupportsCopyAndReplacement() async throws {
        var copiedText = ""
        let subject = DemoModel(processingDelay: .zero, streamDelay: .milliseconds(1), copyText: { copiedText = $0 })
        subject.showPreviewResult()
        subject.writingStyle = "concise"
        subject.submit()
        try await waitForResult(subject)
        #expect(subject.grammarOutcome == .edited)
        subject.copyResult()
        #expect(copiedText == subject.output)
        #expect(subject.copied)
        let result = subject.output
        subject.applyResult()
        #expect(subject.input == result)
        #expect(subject.accepted)
        #expect(!subject.hasResult)
    }

    @Test func otherTaskStyleDoesNotCancelResultAndTranslationHasNoGrammarContent() async throws {
        let subject = model()
        subject.showPreviewResult()
        let result = subject.output
        subject.translationStyle = "literal"
        #expect(subject.output == result)
        subject.mode = .translation
        subject.submit()
        try await waitForResult(subject)
        subject.writingStyle = "social"
        #expect(subject.hasResult)
        #expect(subject.grammarTranslation.isEmpty)
        #expect(subject.corrections.isEmpty && subject.tip.isEmpty)
    }

    @Test func duplicateSubmitDoesNotRestartWork() async throws {
        let subject = model()
        subject.submit()
        subject.submit()
        try await waitForResult(subject)
        #expect(subject.output == "Haha, enjoy~\n\nYou are not the last one.")
    }

    @Test func arbitraryInputIsPreservedAndLabeledAsSimulation() async throws {
        let subject = model()
        subject.input = "Already correct."
        subject.submit()
        try await waitForResult(subject)
        #expect(subject.output == subject.input)
        #expect(subject.corrections.isEmpty)
        #expect(subject.tip.contains("模拟"))
        #expect(subject.grammarOutcome == .unverified)
    }
}
