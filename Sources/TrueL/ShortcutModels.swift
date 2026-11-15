import AppKit
import Carbon.HIToolbox

enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case clipboardTranslation, translation, grammar
    case selectionTranslation, selectionGrammar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .clipboardTranslation: "翻译剪贴板"
        case .translation: "打开翻译"
        case .grammar: "打开改写"
        case .selectionTranslation: "翻译选中文字"
        case .selectionGrammar: "改写选中文字"
        }
    }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt
    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let shift = Self(rawValue: 1 << 2)
    static let command = Self(rawValue: 1 << 3)
    static let function = Self(rawValue: 1 << 4)
    static let supported: Self = [.control, .option, .shift, .command, .function]

    init(rawValue: UInt) { self.rawValue = rawValue & 0x1f }
    init(_ flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.function) { value.insert(.function) }
        self = value
    }

    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
        + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
        + (contains(.function) ? "fn " : "")
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }
}

struct ShortcutStroke: Codable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: ShortcutModifiers

    init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: ShortcutModifiers(event.modifierFlags))
    }
}

struct ShortcutBinding: Codable, Equatable, Sendable {
    let strokes: [ShortcutStroke]
    static let sequenceTimeout: TimeInterval = 1.0

    var needsInputMonitoring: Bool {
        strokes.count > 1 || strokes.contains { $0.modifiers.contains(.function) }
    }

    var startsWithNativeCopy: Bool {
        strokes.first == ShortcutStroke(keyCode: 8, modifiers: .command)
    }

    func conflicts(with other: Self) -> Bool {
        guard !strokes.isEmpty, !other.strokes.isEmpty else { return false }
        return strokes.starts(with: other.strokes) || other.strokes.starts(with: strokes)
    }

    static var defaults: [ShortcutAction: Self] {
        [
            .selectionTranslation: .init(strokes: [
                .init(keyCode: 8, modifiers: .command), .init(keyCode: 8, modifiers: .command)
            ]),
            .clipboardTranslation: .init(strokes: [.init(keyCode: 18, modifiers: [.control, .option, .command])]),
            .translation: .init(strokes: [.init(keyCode: 19, modifiers: [.control, .option, .command])]),
            .grammar: .init(strokes: [.init(keyCode: 20, modifiers: [.control, .option, .command])]),
            .selectionGrammar: .init(strokes: [.init(keyCode: 5, modifiers: [.control, .option, .command])])
        ]
    }
}

/// Retains only progress through configured key codes. It never retains typed text.
struct ShortcutSequenceMatcher {
    var bindings: [ShortcutAction: ShortcutBinding]
    var timeout: TimeInterval = ShortcutBinding.sequenceTimeout
    private var progress: [ShortcutAction: Int] = [:]
    private var lastTimestamp: TimeInterval?
    private(set) var sourcePID: pid_t?

    init(bindings: [ShortcutAction: ShortcutBinding]) { self.bindings = bindings }

    mutating func reset() {
        progress.removeAll(keepingCapacity: true)
        lastTimestamp = nil
        sourcePID = nil
    }

    func isInProgress(for action: ShortcutAction) -> Bool { progress[action] != nil }

    mutating func expireProgress(at timestamp: TimeInterval) {
        if let lastTimestamp, timestamp < lastTimestamp || timestamp - lastTimestamp > timeout { reset() }
    }

    /// Call before reading per-sequence metadata so a new app cannot inherit it.
    mutating func prepareForEvent(at timestamp: TimeInterval, sourcePID: pid_t) {
        expireProgress(at: timestamp)
        if let previousPID = self.sourcePID, previousPID != sourcePID { reset() }
    }

    mutating func process(_ stroke: ShortcutStroke, timestamp: TimeInterval, sourcePID: pid_t = 0,
                          isRepeat: Bool = false) -> ShortcutAction? {
        guard !isRepeat else { return nil }
        prepareForEvent(at: timestamp, sourcePID: sourcePID)
        lastTimestamp = timestamp
        var next: [ShortcutAction: Int] = [:]
        for action in ShortcutAction.allCases {
            guard let steps = bindings[action]?.strokes, !steps.isEmpty else { continue }
            let index = progress[action, default: 0]
            if index < steps.count, steps[index] == stroke {
                if index + 1 == steps.count { reset(); return action }
                next[action] = index + 1
            } else if steps[0] == stroke {
                if steps.count == 1 { reset(); return action }
                next[action] = 1
            }
        }
        progress = next
        self.sourcePID = next.isEmpty ? nil : sourcePID
        return nil
    }
}

@MainActor
enum ShortcutDisplay {
    static func binding(_ binding: ShortcutBinding?) -> String {
        guard let binding, !binding.strokes.isEmpty else { return "未设置" }
        let common = binding.strokes.first?.modifiers
        let sharesModifiers = binding.strokes.allSatisfy { $0.modifiers == common }
        return binding.strokes.enumerated().map { index, stroke in
            let prefix = sharesModifiers && index > 0 ? "" : stroke.modifiers.symbols
            return prefix + key(stroke.keyCode)
        }.joined(separator: ", ")
    }

    static func key(_ keyCode: UInt16) -> String {
        let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "Esc",
            76: "⌤", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        if let name = special[keyCode] { return name }
        let current = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        for source in [current, ascii] {
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            guard let bytes = CFDataGetBytePtr(data) else { continue }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKey: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 16)
            var length = 0
            let result = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                        UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                        &deadKey, characters.count, &length, &characters)
            if result == noErr, length > 0 {
                return String(utf16CodeUnits: characters, count: length).uppercased()
            }
        }
        return "键 \(keyCode)"
    }
}
