import AppKit
import Observation

enum PopupPresentation: String, Sendable {
    case workspace, quick

    var minimumWidth: CGFloat { self == .workspace ? 736 : PopupLayout.compactWidth }
    var initialSize: NSSize {
        self == .workspace ? NSSize(width: 840, height: 400) : NSSize(width: PopupLayout.compactWidth, height: 320)
    }
    var minimumHeight: CGFloat { self == .workspace ? 360 : PopupLayout.baseHeight }
}

enum PopupFocus { case result, source, followUp }
enum PopupReturnAction { case submit, replace, refine, none }

/// Button emphasis and keyboard dispatch read the same state; an empty focused
/// follow-up must never fall through to a destructive replacement.
@MainActor @Observable
final class PopupSession {
    var presentation: PopupPresentation = .workspace
    var focus: PopupFocus = .result

    func returnAction(model: DemoModel) -> PopupReturnAction {
        if model.isProcessing { return .none }
        if focus == .followUp { return .refine }
        if presentation == .workspace { return .submit }
        return model.hasResult ? .replace : .submit
    }

    func canPerform(_ action: PopupReturnAction, model: DemoModel, selection: SelectionReplacementContext) -> Bool {
        guard !model.isProcessing else { return false }
        switch action {
        case .submit: return !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .replace: return model.hasResult && selection.canReplaceSelection
        case .refine: return model.hasResult && !model.followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .none: return false
        }
    }
}
