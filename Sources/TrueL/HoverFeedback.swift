import AppKit
import SwiftUI

extension View {
    /// AppKit enter/exit tracking also works while a nonactivating panel owns keyboard focus.
    func panelHover(_ action: @escaping (Bool) -> Void) -> some View {
        background(PanelHoverRegion(action: action))
    }

    /// A nonactivating tooltip keeps editing focus in the document being explained.
    func hoverTooltip(_ text: String, enabled: Bool = true) -> some View {
        background(TooltipAnchor(text: text, enabled: enabled))
    }
}

private struct PanelHoverRegion: NSViewRepresentable {
    let action: (Bool) -> Void
    func makeNSView(context: Context) -> PanelHoverView { PanelHoverView() }
    func updateNSView(_ view: PanelHoverView, context: Context) { view.action = action }
    static func dismantleNSView(_ view: PanelHoverView, coordinator: ()) { view.endHover() }
}

@MainActor
private final class PanelHoverView: NSView {
    var action: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?
    private var inside = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        guard !inside else { return }
        inside = true
        action?(true)
    }
    override func mouseExited(with event: NSEvent) { endHover() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { endHover() }
    }
    func endHover() {
        guard inside else { return }
        inside = false
        action?(false)
    }
}

private struct TooltipAnchor: NSViewRepresentable {
    let text: String
    let enabled: Bool

    func makeNSView(context: Context) -> TooltipAnchorView { TooltipAnchorView() }

    func updateNSView(_ view: TooltipAnchorView, context: Context) {
        view.text = text
        view.tooltipEnabled = enabled
        view.presenter.update(view)
    }

    static func dismantleNSView(_ view: TooltipAnchorView, coordinator: ()) { view.presenter.dismiss() }
}

@MainActor
private final class TooltipAnchorView: NSView {
    let presenter = TooltipPresenter()
    var text = ""
    var tooltipEnabled = true
    private var hoverArea: NSTrackingArea?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if tooltipEnabled { presenter.enter(self) }
    }

    override func mouseExited(with event: NSEvent) { presenter.leave(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { presenter.detach(self) }
    }
}

@MainActor
private final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class TooltipPresenter: NSObject {
    private weak var anchor: TooltipAnchorView?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var anchorHovered = false
    private var isShowing = false
    private var transitionRevision = 0
    private var dismissing = false
    private let panel: TooltipPanel
    private let glass = NSGlassEffectView()
    private let content = NSView()
    private let label = NSTextField(labelWithString: "")

    override init() {
        panel = TooltipPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        // Ordinary labels do not intercept input. Correction explanations have their own hover lifecycle.
        panel.ignoresMouseEvents = true
        let surface = NSView()
        glass.style = .regular
        glass.cornerRadius = 8
        glass.autoresizingMask = [.width, .height]
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.preferredMaxLayoutWidth = 240
        label.maximumNumberOfLines = 3
        label.isSelectable = false
        label.isEditable = false
        label.setAccessibilityElement(false)
        content.autoresizingMask = [.width, .height]
        content.addSubview(label)
        glass.contentView = content
        surface.addSubview(glass)
        panel.contentView = surface
        // Selector observers do not retain the presenter owned by this tooltip's anchor.
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didHideNotification] {
            center.addObserver(self, selector: #selector(applicationDeactivated), name: name, object: nil)
        }
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            center.addObserver(self, selector: #selector(windowDisappeared), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(windowVisibilityChanged),
                           name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        center.addObserver(self, selector: #selector(applicationDeactivated),
                           name: NSMenu.didBeginTrackingNotification, object: nil)
    }

    func enter(_ view: TooltipAnchorView) {
        showTask?.cancel()
        hideTask?.cancel()
        anchor = view
        anchorHovered = true
        if isShowing {
            show(view)
            return
        }
        showTask = Task { [weak self, weak view] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            guard let self, let view, self.anchor === view, self.anchorHovered,
                  let window = view.window, window.isVisible, !window.isMiniaturized,
                  !view.isHiddenOrHasHiddenAncestor, view.tooltipEnabled else { return }
            let mouseInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            guard view.visibleRect.contains(view.convert(mouseInWindow, from: nil)) else { return }
            self.show(view)
        }
    }

    func leave(_ view: TooltipAnchorView) {
        guard anchor === view else { return }
        anchorHovered = false
        showTask?.cancel()
        scheduleHide()
    }

    func update(_ view: TooltipAnchorView) {
        guard anchor === view else { return }
        if !view.tooltipEnabled || view.text.isEmpty { dismiss() }
        else if isShowing { show(view) }
    }

    func detach(_ view: TooltipAnchorView) {
        if anchor === view { dismiss() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !anchorHovered else { return }
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, !self.anchorHovered else { return }
            self.dismiss(animated: true)
        }
    }

    @objc private func applicationDeactivated(_ notification: Notification) { dismiss() }

    @objc private func windowDisappeared(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === anchor?.window || window === panel.parent { dismiss() }
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === anchor?.window || window === panel.parent else { return }
        if !window.isVisible || window.isMiniaturized { dismiss() }
    }

    func dismiss(animated: Bool = false) {
        guard !dismissing else { return }
        dismissing = true
        defer { dismissing = false }
        showTask?.cancel()
        hideTask?.cancel()
        showTask = nil
        hideTask = nil
        anchorHovered = false
        anchor = nil
        transitionRevision += 1
        let revision = transitionRevision
        let shouldFade = animated && isShowing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isShowing = false
        if shouldFade {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.transitionRevision == revision, !self.isShowing else { return }
                    self.removePanel()
                }
            }
        } else { removePanel() }
    }

    private func removePanel() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func show(_ view: TooltipAnchorView) {
        guard let window = view.window, window.isVisible, !window.isMiniaturized,
              !view.isHiddenOrHasHiddenAncestor, view.tooltipEnabled, !view.text.isEmpty else {
            dismiss()
            return
        }
        transitionRevision += 1
        let shouldFade = !isShowing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        isShowing = true
        panel.appearance = window.effectiveAppearance
        label.stringValue = view.text
        let font = label.font ?? .systemFont(ofSize: 11)
        let natural = (view.text as NSString).size(withAttributes: [.font: font])
        let textWidth = min(240, ceil(natural.width))
        let measured = (view.text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 100), options: [.usesLineFragmentOrigin],
            attributes: [.font: font])
        let textHeight = min(48, max(14, ceil(measured.height)))
        let size = NSSize(width: textWidth + 20, height: textHeight + 12)
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        glass.frame = NSRect(origin: .zero, size: size)
        content.frame = NSRect(origin: .zero, size: size)
        label.frame = NSRect(x: 10, y: 6, width: textWidth, height: textHeight)
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let visibleFrame = window.screen?.visibleFrame ?? rect.insetBy(dx: -200, dy: -200)
        let x = min(max(rect.midX - size.width / 2, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        let below = rect.minY - size.height - 6
        let proposedY = below >= visibleFrame.minY + 8 ? below : rect.maxY + 6
        let y = min(max(proposedY, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        if shouldFade { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        if shouldFade {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else { panel.alphaValue = 1 }
    }
}
