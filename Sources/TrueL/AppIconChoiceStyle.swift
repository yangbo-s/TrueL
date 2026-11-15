import SwiftUI

struct AppIconChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration, selected: selected)
    }

    private struct Content: View {
        let configuration: Configuration
        let selected: Bool
        @SwiftUI.State private var hovered = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(.system(size: TypeScale.control, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                .padding(SurfaceMetrics.inset)
                .background(configuration.isPressed ? Theme.popupPressed : selected ? Theme.selection : hovered ? Theme.popupHover : .clear,
                            in: RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius)
                        .strokeBorder(focused || selected ? Theme.accent : .clear, lineWidth: focused ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius))
                .panelHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
        }
    }
}
