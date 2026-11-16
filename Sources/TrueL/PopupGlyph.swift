import SwiftUI

/// Shared SF Symbols renderer for toolbar, inline and settings pictograms.
struct PopupGlyph: View {
    enum Kind: String, CaseIterable, Sendable {
        case pin = "pin"
        case pinFilled = "pin.fill"
        case grammar = "text.badge.checkmark"
        case translation = "character.bubble"
        case enter = "return"
        case copy = "doc.on.doc"
        case swap = "arrow.left.arrow.right"
        case settings = "slider.horizontal.3"
        case clipboard = "doc.on.clipboard"
        case stop = "stop.fill"
        case eye = "eye"
        case eyeSlash = "eye.slash"
        case close = "xmark"
        case info = "info.circle"
        case check = "checkmark"
        case checkCircleFilled = "checkmark.circle.fill"
    }

    private let symbol: String
    var size: CGFloat = TypeScale.toolSymbol

    init(_ kind: Kind, size: CGFloat = TypeScale.toolSymbol) {
        self.symbol = kind.rawValue
        self.size = size
    }

    init(symbol: String, size: CGFloat = TypeScale.inlineSymbol) {
        self.symbol = symbol
        self.size = size
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
    }
}
