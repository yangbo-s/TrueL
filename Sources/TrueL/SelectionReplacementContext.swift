import Foundation
import Observation

/// Associates an external selection with the editor revision that produced it.
/// The platform bridge still verifies the source application and range at use.
@MainActor
@Observable
final class SelectionReplacementContext {
    private struct Failure {
        let revision: UUID
        let message: String
    }

    private var failure: Failure?
    private var capturedRevision: UUID?
    private let model: DemoModel

    init(model: DemoModel) {
        self.model = model
    }

    var canReplaceSelection: Bool {
        capturedRevision == model.inputRevision
    }

    var replacementError: String? {
        get {
            guard failure?.revision == model.inputRevision else { return nil }
            return failure?.message
        }
        set {
            failure = newValue.map { Failure(revision: model.inputRevision, message: $0) }
        }
    }

    func bind(canReplace: Bool) {
        capturedRevision = canReplace ? model.inputRevision : nil
        replacementError = nil
    }

    func clear() {
        capturedRevision = nil
        replacementError = nil
    }

    func fail(_ message: String) {
        capturedRevision = nil
        replacementError = message
    }
}
