import AppKit

enum AppIconStyle: String, CaseIterable, Identifiable {
    case compactLigature = "1A"
    case openLigature = "1B"
    case literaryLigature = "1C"
    case compactQuotes = "3A"
    case balancedQuotes = "3B"
    case flowingQuotes = "3C"

    static let defaultStyle = Self.compactQuotes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compactLigature: "紧凑联字"
        case .openLigature: "舒展联字"
        case .literaryLigature: "书卷联字"
        case .compactQuotes: "紧凑句读"
        case .balancedQuotes: "平衡句读"
        case .flowingQuotes: "流动句读"
        }
    }
}

@MainActor
enum AppIconAssets {
    private static var previews: [AppIconStyle: NSImage] = [:]

    static func image(for style: AppIconStyle, preview: Bool = false,
                      resourceURL: URL? = Bundle.main.resourceURL) -> NSImage? {
        guard let resourceURL else { return nil }
        let file = style.rawValue + (preview ? "-preview" : "") + ".png"
        guard let image = NSImage(contentsOf: resourceURL.appendingPathComponent("AppIcons").appendingPathComponent(file)),
              image.isValid else { return nil }
        return image
    }

    static func preview(for style: AppIconStyle) -> NSImage? {
        if let image = previews[style] { return image }
        let image = image(for: style, preview: true)
        previews[style] = image
        return image
    }
}

/// The bundle remains immutable; only the running application's Dock tile changes.
@MainActor
final class AppIconController {
    private let loadImage: (AppIconStyle) -> NSImage?
    private let setImage: (NSImage?) -> Void
    private(set) var appliedStyle: AppIconStyle?

    init(loadImage: @escaping (AppIconStyle) -> NSImage? = { AppIconAssets.image(for: $0) },
         setImage: @escaping (NSImage?) -> Void = { NSApp.applicationIconImage = $0 }) {
        self.loadImage = loadImage
        self.setImage = setImage
    }

    @discardableResult
    func apply(_ style: AppIconStyle) -> AppIconStyle {
        guard style != appliedStyle else { return style }
        if style == .defaultStyle {
            setImage(nil)
            appliedStyle = .defaultStyle
            return .defaultStyle
        }
        guard let image = loadImage(style), image.isValid else {
            setImage(nil)
            appliedStyle = .defaultStyle
            return .defaultStyle
        }
        setImage(image)
        appliedStyle = style
        return style
    }
}
