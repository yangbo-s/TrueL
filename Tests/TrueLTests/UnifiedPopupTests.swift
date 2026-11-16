import AppKit
import Testing
@testable import TrueL

@MainActor
@Suite(.serialized)
struct UnifiedPopupTests {
    private func makeDelegate() -> AppDelegate {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        return subject
    }

    private func dispose(_ subject: AppDelegate) {
        subject.model.cancel()
        // Closing settings normally restores the popup; teardown must not do that.
        subject.settings?.delegate = nil
        subject.settings?.close()
        subject.settings?.contentView = nil
        subject.panel?.close()
        subject.panel?.contentView = nil
    }

    private func visibleContentWindows(_ subject: AppDelegate) -> Int {
        [subject.panel, subject.settings].compactMap { $0 }.filter(\.isVisible).count
    }

    @Test func menusAndActionsDoNotExposeAnIndependentQuickTranslation() throws {
        let subject = makeDelegate()
        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu; dispose(subject) }
        subject.setupMenu()
        let windowMenu = try #require(NSApp.mainMenu?.items.first(where: { $0.title == "窗口" })?.submenu)
        #expect(!windowMenu.items.contains { $0.title == "快速翻译" })
        #expect(windowMenu.items.contains { $0.title == "显示主浮窗" })
        #expect(windowMenu.items.contains { $0.title == "翻译剪贴板" })
        #expect(ShortcutAction.allCases.map(\.rawValue) == [
            "clipboardTranslation", "translation", "grammar", "selectionTranslation", "selectionGrammar"
        ])
    }

    @Test func translationGrammarAndNewInputReuseTheOriginalPanel() throws {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.showPanel()
        let original = try #require(subject.panel)
        let number = original.windowNumber

        subject.handleShortcut(.translation)
        #expect(subject.model.mode == .translation)
        #expect(subject.panel === original)
        #expect(subject.panel.windowNumber == number)
        #expect(visibleContentWindows(subject) == 1)

        subject.handleShortcut(.grammar)
        #expect(subject.model.mode == .grammar)
        #expect(subject.panel === original)
        subject.handleShortcut(.translation)
        #expect(subject.model.mode == .translation)
        #expect(subject.panel === original)

        subject.beginInput("A newly captured sentence.", mode: .translation)
        #expect(subject.panel === original)
        #expect(subject.panel.windowNumber == number)
        #expect(subject.model.input == "A newly captured sentence.")
        #expect(subject.model.isProcessing)
        #expect(visibleContentWindows(subject) == 1)
    }

    @Test func settingsAndPopupAreExclusiveAndClosingSettingsRestoresThePanel() throws {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.showPanel()
        let original = try #require(subject.panel)
        subject.model.input = "Keep this draft."

        subject.showSettings(page: .service)
        let settings = try #require(subject.settings)
        #expect(!original.isVisible)
        #expect(settings.isVisible)
        #expect(visibleContentWindows(subject) == 1)

        settings.close()
        #expect(!settings.isVisible)
        #expect(original.isVisible)
        #expect(subject.panel === original)
        #expect(subject.model.input == "Keep this draft.")
        #expect(visibleContentWindows(subject) == 1)

        subject.showSettings(page: .shortcuts)
        subject.shortcuts.beginRecording(action: .selectionTranslation)
        #expect(subject.shortcuts.isRecording)
        subject.handleShortcut(.translation)
        #expect(!subject.shortcuts.isRecording)
        #expect(!settings.isVisible)
        #expect(original.isVisible)
        #expect(subject.panel === original)
        #expect(visibleContentWindows(subject) == 1)
    }

    @Test func reopeningTranslationPreservesTheCurrentTranslationAndDraft() throws {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.handleShortcut(.translation)
        let original = try #require(subject.panel)
        subject.model.loadSample(0)
        subject.model.showPreviewResult()
        let input = subject.model.input
        let output = subject.model.output

        subject.handleShortcut(.translation)
        #expect(subject.panel === original)
        #expect(subject.model.input == input)
        #expect(subject.model.output == output)
        #expect(subject.model.hasResult)
        #expect(!subject.model.isProcessing)
    }

    @Test func repeatedCaptureRestartsEvenWhenSourceTextIsIdentical() async throws {
        let subject = makeDelegate()
        defer { dispose(subject) }
        let text = "Haha, enjoy~\n\nYou not the last one."
        subject.beginInput(text, mode: .translation, canReplaceSelection: true)
        let firstRevision = subject.model.inputRevision
        for _ in 0..<150 {
            if !subject.model.output.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(subject.model.isProcessing)
        #expect(!subject.model.output.isEmpty)

        subject.beginInput(text, mode: .translation)
        #expect(subject.model.inputRevision != firstRevision)
        #expect(subject.model.output.isEmpty)
        #expect(subject.model.isProcessing)
        #expect(!subject.selectionContext.canReplaceSelection)
        // The cancelled stream would append more characters during this interval.
        try await Task.sleep(for: .milliseconds(100))
        #expect(subject.model.output.isEmpty)
    }

    @Test func emptyNewSourceClearsTheOldResultWithoutStartingWork() {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.showPanel()
        subject.model.showPreviewResult()
        subject.selectionContext.bind(canReplace: true)
        #expect(subject.model.hasResult)

        subject.beginInput(" \n\t", mode: .translation)
        #expect(subject.model.input.isEmpty)
        #expect(!subject.model.isProcessing)
        #expect(!subject.model.hasResult)
        #expect(subject.model.errorMessage != nil)
        #expect(!subject.selectionContext.canReplaceSelection)
        #expect(visibleContentWindows(subject) == 1)
    }

    @Test func closingPanelCancelsWorkAndReopeningCannotRestoreTheOldSelection() async throws {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.beginInput("A captured sentence.", mode: .translation, canReplaceSelection: true)
        let original = try #require(subject.panel)
        #expect(subject.selectionContext.canReplaceSelection)

        subject.closePanel()
        #expect(!original.isVisible)
        #expect(!subject.model.isProcessing)
        #expect(!subject.selectionContext.canReplaceSelection)
        try await Task.sleep(for: .milliseconds(750))
        #expect(subject.model.output.isEmpty)

        subject.showPanel()
        #expect(subject.panel === original)
        #expect(subject.model.input == "A captured sentence.")
        #expect(!subject.selectionContext.canReplaceSelection)
        #expect(!subject.model.isProcessing)
    }

    @Test func openingNormalModeDetachesSelectionEvenWhenModeIsUnchanged() {
        let subject = makeDelegate()
        defer { dispose(subject) }
        subject.beginInput("A captured sentence.", mode: .translation, canReplaceSelection: true)
        #expect(subject.selectionContext.canReplaceSelection)

        subject.handleShortcut(.translation)
        #expect(subject.model.mode == .translation)
        #expect(subject.model.input == "A captured sentence.")
        #expect(!subject.selectionContext.canReplaceSelection)

        subject.selectionContext.bind(canReplace: true)
        subject.handleShortcut(.grammar)
        #expect(subject.model.mode == .grammar)
        #expect(!subject.model.isProcessing)
        #expect(!subject.selectionContext.canReplaceSelection)
    }
}
