import Foundation
import Testing
@testable import TrueL

@MainActor
struct PreferencesTests {
    @Test func newInstallDismissesOnBlurAndAnExplicitPinSurvivesRestart() {
        let name = "TrueL.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        #expect(!preferences.alwaysOnTop)
        preferences.alwaysOnTop = true
        #expect(Preferences(defaults: defaults).alwaysOnTop)
    }

    @Test func previewPreferencesDoNotChangePersistedChoices() {
        let name = "TrueL.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let saved = Preferences(defaults: defaults)
        saved.language = "日本語"
        saved.writingScene = "professional"
        let preview = Preferences(persist: false, defaults: defaults)
        preview.language = "English"
        preview.writingScene = "social"
        let restored = Preferences(defaults: defaults)
        #expect(restored.language == "日本語")
        #expect(restored.writingScene == "professional")
    }

    @Test func languageAndStyleSurviveRestartWithoutCredentials() {
        let name = "TrueL.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "English"
        preferences.writingScene = "social"
        preferences.alwaysOnTop = false
        let restored = Preferences(defaults: defaults)
        #expect(restored.language == "English")
        #expect(restored.writingScene == "social")
        #expect(!restored.alwaysOnTop)
        #expect(defaults.persistentDomain(forName: name)?.keys.contains(where: { $0.localizedCaseInsensitiveContains("key") }) == false)
    }
}
