import Foundation

/// Only configured, non-copy prefixes are delayed. Keeping the original events
/// allows an incomplete sequence to retain its native meaning (e.g. Ctrl+A).
struct ShortcutSequenceGate<Event> {
    struct Decision {
        var consumed = false
        var action: ShortcutAction?
        var replay: [(pid_t, Event)] = []
    }
    private var matcher: ShortcutSequenceMatcher
    private var pending: [(pid_t, Event)] = []
    private var held = Set<UInt16>()
    private var suppressedUps = Set<UInt16>()
    private var lastTimestamp: TimeInterval?
    private var sourcePID: pid_t?
    var isPending: Bool { !pending.isEmpty }

    init(bindings: [ShortcutAction: ShortcutBinding]) {
        matcher = ShortcutSequenceMatcher(bindings: bindings.filter { !$0.value.startsWithNativeCopy })
    }

    mutating func flush() -> [(pid_t, Event)] {
        let events = pending
        pending.removeAll()
        held.removeAll()
        matcher.reset()
        lastTimestamp = nil
        sourcePID = nil
        return events
    }

    mutating func process(_ event: Event, stroke: ShortcutStroke, down: Bool, isRepeat: Bool,
                          timestamp: TimeInterval, sourcePID: pid_t) -> Decision {
        var result = Decision()
        if let lastTimestamp, timestamp < lastTimestamp || timestamp - lastTimestamp > ShortcutBinding.sequenceTimeout {
            result.replay += flush()
        }
        if let previous = self.sourcePID, previous != sourcePID { result.replay += flush() }
        if suppressedUps.contains(stroke.keyCode) {
            // A trigger may activate TrueL before its physical key-up arrives.
            if !down { suppressedUps.remove(stroke.keyCode) }
            if !down || isRepeat { result.consumed = true; return result }
            suppressedUps.remove(stroke.keyCode)
        }
        if !down {
            if held.remove(stroke.keyCode) != nil {
                pending.append((sourcePID, event))
                result.consumed = true
            }
            return result
        }
        if isRepeat {
            if held.contains(stroke.keyCode) {
                pending.append((sourcePID, event))
                result.consumed = true
            }
            return result
        }
        if matcher.isInProgress && !matcher.acceptsContinuation(stroke) { result.replay += flush() }
        result.action = matcher.process(stroke, timestamp: timestamp, sourcePID: sourcePID)
        if result.action != nil || matcher.isInProgress {
            pending.append((sourcePID, event))
            held.insert(stroke.keyCode)
            result.consumed = true
            self.sourcePID = sourcePID
            lastTimestamp = timestamp
            if result.action != nil {
                suppressedUps.formUnion(held)
                _ = flush()
            }
        }
        return result
    }
}
