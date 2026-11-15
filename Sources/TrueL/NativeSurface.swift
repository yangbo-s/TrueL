import AppKit
import SwiftUI

/// Keeps the popup's backdrop outside SwiftUI so the system material samples
/// behind the window before the tint and hosted content are composited.
@MainActor
final class NativePanelSurface<Content: View>: NSView {
    let hostingView: NSHostingView<Content>
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()

    override var isOpaque: Bool { false }

    init(rootView: Content, cornerRadius: CGFloat = SurfaceMetrics.windowRadius) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        materialView.material = .hudWindow
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        tintView.wantsLayer = true
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        for view in [materialView, tintView, hostingView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        updateTint()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds
        tintView.frame = bounds
        hostingView.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateTint()
    }

    private func updateTint() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        tintView.layer?.backgroundColor = Theme.panelTint(appearance: effectiveAppearance, opaque: opaque).cgColor
    }

    @objc private func accessibilityOptionsChanged() { updateTint() }
}

/// Place in an empty header area, never over buttons or an editor. NSHostingView
/// consumes background mouse handling, so this region starts AppKit's drag loop.
struct WindowDragRegion: NSViewRepresentable {
    var identifier = "TrueL.windowDragRegion"

    func makeNSView(context: Context) -> WindowDragView {
        let view = WindowDragView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        view.setAccessibilityIdentifier(identifier)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("拖动窗口")
        return view
    }

    func updateNSView(_ nsView: WindowDragView, context: Context) {
        nsView.identifier = NSUserInterfaceItemIdentifier(identifier)
        nsView.setAccessibilityIdentifier(identifier)
    }
}

@MainActor
final class WindowDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
