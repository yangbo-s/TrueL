import AppKit
import Testing
@testable import TrueL

@MainActor
extension UnifiedPopupTests {
    @Test func losingKeyWindowDismissesUnpinnedPanelAndPreservesDraft() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.preferences.alwaysOnTop = false
        subject.showPanel()
        let panel = try #require(subject.panel)
        defer {
            subject.model.cancel()
            panel.delegate = nil
            panel.close()
            panel.contentView = nil
        }
        subject.model.input = "Keep my draft after clicking the browser."
        #expect(panel.isVisible)

        // AppKit sends this event when another window takes keyboard focus.
        panel.resignKey()
        try await Task.sleep(for: .milliseconds(100))

        #expect(!panel.isVisible)
        subject.showPanel()
        #expect(subject.panel === panel)
        #expect(panel.isVisible)
        #expect(subject.model.input == "Keep my draft after clicking the browser.")
    }

    @Test func applicationDeactivationHidesPanelAndInvalidatesExternalSelection() {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        defer { subject.panel.delegate = nil; subject.panel.close() }
        subject.selectionContext.bind(canReplace: true)
        subject.model.showPreviewResult()
        let result = subject.model.output

        subject.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))

        #expect(!subject.panel.isVisible)
        #expect(!subject.selectionContext.canReplaceSelection)
        #expect(subject.model.output == result)
        subject.showPanel()
        #expect(subject.model.hasResult)
    }

    @Test func pinnedPanelStaysVisibleAfterFocusAndApplicationChange() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.preferences.alwaysOnTop = true
        subject.showPanel()
        defer { subject.panel.delegate = nil; subject.panel.close() }

        subject.panel.resignKey()
        subject.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        try await Task.sleep(for: .milliseconds(100))

        #expect(subject.panel.isVisible)
        #expect(subject.panel.level == .floating)
    }

    @Test func childPopoverCanTakeFocusWithoutDismissingPanel() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        let child = FloatingPanel(contentRect: .init(x: 0, y: 0, width: 100, height: 60),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        child.isReleasedWhenClosed = false
        subject.panel.addChildWindow(child, ordered: .above)
        defer {
            subject.panel.removeChildWindow(child)
            child.close()
            subject.panel.delegate = nil
            subject.panel.close()
        }
        child.makeKeyAndOrderFront(nil)
        #expect(child.isKeyWindow)
        try await Task.sleep(for: .milliseconds(100))
        #expect(subject.panel.isVisible)
    }

    @Test func explicitReopenWinsOverPendingDismissal() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        defer { subject.panel.delegate = nil; subject.panel.close() }
        subject.panel.resignKey()
        subject.showPanel()
        try await Task.sleep(for: .milliseconds(100))
        #expect(subject.panel.isVisible)
    }

    @Test func dismissingDuringProcessingPreservesTheRequest() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        defer { subject.model.cancel(); subject.panel.delegate = nil; subject.panel.close() }
        subject.model.submit()
        subject.panel.resignKey()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!subject.panel.isVisible)
        #expect(subject.model.isProcessing)
        subject.showPanel()
        #expect(subject.model.isProcessing)
    }

    @Test func settingsStayOpenOnDeactivationWithoutRestoringThePopup() {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        subject.showSettings(page: .general)
        defer {
            subject.settings?.delegate = nil
            subject.settings?.close()
            subject.panel.delegate = nil
            subject.panel.close()
        }
        subject.settings?.resignKey()
        subject.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        #expect(subject.settings?.isVisible == true)
        #expect(!subject.panel.isVisible)
    }
}
