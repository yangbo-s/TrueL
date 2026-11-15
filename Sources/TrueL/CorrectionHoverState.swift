import Foundation
import Observation

struct CorrectionOccurrenceID: Hashable, Sendable {
    let correctionID: UUID
    let paragraphIndex: Int
    let tokenIndex: Int
}

/// The correction and its explanation share one hover region with a small crossing allowance.
@MainActor
@Observable
final class CorrectionHoverState {
    private(set) var activeID: CorrectionOccurrenceID?
    private var triggerID: CorrectionOccurrenceID?
    private var contentID: CorrectionOccurrenceID?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let triggerExitDelay: Duration
    @ObservationIgnored private let contentExitDelay: Duration

    init(triggerExitDelay: Duration = .milliseconds(350), contentExitDelay: Duration = .milliseconds(250)) {
        self.triggerExitDelay = triggerExitDelay
        self.contentExitDelay = contentExitDelay
    }

    func triggerHover(_ id: CorrectionOccurrenceID, inside: Bool) {
        if inside {
            cancelHide()
            if activeID != id { contentID = nil }
            triggerID = id
            activeID = id
        } else {
            if triggerID == id { triggerID = nil }
            scheduleHide(for: id, after: triggerExitDelay)
        }
    }

    func contentHover(_ id: CorrectionOccurrenceID, inside: Bool) {
        guard activeID == id else { return }
        if inside { contentID = id; cancelHide() }
        else {
            if contentID == id { contentID = nil }
            scheduleHide(for: id, after: contentExitDelay)
        }
    }

    func present(_ id: CorrectionOccurrenceID) {
        cancelHide()
        if activeID != id { contentID = nil }
        activeID = id
    }

    func dismiss(_ id: CorrectionOccurrenceID? = nil) {
        // A dismissed old NSPopover must not clear the word that replaced it.
        if let id, activeID != id { return }
        cancelHide()
        triggerID = nil
        contentID = nil
        activeID = nil
    }

    private func cancelHide() {
        revision += 1
        hideTask?.cancel()
        hideTask = nil
    }

    private func scheduleHide(for id: CorrectionOccurrenceID, after delay: Duration) {
        guard activeID == id else { return }
        cancelHide()
        guard triggerID != id, contentID != id else { return }
        let expected = revision
        hideTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.revision == expected, self.activeID == id, self.triggerID != id, self.contentID != id else { return }
            self.activeID = nil
            self.hideTask = nil
        }
    }
}
