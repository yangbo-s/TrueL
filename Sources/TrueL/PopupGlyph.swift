import SwiftUI

/// All pictograms are supplied by macOS. No recovered paths or bundled icon assets.
struct PopupGlyph: View {
    enum Kind: String, CaseIterable, Sendable {
        case pin = "pin"
        case pinFilled = "pin.fill"
        case grammar = "text.badge.checkmark"
        case translation = "character.bubble"
        case enter = "return"
        case copy = "doc.on.doc"
        case check = "checkmark"
        case checkCircleFilled = "checkmark.circle.fill"
    }

    let kind: Kind
    var size: CGFloat = TypeScale.toolSymbol

    init(_ kind: Kind, size: CGFloat = TypeScale.toolSymbol) {
        self.kind = kind
        self.size = size
    }

    var body: some View {
        Image(systemName: kind.rawValue)
            .font(.system(size: size, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .frame(width: size + 2, height: size + 2)
            .accessibilityHidden(true)
    }
}
