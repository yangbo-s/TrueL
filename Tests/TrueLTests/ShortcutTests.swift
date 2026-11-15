import AppKit
import Testing
@testable import TrueL

@MainActor
struct ShortcutTests {
    private func stroke(_ code: UInt16, _ modifiers: ShortcutModifiers = .command) -> ShortcutStroke {
        .init(keyCode: code, modifiers: modifiers)
    }

    @Test func defaultGlobalChordsLeaveCommonBrowserTabShortcutsAvailable() {
        let defaults = ShortcutBinding.defaults
        #expect(defaults[.selectionTranslation]?.strokes == [stroke(8), stroke(8)])
        for action in ShortcutAction.allCases where action != .selectionTranslation {
            #expect(defaults[action]?.strokes.first?.modifiers == [.control, .option, .command])
        }
        // Defaults avoid common chords, but an intentional user choice remains supported.
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        #expect(store.setBinding(.init(strokes: [stroke(18)]), for: .clipboardTranslation))
    }

    @Test func customNonCopySequencesCannotEnableClipboardFallback() {
        #expect(ShortcutBinding.defaults[.selectionTranslation]?.startsWithNativeCopy == true)
        #expect(!ShortcutBinding(strokes: [stroke(18, .control), stroke(19, .control)]).startsWithNativeCopy)
        #expect(!ShortcutBinding(strokes: [stroke(8, .control), stroke(8, .control)]).startsWithNativeCopy)
        #expect(!ShortcutBinding(strokes: [stroke(8, [.command, .shift]), stroke(8, [.command, .shift])]).startsWithNativeCopy)
        #expect(ShortcutBinding(strokes: [stroke(8), stroke(17)]).startsWithNativeCopy)
    }

    @Test func repeatedCopyRequiresTwoSeparateKeyDowns() {
        var matcher = ShortcutSequenceMatcher(bindings: [.selectionTranslation: .init(strokes: [stroke(8), stroke(8)])])
        #expect(matcher.process(stroke(8), timestamp: 10) == nil)
        #expect(matcher.process(stroke(8), timestamp: 10.1, isRepeat: true) == nil)
        #expect(matcher.process(stroke(8), timestamp: 10.3) == .selectionTranslation)
        #expect(matcher.process(stroke(8), timestamp: 10.4) == nil)
    }

    @Test func copySequenceCannotSpanTwoSourceApplications() {
        var matcher = ShortcutSequenceMatcher(bindings: [.selectionTranslation: .init(strokes: [stroke(8), stroke(8)])])
        #expect(matcher.process(stroke(8), timestamp: 10, sourcePID: 101) == nil)
        #expect(matcher.sourcePID == 101)
        #expect(matcher.process(stroke(8), timestamp: 10.2, sourcePID: 202) == nil)
        #expect(matcher.sourcePID == 202)
        #expect(matcher.process(stroke(8), timestamp: 10.4, sourcePID: 202) == .selectionTranslation)
        #expect(matcher.sourcePID == nil)
    }

    @Test func sourceChangeDiscardsProgressBeforeClipboardMetadataIsRead() {
        var matcher = ShortcutSequenceMatcher(bindings: [.selectionTranslation: .init(strokes: [stroke(8), stroke(8)])])
        #expect(matcher.process(stroke(8), timestamp: 20, sourcePID: 101) == nil)
        #expect(matcher.isInProgress(for: .selectionTranslation))
        matcher.prepareForEvent(at: 20.2, sourcePID: 202)
        #expect(!matcher.isInProgress(for: .selectionTranslation))
        #expect(matcher.sourcePID == nil)
        // Returning to the first app must start again rather than finish its old copy.
        #expect(matcher.process(stroke(8), timestamp: 20.4, sourcePID: 101) == nil)
        #expect(matcher.process(stroke(8), timestamp: 20.6, sourcePID: 101) == .selectionTranslation)
    }

    @Test func sequencesSupportControlAndDifferentOrdinaryKeys() {
        let sequence = [stroke(18, .control), stroke(19, .control)]
        var matcher = ShortcutSequenceMatcher(bindings: [.selectionTranslation: .init(strokes: sequence)])
        #expect(matcher.process(stroke(18, .control), timestamp: 0) == nil)
        #expect(matcher.process(stroke(19, .command), timestamp: 0.1) == nil)
        #expect(matcher.process(stroke(18, .control), timestamp: 0.2) == nil)
        #expect(matcher.process(stroke(19, .control), timestamp: 0.4) == .selectionTranslation)
    }

    @Test func timeoutAndUnrelatedKeysCannotCompleteAStaleSequence() {
        var matcher = ShortcutSequenceMatcher(bindings: [.selectionTranslation: .init(strokes: [stroke(8), stroke(8)])])
        #expect(matcher.process(stroke(8), timestamp: 2) == nil)
        #expect(matcher.process(stroke(8), timestamp: 3.1) == nil)
        #expect(matcher.process(stroke(0, []), timestamp: 3.2) == nil)
        #expect(matcher.process(stroke(8), timestamp: 3.3) == nil)
        #expect(matcher.process(stroke(8), timestamp: 3.5) == .selectionTranslation)
        matcher.reset()
        #expect(matcher.process(stroke(8), timestamp: 3.6) == nil)
    }

    @Test func shorterAndLongerPrefixesAreRejectedWithoutOverwritingBindings() {
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let original = store.bindings[.grammar]
        #expect(!store.setBinding(.init(strokes: [stroke(8)]), for: .grammar))
        #expect(store.bindings[.grammar] == original)
        #expect(store.recordingError?.contains("前缀") == true)
        #expect(!store.setBinding(.init(strokes: [stroke(8), stroke(8), stroke(8)]), for: .grammar))
        #expect(!store.setBinding(.init(strokes: [stroke(8), stroke(8)]), for: .grammar))
    }

    @Test func recorderRetainsExactModifiersAndDoesNotSaveUntilCommitted() {
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let original = store.bindings[.selectionTranslation]
        store.beginRecording(action: .selectionTranslation)
        store.record(stroke(8, .control), timestamp: 0)
        store.record(stroke(8, .control), timestamp: 0.1, isRepeat: true)
        store.record(stroke(8, .control), timestamp: 0.2)
        #expect(store.recordingStrokes.count == 2)
        #expect(store.bindings[.selectionTranslation] == original)
        #expect(store.commitRecording())
        #expect(!store.isRecording)
        #expect(store.bindings[.selectionTranslation]?.strokes == [stroke(8, .control), stroke(8, .control)])
    }

    @Test(arguments: [ShortcutModifiers.command, .control])
    func recorderIgnoresOtherAppsInjectedKeysButRetainsRealRepeatedPresses(_ modifiers: ShortcutModifiers) {
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let key = stroke(8, modifiers)
        store.beginRecording(action: .selectionTranslation)
        store.record(key, timestamp: 10, sourcePID: 101)
        store.record(key, timestamp: 10.2, sourcePID: 101)
        // Another translator can inject its own copy after seeing a double copy.
        // It is a new event, not autorepeat or a duplicate timestamp.
        store.record(key, timestamp: 10.227, sourcePID: 202)
        #expect(store.recordingStrokes == [key, key])
        // A distinct event must count, even with a very short interval.
        store.record(key, timestamp: 10.228, sourcePID: 101)
        #expect(store.recordingStrokes == [key, key, key])
        #expect(store.commitRecording())
        #expect(store.bindings[.selectionTranslation]?.strokes == [key, key, key])
        store.beginRecording(action: .selectionTranslation)
        store.record(key, timestamp: 11, sourcePID: 202)
        #expect(store.recordingStrokes == [key])
    }

    @Test func recordingTimeoutStartsANewSequenceAndEscapeCancels() {
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let original = store.bindings[.selectionTranslation]
        store.beginRecording(action: .selectionTranslation)
        store.record(stroke(18, .control), timestamp: 0)
        store.record(stroke(19, .control), timestamp: 1.1)
        #expect(store.recordingStrokes == [stroke(19, .control)])
        store.record(stroke(53, []), timestamp: 1.2)
        #expect(!store.isRecording)
        #expect(store.bindings[.selectionTranslation] == original)
    }

    @Test func arbitraryKeyCodesAndLongSequencesAreNotRestrictedToLetterMenus() {
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let steps = (UInt16(70)...UInt16(90)).map { stroke($0, [.control, .option, .shift]) }
        #expect(store.setBinding(.init(strokes: steps), for: .selectionTranslation))
        #expect(store.bindings[.selectionTranslation]?.strokes.count == 21)
        #expect(!store.setBinding(.init(strokes: [stroke(8, [])]), for: .selectionTranslation))
    }

    @Test func bindingsAndClearedActionsSurviveStoreRecreation() throws {
        let suite = "TrueL.ShortcutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
        let binding = ShortcutBinding(strokes: [stroke(18, .control), stroke(19, .control)])
        #expect(first.setBinding(binding, for: .selectionTranslation))
        first.clearBinding(for: .translation)
        let second = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
        #expect(second.bindings[.selectionTranslation] == binding)
        #expect(second.bindings[.translation] == nil)
        #expect(!second.isRecording)
        #expect(second.recordingStrokes.isEmpty)
    }

    @Test func modifierNormalizationIgnoresCapsLockAndNumericPad() {
        let value = ShortcutModifiers([.control, .command, .capsLock, .numericPad])
        #expect(value == [.control, .command])
    }

    @Test func legacyQuickBindingMigratesOnceAndCanStillBeCleared() throws {
        let suite = "TrueL.ShortcutMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldSelection = ShortcutBinding(strokes: [stroke(17, [.control, .option, .command])])
        let customCopy = ShortcutBinding(strokes: [stroke(8, .control), stroke(8, .control)])
        let oldData = try JSONEncoder().encode([
            "quickTranslation": customCopy, "selectionTranslation": oldSelection,
            "grammar": ShortcutBinding.defaults[.grammar]!
        ])
        defaults.set(oldData, forKey: "TrueL.shortcuts.v1")

        let store = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
        #expect(store.bindings[.selectionTranslation] == customCopy)
        #expect(store.bindings[.translation] == nil)
        #expect(defaults.data(forKey: "TrueL.shortcuts.v1") == oldData)
        let migrated = try JSONDecoder().decode([String: ShortcutBinding].self,
                                               from: #require(defaults.data(forKey: "TrueL.shortcuts.v2")))
        #expect(migrated["quickTranslation"] == nil)
        #expect(migrated["selectionTranslation"] == customCopy)

        store.clearBinding(for: .selectionTranslation)
        let reloaded = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
        #expect(reloaded.bindings[.selectionTranslation] == nil)
        #expect(reloaded.bindings[.grammar] == store.bindings[.grammar])
    }

    @Test func migrationKeepsCustomSelectionAndDisabledActions() throws {
        let suite = "TrueL.ShortcutMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let selection = ShortcutBinding(strokes: [stroke(18, .control), stroke(19, .control)])
        let copy = ShortcutBinding(strokes: [stroke(8), stroke(8)])
        defaults.set(try JSONEncoder().encode(["selectionTranslation": selection, "quickTranslation": copy]),
                     forKey: "TrueL.shortcuts.v1")
        let store = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
        #expect(store.bindings == [.selectionTranslation: selection])

        defaults.removeObject(forKey: "TrueL.shortcuts.v2")
        defaults.set(try JSONEncoder().encode([String: ShortcutBinding]()), forKey: "TrueL.shortcuts.v1")
        #expect(ShortcutStore(defaults: defaults, captureKeyboardEvents: false).bindings.isEmpty)
    }

    @Test func migrationRejectsInvalidOrConflictingQuickBinding() throws {
        let suite = "TrueL.ShortcutMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldSelection = ShortcutBinding(strokes: [stroke(17, [.control, .option, .command])])
        let grammar = try #require(ShortcutBinding.defaults[.grammar])
        for rejected in [ShortcutBinding(strokes: [stroke(8, [])]), grammar] {
            defaults.removeObject(forKey: "TrueL.shortcuts.v2")
            defaults.set(try JSONEncoder().encode([
                "quickTranslation": rejected, "selectionTranslation": oldSelection, "grammar": grammar
            ]), forKey: "TrueL.shortcuts.v1")
            let store = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
            #expect(store.bindings[.selectionTranslation] == oldSelection)
            #expect(store.bindings[.grammar] == grammar)
        }
    }

    @Test func migrationPreservesEachLegacyBindingWhenTheOtherWasDisabled() throws {
        let suite = "TrueL.ShortcutMigrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let oldSelection = ShortcutBinding(strokes: [stroke(17, [.control, .option, .command])])
        let copy = ShortcutBinding(strokes: [stroke(8), stroke(8)])
        for (name, binding) in [("selectionTranslation", oldSelection), ("quickTranslation", copy)] {
            defaults.removeObject(forKey: "TrueL.shortcuts.v2")
            defaults.set(try JSONEncoder().encode([name: binding]), forKey: "TrueL.shortcuts.v1")
            let store = ShortcutStore(defaults: defaults, captureKeyboardEvents: false)
            #expect(store.bindings == [.selectionTranslation: binding])
        }
    }

    @Test func permissionPreviewDoesNotBecomeGrantedAfterRefresh() {
        let permissions = SystemPermissions(accessibilityGranted: false, inputMonitoringGranted: false)
        permissions.refresh()
        #expect(!permissions.accessibilityGranted)
        #expect(!permissions.inputMonitoringGranted)
    }
}
