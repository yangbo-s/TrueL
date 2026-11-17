import AppKit
import ApplicationServices

private enum ProbeError: Error { case failed(String) }

@main struct QuickWorkflowProbe {
    @MainActor static func main() {
        do { try run() }
        catch { fputs("FAIL \(error)\n", stderr); exit(1) }
    }

    @MainActor static func run() throws {
        _ = NSApplication.shared
        let permissions = SystemPermissions()
        guard permissions.accessibilityGranted, permissions.inputMonitoringGranted else {
            throw ProbeError.failed("Probe needs existing Accessibility and Input Monitoring permissions")
        }
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = Process()
        fixture.executableURL = fixtureURL
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate(); fixture.waitUntilExit() } }
        func wait(_ seconds: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.processIdentifier { break }
            wait(0.1)
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.processIdentifier else {
            throw ProbeError.failed("Own fixture did not activate; no input was sent")
        }
        let app = AXUIElementCreateApplication(fixture.processIdentifier)
        func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        guard let focused = attr(app, kAXFocusedUIElementAttribute) else { throw ProbeError.failed("No fixture editor") }
        let editor = unsafeDowncast(focused, to: AXUIElement.self)
        guard attr(editor, kAXValueAttribute) as? String == "Fixture. Same. Same." else {
            throw ProbeError.failed("Fixture text mismatch; no input was sent")
        }
        func select(_ location: Int, _ length: Int) throws {
            var range = CFRange(location: location, length: length)
            guard AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString,
                AXValueCreate(.cfRange, &range)!) == .success else { throw ProbeError.failed("Cannot select fixture") }
        }
        func key(_ code: CGKeyCode, flags: CGEventFlags, down: Bool, delay: Double = 0.06) throws {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == fixture.processIdentifier else {
                throw ProbeError.failed("Fixture lost focus; stopped input")
            }
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.post(tap: .cgSessionEventTap)
            if delay > 0 { wait(delay) }
        }
        let store = ShortcutStore(persist: false, captureKeyboardEvents: false)
        let bridge = SelectionBridge()
        var captures: [(ShortcutAction, String)] = []
        let monitor = GlobalShortcutMonitor(store: store, permissions: permissions) { action in
            captures.append((action, bridge.captureSelection()?.text ?? ""))
        }
        monitor.isPaused = { false }
        monitor.start()
        defer { monitor.stop() }
        guard store.registrationErrors.isEmpty else { throw ProbeError.failed("Monitor registration: \(store.registrationErrors)") }
        try select(0, 8)
        for code: CGKeyCode in [0, 0] {
            try key(code, flags: .maskControl, down: true)
            try key(code, flags: .maskControl, down: false)
        }
        wait()
        guard captures.count == 1, captures[0].0 == .selectionGrammar, captures[0].1 == "Fixture.", bridge.canReplace else {
            throw ProbeError.failed("Ctrl+A+A did not preserve editable selection: \(captures)")
        }
        let resultWindow = NSPanel(contentRect: NSRect(x: 600, y: 300, width: 464, height: 256),
                                   styleMask: [.titled], backing: .buffered, defer: false)
        resultWindow.title = "TrueL isolated result fixture"
        NSApp.setActivationPolicy(.regular)
        resultWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        wait()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
            throw ProbeError.failed("Result fixture did not activate")
        }
        try bridge.replaceSelectedText("Rewritten.")
        resultWindow.orderOut(nil)
        NSRunningApplication(processIdentifier: fixture.processIdentifier)?.activate(options: [])
        wait()
        guard attr(editor, kAXValueAttribute) as? String == "Rewritten. Same. Same." else {
            throw ProbeError.failed("Editable replacement failed")
        }
        print("PASS Ctrl+A+A preserved selection and AX replaced exactly the selected text while the result window was active")

        try select(0, 10)
        for code: CGKeyCode in [8, 8] {
            try key(code, flags: .maskControl, down: true)
            try key(code, flags: .maskControl, down: false)
        }
        guard captures.count == 2, captures[1].0 == .selectionTranslation, captures[1].1 == "Rewritten." else {
            throw ProbeError.failed("Ctrl+C+C capture failed")
        }
        try select(11, 5)
        do { try bridge.replaceSelectedText("MUST NOT WRITE"); throw ProbeError.failed("Stale selection accepted") }
        catch SelectionBridgeError.selectionChanged { }
        guard attr(editor, kAXValueAttribute) as? String == "Rewritten. Same. Same." else { throw ProbeError.failed("Stale selection wrote text") }
        print("PASS Ctrl+C+C captured once; changed range rejected without writing")

        try select(11, 5)
        try key(0, flags: .maskControl, down: true)
        try key(0, flags: .maskControl, down: false)
        guard attr(editor, kAXSelectedTextAttribute) as? String == "Same." else { throw ProbeError.failed("Prefix moved cursor before timeout") }
        wait(1.15)
        guard attr(editor, kAXSelectedTextAttribute) as? String == "", captures.count == 2 else { throw ProbeError.failed("Incomplete Ctrl+A was not replayed") }
        print("PASS incomplete Ctrl+A replayed its native cursor action after timeout")
        try select(11, 5)
        try key(0, flags: .maskControl, down: true)
        try key(0, flags: .maskControl, down: false)
        try key(7, flags: [], down: true)
        try key(7, flags: [], down: false)
        wait()
        guard attr(editor, kAXValueAttribute) as? String == "xRewritten. Same. Same." else {
            throw ProbeError.failed("Mismatched prefix did not replay before the next typed character")
        }
        guard AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, "Rewritten. Same. Same." as CFString) == .success else {
            throw ProbeError.failed("Cannot restore owned fixture")
        }
        print("PASS mismatched Ctrl+A replayed before the next typed character")

        let selectAll = ShortcutStroke(keyCode: 0, modifiers: .command)
        guard store.setBinding(.init(strokes: [selectAll, selectAll]), for: .selectionGrammar) else {
            throw ProbeError.failed("Cannot configure Command+A,A")
        }
        monitor.refreshConfiguration()
        let fullText = "Rewritten. Same. Same."
        var selectionTimes: [Double] = []
        for _ in 0..<5 {
            monitor.stop()
            monitor.start()
            try select(11, 5)
            let start = ProcessInfo.processInfo.systemUptime
            try key(0, flags: .maskCommand, down: true, delay: 0)
            try key(0, flags: .maskCommand, down: false, delay: 0)
            while attr(editor, kAXSelectedTextAttribute) as? String != fullText,
                  ProcessInfo.processInfo.systemUptime - start < 0.25 { wait(0.002) }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            guard attr(editor, kAXSelectedTextAttribute) as? String == fullText, elapsed < 0.25,
                  captures.count == 2 else { throw ProbeError.failed("Single Command+A waited instead of selecting immediately") }
            selectionTimes.append(elapsed * 1000)
        }
        print("PASS single Command+A selected immediately (ms): \(selectionTimes.map { String(format: "%.2f", $0) }.joined(separator: ", "))")
        try select(11, 5)
        wait(1.15)
        guard attr(editor, kAXSelectedTextAttribute) as? String == "Same.", captures.count == 2 else {
            throw ProbeError.failed("Expired Command+A replayed select-all or triggered rewriting")
        }
        // Both presses are posted in one burst so the real monitor/capture ordering is exercised.
        for attempt in 0..<10 {
            try select(11, 5)
            for _ in 0..<2 {
                try key(0, flags: .maskCommand, down: true, delay: 0)
                try key(0, flags: .maskCommand, down: false, delay: 0)
            }
            wait(0.15)
            guard captures.count == 3 + attempt, captures.last?.0 == .selectionGrammar,
                  captures.last?.1 == fullText, bridge.canReplace else {
                throw ProbeError.failed("Command+A,A did not capture the native full selection exactly once: \(captures)")
            }
        }
        try bridge.replaceSelectedText("All rewritten.")
        guard attr(editor, kAXValueAttribute) as? String == "All rewritten." else {
            throw ProbeError.failed("Command+A,A replacement did not replace the complete selection")
        }
        guard AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, fullText as CFString) == .success else {
            throw ProbeError.failed("Cannot restore owned fixture after full-selection rewrite")
        }
        print("PASS 10 burst Command+A,A sequences each captured the full selection once; replacement used that full selection; timeout did not replay")
        let completed = captures.count
        for _ in 0..<2 {
            try key(0, flags: .maskCommand, down: true, delay: 0)
            try key(0, flags: .maskCommand, down: false, delay: 0)
        }
        wait(0.01)
        monitor.stop()
        monitor.start()
        wait(0.15)
        guard captures.count == completed else { throw ProbeError.failed("Restart delivered an obsolete pending rewrite") }
        print("PASS restarting the monitor canceled pending native-selection capture")
        monitor.stop()
        try select(11, 5)
        guard bridge.captureSelection() != nil else { throw ProbeError.failed("Cannot capture final fixture") }
        fixture.terminate()
        fixture.waitUntilExit()

        do { try bridge.replaceSelectedText("MUST NOT WRITE"); throw ProbeError.failed("Closed source accepted") }
        catch SelectionBridgeError.sourceClosed { }
        print("PASS closed source rejected without writing")

        let readonly = Process()
        readonly.executableURL = fixtureURL
        readonly.arguments = ["--readonly"]
        try readonly.run()
        defer { readonly.terminate(); readonly.waitUntilExit() }
        for _ in 0..<30 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == readonly.processIdentifier { break }
            wait(0.1)
        }
        guard let read = bridge.captureSelection(), read.sourcePID == readonly.processIdentifier, read.text == "Fixture.", !bridge.canReplace else {
            throw ProbeError.failed("Read-only capture incorrectly permits replacement")
        }
        do { try bridge.replaceSelectedText("MUST NOT WRITE"); throw ProbeError.failed("Read-only write accepted") }
        catch SelectionBridgeError.replacementUnavailable { }
        print("PASS read-only text can be captured but cannot be replaced")
    }
}
