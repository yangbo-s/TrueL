import AppKit
import Carbon.HIToolbox
import Observation

/// Carbon handles ordinary chords without a permission. A listen-only event tap
/// recognizes sequences without consuming either copy event in ⌘C, C.
@MainActor
final class GlobalShortcutMonitor {
    let store: ShortcutStore
    let permissions: SystemPermissions
    var onTrigger: (ShortcutAction) -> Void
    private(set) var clipboardChangedDuringSequence = false
    var isPaused: () -> Bool = {
        NSApp.isActive && (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable == true
    }

    private var running = false
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var heldHotKeys = Set<UInt32>()
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var localMonitor: Any?
    private var focusTimer: Timer?
    private var notifications: [NSObjectProtocol] = []
    private var workspaceActivationObserver: NSObjectProtocol?
    private var lastBindings: [ShortcutAction: ShortcutBinding]?
    private var lastPaused: Bool?
    private var lastPermission: Bool?
    private var matcher = ShortcutSequenceMatcher(bindings: [:])
    private var sequenceClipboardChangeCount: Int?
    private static let signature: OSType = 0x5452554c

    init(store: ShortcutStore, permissions: SystemPermissions, onTrigger: @escaping (ShortcutAction) -> Void) {
        self.store = store
        self.permissions = permissions
        self.onTrigger = onTrigger
    }

    func start() {
        guard !running else { return }
        running = true
        permissions.refresh()
        observeConfiguration()
        // Responder changes have no single AppKit notification. Check after
        // local interactions and on activation so editing keeps its own keys.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor in self?.refreshConfiguration() }
            return event
        }
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshConfiguration() }
            })
        }
        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Also covers A → B → A when no key is pressed in the intervening app.
            MainActor.assumeIsolated { self?.resetSequence() }
        }
        focusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConfiguration() }
        }
        focusTimer?.tolerance = 0.1
    }

    func stop() {
        running = false
        unregisterHotKeys()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        stopEventTap()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        for token in notifications { NotificationCenter.default.removeObserver(token) }
        notifications.removeAll()
        if let workspaceActivationObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver) }
        workspaceActivationObserver = nil
        focusTimer?.invalidate()
        focusTimer = nil
        resetSequence()
        lastBindings = nil
        lastPaused = nil
        lastPermission = nil
        store.status = "快捷键已停止"
    }

    private func observeConfiguration() {
        guard running else { return }
        withObservationTracking {
            _ = store.bindings
            _ = store.isRecording
            _ = permissions.inputMonitoringGranted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.refreshConfiguration()
                self.observeConfiguration()
            }
        }
        refreshConfiguration()
    }

    func refreshConfiguration() {
        guard running else { return }
        let bindings = store.bindings
        let paused = store.isRecording || isPaused()
        let granted = permissions.inputMonitoringGranted
        guard bindings != lastBindings || paused != lastPaused || granted != lastPermission else { return }
        lastBindings = bindings
        lastPaused = paused
        lastPermission = granted
        unregisterHotKeys()
        matcher = ShortcutSequenceMatcher(bindings: bindings.filter { $0.value.needsInputMonitoring })
        sequenceClipboardChangeCount = nil
        clipboardChangedDuringSequence = false
        store.registrationErrors = [:]
        if paused {
            matcher.reset()
            store.status = store.isRecording ? "录制期间暂停全局快捷键" : "编辑文字时暂停全局快捷键"
            return
        }
        installCarbonHandlerIfNeeded()
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let binding = bindings[action], !binding.needsInputMonitoring,
                  let stroke = binding.strokes.first else { continue }
            guard eventHandler != nil else {
                store.registrationErrors[action] = "系统快捷键监听未能启动。"
                continue
            }
            var ref: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            let code = RegisterEventHotKey(UInt32(stroke.keyCode), stroke.modifiers.carbonFlags, identifier,
                                          GetApplicationEventTarget(), 0, &ref)
            if code == noErr, let ref { hotKeys.append(ref) }
            else { store.registrationErrors[action] = "注册失败（\(code)），可能与其他应用的快捷键冲突。" }
        }
        let sequences = bindings.filter { $0.value.needsInputMonitoring }
        if sequences.isEmpty { stopEventTap() }
        else if !granted {
            stopEventTap()
            for action in sequences.keys { store.registrationErrors[action] = "需要在系统设置中允许输入监控。" }
        } else if !startEventTapIfNeeded() {
            for action in sequences.keys { store.registrationErrors[action] = "输入监听未能启动，请检查权限后重新启动 TrueL。" }
        }
        if bindings.isEmpty { store.status = "未设置全局快捷键" }
        else if store.registrationErrors.isEmpty { store.status = "全局快捷键已启用" }
        else { store.status = "部分快捷键未启用，请查看对应提示。" }
    }

    private func installCarbonHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let code = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard code == noErr else { return code }
            let id = identifier.id
            let signature = identifier.signature
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            return MainActor.assumeIsolated {
                guard signature == GlobalShortcutMonitor.signature else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
                monitor.receiveCarbon(id: id, released: released)
                return noErr
            }
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if result != noErr { eventHandler = nil }
    }

    private func receiveCarbon(id: UInt32, released: Bool) {
        if released { heldHotKeys.remove(id); return }
        guard running, !store.isRecording, !isPaused(), heldHotKeys.insert(id).inserted,
              id > 0, Int(id) <= ShortcutAction.allCases.count else { return }
        clipboardChangedDuringSequence = false
        onTrigger(ShortcutAction.allCases[Int(id) - 1])
    }

    private func unregisterHotKeys() {
        for key in hotKeys { UnregisterEventHotKey(key) }
        hotKeys.removeAll()
        heldHotKeys.removeAll()
    }

    @discardableResult
    private func startEventTapIfNeeded() -> Bool {
        if eventTap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                MainActor.assumeIsolated {
                    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
                    monitor.receiveEvent(type: type, event: event)
                }
                // Listen-only also enforces this in the OS: copy/typing is never swallowed.
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        eventTap = tap
        eventSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func receiveEvent(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetSequence()
            if let eventTap, permissions.inputMonitoringGranted { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        guard running, type == .keyDown, !store.isRecording, !isPaused() else {
            resetSequence()
            return
        }
        guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
        guard let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            resetSequence()
            return
        }
        let stroke = ShortcutStroke(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: ShortcutModifiers(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))))
        let timestamp = Double(event.timestamp) / 1_000_000_000
        matcher.prepareForEvent(at: timestamp, sourcePID: sourcePID)
        if !matcher.isInProgress(for: .selectionTranslation) {
            let selectionBinding = store.bindings[.selectionTranslation]
            sequenceClipboardChangeCount = selectionBinding?.startsWithNativeCopy == true && selectionBinding?.strokes.first == stroke
                ? NSPasteboard.general.changeCount : nil
        }
        if let action = matcher.process(stroke, timestamp: timestamp, sourcePID: sourcePID) {
            let changed = action == .selectionTranslation && sequenceClipboardChangeCount.map { $0 != NSPasteboard.general.changeCount } == true
            sequenceClipboardChangeCount = nil
            // Leave the tap callback promptly. Capture the source app in the action
            // handler before presenting any TrueL window.
            Task { @MainActor [weak self] in
                guard let self, self.running, !self.store.isRecording, !self.isPaused(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return }
                self.clipboardChangedDuringSequence = changed
                self.onTrigger(action)
                self.clipboardChangedDuringSequence = false
            }
        } else if !matcher.isInProgress(for: .selectionTranslation) {
            sequenceClipboardChangeCount = nil
        }
    }

    private func resetSequence() {
        matcher.reset()
        sequenceClipboardChangeCount = nil
        clipboardChangedDuringSequence = false
    }

    private func stopEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        eventTap = nil
        eventSource = nil
    }
}
