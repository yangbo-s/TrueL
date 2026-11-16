import AppKit
import SwiftUI

/// Languages and styles share the exact renderer used by model and settings menus.
struct NativeProviderMenu: NSViewRepresentable {
    @Binding var selection: String
    let choices: [String]
    let accessibilityLabel: String
    var displayTitle: String? = nil
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String { displayTitle ?? selection }
    func makeNSView(context: Context) -> SettingsMenuButton {
        SettingsMenuButton(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width(for: title), height: SurfaceMetrics.controlHeight))
    }
    func updateNSView(_ view: SettingsMenuButton, context: Context) {
        view.compact = true
        view.title = title
        view.selection = selection
        view.choices = choices.map { SettingsMenuChoice(value: $0, title: $0) }
        view.isEnabled = isEnabled && !choices.isEmpty
        view.reduceMotion = reduceMotion
        view.onSelect = { selection = $0 }
        view.toolTip = title
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityValue(title)
        view.refreshPalette(animated: false)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsMenuButton, context: Context) -> CGSize? {
        CGSize(width: MenuMetrics.width(for: title), height: SurfaceMetrics.controlHeight)
    }
}
