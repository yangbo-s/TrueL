import AppKit
import SwiftUI
import Observation
import QuartzCore

@main
struct TrueLApplication {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model: DemoModel
    let preferences: Preferences
    let updater: AppUpdater
    let service: ServiceConfiguration
    let shortcuts: ShortcutStore
    let permissions: SystemPermissions
    let selectionBridge = SelectionBridge()
    let selectionContext: SelectionReplacementContext
    private var isTerminating = false
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var panelDismissal: Task<Void, Never>?

    override convenience init() {
        self.init(preview: ProcessInfo.processInfo.environment["APP_SNAPSHOT"] != nil)
    }

    init(preview: Bool) {
        let client: any AIClientProtocol = preview ? PreviewAIClient() : AIClient()
        let configuration = ServiceConfiguration(persist: !preview, client: client)
        updater = AppUpdater(enabled: !preview)
        service = configuration
        preferences = Preferences(persist: !preview)
        shortcuts = ShortcutStore(persist: !preview)
        permissions = preview ? SystemPermissions(accessibilityGranted: false, inputMonitoringGranted: false) : SystemPermissions()
        let engine: (any LanguageEngine)? = preview ? nil : ProviderLanguageEngine(service: configuration, client: client)
        let copy: @MainActor (String) -> Void = { text in
            guard !preview else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        model = DemoModel(engine: engine, copyText: copy)
        selectionContext = SelectionReplacementContext(model: model)
        super.init()
        if !preview { model.reset() }
    }
    var panel: FloatingPanel!
    var settings: NSWindow?
    var desiredHeight: CGFloat = PopupLayout.baseHeight
    private var minimumPanelHeight: CGFloat = PopupLayout.baseHeight
    // The isolated snapshot runner restores this after exercising a user resize.
    var userPanelHeight: CGFloat?
    private var panelLiveResizeStart: NSSize?
    private var panelIsMiniaturizing = false
    var snapshotRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        updater.start()
        setupMenu()
        showPanel()
        observePreferences()
        observeService()
        if let directory = ProcessInfo.processInfo.environment["APP_SNAPSHOT"] {
            snapshotRunning = true
            Task { await takeSnapshots(directory: directory) }
        } else {
            permissions.startPolling()
            shortcutMonitor = GlobalShortcutMonitor(store: shortcuts, permissions: permissions) { [weak self] action in
                self?.handleShortcut(action)
            }
            shortcutMonitor?.start()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel(); return true
    }

    @objc func showPanel() {
        panelDismissal?.cancel()
        shortcuts.cancelRecording()
        settings?.orderOut(nil)
        if panel == nil {
            panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: PopupLayout.compactWidth, height: desiredHeight),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            panel.title = "TrueL"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.animationBehavior = .none
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            // Explicit orderOut below avoids a hidden utility reappearing on app activation.
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: PopupLayout.compactWidth, height: PopupLayout.baseHeight)
            panel.collectionBehavior = [.fullScreenAuxiliary]
            let content = PopupView(model: model, preferences: preferences, service: service,
                selectionContext: selectionContext,
                onTranslateClipboard: { [weak self] in self?.translateClipboard() },
                onReplaceSelection: { [weak self] in self?.replaceSelection() },
                onLanguageChange: { [weak self] in self?.changeTranslationLanguage() },
                onSettings: { [weak self] in self?.openSettings() },
                onPin: { [weak self] value in self?.preferences.alwaysOnTop = value },
                onHeightChange: { [weak self] preferred, minimum in
                    self?.resize(height: preferred, minimumHeight: minimum)
                },
                availableHeight: { [weak self] in
                    floor(((self?.panel?.screen ?? NSScreen.main)?.visibleFrame.height ?? 800) * 0.8)
                })
            panel.contentView = NativePanelSurface(rootView: content, cornerRadius: SurfaceMetrics.windowRadius)
            panel.center()
        }
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        alignTrafficLights(in: panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(nil)
    }

    @objc func openSettings() { showSettings(page: .service) }
    func showSettings(page: SettingsPage) {
        shortcuts.cancelRecording()
        panel?.orderOut(nil)
        if settings == nil {
            settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.width, height: SettingsLayout.height),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            settings?.title = "TrueL 设置"
            settings?.animationBehavior = .none
            settings?.titleVisibility = .hidden
            settings?.titlebarAppearsTransparent = true
            settings?.isReleasedWhenClosed = false
            settings?.isMovableByWindowBackground = true
            settings?.backgroundColor = .clear
            settings?.isOpaque = false
            settings?.minSize = NSSize(width: SettingsLayout.width, height: SettingsLayout.height)
            settings?.delegate = self
            settings?.center()
        }
        settings?.contentView = NativePanelSurface(rootView:
            SettingsView(preferences: preferences, service: service, shortcuts: shortcuts,
                         permissions: permissions, updater: updater, initialPage: page).tint(Theme.accent))
        // Preferences should remain usable while the utility is pinned.
        settings?.level = panel?.level ?? .normal
        settings?.makeKeyAndOrderFront(nil)
        settings?.makeFirstResponder(nil)
        alignTrafficLights(in: settings)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDidResize(_ notification: Notification) {
        let window = notification.object as? NSWindow
        alignTrafficLights(in: window)
        // AppKit can lay out the titlebar again after the resize notification.
        Task { @MainActor [weak self, weak window] in
            await Task.yield()
            self?.alignTrafficLights(in: window)
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        panelLiveResizeStart = window.frame.size
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        if let start = panelLiveResizeStart, abs(start.height - window.frame.height) > 1 {
            userPanelHeight = window.frame.height
        }
        panelLiveResizeStart = nil
        resize(height: desiredHeight, minimumHeight: minimumPanelHeight)
    }

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        if window === panel { userPanelHeight = newFrame.height }
        return true
    }

    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        guard window === panel else { return newFrame }
        // Use the same screen inset as content resizing, so a layout callback
        // cannot shrink the zoomed frame and make AppKit lose its zoom state.
        return (window.screen?.visibleFrame ?? newFrame).insetBy(dx: 8, dy: 8)
    }

    func windowWillMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === panel {
            panelIsMiniaturizing = true
            panelDismissal?.cancel()
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if notification.object as? NSWindow === panel { panelIsMiniaturizing = false }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === panel else { return true }
        closePanel()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        panelDismissal?.cancel()
        panelDismissal = Task { @MainActor [weak self] in
            // A popover's key-window handoff finishes after this delegate callback.
            await Task.yield()
            guard !Task.isCancelled, let self, let panel = self.panel, !panel.isKeyWindow else { return }
            var focused = NSApp.keyWindow
            while let window = focused {
                if window === panel { return }
                focused = window.parent
            }
            if let sheet = panel.attachedSheet, sheet.isKeyWindow { return }
            self.dismissUnpinnedPanel()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Nonactivating panels can lose application activation without a key-window change.
        dismissUnpinnedPanel()
    }

    private func dismissUnpinnedPanel() {
        guard let panel, panel.isVisible, !panel.isMiniaturized, !panelIsMiniaturizing,
              !preferences.alwaysOnTop else { return }
        clearSelection()
        panel.orderOut(nil)
        // Keep the draft, result and in-flight request for the next explicit opening.
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === settings, !isTerminating else { return }
        // Hide synchronously before restoring the panel, including during close animation.
        closing.orderOut(nil)
        showPanel()
    }

    private func alignTrafficLights(in window: NSWindow?) {
        guard let window else { return }
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind), let parent = button.superview else { continue }
            let center = parent.convert(NSPoint(
                x: WindowChromeMetrics.trafficLightFirstCenter + CGFloat(index) * WindowChromeMetrics.trafficLightPitch,
                y: window.frame.height - WindowChromeMetrics.height / 2), from: nil)
            button.setFrameOrigin(NSPoint(x: center.x - button.frame.width / 2, y: center.y - button.frame.height / 2))
        }
    }

    func resize(height: CGFloat, minimumHeight: CGFloat? = nil) {
        desiredHeight = max(PopupLayout.baseHeight, min(height, 780))
        guard let panel else { return }
        if let minimumHeight {
            minimumPanelHeight = max(PopupLayout.baseHeight, minimumHeight)
            panel.minSize = NSSize(width: PopupLayout.compactWidth, height: minimumPanelHeight)
        }
        guard !panel.inLiveResize, panelLiveResizeStart == nil else { return }
        let screen = panel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let width = min(max(PopupLayout.compactWidth, panel.frame.width), screen.width - 16)
        let targetHeight = min(ceil(max(minimumPanelHeight, userPanelHeight ?? desiredHeight)), screen.height - 16)
        let old = panel.frame
        let x = min(max(old.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        let y = min(max(old.maxY - targetHeight, screen.minY + 8), screen.maxY - targetHeight - 8)
        let target = NSRect(x: x, y: y, width: width, height: targetHeight)
        guard abs(old.height - target.height) > 0.5 || abs(old.width - target.width) > 0.5 else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || snapshotRunning {
            panel.setFrame(target, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12 + 0.08 * min(abs(old.height - target.height) / 240, 1)
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
                panel.animator().setFrame(target, display: true)
            }
        }
    }

    func observePreferences() {
        withObservationTracking {
            NSApp.appearance = preferences.appearance == "system" ? nil
                : NSAppearance(named: preferences.appearance == "dark" ? .darkAqua : .aqua)
            panel?.level = preferences.alwaysOnTop ? .floating : .normal
            settings?.level = panel?.level ?? .normal
            model.targetLanguage = preferences.language
            model.writingStyle = preferences.writingScene
        } onChange: { [weak self] in
            Task { @MainActor in self?.observePreferences() }
        }
    }

    private func observeService() {
        let observedMode = model.mode
        let revision = service.configurationRevision(for: observedMode)
        withObservationTracking {
            _ = model.mode
            _ = service.configurationRevision(for: observedMode)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.model.mode == observedMode,
                   self.service.configurationRevision(for: observedMode) != revision {
                    self.model.cancel()
                }
                self.observeService()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        panelDismissal?.cancel()
        shortcutMonitor?.stop()
        permissions.stopPolling()
        model.cancel()
    }

    func closePanel() {
        model.cancel()
        clearSelection()
        panel?.orderOut(nil)
    }

    private func clearSelection() {
        selectionBridge.clearCapture()
        selectionContext.clear()
    }

    @objc func translateClipboard() {
        clearSelection()
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        beginInput(text, mode: .translation)
    }

    /// Every external source replaces the same editor and cancels its previous request,
    /// even if a repeated shortcut captures exactly the same text.
    func beginInput(_ text: String, mode: WorkMode, canReplaceSelection: Bool = false) {
        model.reset()
        selectionContext.clear()
        model.mode = mode
        model.targetLanguage = preferences.language
        model.input = text
        selectionContext.bind(canReplace: canReplaceSelection)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.reportInputError("没有可处理的文字。请先选择或复制文字，也可以直接在此输入。")
        } else {
            model.submit()
        }
        showPanel()
    }

    private func changeTranslationLanguage() {
        model.targetLanguage = preferences.language
        guard model.mode == .translation, panel?.isVisible == true, !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.submit()
    }

    private func replaceSelection() {
        guard model.hasResult, selectionContext.canReplaceSelection else { return }
        do {
            try selectionBridge.replaceSelectedText(model.output)
            closePanel()
        } catch {
            selectionContext.fail(error.localizedDescription)
            selectionBridge.clearCapture()
        }
    }

    func handleShortcut(_ action: ShortcutAction) {
        switch action {
        case .selectionTranslation:
            // Capture before showing our panel changes the front application.
            if let selection = selectionBridge.captureSelection(), !selection.text.isEmpty {
                beginInput(selection.text, mode: .translation, canReplaceSelection: selectionBridge.canReplace)
            } else if shortcutMonitor?.clipboardChangedDuringSequence == true {
                translateClipboard()
            } else {
                clearSelection()
                model.reset()
                model.mode = .translation
                model.reportInputError("未能读取选区。请先复制文字，使用“翻译剪贴板”，或在设置中开启辅助功能权限。")
                showPanel()
            }
        case .clipboardTranslation:
            translateClipboard()
        case .translation, .grammar:
            clearSelection()
            model.mode = action == .translation ? .translation : .grammar
            showPanel()
        case .selectionGrammar:
            let selection = selectionBridge.captureSelection()
            beginInput(selection?.text ?? "", mode: .grammar,
                       canReplaceSelection: selectionBridge.canReplace)
        }
    }

    @objc func submit() { model.submit() }
    @objc func cancel() { model.cancel() }
    @objc func sample() { clearSelection(); model.loadSample(0); showPanel() }
    @objc func closeWindow() {
        if NSApp.keyWindow === settings { settings?.close() }
        else { closePanel() }
    }
    func setupMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let setting = appMenu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        setting.target = self
        appMenu.addItem(updater.menuItem())
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 TrueL", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); editItem.title = "编辑"; menu.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windowItem = NSMenuItem(); windowItem.title = "窗口"; menu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口"); windowItem.submenu = windowMenu
        let show = windowMenu.addItem(withTitle: "显示主浮窗", action: #selector(showPanel), keyEquivalent: ""); show.target = self
        let clipboard = windowMenu.addItem(withTitle: "翻译剪贴板", action: #selector(translateClipboard), keyEquivalent: "")
        clipboard.target = self
        let close = windowMenu.addItem(withTitle: "关闭窗口", action: #selector(closeWindow), keyEquivalent: "w"); close.target = self
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放窗口", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let demo = windowMenu.addItem(withTitle: "载入示例", action: #selector(sample), keyEquivalent: ""); demo.target = self
        NSApp.mainMenu = menu
    }
}
