import AppKit
import SwiftUI

/// A transparent native editor keeps selection and IME behavior inside the panel.
struct PanelEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = PanelTextView()
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.font = BodyTextStyle.font
        editor.defaultParagraphStyle = BodyTextStyle.paragraph
        editor.textColor = NSColor(Theme.text)
        editor.insertionPointColor = NSColor(Theme.accent)
        editor.textContainerInset = NSSize(width: PopupLayout.textInset, height: 0)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        // The editor, placeholder, results and follow-up share one content edge.
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.string = text
        editor.applyBodyStyle()
        editor.delegate = context.coordinator
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        editor.onFocusChange = onFocusChange
        editor.setAccessibilityLabel("原文")
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PanelTextView else { return }
        editor.onSubmit = onSubmit
        editor.onCancel = onCancel
        editor.onFocusChange = onFocusChange
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.applyBodyStyle()
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PanelEditor
        init(_ parent: PanelEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

final class PanelTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
    func applyBodyStyle() {
        let paragraph = BodyTextStyle.paragraph
        textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                 range: NSRange(location: 0, length: (string as NSString).length))
        typingAttributes[.paragraphStyle] = paragraph
    }

    override func keyDown(with event: NSEvent) {
        // Let the input method confirm its candidate before interpreting Return.
        if hasMarkedText() {
            super.keyDown(with: event)
        } else if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) {
            onSubmit?()
        } else if event.keyCode == 36 || event.keyCode == 76 {
            insertNewlineIgnoringFieldEditor(self)
        } else if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
