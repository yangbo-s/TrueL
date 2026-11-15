import AppKit
import Testing
@testable import TrueL

@MainActor
struct EditorSubmissionTests {
    private func event(_ key: UInt16 = 36, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                        isARepeat: false, keyCode: key)!
    }

    @Test(arguments: [UInt16(36), UInt16(76)])
    func returnSubmitsWithoutInsertingNewline(_ key: UInt16) {
        let view = PanelTextView()
        view.string = "Hello"
        var submits = 0
        view.onSubmit = { submits += 1 }
        view.keyDown(with: event(key))
        #expect(submits == 1)
        #expect(view.string == "Hello")
    }

    @Test(arguments: [UInt16(36), UInt16(76)])
    func shiftReturnInsertsNewlineWithoutSubmitting(_ key: UInt16) {
        let view = PanelTextView()
        view.string = "Hello"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        var submits = 0
        view.onSubmit = { submits += 1 }
        view.keyDown(with: event(key, modifiers: .shift))
        #expect(submits == 0)
        #expect(view.string == "Hello\n")
    }

    @Test func returnDuringCompositionDoesNotSubmit() {
        let view = PanelTextView()
        view.setMarkedText("你好", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        var submits = 0
        view.onSubmit = { submits += 1 }
        view.keyDown(with: event())
        #expect(submits == 0)
    }

    @Test func emptySourceCannotStartRequestOnReturn() {
        let model = DemoModel()
        model.reset()
        let view = PanelTextView()
        view.onSubmit = { model.submit() }
        view.keyDown(with: event())
        #expect(!model.isProcessing)
        #expect(!model.hasResult)
    }
}
