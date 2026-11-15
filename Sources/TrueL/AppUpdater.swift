import AppKit
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(enabled: Bool) {
        // Snapshot and test launches never initialize a network updater or its preferences.
        guard enabled else { controller = nil; return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        observations = [
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
            },
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                let value = change.newValue ?? false
                Task { @MainActor [weak self] in self?.automaticallyChecksForUpdates = value }
            }
        ]
    }

    func start() { controller?.startUpdater() }
    func checkForUpdates() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? false
    }
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "检查更新…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        item.isEnabled = controller != nil
        return item
    }
}
