import AppKit
import Testing
@testable import TrueL

@MainActor
extension UnifiedPopupTests {
    @Test func bothWindowsExposeWorkingNativeWindowControls() throws {
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
        for window in [subject.panel as NSWindow?, subject.settings].compactMap({ $0 }) {
            #expect(window.styleMask.contains(.resizable))
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = try #require(window.standardWindowButton(kind))
                #expect(button.isEnabled)
                #expect(!button.isHidden)
            }
        }
    }

    @Test func resizingPreservesUserDimensionsAcrossContentAndWindowChanges() throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        let panel = try #require(subject.panel)
        defer {
            subject.settings?.delegate = nil
            subject.settings?.close()
            panel.delegate = nil
            panel.close()
        }
        subject.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        var frame = panel.frame
        frame.size = NSSize(width: 680, height: 480)
        panel.setFrame(frame, display: true)
        // A content update during the drag must not undo the user's frame.
        subject.resize(height: 600, minimumHeight: PopupLayout.baseHeight)
        #expect(panel.frame.size == frame.size)
        subject.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
        subject.resize(height: 350, minimumHeight: PopupLayout.baseHeight)
        #expect(panel.frame.size == frame.size)
        subject.showSettings(page: .shortcuts)
        subject.settings?.close()
        #expect(subject.panel === panel)
        #expect(panel.frame.size == frame.size)
        subject.resize(height: 600, minimumHeight: 520)
        #expect(panel.frame.width == 680)
        #expect(panel.frame.height >= 520)
    }

    @Test func nativeCloseCancelsRequestAndReopenKeepsDraft() throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.beginInput("Keep this draft after closing.", mode: .translation, canReplaceSelection: true)
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close() }
        panel.performClose(nil)
        #expect(!panel.isVisible)
        #expect(!subject.model.isProcessing)
        #expect(!subject.selectionContext.canReplaceSelection)
        subject.showPanel()
        #expect(subject.panel === panel)
        #expect(subject.model.input == "Keep this draft after closing.")
        #expect(panel.isVisible)
    }

    @Test func nativeMinimizeAndReopenPreserveTheSamePanel() async throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close() }
        subject.model.input = "Keep the minimized draft."
        panel.miniaturize(nil)
        for _ in 0..<25 where !panel.isMiniaturized {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(panel.isMiniaturized)
        subject.showPanel()
        #expect(!panel.isMiniaturized)
        #expect(panel.isVisible)
        #expect(subject.panel === panel)
        #expect(subject.model.input == "Keep the minimized draft.")
    }

    @Test func nativeZoomAndRestoreKeepContentAndAdaptiveLayout() throws {
        _ = NSApplication.shared
        let subject = AppDelegate(preview: true)
        subject.snapshotRunning = true
        subject.showPanel()
        let panel = try #require(subject.panel)
        defer { subject.model.cancel(); panel.delegate = nil; panel.close() }
        subject.model.input = "Keep this text while zooming."
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let original = panel.frame
        panel.performZoom(nil)
        // Native zoom animates independently of the content-height animation.
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        #expect(panel.isZoomed)
        #expect(panel.frame.size != original.size)
        #expect(panel.frame.width >= original.width)
        #expect(subject.model.input == "Keep this text while zooming.")
        panel.performZoom(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        #expect(abs(panel.frame.width - original.width) < 1)
        #expect(abs(panel.frame.height - original.height) < 1)
        #expect(panel.isVisible)
    }
}
