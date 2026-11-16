import AppKit
import Observation

@MainActor
@Observable
final class ShortcutStore {
    private(set) var bindings: [ShortcutAction: ShortcutBinding]
    private(set) var recordingAction: ShortcutAction?
    private(set) var recordingStrokes: [ShortcutStroke] = []
    private(set) var recordingError: String?
    var status = "快捷键尚未启动"
    var registrationErrors: [ShortcutAction: String] = [:]
    var isRecording: Bool { recordingAction != nil }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let captureKeyboardEvents: Bool
    @ObservationIgnored private var localMonitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var lastRecordedTimestamp: TimeInterval?
    @ObservationIgnored private var recordingSourcePID: Int64?
    private static let storageKey = "TrueL.shortcuts.v2"
    private static let legacyStorageKey = "TrueL.shortcuts.v1"
    private static let quickDefaultsKey = "TrueL.shortcuts.quickDefaults.v1"

    init(persist: Bool = true, defaults: UserDefaults = .standard, captureKeyboardEvents: Bool = true) {
        self.persist = persist
        self.defaults = defaults
        self.captureKeyboardEvents = captureKeyboardEvents
        let currentData = persist ? defaults.data(forKey: Self.storageKey) : nil
        let legacyData = persist && currentData == nil ? defaults.data(forKey: Self.legacyStorageKey) : nil
        if let data = currentData ?? legacyData,
           let stored = try? JSONDecoder().decode([String: ShortcutBinding].self, from: data) {
            bindings = Self.restoredBindings(stored, migratingLegacy: legacyData != nil)
            // Keep v1 intact for a rollback. A saved v2 prevents cleared actions
            // from being resurrected by migration on the next launch.
            if legacyData != nil { save() }
        } else { bindings = ShortcutBinding.defaults }
        if persist && !defaults.bool(forKey: Self.quickDefaultsKey) {
            let previous: [ShortcutAction: ShortcutBinding] = [
                .selectionTranslation: .init(strokes: [.init(keyCode: 8, modifiers: .command), .init(keyCode: 8, modifiers: .command)]),
                .selectionGrammar: .init(strokes: [.init(keyCode: 5, modifiers: [.control, .option, .command])])
            ]
            for action in [ShortcutAction.selectionTranslation, .selectionGrammar] {
                guard currentData != nil, bindings[action] == previous[action], let replacement = ShortcutBinding.defaults[action],
                      validationError(for: replacement, replacing: action) == nil else { continue }
                bindings[action] = replacement
            }
            save()
            defaults.set(true, forKey: Self.quickDefaultsKey)
        }
    }

    private static func restoredBindings(_ stored: [String: ShortcutBinding], migratingLegacy: Bool)
        -> [ShortcutAction: ShortcutBinding] {
        var validated: [ShortcutAction: ShortcutBinding] = [:]
        for action in ShortcutAction.allCases where action != .selectionTranslation {
            guard let binding = stored[action.rawValue], basicValidation(binding) == nil,
                  !validated.values.contains(where: { $0.conflicts(with: binding) }) else { continue }
            validated[action] = binding
        }
        let selection = stored[ShortcutAction.selectionTranslation.rawValue]
        var candidates = [selection]
        if migratingLegacy {
            let legacyDefault = ShortcutBinding(strokes: [
                .init(keyCode: 17, modifiers: [.control, .option, .command])
            ])
            let legacyQuick = stored["quickTranslation"]
            candidates = selection != nil && selection != legacyDefault
                ? [selection, legacyQuick] : [legacyQuick, selection]
        }
        validated[.selectionTranslation] = candidates.compactMap { $0 }.first { binding in
            basicValidation(binding) == nil && !validated.values.contains { $0.conflicts(with: binding) }
        }
        return validated
    }

    func display(for action: ShortcutAction) -> String { ShortcutDisplay.binding(bindings[action]) }

    func beginRecording(action: ShortcutAction) {
        cancelRecording()
        recordingAction = action
        recordingStrokes = []
        recordingError = nil
        lastRecordedTimestamp = nil
        guard captureKeyboardEvents else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isRecording else { return false }
                if event.keyCode == 53 { self.cancelRecording() }
                else {
                    self.record(ShortcutStroke(event: event), timestamp: event.timestamp, isRepeat: event.isARepeat,
                                sourcePID: event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0)
                }
                return true
            }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancelRecording() }
            }
    }

    func record(_ stroke: ShortcutStroke, timestamp: TimeInterval, isRepeat: Bool = false, sourcePID: Int64 = 0) {
        guard isRecording, !isRepeat else { return }
        guard stroke.keyCode != 53 else { cancelRecording(); return }
        // Another translator may react to a double copy by injecting another C.
        // Keep this recording's input source so that event cannot append a key.
        // Real repeated presses are preserved without any timing debounce.
        guard recordingSourcePID == nil || recordingSourcePID == sourcePID else { return }
        recordingSourcePID = sourcePID
        if let lastRecordedTimestamp, timestamp - lastRecordedTimestamp > ShortcutBinding.sequenceTimeout {
            recordingStrokes.removeAll()
        }
        lastRecordedTimestamp = timestamp
        recordingStrokes.append(stroke)
        recordingError = validationError(for: ShortcutBinding(strokes: recordingStrokes), replacing: recordingAction)
    }

    @discardableResult
    func commitRecording() -> Bool {
        guard let action = recordingAction else { return false }
        let binding = ShortcutBinding(strokes: recordingStrokes)
        guard setBinding(binding, for: action) else { return false }
        cancelRecording()
        return true
    }

    @discardableResult
    func setBinding(_ binding: ShortcutBinding, for action: ShortcutAction) -> Bool {
        if let error = validationError(for: binding, replacing: action) { recordingError = error; return false }
        bindings[action] = binding
        recordingError = nil
        save()
        return true
    }

    func cancelRecording() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        localMonitor = nil
        resignObserver = nil
        recordingAction = nil
        recordingStrokes = []
        recordingError = nil
        lastRecordedTimestamp = nil
        recordingSourcePID = nil
    }

    func clearBinding(for action: ShortcutAction) {
        if recordingAction == action { cancelRecording() }
        bindings.removeValue(forKey: action)
        save()
    }

    func restoreDefaults() {
        cancelRecording()
        bindings = ShortcutBinding.defaults
        save()
    }

    func validationError(for binding: ShortcutBinding, replacing action: ShortcutAction?) -> String? {
        if let error = Self.basicValidation(binding) { return error }
        if let other = ShortcutAction.allCases.first(where: {
            $0 != action && bindings[$0]?.conflicts(with: binding) == true
        }) { return "与“\(other.title)”重复或存在前缀冲突，请换一组按键。" }
        return nil
    }

    private static func basicValidation(_ binding: ShortcutBinding) -> String? {
        guard let first = binding.strokes.first else { return "请先按下快捷键。" }
        guard !first.modifiers.isEmpty else { return "首个按键需要修饰键，避免普通输入触发全局动作。" }
        guard !binding.strokes.contains(where: { $0.keyCode == 53 }) else { return "Esc 用于取消录制，请选择其他按键。" }
        return nil
    }

    private func save() {
        guard persist else { return }
        let stored = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.storageKey) }
    }
}
