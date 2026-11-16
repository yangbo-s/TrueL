import AppKit
import Testing
@testable import TrueL

@MainActor
extension UnifiedPopupTests {
    @Test(arguments: WorkMode.allCases, [CGFloat(736), CGFloat(960)])
    func popupAlignsSideBySideTypographyAndScrollColumns(mode: WorkMode, width: CGFloat) async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.model.mode = mode
        let text = mode == .translation
            ? "More performance work.\n• 42% less memory at startup\n• 40% less memory per chat\n• CPU usage: 20% → 8%\n每个聊天的内存占用减少 40%，阅读和输入保持相同字号。"
            : "Haha, enjoy~\n\nYou not the last one."
        subject.model.input = Array(repeating: text, count: 8).joined(separator: "\n\n")
        subject.showPanel()
        subject.model.showPreviewResult()
        let panel = try #require(subject.panel)
        panel.setContentSize(NSSize(width: width, height: 520))
        defer { subject.model.cancel(); panel.delegate = nil; panel.close(); panel.contentView = nil }
        try await Task.sleep(for: .milliseconds(300))
        let root = try #require(panel.contentView)
        root.layoutSubtreeIfNeeded()
        let views = descendantViews(root)
        let editor = try #require(views.compactMap { $0 as? PanelTextView }.first)
        let sourceScroll = try #require(editor.enclosingScrollView)
        let resultScroll = try #require(views.compactMap { $0 as? NSScrollView }.first { $0 !== sourceScroll })
        let sourceFrame = sourceScroll.convert(sourceScroll.bounds, to: root)
        let resultFrame = resultScroll.convert(resultScroll.bounds, to: root)
        let stride = resultFrame.minX - sourceFrame.minX
        #expect(stride > 300)
        #expect(abs(sourceFrame.width - resultFrame.width) <= 0.5)
        #expect(abs(sourceFrame.minY - resultFrame.minY) <= 0.5)
        #expect(abs(sourceFrame.maxY - resultFrame.maxY) <= 0.5)
        #expect(sourceScroll.scrollerStyle == resultScroll.scrollerStyle)
        for style in [sourceScroll.scrollerStyle, .overlay, .legacy] {
            sourceScroll.scrollerStyle = style
            resultScroll.scrollerStyle = style
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let sourceScroller = try #require(sourceScroll.verticalScroller)
            let resultScroller = try #require(resultScroll.verticalScroller)
            let sourceRight = sourceScroller.convert(sourceScroller.bounds, to: root).maxX
            let resultRight = resultScroller.convert(resultScroller.bounds, to: root).maxX
            #expect(abs(sourceRight + stride - resultRight) <= 0.5)
            let lastCharacter = NSRange(location: (editor.string as NSString).length - 1, length: 1)
            let container = try #require(editor.textContainer)
            let layout = try #require(editor.layoutManager)
            layout.ensureLayout(for: container)
            let lastGlyphs = layout.glyphRange(forCharacterRange: lastCharacter, actualCharacterRange: nil)
            let lastLine = layout.boundingRect(forGlyphRange: lastGlyphs, in: container)
                .offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
            #expect(editor.bounds.maxY >= lastLine.maxY)
            editor.scrollRangeToVisible(lastCharacter)
            #expect(editor.visibleRect.insetBy(dx: -1, dy: -1).contains(lastLine))
            if mode == .translation {
                let sourceFont = try #require(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                let sourceParagraph = try #require(editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                let paragraphs = descendantViews(resultScroll).compactMap { $0 as? NSTextView }.filter { !$0.isEditable && !$0.string.isEmpty }
                #expect(!paragraphs.isEmpty)
                for result in paragraphs {
                    let resultFont = try #require(result.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                    let resultParagraph = try #require(result.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                    #expect(sourceFont.pointSize == resultFont.pointSize)
                    #expect(sourceParagraph.lineSpacing == resultParagraph.lineSpacing)
                    let sourceTextX = editor.convert(editor.textContainerOrigin, to: root).x
                    let resultTextX = result.convert(result.textContainerOrigin, to: root).x
                    #expect(abs(sourceTextX + stride - resultTextX) <= 0.5)
                }
            }
        }
    }

    @Test(arguments: [PopupPresentation.workspace, .quick])
    func translationRemainsReadableAfterStyleChanges(presentation: PopupPresentation) async throws {
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.beginInput("Haha, enjoy~\n\nYou not the last one.", mode: .translation, presentation: presentation)
        subject.model.showPreviewResult()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close(); panel.contentView = nil }
        try await Task.sleep(for: .milliseconds(150))
        for style in ["literal", "concise", "standard"] {
            subject.changeStyle(style)
            subject.model.showPreviewResult()
            try await Task.sleep(for: .milliseconds(100))
            let root = try #require(panel.contentView)
            let text = try #require(descendantViews(root).compactMap { $0 as? NSTextView }
                .first { !$0.isEditable && !$0.string.isEmpty })
            let container = try #require(text.textContainer)
            #expect(text.bounds.width > 200)
            #expect(abs(container.containerSize.width - text.bounds.width) <= 1)
            #expect(container.containerSize.width > 200)
        }
    }

    private func descendantViews(_ root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap { descendantViews($0) }
    }
}
