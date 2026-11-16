import AppKit
import CredentialCore
import Sparkle

@main
struct UpdateProbeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = UpdateProbe()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class UpdateProbe: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, SPUUserDriver {
    var updater: SPUUpdater?
    var stage: Int { Bundle.main.object(forInfoDictionaryKey: "TrueLTestStage") as! Int }
    var ticket: String { Bundle.main.object(forInfoDictionaryKey: "TrueLTestTicket") as! String }
    var report: URL { URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "TrueLTestReport") as! String) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do {
                let client = CredentialBrokerClient()
                if stage == 1 { try await client.checkStorage(ticket: ticket, operation: "create") }
                try await client.checkStorage(ticket: ticket, operation: "read")
                record("credential-read", success: true)
                if stage == 3 {
                    try await client.checkStorage(ticket: ticket, operation: "delete")
                    record("cleanup", success: true)
                    NSApp.terminate(nil)
                    return
                }
                let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
                self.updater = updater
                try updater.start()
                updater.checkForUpdates()
            } catch {
                record("credential-or-updater-error", success: false, code: (error as NSError).code)
                exit(1)
            }
        }
    }

    func record(_ event: String, success: Bool, code: Int = 0) {
        let value: [String: Any] = ["stage": stage, "event": event, "success": success, "code": code]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { exit(70) }
        if !FileManager.default.fileExists(atPath: report.path) { FileManager.default.createFile(atPath: report.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: report) else { exit(70) }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data + Data([10]))
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("update-found", success: true); reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        record("update-not-found", success: false, code: (error as NSError).code); acknowledgement(); exit(1)
    }
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        record("updater-error", success: false, code: (error as NSError).code); acknowledgement(); exit(1)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("extracting", success: true) }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("install-and-relaunch", success: true); reply(.install)
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() {}
}
