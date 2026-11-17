import AppKit
import Testing
@testable import TrueL

@MainActor
struct PopupReturnTests {
    @Test func returnTracksPresentationAndRequiresAValidSelection() {
        let model = DemoModel()
        model.showPreviewResult()
        let context = SelectionReplacementContext(model: model)
        context.bind(canReplace: true)
        let session = PopupSession()
        session.presentation = .quick
        #expect(session.returnAction(model: model) == .replace)
        #expect(session.canPerform(.replace, model: model, selection: context))
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
        #expect(session.returnAction(model: model) == .none)
    }
}

@MainActor
extension UnifiedPopupTests {
    @Test(arguments: ["editable", "readonly", "failed"])
    func quickModeSwitchReprocessesSourceWithoutRevivingInvalidSelection(source: String) {
        let subject = AppDelegate(preview: true)
        subject.setPresentation(.quick)
        subject.model.input = "A selected sentence."
        subject.model.showPreviewResult()
        subject.selectionContext.bind(canReplace: source != "readonly")
        if source == "failed" { subject.selectionContext.fail("The selection changed.") }
        subject.changeWorkMode(.translation)
        defer { subject.model.cancel() }
        #expect(subject.model.mode == .translation)
        #expect(subject.model.input == "A selected sentence.")
        #expect(subject.model.isProcessing)
        #expect(subject.model.output.isEmpty)
        #expect(subject.session.focus == .result)
        #expect(subject.selectionContext.canReplaceSelection == (source == "editable"))
    }

    @Test func workspaceModeSwitchWaitsForSubmissionAndQuickEmptySourceDoesNotSubmit() {
        let subject = AppDelegate(preview: true)
        subject.model.showPreviewResult()
        subject.selectionContext.bind(canReplace: true)
        let input = subject.model.input
        subject.changeWorkMode(.translation)
        #expect(subject.model.input == input)
        #expect(subject.model.output.isEmpty && !subject.model.isProcessing)
        #expect(!subject.selectionContext.canReplaceSelection)
        subject.setPresentation(.quick)
        subject.model.reset()
        subject.changeWorkMode(.grammar)
        #expect(!subject.model.isProcessing)
        #expect(subject.model.errorMessage != nil)
    }

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
        subject.changeStyle("concise")
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

    @Test func quickStyleChangePreservesCaptureAndHasNoEditableInstructionField() async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.beginInput("Haha, enjoy~\n\nYou not the last one.", mode: .grammar,
                           canReplaceSelection: true, presentation: .quick)
        subject.model.showPreviewResult()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close(); panel.contentView = nil }
        try await Task.sleep(for: .milliseconds(120))
        let root = try #require(panel.contentView)
        #expect(!descendants(root).compactMap { $0 as? NSTextField }.contains { $0.isEditable })
        #expect(!descendants(root).compactMap { $0 as? NSTextView }.contains { $0.isEditable })
        subject.changeStyle("concise")
        #expect(subject.model.isProcessing)
        #expect(subject.selectionContext.canReplaceSelection)
        #expect(subject.preferences.writingScene == "concise")
        subject.model.showPreviewResult()
        #expect(subject.session.returnAction(model: subject.model) == .replace)
        subject.selectionContext.clear()
        subject.performReturnAction()
        #expect(subject.selectionContext.replacementError == nil)
        #expect(subject.model.hasResult)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

}

struct ShortcutSequenceGateTests {
    private let a = ShortcutStroke(keyCode: 0, modifiers: .control)
    private let x = ShortcutStroke(keyCode: 7, modifiers: .control)

    @Test func nativeSelectAllEventsAreNeverBuffered() {
        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [selectAll, selectAll])])
        let first = gate.process(1, stroke: selectAll, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        #expect(!first.consumed && first.action == nil && first.replay.isEmpty)
        #expect(!gate.process(2, stroke: selectAll, down: false, isRepeat: false, timestamp: 1.1, sourcePID: 42).consumed)
        let second = gate.process(3, stroke: selectAll, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 42)
        // Native sequences are recognized by the same non-consuming matcher as Command+C,C.
        #expect(!second.consumed && second.action == nil && second.replay.isEmpty)
        let repeatAfterTrigger = gate.process(4, stroke: selectAll, down: true, isRepeat: true, timestamp: 1.3, sourcePID: 99)
        #expect(!repeatAfterTrigger.consumed && repeatAfterTrigger.action == nil)
        #expect(!gate.process(5, stroke: selectAll, down: false, isRepeat: false, timestamp: 1.4, sourcePID: 99).consumed)
        #expect(gate.flush().isEmpty)
    }

    @Test func holdingCommandADoesNotTriggerOrBufferNativeRepeats() {
        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [selectAll, selectAll])])
        _ = gate.process(1, stroke: selectAll, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        for index in 2...5 {
            let repeated = gate.process(index, stroke: selectAll, down: true, isRepeat: true,
                                        timestamp: 1 + Double(index) / 10, sourcePID: 42)
            #expect(!repeated.consumed && repeated.action == nil && repeated.replay.isEmpty)
        }
        #expect(!gate.process(6, stroke: selectAll, down: false, isRepeat: false, timestamp: 1.6, sourcePID: 42).consumed)
        #expect(gate.flush().isEmpty)
    }

    @Test func commandATimeoutMismatchAndResetDoNotReplaySelectAll() {
        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [selectAll, selectAll])])
        _ = gate.process(1, stroke: selectAll, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        let expired = gate.process(2, stroke: selectAll, down: true, isRepeat: false, timestamp: 2.1, sourcePID: 42)
        #expect(!expired.consumed && expired.action == nil && expired.replay.isEmpty)
        let mismatch = gate.process(3, stroke: x, down: true, isRepeat: false, timestamp: 2.2, sourcePID: 42)
        #expect(!mismatch.consumed && mismatch.action == nil && mismatch.replay.isEmpty)
        let restarted = gate.process(4, stroke: selectAll, down: true, isRepeat: false, timestamp: 2.3, sourcePID: 42)
        #expect(!restarted.consumed && restarted.action == nil)
        #expect(gate.flush().isEmpty)
        #expect(gate.process(5, stroke: selectAll, down: true, isRepeat: false, timestamp: 2.4, sourcePID: 42).action == nil)
    }

    @Test func commandASequenceCannotCrossApplications() {
        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [selectAll, selectAll])])
        _ = gate.process(1, stroke: selectAll, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        let switched = gate.process(2, stroke: selectAll, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 99)
        #expect(!switched.consumed && switched.action == nil && switched.replay.isEmpty)
        let returned = gate.process(3, stroke: selectAll, down: true, isRepeat: false, timestamp: 1.4, sourcePID: 42)
        #expect(!returned.consumed && returned.action == nil && returned.replay.isEmpty)
    }

    @Test func commandASequenceContinuationsPassThroughLikeNativeCopy() {
        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        let b = ShortcutStroke(keyCode: 11, modifiers: .command)
        let c = ShortcutStroke(keyCode: 8, modifiers: .command)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [selectAll, b, c])])
        #expect(!gate.process(1, stroke: selectAll, down: true, isRepeat: false, timestamp: 1, sourcePID: 42).consumed)
        #expect(!gate.process(2, stroke: selectAll, down: false, isRepeat: false, timestamp: 1.1, sourcePID: 42).consumed)
        #expect(!gate.process(3, stroke: b, down: true, isRepeat: false, timestamp: 1.2, sourcePID: 42).consumed)
        #expect(!gate.process(4, stroke: b, down: false, isRepeat: false, timestamp: 1.3, sourcePID: 42).consumed)
        let mismatch = gate.process(5, stroke: x, down: true, isRepeat: false, timestamp: 1.4, sourcePID: 42)
        #expect(!mismatch.consumed && mismatch.action == nil)
        #expect(mismatch.replay.isEmpty)
        #expect(gate.flush().isEmpty)
    }

    @Test(arguments: [ShortcutModifiers.control, [.command, .shift], [.command, .option]])
    func onlyUnmodifiedCommandAPrefixPassesThrough(_ modifiers: ShortcutModifiers) {
        let otherA = ShortcutStroke(keyCode: 0, modifiers: modifiers)
        var gate = ShortcutSequenceGate<Int>(bindings: [.selectionGrammar: .init(strokes: [otherA, otherA])])
        let first = gate.process(1, stroke: otherA, down: true, isRepeat: false, timestamp: 1, sourcePID: 42)
        #expect(first.consumed && first.action == nil && first.replay.isEmpty)
        #expect(gate.flush().map { $0.1 } == [1])
    }

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
