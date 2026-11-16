import AppKit
import Testing
@testable import TrueL

@MainActor
struct LanguageWorkspaceTests {
    @Test func detectionAndSameLanguageFallbackKeepLanguageDirectionUseful() {
        let model = DemoModel()
        model.mode = .translation
        model.input = "把复杂的想法，写得清楚一点。"
        #expect(model.resolvedSourceLanguage == .simplifiedChinese)
        #expect(model.resolvedTargetLanguage == .english)
        model.targetLanguage = "繁體中文"
        #expect(model.resolvedTargetLanguage == .traditionalChinese)
        model.input = "This is a complete sentence written in English."
        model.targetLanguage = "English"
        #expect(model.resolvedSourceLanguage == .english)
        #expect(model.resolvedTargetLanguage == .simplifiedChinese)
        model.input = "42 🙂"
        #expect(model.resolvedSourceLanguage == nil)
        #expect(model.sourceLanguageTitle == TextLanguage.automatic)
        #expect(model.resolvedTargetLanguage == .english)
        model.sourceLanguage = "日本語"
        #expect(model.resolvedSourceLanguage == .japanese)
        model.input = "Another sentence written in English."
        #expect(model.resolvedSourceLanguage == .japanese)
        model.sourceLanguage = TextLanguage.automatic
        #expect(model.resolvedSourceLanguage == .english)
    }

    @Test(arguments: ["你好", "谢谢", "中文", "繁體中文"])
    func shortChinesePhrasesAvoidSameLanguageTranslation(text: String) {
        let model = DemoModel()
        model.mode = .translation
        model.input = text
        #expect(model.resolvedSourceLanguage == (text == "繁體中文" ? .traditionalChinese : .simplifiedChinese))
        model.targetLanguage = model.resolvedSourceLanguage!.rawValue
        #expect(model.resolvedTargetLanguage == .english)
    }

    @Test func swapUsesCompleteResultAndInvalidatesSourceBinding() {
        let model = DemoModel()
        model.mode = .translation
        model.showPreviewResult()
        let originalSourceLanguage = model.resolvedSourceLanguage
        let previousTarget = model.resolvedTargetLanguage
        let result = model.output
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        #expect(model.canSwapLanguages)
        model.swapLanguages()
        #expect(model.input == result)
        #expect(model.resolvedSourceLanguage == previousTarget)
        #expect(model.resolvedTargetLanguage == originalSourceLanguage)
        #expect(!model.hasResult && !context.canReplaceSelection)
        let source = model.input
        model.swapLanguages()
        #expect(model.input == source)
        model.mode = .grammar
        model.showPreviewResult()
        #expect(!model.canSwapLanguages)
    }

    @Test func bothStylePreferencesPersistIndependentlyAndPreviewIsIsolated() {
        let name = "TrueL.tests.styles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.translationStyle = "literal"
        prefs.writingScene = "social"
        let preview = Preferences(persist: false, defaults: defaults)
        preview.translationStyle = "concise"
        preview.writingScene = "professional"
        let restored = Preferences(defaults: defaults)
        #expect(restored.translationStyle == "literal")
        #expect(restored.writingScene == "social")
        #expect(TextStyle.resolve("obsolete", for: .translation).id == "standard")
    }

    @Test(arguments: ["简体中文", "English", "自然", "gpt-6-luna", "A very long model name"])
    func menuTextAndArrowShareEqualOuterInsets(title: String) {
        let bounds = NSRect(x: 0, y: 0, width: MenuMetrics.width(for: title), height: 28)
        let text = MenuMetrics.textRect(in: bounds, height: 14)
        let arrow = MenuMetrics.arrowRect(in: bounds)
        #expect(text.minX == bounds.maxX - arrow.maxX)
        #expect(arrow.minX - text.maxX == MenuMetrics.gap)
        #expect(text.midY == arrow.midY)
        let narrow = NSRect(x: 0, y: 0, width: 144, height: 28)
        #expect(MenuMetrics.textRect(in: narrow, height: 14).maxX + MenuMetrics.gap == MenuMetrics.arrowRect(in: narrow).minX)
    }
}

@MainActor
extension UnifiedPopupTests {
    @Test(arguments: ["close", "deactivate", "settings", "reopen"], [false, true])
    func quickSessionEndsAtEveryNormalEntry(exit: String, pinned: Bool) async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.preferences.alwaysOnTop = pinned
        subject.beginInput("Haha, enjoy~\n\nYou not the last one.", mode: .translation,
                           canReplaceSelection: true, presentation: .quick)
        subject.model.showPreviewResult()
        let panel = try #require(subject.panel)
        defer {
            subject.model.cancel()
            subject.settings?.delegate = nil; subject.settings?.close()
            panel.delegate = nil; panel.close(); panel.contentView = nil
        }
        let source = subject.model.input
        let result = subject.model.output
        switch exit {
        case "close": panel.performClose(nil)
        case "deactivate": subject.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        case "settings": subject.showSettings(page: .general)
        default: _ = subject.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        }
        #expect(subject.session.presentation == .workspace)
        #expect(!subject.selectionContext.canReplaceSelection)
        if exit == "close" || exit == "deactivate" { #expect(!panel.isVisible) }
        subject.showPanel()
        try await Task.sleep(for: .milliseconds(80))
        #expect(subject.panel === panel && panel.isVisible)
        #expect(panel.frame.width >= PopupPresentation.workspace.minimumWidth)
        #expect(subject.model.input == source && subject.model.output == result)
        #expect(subject.session.returnAction(model: subject.model) == .submit)
    }

    @Test func dismissingQuickLoadingCancelsRequestAndNormalReopenKeepsSource() async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.beginInput("A selected sentence.", mode: .translation, presentation: .quick)
        defer { subject.model.cancel(); subject.panel.delegate = nil; subject.panel.close() }
        subject.panel.resignKey()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!subject.model.isProcessing)
        #expect(subject.session.presentation == .workspace)
        #expect(!subject.panel.isVisible)
        subject.showPanel()
        #expect(subject.model.input == "A selected sentence.")
    }

    @Test func styleAndLanguageEditsDoNotAutoSubmitUntouchedDraftsAndSwapRequiresWorkspace() {
        let subject = AppDelegate(preview: true)
        subject.model.mode = .translation
        subject.changeStyle("concise")
        subject.changeTranslationLanguage("日本語")
        subject.changeSourceLanguage("English")
        #expect(!subject.model.isProcessing)
        #expect(subject.model.currentStyle.id == "concise")
        subject.model.showPreviewResult()
        let result = subject.model.output
        subject.changeTranslationLanguage("日本語")
        #expect(subject.model.output == result && !subject.model.isProcessing)
        subject.setPresentation(.quick)
        let input = subject.model.input
        subject.swapLanguages()
        #expect(subject.model.input == input && subject.model.hasResult)
        subject.setPresentation(.workspace)
        subject.swapLanguages()
        defer { subject.model.cancel() }
        #expect(subject.model.isProcessing)
        #expect(subject.preferences.language == "English")
        #expect(subject.model.sourceLanguage == "日本語")
    }
}
