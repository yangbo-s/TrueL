import AppKit
import SwiftUI

/// Compact native choices on the same quiet surface as the popup toolbar.
struct NativeProviderMenu: NSViewRepresentable {
    @Binding var selection: String
    let choices: [String]
    let accessibilityLabel: String
    @Environment(\.isEnabled) private var isEnabled

    init(selection: Binding<String>, choices: [String], accessibilityLabel: String) {
        _selection = selection
        self.choices = choices
        self.accessibilityLabel = accessibilityLabel
    }

    func makeNSView(context: Context) -> ProviderMenuButton {
        ProviderMenuButton(frame: NSRect(x: 0, y: 0, width: 96, height: SurfaceMetrics.controlHeight))
    }

    func updateNSView(_ view: ProviderMenuButton, context: Context) {
        view.configure(selection: selection, choices: choices, accessibilityLabel: accessibilityLabel, enabled: isEnabled) {
            selection = $0
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProviderMenuButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

@MainActor
final class ProviderMenuButton: NSButton {
    private let content = ProviderMenuContentView()
    private let label = NSTextField(labelWithString: "")
    private let arrow = NSImageView()
    private var choices: [String] = []
    private var selection = ""
    private var onSelect: ((String) -> Void)?
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
        setAccessibilityRole(.popUpButton)

        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.cornerRadius = SurfaceMetrics.controlRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        addSubview(content)

        label.font = .systemFont(ofSize: TypeScale.control)
        label.textColor = NSColor(Theme.secondary)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.addSubview(label)

        arrow.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        arrow.contentTintColor = NSColor(Theme.secondary)
        arrow.imageScaling = .scaleProportionallyUpOrDown
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.setAccessibilityElement(false)
        content.addSubview(arrow)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            arrow.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            arrow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            arrow.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 8),
            arrow.heightAnchor.constraint(equalToConstant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(80, ceil(label.intrinsicContentSize.width) + 40), height: SurfaceMetrics.controlHeight)
    }

    func configure(selection: String, choices: [String], accessibilityLabel: String, enabled: Bool, onSelect: @escaping (String) -> Void) {
        self.selection = selection
        self.choices = choices
        self.onSelect = onSelect
        if label.stringValue != selection {
            label.stringValue = selection
            title = selection
            invalidateIntrinsicContentSize()
        }
        isEnabled = enabled && !choices.isEmpty
        if !isEnabled { hovering = false }
        setAccessibilityLabel(accessibilityLabel)
        setAccessibilityValue(selection)
        refreshHover()
    }

    // NSButton supplies keyboard/menu actions; AppKit paints the exterior focus ring.
    override func draw(_ dirtyRect: NSRect) {}
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: SurfaceMetrics.controlRadius, yRadius: SurfaceMetrics.controlRadius).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled, !menuOpen else { return }
        hovering = true
        refreshHover(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshHover(animated: true)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        showMenu()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshHover()
    }

    private func refreshHover(animated: Bool = false) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            label.textColor = NSColor(Theme.secondary).withAlphaComponent(isEnabled ? 1 : 0.45)
            arrow.contentTintColor = label.textColor
            let color = NSColor(menuOpen ? Theme.popupPressed : (hovering && isEnabled ? Theme.popupHover : .clear))
            guard let layer = content.layer else { return }
            if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
                animation.toValue = color.cgColor
                animation.duration = 0.16
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: "hover")
            } else { layer.removeAnimation(forKey: "hover") }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = color.cgColor
            CATransaction.commit()
        }
    }

    @objc private func showMenu() {
        guard isEnabled, !choices.isEmpty, !menuOpen else { return }
        hovering = false
        menuOpen = true
        refreshHover()
        defer { menuOpen = false; refreshHover(animated: true) }

        let menu = NSMenu()
        menu.autoenablesItems = false
        for choice in choices {
            let item = NSMenuItem(title: choice, action: #selector(selectItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice
            item.state = choice == selection ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items.first(where: { ($0.representedObject as? String) == selection }),
                   at: NSPoint(x: 0, y: -4), in: self)
    }

    @objc private func selectItem(_ sender: NSMenuItem) {
        guard isEnabled, let value = sender.representedObject as? String, choices.contains(value) else { return }
        selection = value
        label.stringValue = value
        title = value
        setAccessibilityValue(value)
        invalidateIntrinsicContentSize()
        onSelect?(value)
    }
}


@MainActor
private final class ProviderMenuContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
