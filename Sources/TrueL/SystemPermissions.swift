import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class SystemPermissions {
    private(set) var accessibilityGranted: Bool
    private(set) var inputMonitoringGranted: Bool
    @ObservationIgnored private let readsSystem: Bool
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init() {
        readsSystem = true
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    /// Fixed state for snapshots; it never requests or changes system permissions.
    init(accessibilityGranted: Bool, inputMonitoringGranted: Bool) {
        readsSystem = false
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
    }

    func refresh() {
        guard readsSystem else { return }
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func startPolling() {
        guard readsSystem, pollingTask == nil else { return }
        refresh()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay: Duration = self.accessibilityGranted && self.inputMonitoringGranted ? .seconds(20) : .milliseconds(1500)
                do { try await Task.sleep(for: delay, tolerance: .milliseconds(200)) }
                catch { return }
                self.refresh()
            }
        }
    }

    func stopPolling() { pollingTask?.cancel(); pollingTask = nil }

    func openAccessibilitySettings() { openPrivacyPane("Privacy_Accessibility") }
    func openInputMonitoringSettings() { openPrivacyPane("Privacy_ListenEvent") }

    private func openPrivacyPane(_ pane: String) {
        guard readsSystem, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
