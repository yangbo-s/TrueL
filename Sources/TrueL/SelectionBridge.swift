import AppKit
import ApplicationServices

struct SelectionCapture {
    let text: String
    let sourceName: String
    let sourceBundleIdentifier: String?
    let sourcePID: pid_t
}

enum SelectionBridgeError: LocalizedError {
    case noCapture, permissionMissing, sourceClosed, selectionChanged, replacementUnavailable, writeFailed

    var errorDescription: String? {
        switch self {
        case .noCapture: "这段文字没有可替换的来源选区。"
        case .permissionMissing: "需要辅助功能权限才能替换来源应用中的文字。"
        case .sourceClosed: "来源应用已关闭，请重新选中文字。"
        case .selectionChanged: "来源选区已变化，请重新选中文字后再替换。"
        case .replacementUnavailable: "来源应用不支持直接替换选区，请复制结果后手动粘贴。"
        case .writeFailed: "来源应用未接受替换，请复制结果后手动粘贴。"
        }
    }
}

/// Reads only after an explicit shortcut/action. The saved AX element binds a
/// replacement to its source process; no writes are sent to the current front app.
@MainActor
final class SelectionBridge {
    private(set) var capturedSelection: SelectionCapture?
    private var targetElement: AXUIElement?
    private var targetRange: CFTypeRef?
    private var replacementSupported = false
    var canReplace: Bool {
        capturedSelection != nil && targetElement != nil && targetRange != nil && replacementSupported && AXIsProcessTrusted()
    }

    @discardableResult
    func captureSelection() -> SelectionCapture? {
        clearCapture()
        guard AXIsProcessTrusted(), let source = NSWorkspace.shared.frontmostApplication,
              source.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(source.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.25)
        guard let selected = attribute(element, kAXSelectedTextAttribute) as? String, !selected.isEmpty else { return nil }
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success, elementPID == source.processIdentifier else { return nil }
        var settable = DarwinBoolean(false)
        replacementSupported = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        targetRange = attribute(element, kAXSelectedTextRangeAttribute)
        targetElement = element
        let capture = SelectionCapture(text: selected, sourceName: source.localizedName ?? "来源应用",
            sourceBundleIdentifier: source.bundleIdentifier, sourcePID: source.processIdentifier)
        capturedSelection = capture
        return capture
    }

    func clearCapture() {
        capturedSelection = nil
        targetElement = nil
        targetRange = nil
        replacementSupported = false
    }

    func replaceSelectedText(_ replacement: String) throws {
        guard AXIsProcessTrusted() else { throw SelectionBridgeError.permissionMissing }
        guard let capture = capturedSelection, let element = targetElement else { throw SelectionBridgeError.noCapture }
        guard let targetRange else { throw SelectionBridgeError.replacementUnavailable }
        guard let application = NSRunningApplication(processIdentifier: capture.sourcePID), !application.isTerminated,
              application.bundleIdentifier == capture.sourceBundleIdentifier else { throw SelectionBridgeError.sourceClosed }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == capture.sourcePID else { throw SelectionBridgeError.sourceClosed }
        let sourceApp = AXUIElementCreateApplication(capture.sourcePID)
        AXUIElementSetMessagingTimeout(sourceApp, 0.25)
        guard let current = attribute(sourceApp, kAXFocusedUIElementAttribute), CFEqual(current, element),
              let selected = attribute(element, kAXSelectedTextAttribute) as? String,
              selected == capture.text else { throw SelectionBridgeError.selectionChanged }
        guard let currentRange = attribute(element, kAXSelectedTextRangeAttribute), CFEqual(currentRange, targetRange) else {
            throw SelectionBridgeError.selectionChanged
        }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { throw SelectionBridgeError.replacementUnavailable }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString) == .success else {
            throw SelectionBridgeError.writeFailed
        }
        clearCapture()
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
