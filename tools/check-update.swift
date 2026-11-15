import AppKit
import Sparkle

// Read-only integration check using Sparkle's real parser and updater.
// The host is a disposable bundle whose build number controls the expected result.
@MainActor
final class UpdateProbe: NSObject, SPUUpdaterDelegate {
    let expectedVersion: String
    let expectsUpdate: Bool
    init(version: String, expectsUpdate: Bool) {
        expectedVersion = version
        self.expectsUpdate = expectsUpdate
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard expectsUpdate, item.versionString == expectedVersion else {
            fputs("FAIL unexpected available version \(item.versionString)\n", stderr); exit(1)
        }
        print("PASS Sparkle found signed update build \(item.versionString)")
        exit(0)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard !expectsUpdate else { fputs("FAIL expected update was not found\n", stderr); exit(1) }
        print("PASS Sparkle reports current version is up to date")
        exit(0)
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        fputs("FAIL Sparkle: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

@main
struct CheckUpdate {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 4,
              let bundle = Bundle(path: CommandLine.arguments[1]) else {
            fputs("Usage: check-update HOST_APP EXPECTED_BUILD available|current\n", stderr); exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = UpdateProbe(version: CommandLine.arguments[2], expectsUpdate: CommandLine.arguments[3] == "available")
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: probe)
        try updater.start()
        updater.checkForUpdateInformation()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(45))
            fputs("FAIL update check timed out\n", stderr); exit(1)
        }
        app.run()
        withExtendedLifetime((probe, driver, updater)) {}
    }
}
