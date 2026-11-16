import AppKit
import SwiftUI

// Relationships, not per-view guesses: windows contain islands; islands contain controls.
enum SurfaceMetrics {
    static let windowRadius: CGFloat = 24
    static let islandRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let embeddedRadius: CGFloat = 4
    static let edge: CGFloat = 12
    static let islandGap: CGFloat = 8
    static let inset: CGFloat = 12
    static let rowGap: CGFloat = 8
    static let relatedGap: CGFloat = 8
    static let controlHeight: CGFloat = 28
    static let embeddedSize: CGFloat = 20
}

enum TypeScale {
    static let control: CGFloat = 12
    static let value: CGFloat = 13
    static let body: CGFloat = 14
    static let toolSymbol: CGFloat = 13
    static let inlineSymbol: CGFloat = 12
    static let accessory: CGFloat = 8
}

@MainActor
enum BodyTextStyle {
    static let lineHeight: CGFloat = 22
    static var font: NSFont { .systemFont(ofSize: TypeScale.body) }
    static var paragraph: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(0, lineHeight - NSLayoutManager().defaultLineHeight(for: font))
        style.lineBreakMode = .byWordWrapping
        return style
    }
}

enum WindowChromeMetrics {
    static let height: CGFloat = 52
    static let contentGap: CGFloat = 0
    static let trafficLightFirstCenter: CGFloat = 20
    static let trafficLightPitch: CGFloat = 20
}

// Geometry is shared by the AppKit window and its SwiftUI content.
enum PopupLayout {
    static let compactWidth: CGFloat = 464
    static let wideWidth: CGFloat = 760
    static let baseHeight: CGFloat = 256
    static let textInset: CGFloat = SurfaceMetrics.inset
    static let iconButtonSize: CGFloat = SurfaceMetrics.controlHeight
    static let controlHeight: CGFloat = SurfaceMetrics.controlHeight
    static let resultHeaderHeight: CGFloat = 48
    static let followUpHeight: CGFloat = 48
}

enum SettingsLayout {
    static let width: CGFloat = 544
    static let height: CGFloat = 384
}

@MainActor
enum Theme {
    static var accent: Color { adaptive(0x176d62, 0xa9ddce) }
    static var onAccent: Color { adaptive(0xffffff, 0x12352e) }
    static var text: Color { adaptive(0x242724, 0xeeefed) }
    static var secondary: Color { adaptive(0x59605b, 0xe0e5e1) }
    static var hairline: Color { adaptive(0x263b30, 0xe0ede5).opacity(0.12) }
    static var surface: Color { adaptive(0xffffff, 0x2c3430).opacity(0.5) }
    static var hover: Color { adaptive(0x243d31, 0xc8e7d7).opacity(0.06) }
    static var popupHover: Color { adaptive(0x243d31, 0xc8e7d7).opacity(0.09) }
    static var popupPressed: Color { adaptive(0x243d31, 0x243d31).opacity(0.15) }
    static var selection: Color { accent.opacity(0.1) }
    static var toggleOn: Color { accent }
    static var success: Color { adaptive(0x226b4c, 0x9cd8b9) }
    static var error: Color { adaptive(0xa23932, 0xffcec5) }
    static var resultText: Color { text }
    static var resultSecondary: Color { secondary }
    static var resultBorder: Color { hairline }
    static var resultGreen: Color { success }
    static var resultBlue: Color { accent }
    static var resultSuccess: Color { success }
    static var originalText: Color { error }
    static var originalBackground: Color { error.opacity(0.09) }
    static var replacementText: Color { accent }
    static var replacementBackground: Color { accent.opacity(0.1) }
    static var correctionBackground: Color { accent.opacity(0.1) }
    static var correctionHover: Color { accent.opacity(0.18) }
    static var tip: Color { hover }
    static var controlSurface: Color { adaptive(0xffffff, 0xe9f2ec).opacity(0.1) }
    static var editorSurface: Color { adaptive(0xffffff, 0x202421).opacity(0.42) }
    static var readingSurface: Color { adaptive(0xffffff, 0x202421).opacity(0.18) }
    static var island: Color { adaptive(0xffffff, 0x242a27).opacity(0.46) }
    static var field: Color { adaptive(0xffffff, 0x131b16).opacity(0.24) }
    static var panel: Color { Color(nsColor: panelTint()) }

    static func panelTint(appearance: NSAppearance? = nil, opaque: Bool = false) -> NSColor {
        let isDark = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return nsColor(isDark ? 0x242724 : 0xf1f2ef, alpha: opaque ? 1 : (isDark ? 0.52 : 0.28))
    }

    static func adaptive(_ light: Int, _ dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }

    nonisolated private static func nsColor(_ value: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                green: Double((value >> 8) & 255) / 255,
                blue: Double(value & 255) / 255, alpha: alpha)
    }
}

struct TrueLWordmark: View {
    var size: CGFloat = 14
    var body: some View {
        Text("\(Text("True").foregroundColor(Theme.text))\(Text("L").foregroundColor(Theme.accent))")
            .font(.system(size: size, weight: .semibold))
            .accessibilityLabel("TrueL")
    }
}

/// The native traffic lights occupy the left slot; title and tools share their centre line.
struct WindowChrome<Trailing: View>: View {
    var title: String? = nil
    var dragIdentifier = "TrueL.windowDragRegion"
    @ViewBuilder var trailing: Trailing
    var body: some View {
        ZStack {
            WindowDragRegion(identifier: dragIdentifier)
                .padding(.leading, 80).padding(.trailing, 104)
            Group {
                if let title { Text(title).font(.system(size: TypeScale.value, weight: .medium)).foregroundStyle(Theme.text) }
                else { TrueLWordmark(size: TypeScale.value) }
            }
            .allowsHitTesting(false)
            HStack(spacing: 0) {
                Spacer(minLength: 80)
                trailing
            }
            .padding(.trailing, SurfaceMetrics.edge)
        }
        .frame(height: WindowChromeMetrics.height)
    }
}

enum TrueLControlRole: Equatable { case primary, secondary, tertiary }

/// All action roles use the same silhouette, typography and state timing.
struct TrueLButtonStyle: ButtonStyle {
    var role: TrueLControlRole = .secondary
    var iconOnly = false
    var embedded = false
    var joinsPreviousControl = false
    var joinsNextControl = false
    func makeBody(configuration: Configuration) -> some View {
        StyledContent(configuration: configuration, role: role, iconOnly: iconOnly,
                      embedded: embedded, joinsPreviousControl: joinsPreviousControl,
                      joinsNextControl: joinsNextControl)
    }
    private struct StyledContent: View {
        let configuration: Configuration
        let role: TrueLControlRole
        let iconOnly: Bool
        let embedded: Bool
        let joinsPreviousControl: Bool
        let joinsNextControl: Bool
        @SwiftUI.State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private var height: CGFloat { embedded ? SurfaceMetrics.embeddedSize : SurfaceMetrics.controlHeight }
        private var radius: CGFloat { embedded ? SurfaceMetrics.embeddedRadius : SurfaceMetrics.controlRadius }
        private var fill: Color {
            if enabled && role == .primary { return Theme.accent }
            if enabled && configuration.isPressed { return Theme.popupPressed }
            if enabled && hovered { return Theme.popupHover }
            return role == .tertiary ? .clear : Theme.controlSurface
        }
        var body: some View {
            configuration.label
                .font(.system(size: TypeScale.control, weight: .medium))
                .foregroundStyle(enabled && role == .primary ? Theme.onAccent : role == .tertiary ? Theme.secondary : Theme.text)
                .padding(.leading, iconOnly ? 0 : embedded || joinsPreviousControl ? 4 : 12)
                .padding(.trailing, iconOnly ? 0 : embedded || joinsNextControl ? 4 : 12)
                .frame(width: iconOnly ? height : nil, height: height)
                .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(role == .secondary || role == .primary && !enabled ? Theme.hairline : .clear, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).inset(by: -3)
                        .stroke(focused && enabled ? Theme.accent : .clear, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(role == .primary && enabled ? .black.opacity(configuration.isPressed ? 0.12 : hovered ? 0.06 : 0) : .clear)
                        .allowsHitTesting(false)
                }
                .opacity(enabled ? 1 : 0.45)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .panelHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
        }
    }
}

struct QuietIconStyle: ButtonStyle {
    var isIconOnly = true
    var embedded = false
    var joinsPreviousControl = false
    var joinsNextControl = false
    func makeBody(configuration: Configuration) -> some View {
        TrueLButtonStyle(role: .tertiary, iconOnly: isIconOnly,
                        embedded: embedded, joinsPreviousControl: joinsPreviousControl,
                        joinsNextControl: joinsNextControl)
            .makeBody(configuration: configuration)
    }
}

struct TrueLTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        StyledContent(configuration: configuration, selected: selected)
    }
    private struct StyledContent: View {
        let configuration: Configuration
        let selected: Bool
        @SwiftUI.State private var hovered = false
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .font(.system(size: TypeScale.control, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accent : Theme.secondary)
                .frame(height: SurfaceMetrics.controlHeight)
                .background(configuration.isPressed ? Theme.popupPressed : selected ? Theme.selection : hovered ? Theme.popupHover : .clear,
                            in: RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius))
                .overlay { RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius).stroke(focused ? Theme.accent : .clear, lineWidth: 2) }
                .contentShape(Rectangle())
                .panelHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        }
    }
}

struct TrueLIsland: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.island, in: RoundedRectangle(cornerRadius: SurfaceMetrics.islandRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SurfaceMetrics.islandRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false)
            }
    }
}

struct TrueLField: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        content
            .background(Theme.field, in: RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SurfaceMetrics.controlRadius, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.hairline, lineWidth: focused ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

struct TrueLInlineStatus: View {
    enum Tone { case neutral, success, error }
    let text: String
    var tone: Tone = .neutral
    var symbol: String = "info.circle"
    private var ink: Color {
        switch tone {
        case .neutral: Theme.secondary
        case .success: Theme.success
        case .error: Theme.error
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: SurfaceMetrics.relatedGap) {
            Image(systemName: symbol).foregroundStyle(ink)
                .frame(width: TypeScale.inlineSymbol, height: 16)
            Text(text).foregroundStyle(Theme.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: TypeScale.control)).lineSpacing(2)
        .accessibilityElement(children: .combine)
    }
}

struct WarmMaterial: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        MaterialView().overlay(Theme.panel)
            .overlay(reduceTransparency ? Theme.adaptive(0xf1f2ef, 0x242724) : .clear)
            .ignoresSafeArea().allowsHitTesting(false)
    }
}

private struct MaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
