import AppKit
import Testing
@testable import TrueL

@MainActor
struct PopupReturnTests {
    @Test func focusedEmptyInstructionNeverFallsThroughToReplacement() {
        let model = DemoModel()
        model.showPreviewResult()
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        let session = PopupSession()
        session.presentation = .quick
        #expect(session.returnAction(model: model) == .replace)
        #expect(session.canPerform(.replace, model: model, selection: context))
        session.focus = .followUp
        #expect(session.returnAction(model: model) == .refine)
        #expect(!session.canPerform(.refine, model: model, selection: context))
        model.followUp = "Make it shorter."
        #expect(session.canPerform(.refine, model: model, selection: context))
        session.focus = .result
        context.clear()
        #expect(!session.canPerform(session.returnAction(model: model), model: model, selection: context))
        session.presentation = .workspace
        #expect(session.returnAction(model: model) == .submit)
    }

    @Test func processingHasNoReturnAction() {
        let model = DemoModel()
        let session = PopupSession()
        session.presentation = .quick
        model.submit()
        defer { model.cancel() }
        #expect(session.returnAction(model: model) == .none)
        session.focus = .followUp
        #expect(session.returnAction(model: model) == .none)
    }
}

@MainActor
extension UnifiedPopupTests {
    @Test func quickAndWorkspaceShareWindowAndRememberIndependentSizes() async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close(); panel.contentView = nil }
        let originalNumber = panel.windowNumber
        subject.userPanelHeight = 560
        panel.setContentSize(NSSize(width: 900, height: 560))
        subject.beginInput("Haha, enjoy~\n\nYou not the last one.", mode: .grammar,
                           canReplaceSelection: true, presentation: .quick)
        subject.model.showPreviewResult()
        try await Task.sleep(for: .milliseconds(200))
        #expect(subject.panel.windowNumber == originalNumber)
        #expect(panel.frame.width == PopupLayout.compactWidth)
        #expect(!descendants(try #require(panel.contentView)).contains { $0 is PanelTextView })
        #expect(subject.session.returnAction(model: subject.model) == .replace)
        subject.session.focus = .followUp
        subject.model.followUp = "更简洁"
        subject.performReturnAction()
        #expect(subject.model.isProcessing)
        #expect(subject.session.focus == .result)
        #expect(subject.selectionContext.canReplaceSelection)
        subject.model.cancel()
        subject.handleShortcut(.grammar)
        try await Task.sleep(for: .milliseconds(200))
        #expect(subject.panel.windowNumber == originalNumber)
        #expect(panel.frame.size == NSSize(width: 900, height: 560))
        #expect(descendants(try #require(panel.contentView)).contains { $0 is PanelTextView })
        #expect(!subject.selectionContext.canReplaceSelection)
    }

    @Test func windowReturnHandlesReadOnlyResultsButNotEditableOrModifiedReturn() throws {
        _ = NSApplication.shared
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 464, height: 320),
                                  styleMask: [.titled], backing: .buffered, defer: false)
        defer { panel.orderOut(nil); panel.contentView = nil }
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        text.isEditable = false
        text.string = "Read-only result"
        panel.contentView = text
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(text)
        var replacements = 0
        panel.onReturn = { replacements += 1 }
        func send(_ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: repeatKey, keyCode: 36))
            panel.sendEvent(event)
        }
        try send()
        #expect(replacements == 1)
        try send(repeatKey: true)
        try send(.shift)
        #expect(replacements == 1)
        text.isEditable = true
        panel.makeFirstResponder(text)
        #expect(panel.firstResponder === text)
        try send()
        #expect(replacements == 1)
    }

    @Test func nativeFollowUpReturnSubmitsInstructionAndEmptyReturnDoesNotReplace() async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.beginInput("Haha, enjoy~\n\nYou not the last one.", mode: .grammar,
                           canReplaceSelection: true, presentation: .quick)
        subject.model.showPreviewResult()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close(); panel.contentView = nil }
        try await Task.sleep(for: .milliseconds(120))
        let root = try #require(panel.contentView)
        let field = try #require(descendants(root)
            .compactMap { $0 as? NSTextField }.first { $0.isEditable })
        #expect(panel.makeFirstResponder(field))
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.session.focus == .followUp)
        let editor = try #require(panel.firstResponder as? NSTextView)
        #expect(editor.isEditable && editor.isFieldEditor)
        func sendReturn() throws {
            panel.sendEvent(try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)))
        }
        try sendReturn()
        try await Task.sleep(for: .milliseconds(60))
        #expect(!subject.model.isProcessing)
        #expect(subject.selectionContext.replacementError == nil)
        #expect(subject.selectionContext.canReplaceSelection)
        subject.model.followUp = "Use a warmer tone."
        try await Task.sleep(for: .milliseconds(60))
        try sendReturn()
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.model.isProcessing)
        #expect(subject.model.followUp.isEmpty)
        #expect(subject.session.focus == .result)
        #expect(subject.selectionContext.replacementError == nil)
        #expect(subject.selectionContext.canReplaceSelection)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
}

struct ShortcutSequenceGateTests {
    private let a = ShortcutStroke(keyCode: 0, modifiers: .control)
    private let x = ShortcutStroke(keyCode: 7, modifiers: .control)

    @Test func doubleAIsConsumedWithNoNativeCursorMovementAndOneTrigger() {
        var gate = ShortcutSequenceGate<Int>(bindings: ShortcutBinding.defaults)
        let first = gate.process(1, stroke: a, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        #expect(first.consumed && first.action == nil && first.replay.isEmpty)
        #expect(gate.process(2, stroke: a, down: false, isRepeat: false, timestamp: 1.1, sourcePID: 42).consumed)
        let complete = gate.process(3, stroke: a, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 42)
        #expect(complete.consumed && complete.action == .selectionGrammar && complete.replay.isEmpty)
        #expect(gate.process(4, stroke: a, down: false, isRepeat: false, timestamp: 1.3, sourcePID: 99).consumed)
        #expect(gate.flush().isEmpty)
    }

    @Test func mismatchAndTimeoutReturnOriginalEventsInOrderToOriginalProcess() {
        var gate = ShortcutSequenceGate<Int>(bindings: ShortcutBinding.defaults)
        _ = gate.process(1, stroke: a, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        _ = gate.process(2, stroke: a, down: false, isRepeat: false, timestamp: 1.1, sourcePID: 42)
        let mismatch = gate.process(3, stroke: x, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 42)
        #expect(!mismatch.consumed && mismatch.action == nil)
        #expect(mismatch.replay.map { $0.1 } == [1, 2])
        #expect(mismatch.replay.allSatisfy { $0.0 == 42 })
        _ = gate.process(4, stroke: a, down: true, isRepeat: false, timestamp: 2, sourcePID: 42)
        let expired = gate.process(5, stroke: a, down: true, isRepeat: false, timestamp: 3.1, sourcePID: 42)
        #expect(expired.action == nil && expired.replay.map { $0.1 } == [4])
        #expect(gate.flush().map { $0.1 } == [5])
    }

    @Test func appChangeAndHeldKeyNeverCompleteASequence() {
        var gate = ShortcutSequenceGate<Int>(bindings: ShortcutBinding.defaults)
        _ = gate.process(1, stroke: a, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        let repeated = gate.process(2, stroke: a, down: true, isRepeat: true, timestamp: 1.1, sourcePID: 42)
        #expect(repeated.consumed && repeated.action == nil)
        let changed = gate.process(3, stroke: a, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 99)
        #expect(changed.action == nil)
        #expect(changed.replay.map { $0.1 } == [1, 2])
        #expect(changed.replay.allSatisfy { $0.0 == 42 })
    }

    @Test func nativeCopyIsNotDelayed() {
        let c = ShortcutStroke(keyCode: 8, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionTranslation: .init(strokes: [c, c])])
        #expect(!gate.process(1, stroke: c, down: true, isRepeat: false, timestamp: 1, sourcePID: 42).consumed)
        #expect(gate.flush().isEmpty)
    }
}
