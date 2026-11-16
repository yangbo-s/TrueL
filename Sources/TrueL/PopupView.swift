import AppKit
import SwiftUI

private typealias PopupState<Value> = SwiftUI.State<Value>

struct PopupView: View {
    @Bindable var model: DemoModel
    @Bindable var preferences: Preferences
    @Bindable var service: ServiceConfiguration
    @Bindable var selectionContext: SelectionReplacementContext
    @Bindable var session: PopupSession
    var onTranslateClipboard: () -> Void
    var onReplaceSelection: () -> Void
    var onRefine: () -> Void
    var onModeChange: (WorkMode) -> Void
    var onLanguageChange: () -> Void
    var onSettings: () -> Void
    var onPin: (Bool) -> Void
    var onHeightChange: (_ preferred: CGFloat, _ minimum: CGFloat) -> Void
    var availableHeight: () -> CGFloat = { 640 }
    @PopupState<CGFloat> private var measuredResultHeight = 180
    @FocusState private var followUpFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isQuick: Bool { session.presentation == .quick }
    private var primaryAction: PopupReturnAction { session.returnAction(model: model) }
    private var displayedError: String? {
        let messages = [model.errorMessage, selectionContext.replacementError].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    private var quickHeight: CGFloat {
        min(availableHeight(), max(PopupLayout.baseHeight,
            WindowChromeMetrics.height + SurfaceMetrics.edge + PopupLayout.resultHeaderHeight
                + measuredResultHeight + PopupLayout.followUpHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: SurfaceMetrics.islandGap) {
                if !isQuick { sourceIsland }
                resultIsland
            }
            .padding(.horizontal, SurfaceMetrics.edge)
            .padding(.bottom, SurfaceMetrics.edge)
        }
        .onChange(of: quickHeight, initial: true) { _, height in updateWindowHeight(height) }
        .onChange(of: session.presentation) { _, _ in
            followUpFocused = false
            updateWindowHeight(quickHeight)
        }
        .onChange(of: model.inputRevision) { _, _ in followUpFocused = false }
        .onChange(of: followUpFocused) { _, focused in
            if focused { session.focus = .followUp }
            else if session.focus == .followUp { session.focus = .result }
        }
        .onChange(of: session.focus) { _, focus in
            followUpFocused = focus == .followUp
        }
        .onExitCommand { model.cancel(); followUpFocused = false }
    }

    private func updateWindowHeight(_ height: CGFloat) {
        onHeightChange(isQuick ? height : session.presentation.initialSize.height,
                       session.presentation.minimumHeight)
    }

    private var sourceIsland: some View {
        VStack(spacing: 0) {
            sourceHeader
                .padding(.horizontal, SurfaceMetrics.inset)
                .padding(.top, SurfaceMetrics.inset)
                .padding(.bottom, SurfaceMetrics.relatedGap)
            editor.padding(.horizontal, SurfaceMetrics.inset)
            if let error = displayedError {
                TrueLInlineStatus(text: error, tone: .error, symbol: "exclamationmark.circle")
                    .padding(.horizontal, SurfaceMetrics.inset * 2)
                    .padding(.top, SurfaceMetrics.relatedGap)
                    .frame(maxHeight: 80)
            }
            toolbar
                .padding(.horizontal, SurfaceMetrics.inset)
                .padding(.top, SurfaceMetrics.relatedGap)
                .padding(.bottom, SurfaceMetrics.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(TrueLIsland())
    }

    private var resultIsland: some View {
        VStack(spacing: 0) {
            fixedResultHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isQuick, let error = displayedError {
                        TrueLInlineStatus(text: error, tone: .error, symbol: "exclamationmark.circle")
                    }
                    if model.isProcessing { processingResult }
                    else if model.hasResult {
                        if model.mode == .translation { TranslationResultText(text: model.output) }
                        else {
                            CorrectedText(output: model.output, corrections: model.corrections)
                            if !model.tip.isEmpty { AnalysisTip(text: model.tip) }
                        }
                    } else if displayedError == nil {
                        Text(model.mode == .translation ? "译文将在这里显示" : "修改结果将在这里显示")
                            .font(.system(size: TypeScale.body)).foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PopupLayout.textInset)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { height in
                    if abs(height - measuredResultHeight) > 0.5 { measuredResultHeight = height }
                }
            }
            .scrollIndicators(.automatic)
            .padding(.horizontal, SurfaceMetrics.inset)
            followUp
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(TrueLIsland())
    }

    private var header: some View {
        WindowChrome(dragIdentifier: "TrueL.main.drag") {
            HStack(spacing: 4) {
                if model.accepted {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.success).accessibilityLabel("已接受修改")
                        .frame(width: SurfaceMetrics.controlHeight, height: SurfaceMetrics.controlHeight)
                }
            Button { onPin(!preferences.alwaysOnTop) } label: {
                PopupGlyph(preferences.alwaysOnTop ? .pinFilled : .pin)
                    .foregroundStyle(preferences.alwaysOnTop ? Theme.accent : Theme.secondary)
            }
            .buttonStyle(QuietIconStyle())
            .accessibilityLabel(preferences.alwaysOnTop ? "取消置顶" : "窗口置顶")
            .help(preferences.alwaysOnTop ? "取消置顶后，点击外部收起" : "置顶后，点击外部保持显示")
            Button(action: onSettings) {
                Image(systemName: "slider.horizontal.3").font(.system(size: TypeScale.toolSymbol))
            }.buttonStyle(QuietIconStyle()).help("设置").accessibilityLabel("设置")
            }
        }
        .overlay(alignment: .leading) {
            HStack(spacing: 4) {
                modeButton(.translation, title: "翻译")
                modeButton(.grammar, title: "改写")
            }
            .padding(.leading, WindowChromeMetrics.leadingContentInset)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("语法检查示例") { model.mode = .grammar; model.loadSample(0) }
            Button("写作润色示例") { model.mode = .grammar; model.loadSample(1) }
            Button("翻译示例") { model.mode = .translation; model.loadSample(2) }
            Divider()
            Button("清空内容") { model.reset() }
            Divider()
            Button("设置…", action: onSettings)
        }
    }

    private var sourceHeader: some View {
        HStack(spacing: 4) {
            Text("原有内容")
                .font(.system(size: TypeScale.control, weight: .semibold))
                .foregroundStyle(Theme.resultSecondary)
                .padding(.leading, SurfaceMetrics.inset)
            Spacer(minLength: 12)
            if model.mode == .translation { languageMenu }
        }
        .frame(height: SurfaceMetrics.controlHeight)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.input.isEmpty {
                Text("输入或粘贴原文")
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, PopupLayout.textInset)
                    .allowsHitTesting(false)
            }
            PanelEditor(text: $model.input, onSubmit: { model.submit() }, onCancel: { model.cancel() },
                        onFocusChange: { focused in
                            if focused { session.focus = .source }
                            else if session.focus == .source { session.focus = .result }
                        })
        }
        .frame(maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                TaskModelMenu(service: service, mode: model.mode, maximumWidth: 180, onSettings: onSettings)
                Button(action: onTranslateClipboard) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: TypeScale.toolSymbol))
                }.buttonStyle(QuietIconStyle()).help("翻译剪贴板").accessibilityLabel("翻译剪贴板")
            }
            .fixedSize()
            Spacer(minLength: 8)
            Button {
                if model.isProcessing { model.cancel() }
                else { model.submit() }
            } label: {
                HStack(spacing: 8) {
                    if model.isProcessing {
                        Image(systemName: "stop.fill").font(.system(size: TypeScale.inlineSymbol))
                        Text("停止")
                    } else {
                        Text(model.mode == .grammar ? "检查" : "翻译")
                        ReturnGlyph()
                    }
                }
            }
            .buttonStyle(TrueLButtonStyle(role: primaryAction == .submit ? .primary : .secondary))
            .help("回车提交 · Shift＋回车换行")
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .frame(height: SurfaceMetrics.controlHeight)
    }

    private var languageMenu: some View {
        NativeProviderMenu(selection: Binding(get: { preferences.language }, set: { language in
            guard language != preferences.language else { return }
            followUpFocused = false
            preferences.language = language
            onLanguageChange()
        }), choices: Preferences.supportedLanguages, accessibilityLabel: "目标语言")
        .fixedSize()
    }

    private func modeButton(_ mode: WorkMode, title: String) -> some View {
        Button {
            guard model.mode != mode else { return }
            followUpFocused = false
            onModeChange(mode)
        } label: {
            Text(title).frame(width: 48)
        }
        .buttonStyle(TrueLTabStyle(selected: model.mode == mode))
        .accessibilityLabel(mode == .grammar ? "语法检查与改写" : "翻译")
        .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
    }

    private var fixedResultHeader: some View {
        resultHeader
            .padding(.horizontal, SurfaceMetrics.inset)
            .padding(.top, SurfaceMetrics.inset)
            .padding(.bottom, SurfaceMetrics.relatedGap)
    }

    private var resultHeader: some View {
        HStack(spacing: 8) {
            Text(model.mode == .translation ? "译文" : "修改结果")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.resultSecondary)
                .padding(.leading, SurfaceMetrics.inset)
            Spacer(minLength: 8)
            if model.hasResult {
                Button { model.copyResult() } label: {
                    PopupGlyph(model.copied ? .checkCircleFilled : .copy, size: TypeScale.toolSymbol)
                        .foregroundStyle(model.copied ? Theme.resultSuccess : Theme.resultSecondary)
                }
                .buttonStyle(QuietIconStyle())
                .accessibilityLabel(model.copied ? "已复制" : "复制结果")
                .help(model.copied ? "已复制" : "复制结果")
                Button {
                    if isQuick { onReplaceSelection() }
                    else { model.applyResult() }
                } label: {
                    HStack(spacing: 8) {
                        Text("替换")
                        ReturnGlyph()
                    }
                }
                .buttonStyle(TrueLButtonStyle(role: primaryAction == .replace ? .primary : .tertiary))
                .disabled(isQuick ? !selectionContext.canReplaceSelection : model.accepted)
                .accessibilityLabel(isQuick ? "替换原选区" : "将结果放回原文编辑区")
                .help(isQuick ? (selectionContext.canReplaceSelection ? "回车替换原应用中的选中文字"
                    : "原选区不可编辑或已失效，可以复制结果") : "将结果放回左侧编辑区")
            } else if isQuick, model.isProcessing {
                Button { model.cancel() } label: {
                    Image(systemName: "stop.fill").font(.system(size: TypeScale.inlineSymbol))
                }.buttonStyle(QuietIconStyle()).accessibilityLabel("停止处理")
            } else if isQuick, !model.input.isEmpty {
                Button { model.submit() } label: {
                    HStack(spacing: 8) { Text("重试"); ReturnGlyph() }
                }.buttonStyle(TrueLButtonStyle(role: .primary))
            }
        }
        .frame(height: PopupLayout.iconButtonSize)
    }

    private var processingResult: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(model.output.isEmpty ? (model.mode == .translation ? "正在翻译…" : "正在检查…") : model.output)
                .font(.system(size: TypeScale.body))
                .foregroundStyle(Theme.resultSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }

    private var followUp: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if model.followUp.isEmpty {
                    Text(model.mode == .translation ? "继续调整译文" : "继续调整措辞")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextField("", text: $model.followUp)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .focused($followUpFocused).onSubmit(onRefine)
                    .accessibilityLabel("追问或调整要求")
            }
            .padding(.horizontal, SurfaceMetrics.inset)
            .frame(height: SurfaceMetrics.controlHeight)
            .modifier(TrueLField(focused: followUpFocused))
            Button(action: onRefine) {
                ReturnGlyph()
            }
            .buttonStyle(TrueLButtonStyle(role: primaryAction == .refine ? .primary : .tertiary, iconOnly: true))
            .accessibilityLabel("提交调整要求").help("回车提交调整要求")
            .disabled(!session.canPerform(.refine, model: model, selection: selectionContext))
        }
        .disabled(model.isProcessing || !model.hasResult)
        .padding(.top, SurfaceMetrics.relatedGap)
        .padding(.horizontal, SurfaceMetrics.inset).padding(.bottom, SurfaceMetrics.inset)
    }

}

private struct ReturnGlyph: View {
    var body: some View {
        Image(systemName: "return")
            .font(.system(size: TypeScale.inlineSymbol, weight: .medium))
            .accessibilityHidden(true)
    }
}

private struct AnalysisTip: View {
    let text: String
    var body: some View { card }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("用法提示").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Theme.resultSecondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Theme.resultText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SurfaceMetrics.inset)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius, style: .continuous))
        .padding(.horizontal, -SurfaceMetrics.inset)
    }
}

private struct CorrectedText: View {
    @PopupState<CorrectionHoverState> private var hover = CorrectionHoverState()
    let output: String
    let corrections: [Correction]

    private var paragraphs: [[ResultToken]] {
        var consumedCorrections: Set<UUID> = []
        return output.components(separatedBy: "\n").map { line in
            var tokens: [ResultToken] = []
            var pendingWhitespace = ""
            // Whitespace belongs to the following token, including across a chip boundary.
            // This preserves punctuation adjacency and multiple spaces without special cases.
            func appendPlain(_ text: Substring) {
                var word = ""
                for character in text {
                    if character.isWhitespace {
                        if !word.isEmpty {
                            tokens.append(ResultToken(text: word, correction: nil, leadingWhitespace: pendingWhitespace,
                                                      roundsLeadingWhitespace: tokens.last?.correction != nil))
                            word = ""
                            pendingWhitespace = ""
                        }
                        pendingWhitespace.append(character)
                    } else {
                        word.append(character)
                    }
                }
                if !word.isEmpty {
                    tokens.append(ResultToken(text: word, correction: nil, leadingWhitespace: pendingWhitespace,
                                              roundsLeadingWhitespace: tokens.last?.correction != nil))
                    pendingWhitespace = ""
                }
            }
            var remainder = line[...]
            while !remainder.isEmpty {
                let match = corrections.compactMap { correction -> (Correction, Range<String.Index>)? in
                    guard !consumedCorrections.contains(correction.id), !correction.replacement.isEmpty,
                          let range = remainder.range(of: correction.replacement) else { return nil }
                    return (correction, range)
                }.sorted { $0.1.lowerBound < $1.1.lowerBound }.first
                guard let (correction, range) = match else {
                    appendPlain(remainder)
                    break
                }
                appendPlain(remainder[..<range.lowerBound])
                tokens.append(ResultToken(text: String(remainder[range]), correction: correction, leadingWhitespace: pendingWhitespace,
                                          roundsLeadingWhitespace: tokens.last?.correction != nil))
                // Each response entry marks one occurrence even when the same word appears twice.
                consumedCorrections.insert(correction.id)
                pendingWhitespace = ""
                remainder = remainder[range.upperBound...]
            }
            return tokens
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { paragraphIndex, tokens in
                // A blank paragraph adds space without inventing text.
                if tokens.isEmpty { Color.clear.frame(height: BodyTextStyle.lineHeight) }
                else {
                    WordFlow(lineSpacing: 0) {
                        ForEach(Array(tokens.enumerated()), id: \.offset) { tokenIndex, token in
                            if let correction = token.correction {
                                CorrectionChip(correction: correction,
                                               occurrenceID: CorrectionOccurrenceID(correctionID: correction.id,
                                                                                    paragraphIndex: paragraphIndex,
                                                                                    tokenIndex: tokenIndex),
                                               hover: hover)
                                    .layoutValue(key: LeadingWhitespaceWidth.self, value: token.leadingWidth)
                            } else {
                                Text(token.text).font(.system(size: TypeScale.body)).foregroundStyle(Theme.resultText)
                                    .lineSpacing(BodyTextStyle.paragraph.lineSpacing)
                                    .frame(minHeight: BodyTextStyle.lineHeight, alignment: .topLeading)
                                    .layoutValue(key: LeadingWhitespaceWidth.self, value: token.leadingWidth)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

private struct ResultToken {
    var text: String
    var correction: Correction?
    var leadingWhitespace: String
    var roundsLeadingWhitespace = false

    var leadingWidth: CGFloat {
        let width = (leadingWhitespace as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: TypeScale.body)]).width
        guard roundsLeadingWhitespace else { return width }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return ceil(width * scale) / scale
    }
}

private struct LeadingWhitespaceWidth: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

private struct CorrectionChip: View {
    let correction: Correction
    let occurrenceID: CorrectionOccurrenceID
    let hover: CorrectionHoverState

    var body: some View {
        // Click/keyboard activation is an accessible supplement; it never toggles a hovered explanation shut.
        Button { hover.present(occurrenceID) } label: {
            Text(correction.replacement)
                .font(.system(size: TypeScale.body))
                .foregroundStyle(Theme.replacementText)
                .lineSpacing(BodyTextStyle.paragraph.lineSpacing)
                .frame(minHeight: BodyTextStyle.lineHeight, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: SurfaceMetrics.embeddedRadius, style: .continuous)
                        .fill(hover.activeID == occurrenceID ? Theme.correctionHover : Theme.correctionBackground)
                        // Keep adjacent corrections separate within a normal word space.
                        .padding(.horizontal, -1) // grid: ok 1pt optical bleed stays inside a normal word space
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("修改为 \(correction.replacement)，查看解释")
        .panelHover { hover.triggerHover(occurrenceID, inside: $0) }
        .popover(isPresented: Binding(get: { hover.activeID == occurrenceID }, set: { if !$0 { hover.dismiss(occurrenceID) } }), arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                // Flow spacing is vertical. The localized prefix/infix already contain their horizontal spaces.
                WordFlow(lineSpacing: 4) {
                    Text("已将 ")
                        .font(.system(size: 12)).foregroundStyle(.primary)
                        .padding(.vertical, 2)
                    Text(correction.original)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.originalText)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Theme.originalBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    Text(" 改为 ")
                        .font(.system(size: 12)).foregroundStyle(.primary)
                        .padding(.vertical, 2)
                    Text(correction.replacement)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.replacementText)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Theme.replacementBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                Divider()
                Text(correction.explanation)
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(minWidth: 200, maxWidth: 320, alignment: .leading)
            .panelHover { hover.contentHover(occurrenceID, inside: $0) }
        }
        .onDisappear { hover.dismiss(occurrenceID) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in hover.dismiss() }
    }
}

private struct WordFlow: Layout {
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 400, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in layout.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                                 anchor: .topLeading, proposal: ProposedViewSize(width: layout.widths[index], height: nil))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint], widths: [CGFloat]) {
        let width = max(1, width)
        var positions: [CGPoint] = []
        var widths: [CGFloat] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            var gap = subview[LeadingWhitespaceWidth.self]
            if x > 0 && x + gap + ideal.width > width {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
                gap = 0
            }
            // Indentation consumes line width too; use the same constrained proposal
            // for measuring and placing long unbroken words or correction chips.
            gap = min(gap, max(0, width - x - 1))
            let proposedWidth = min(ideal.width, width - x - gap)
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            x += gap
            positions.append(CGPoint(x: x, y: y))
            widths.append(proposedWidth)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), positions, widths)
    }
}
