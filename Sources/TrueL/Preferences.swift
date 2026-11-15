import Foundation
import Observation

@MainActor
@Observable
final class Preferences {
    static let supportedLanguages = ["简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español"]
    var appearance: String { didSet { save() } }
    var language: String { didSet { save() } }
    var writingScene: String { didSet { save() } }
    var alwaysOnTop: Bool { didSet { save() } }
    var appIcon: AppIconStyle { didSet { save() } }

    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(persist: Bool = true, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.defaults = defaults
        appearance = persist ? defaults.string(forKey: "TrueL.appearance") ?? "system" : "system"
        language = persist ? defaults.string(forKey: "TrueL.language") ?? "简体中文" : "简体中文"
        writingScene = persist ? defaults.string(forKey: "TrueL.writingScene") ?? "standard" : "standard"
        alwaysOnTop = persist ? defaults.object(forKey: "TrueL.alwaysOnTop") as? Bool ?? false : false
        appIcon = persist ? defaults.string(forKey: "TrueL.appIcon").flatMap(AppIconStyle.init(rawValue:)) ?? .defaultStyle : .defaultStyle
    }

    func save() {
        guard persist else { return }
        defaults.set(appearance, forKey: "TrueL.appearance")
        defaults.set(language, forKey: "TrueL.language")
        defaults.set(writingScene, forKey: "TrueL.writingScene")
        defaults.set(alwaysOnTop, forKey: "TrueL.alwaysOnTop")
        defaults.set(appIcon.rawValue, forKey: "TrueL.appIcon")
    }
}
