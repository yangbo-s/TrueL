import AppKit

@MainActor final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 460, height: 240),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "TrueL isolated selection fixture"
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 240))
        editor.string = "Fixture. Same. Same."
        editor.font = .systemFont(ofSize: 14)
        editor.isEditable = !CommandLine.arguments.contains("--readonly")
        editor.isSelectable = true
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: 8))
    }
}

@main struct SelectionFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
