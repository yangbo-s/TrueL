import Foundation
import Testing
@testable import TrueL

@MainActor
struct CorrectionHoverTests {
    private func state() -> CorrectionHoverState {
        CorrectionHoverState(triggerExitDelay: .milliseconds(35), contentExitDelay: .milliseconds(25))
    }

    private func occurrence() -> CorrectionOccurrenceID {
        CorrectionOccurrenceID(correctionID: UUID(), paragraphIndex: 0, tokenIndex: 0)
    }

    @Test func enteringCorrectionOpensWithoutTooltipDelay() {
        let subject = state()
        let id = occurrence()
        subject.triggerHover(id, inside: true)
        #expect(subject.activeID == id)
    }

    @Test func crossingIntoExplanationSurvivesLateTriggerExit() async throws {
        let subject = state()
        let id = occurrence()
        subject.triggerHover(id, inside: true)
        subject.contentHover(id, inside: true)
        subject.triggerHover(id, inside: false)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == id)
        subject.contentHover(id, inside: false)
        #expect(subject.activeID == id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(subject.activeID == nil)
    }

    @Test func reentryCancelsPendingHide() async throws {
        let subject = state()
        let id = occurrence()
        subject.triggerHover(id, inside: true)
        subject.triggerHover(id, inside: false)
        try await Task.sleep(for: .milliseconds(10))
        subject.triggerHover(id, inside: true)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == id)
    }

    @Test func dismissedExplanationCannotBeClosedByOldTimerAfterReopening() async throws {
        let subject = state()
        let id = occurrence()
        subject.triggerHover(id, inside: true)
        subject.triggerHover(id, inside: false)
        subject.dismiss()
        subject.present(id)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == id)
        subject.dismiss()
        #expect(subject.activeID == nil)
    }

    @Test func movingBetweenWordsKeepsOnlyLatestExplanation() async throws {
        let subject = state()
        let first = occurrence(), second = occurrence()
        subject.triggerHover(first, inside: true)
        subject.triggerHover(first, inside: false)
        subject.triggerHover(second, inside: true)
        // Both the late exit and NSPopover dismissal of A can arrive after B opens.
        subject.contentHover(first, inside: false)
        subject.dismiss(first)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == second)
        subject.contentHover(second, inside: true)
        subject.triggerHover(second, inside: false)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == second)
    }

    @Test func clickKeepsHoveredExplanationOpen() {
        let subject = state()
        let id = occurrence()
        subject.triggerHover(id, inside: true)
        subject.present(id)
        #expect(subject.activeID == id)
    }

    @Test(arguments: [(0, 1), (1, 0)])
    func repeatedCorrectionKeepsOnlyLatestOccurrence(paragraphIndex: Int, tokenIndex: Int) async throws {
        let subject = state()
        let correctionID = UUID()
        let first = CorrectionOccurrenceID(correctionID: correctionID, paragraphIndex: 0, tokenIndex: 0)
        let second = CorrectionOccurrenceID(correctionID: correctionID,
                                            paragraphIndex: paragraphIndex, tokenIndex: tokenIndex)
        subject.triggerHover(first, inside: true)
        subject.triggerHover(first, inside: false)
        subject.triggerHover(second, inside: true)
        // Repeated words share correction data, but their popovers and late events must stay distinct.
        subject.contentHover(first, inside: false)
        subject.dismiss(first)
        #expect(subject.activeID == second)
        #expect(subject.activeID != first)
        try await Task.sleep(for: .milliseconds(60))
        #expect(subject.activeID == second)
        subject.triggerHover(second, inside: false)
        // Wait for the observable outcome: AppKit window tests can occupy the
        // main actor before the delayed task gets its first scheduling turn.
        let deadline = ContinuousClock.now + .seconds(1)
        while subject.activeID != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(subject.activeID == nil)
    }

}
