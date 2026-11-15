import AppKit
import SwiftUI

/// Selectable reading text with paragraph spacing and inline emphasis.
struct TranslationResultText: View {
    let text: String

    private var paragraphs: [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                SelectableTranslationParagraph(text: paragraph)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SelectableTranslationParagraph: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TranslationTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        let view = TranslationTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.backgroundColor = NSColor.clear
        view.textContainerInset = CGSize.zero
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setAccessibilityLabel(text)
        view.updateText(text)
        return view
    }

    func updateNSView(_ view: TranslationTextView, context: Context) { view.updateText(text) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: TranslationTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 400)
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        container.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        var height = used.height
        if nsView.string.hasSuffix("\n") { height = max(height, layout.extraLineFragmentRect.maxY) }
        return CGSize(width: width, height: ceil(max(20, height)))
    }
}

@MainActor
private final class TranslationTextView: NSTextView {
    private var source: String?

    func updateText(_ text: String) {
        guard source != text else { return }
        source = text
        let selection = selectedRange()
        let content = Self.attributedText(text)
        textStorage?.setAttributedString(content)
        let start = min(selection.location, content.length)
        setSelectedRange(NSRange(location: start, length: min(selection.length, content.length - start)))
        setAccessibilityLabel(content.string)
        invalidateIntrinsicContentSize()
    }

    private static func attributedText(_ text: String) -> NSAttributedString {
        let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let result = NSMutableAttributedString(string: "")
        let regularFont = NSFont.systemFont(ofSize: 16)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, 26 - NSLayoutManager().defaultLineHeight(for: regularFont))
        paragraph.lineBreakMode = .byWordWrapping

        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
                : NSFont.systemFont(ofSize: 16, weight: intent.contains(.stronglyEmphasized) ? .semibold : .regular)
            if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(Theme.resultText),
                .paragraphStyle: paragraph
            ]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if intent.contains(.code) { attributes[.backgroundColor] = NSColor(Theme.hover) }
            if run.link != nil { attributes[.foregroundColor] = NSColor(Theme.resultBlue) }
            result.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return result
    }
}
