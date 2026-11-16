import AppKit
import Carbon.HIToolbox
import Observation

/// Carbon handles ordinary chords. The event tap preserves native copy sequences
/// and holds other configured prefixes so they cannot destroy a selection.
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
    private var lastAccessibility: Bool?
    private var gate = ShortcutSequenceGate<CGEvent>(bindings: [:])
    private var sequenceTimer: Timer?
    private var tapCanSuppress = false
    private static let replayMarker: Int64 = 0x5452554c534551
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
        lastAccessibility = nil
        store.status = "快捷键已停止"
    }

    private func observeConfiguration() {
        guard running else { return }
        withObservationTracking {
            _ = store.bindings
            _ = store.isRecording
            _ = permissions.inputMonitoringGranted
            _ = permissions.accessibilityGranted
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
        let accessibility = permissions.accessibilityGranted
        guard bindings != lastBindings || paused != lastPaused || granted != lastPermission
                || accessibility != lastAccessibility else { return }
        resetSequence()
        if accessibility != lastAccessibility { stopEventTap() }
        lastAccessibility = accessibility
        lastBindings = bindings
        lastPaused = paused
        lastPermission = granted
        unregisterHotKeys()
        let observed = bindings.filter { $0.value.needsInputMonitoring }
        matcher = ShortcutSequenceMatcher(bindings: observed.filter { $0.value.startsWithNativeCopy })
        gate = ShortcutSequenceGate(bindings: observed)
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
        if !accessibility {
            for (action, binding) in sequences where !binding.startsWithNativeCopy {
                store.registrationErrors[action] = "需要辅助功能权限以保留原选区。"
            }
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
        tapCanSuppress = permissions.accessibilityGranted
        let mask = [CGEventType.keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: tapCanSuppress ? .defaultTap : .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
                    return monitor.receiveEvent(type: type, event: event)
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
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

    private func receiveEvent(type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetSequence()
            if let eventTap, permissions.inputMonitoringGranted { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }
        guard running, !store.isRecording, !isPaused(),
              let sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            resetSequence()
            return false
        }
        guard type == .keyDown || type == .keyUp else { resetSequence(); return false }
        let stroke = ShortcutStroke(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: ShortcutModifiers(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))))
        let timestamp = Double(event.timestamp) / 1_000_000_000
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if tapCanSuppress, let copy = event.copy() {
            let decision = gate.process(copy, stroke: stroke, down: type == .keyDown, isRepeat: repeated,
                                        timestamp: timestamp, sourcePID: sourcePID)
            replay(decision.replay)
            if let action = decision.action { trigger(action, sourcePID: sourcePID, clipboardChanged: false) }
            if gate.isPending {
                if type == .keyDown && !repeated { armSequenceTimeout() }
            } else { sequenceTimer?.invalidate(); sequenceTimer = nil }
            if decision.consumed { return true }
        }
        guard type == .keyDown, !repeated else { return false }
        matcher.prepareForEvent(at: timestamp, sourcePID: sourcePID)
        if !matcher.isInProgress(for: .selectionTranslation) {
            let selectionBinding = store.bindings[.selectionTranslation]
            sequenceClipboardChangeCount = selectionBinding?.startsWithNativeCopy == true && selectionBinding?.strokes.first == stroke
                ? NSPasteboard.general.changeCount : nil
        }
        if let action = matcher.process(stroke, timestamp: timestamp, sourcePID: sourcePID) {
            let changed = action == .selectionTranslation && sequenceClipboardChangeCount.map { $0 != NSPasteboard.general.changeCount } == true
            sequenceClipboardChangeCount = nil
            trigger(action, sourcePID: sourcePID, clipboardChanged: changed)
        } else if !matcher.isInProgress(for: .selectionTranslation) { sequenceClipboardChangeCount = nil }
        return false
    }

    private func trigger(_ action: ShortcutAction, sourcePID: pid_t, clipboardChanged: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.running, !self.store.isRecording, !self.isPaused(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return }
            self.clipboardChangedDuringSequence = clipboardChanged
            self.onTrigger(action)
            self.clipboardChangedDuringSequence = false
        }
    }

    private func armSequenceTimeout() {
        sequenceTimer?.invalidate()
        let timer = Timer(timeInterval: ShortcutBinding.sequenceTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetSequence() }
        }
        sequenceTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func replay(_ events: [(pid_t, CGEvent)]) {
        for (pid, event) in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.postToPid(pid)
        }
    }

    private func resetSequence() {
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        replay(gate.flush())
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
