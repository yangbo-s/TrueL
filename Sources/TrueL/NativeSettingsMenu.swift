import AppKit
import SwiftUI

struct SettingsMenuChoice {
    let value: String
    let title: String
    var group: String? = nil
}

/// A native menu shares the form controls’ spacing while retaining AppKit keyboard navigation.
struct NativeSettingsMenu: NSViewRepresentable {
    @Binding var selection: String
    var choices: [SettingsMenuChoice]
    var width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> SettingsMenuButton {
        SettingsMenuButton(frame: NSRect(x: 0, y: 0, width: width, height: SurfaceMetrics.controlHeight))
    }

    func updateNSView(_ view: SettingsMenuButton, context: Context) {
        view.choices = choices
        view.selection = selection
        view.title = choices.first(where: { $0.value == selection })?.title ?? selection
        view.isEnabled = isEnabled
        view.reduceMotion = reduceMotion
        view.onSelect = { selection = $0 }
        view.setAccessibilityValue(view.title)
        view.refreshPalette(animated: false)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsMenuButton, context: Context) -> CGSize? {
        CGSize(width: width, height: SurfaceMetrics.controlHeight)
    }
}

@MainActor
final class SettingsMenuButton: NSButton {
    var choices: [SettingsMenuChoice] = []
    var selection = ""
    var reduceMotion = false
    var onSelect: ((String) -> Void)?
    var compact = false
    private var hovering = false
    private var menuOpen = false
    private var hoverTracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .exterior
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(showMenu)
        wantsLayer = true
        layer?.cornerRadius = SurfaceMetrics.controlRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0
        setAccessibilityRole(.popUpButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 144, height: SurfaceMetrics.controlHeight) }

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: SurfaceMetrics.controlRadius, yRadius: SurfaceMetrics.controlRadius).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refreshPalette(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshPalette(animated: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshPalette(animated: false)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        refreshPalette(animated: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = true
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: SurfaceMetrics.controlRadius, yRadius: SurfaceMetrics.controlRadius)
        border.lineWidth = 1
        NSColor(Theme.hairline).setStroke()
        if !compact { border.stroke() }
        NSGraphicsContext.restoreGraphicsState()
        let ink = NSColor(compact ? Theme.secondary : Theme.text).withAlphaComponent(isEnabled ? 1 : 0.45)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: compact ? TypeScale.control : TypeScale.value),
            .foregroundColor: ink,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: title, attributes: attributes)
        let height = string.size().height
        string.draw(in: NSRect(x: 12, y: (bounds.height - height) / 2,
                              width: max(bounds.width - (compact ? 28 : 40), 0), height: height))
        let arrowColor = NSColor(Theme.secondary).withAlphaComponent(isEnabled ? 1 : 0.45)
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [arrowColor]))
        NSImage(systemSymbolName: compact ? "chevron.down" : "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)?
            .draw(in: NSRect(x: bounds.width - (compact ? 12 : 20), y: (bounds.height - 8) / 2, width: 8, height: 8))
    }

    func refreshPalette(animated: Bool) {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let pressed = (isHighlighted || menuOpen) && isEnabled
            let background: NSColor
            if pressed {
                background = NSColor(Theme.popupPressed)
            } else if hovering && isEnabled {
                background = NSColor(Theme.popupHover)
            } else {
                background = compact ? .clear : NSColor(Theme.field)
            }
            if animated && !reduceMotion && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
                animation.toValue = background.cgColor
                animation.duration = 0.16
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: "menuHover")
            } else {
                layer.removeAnimation(forKey: "menuHover")
            }
            layer.backgroundColor = background.cgColor
            needsDisplay = true
        }
    }

    @objc private func showMenu() {
        guard isEnabled else { return }
        let menu = NSMenu()
        menu.font = .systemFont(ofSize: TypeScale.value)
        menu.minimumWidth = bounds.width
        menu.autoenablesItems = false
        var previousGroup: String?
        for choice in choices {
            if let group = choice.group, group != previousGroup {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                let heading = NSMenuItem.sectionHeader(title: group)
                menu.addItem(heading)
            }
            previousGroup = choice.group
            let item = NSMenuItem(title: choice.title, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.value
            item.state = choice.value == selection ? .on : .off
            menu.addItem(item)
        }
        menuOpen = true
        refreshPalette(animated: true)
        defer {
            menuOpen = false
            refreshPalette(animated: true)
        }
        menu.popUp(positioning: menu.items.first(where: { ($0.representedObject as? String) == selection }),
                   at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        selection = value
        title = sender.title
        setAccessibilityValue(title)
        onSelect?(value)
        needsDisplay = true
    }
}
