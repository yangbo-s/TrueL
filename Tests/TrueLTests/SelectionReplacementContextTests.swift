import Testing
@testable import TrueL

@MainActor
struct SelectionReplacementContextTests {
    private func model() -> DemoModel {
        DemoModel(processingDelay: .zero, streamDelay: .zero, copyText: { _ in })
    }

    private func waitForResult(_ model: DemoModel) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isProcessing, ContinuousClock.now < deadline { await Task.yield() }
        #expect(!model.isProcessing)
        #expect(model.hasResult)
    }

    @Test func editingBackToOriginalTextDoesNotRestoreCapturedSelection() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        let original = model.input
        context.bind(canReplace: true)
        #expect(context.canReplaceSelection)

        model.input = "Different text"
        #expect(!context.canReplaceSelection)
        model.input = original
        #expect(!context.canReplaceSelection)
    }

    @Test func switchingModesBackDoesNotRestoreCapturedSelection() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        model.mode = .translation
        #expect(!context.canReplaceSelection)
        model.mode = .grammar
        #expect(!context.canReplaceSelection)
    }

    @Test func resetAndLoadingIdenticalSampleStartNewEditingSessions() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        model.loadSample()
        #expect(!context.canReplaceSelection)

        model.reset()
        context.bind(canReplace: true)
        model.reset()
        #expect(!context.canReplaceSelection)
    }

    @Test func unchangedViewBindingsKeepTheSelection() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        let input = model.input
        let mode = model.mode
        model.input = input
        model.mode = mode
        #expect(context.canReplaceSelection)
    }

    @Test func newCaptureBindsCurrentRevisionAndClearsPreviousFailure() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        #expect(!context.canReplaceSelection)
        context.bind(canReplace: true)
        context.fail("The original selection changed.")
        #expect(!context.canReplaceSelection)
        #expect(context.replacementError != nil)

        model.input = "A new selection"
        context.bind(canReplace: true)
        #expect(context.canReplaceSelection)
        #expect(context.replacementError == nil)
        context.bind(canReplace: false)
        #expect(!context.canReplaceSelection)
    }

    @Test func clearingContextRemovesCaptureAndErrorWithoutChangingEditor() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        let input = model.input
        context.bind(canReplace: true)
        context.fail("Failed")
        context.clear()
        #expect(!context.canReplaceSelection)
        #expect(context.replacementError == nil)
        #expect(model.input == input)
    }

    @Test func editingBackToOriginalTextDoesNotRestoreReplacementFailure() {
        let model = model()
        let context = SelectionReplacementContext(model: model)
        let original = model.input
        context.bind(canReplace: true)
        context.fail("The original selection changed.")
        #expect(context.replacementError != nil)

        model.input = "Different text"
        #expect(context.replacementError == nil)
        model.input = original
        #expect(context.replacementError == nil)
        #expect(!context.canReplaceSelection)

        context.bind(canReplace: true)
        #expect(context.replacementError == nil)
        #expect(context.canReplaceSelection)
    }

    @Test func translatingCopyingAndRestylingKeepOriginalSelectionBound() async {
        let model = model()
        model.mode = .translation
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        model.submit()
        #expect(context.canReplaceSelection)
        await waitForResult(model)
        model.copyResult()
        #expect(model.copied)
        #expect(context.canReplaceSelection)

        model.translationStyle = "concise"
        model.submit()
        #expect(context.canReplaceSelection)
        await waitForResult(model)
        #expect(context.canReplaceSelection)
    }

    @Test func changingTargetLanguageKeepsSelectionButClearsItsOldResult() async {
        let model = model()
        model.mode = .translation
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        model.submit()
        await waitForResult(model)
        model.targetLanguage = "日本語"
        #expect(!model.hasResult)
        #expect(context.canReplaceSelection)
    }
}
