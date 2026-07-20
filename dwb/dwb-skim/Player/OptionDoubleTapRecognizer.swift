import Cocoa

enum OptionKeySide: Equatable, Hashable {
    case left
    case right
}

struct OptionDoubleTapRecognizer {
    private enum State: Equatable {
        case idle
        case pressed(side: OptionKeySide, firstCompletedAt: TimeInterval?)
        case waiting(firstCompletedAt: TimeInterval)
        case invalidUntilRelease(side: OptionKeySide)
    }

    private var state: State = .idle
    let maximumInterval: TimeInterval

    init(maximumInterval: TimeInterval = 0.4) {
        self.maximumInterval = maximumInterval
    }

    var waitingDeadline: TimeInterval? {
        guard case .waiting(let firstCompletedAt) = state else { return nil }
        return firstCompletedAt + maximumInterval
    }

    mutating func optionChanged(side: OptionKeySide,
                                isDown: Bool,
                                isRepeat: Bool,
                                timestamp: TimeInterval,
                                isEligible: Bool) -> Bool {
        guard isEligible else {
            reset()
            return false
        }
        expireIfNeeded(at: timestamp)

        if isDown {
            guard !isRepeat else { return false }
            switch state {
            case .idle:
                state = .pressed(side: side, firstCompletedAt: nil)
            case .waiting(let firstCompletedAt):
                state = .pressed(side: side, firstCompletedAt: firstCompletedAt)
            case .pressed, .invalidUntilRelease:
                break
            }
            return false
        }

        switch state {
        case .pressed(let pressedSide, let firstCompletedAt) where pressedSide == side:
            if let firstCompletedAt,
               timestamp - firstCompletedAt <= maximumInterval {
                state = .idle
                return true
            }
            state = .waiting(firstCompletedAt: timestamp)
        case .invalidUntilRelease(let invalidSide) where invalidSide == side:
            state = .idle
        default:
            break
        }
        return false
    }

    mutating func nonModifierKeyPressed() {
        switch state {
        case .pressed(let side, _):
            state = .invalidUntilRelease(side: side)
        default:
            state = .idle
        }
    }

    mutating func focusChanged() { reset() }

    mutating func timeout(at timestamp: TimeInterval) {
        expireIfNeeded(at: timestamp)
    }

    mutating func reset() { state = .idle }

    private mutating func expireIfNeeded(at timestamp: TimeInterval) {
        guard case .waiting(let completedAt) = state,
              timestamp - completedAt > maximumInterval else { return }
        state = .idle
    }
}

enum OptionDoubleTapEventKind: Equatable {
    case flagsChanged
    case keyDown
    case keyUp
}

/// A testable representation of the AppKit fields that affect the shortcut.
/// Modifier flags are normalized by the adapter, not by callers.
struct OptionDoubleTapEventSnapshot: Equatable {
    let kind: OptionDoubleTapEventKind
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let isRepeat: Bool
    let timestamp: TimeInterval

    init(kind: OptionDoubleTapEventKind,
         keyCode: UInt16,
         modifierFlags: NSEvent.ModifierFlags,
         isRepeat: Bool = false,
         timestamp: TimeInterval) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.isRepeat = isRepeat
        self.timestamp = timestamp
    }

    init?(event: NSEvent) {
        let kind: OptionDoubleTapEventKind
        switch event.type {
        case .flagsChanged: kind = .flagsChanged
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        default: return nil
        }
        // -[NSEvent isARepeat] is only valid for keyDown/keyUp. Reading it on a
        // flagsChanged event raises NSInternalInconsistencyException ("Invalid
        // message sent to event"), which previously aborted snapshot creation
        // for every real Option press before the recognizer ever saw it.
        // Modifier-only events have no repeat concept, so report false.
        let isRepeat = (kind == .flagsChanged) ? false : event.isARepeat
        self.init(kind: kind,
                  keyCode: event.keyCode,
                  modifierFlags: event.modifierFlags,
                  isRepeat: isRepeat,
                  timestamp: event.timestamp)
    }

    var normalizedModifierFlags: NSEvent.ModifierFlags {
        modifierFlags.intersection(.deviceIndependentFlagsMask)
    }
}

/// Converts real AppKit event fields into complete per-side Option taps. AppKit
/// exposes only an aggregate Option flag, so the adapter retains side state to
/// distinguish a release while the other Option key remains pressed.
struct OptionDoubleTapEventAdapter {
    private var recognizer = OptionDoubleTapRecognizer()
    private var pressedOptionSides: Set<OptionKeySide> = []
    private var heldNonModifierKeyCodes: Set<UInt16> = []

    var waitingDeadline: TimeInterval? { recognizer.waitingDeadline }

    mutating func handle(_ snapshot: OptionDoubleTapEventSnapshot,
                         targetIsEligible: Bool) -> Bool {
        guard targetIsEligible else {
            reset()
            return false
        }

        switch snapshot.kind {
        case .keyDown:
            guard Self.optionSide(for: snapshot.keyCode) == nil else { return false }
            heldNonModifierKeyCodes.insert(snapshot.keyCode)
            recognizer.nonModifierKeyPressed()
            return false
        case .keyUp:
            heldNonModifierKeyCodes.remove(snapshot.keyCode)
            return false
        case .flagsChanged:
            break
        }

        let flags = snapshot.normalizedModifierFlags
        let hasForbiddenChord = !flags.intersection([.command, .control, .shift]).isEmpty
        guard let side = Self.optionSide(for: snapshot.keyCode) else {
            if flags.contains(.option) && hasForbiddenChord {
                recognizer.nonModifierKeyPressed()
            }
            return false
        }

        guard !snapshot.isRepeat, !hasForbiddenChord, heldNonModifierKeyCodes.isEmpty else {
            recognizer.nonModifierKeyPressed()
            return false
        }

        let isDown: Bool
        if pressedOptionSides.contains(side) {
            // With one known side down, a remaining aggregate Option bit is a
            // duplicate press transition. With both sides down it is the valid
            // release of this side while the other side remains pressed.
            guard !flags.contains(.option) || pressedOptionSides.count > 1 else { return false }
            pressedOptionSides.remove(side)
            isDown = false
        } else {
            // An Option-up transition after a reset has no matching press and
            // must not become a tap by itself.
            guard flags.contains(.option) else { return false }
            pressedOptionSides.insert(side)
            isDown = true
        }

        return recognizer.optionChanged(side: side,
                                        isDown: isDown,
                                        isRepeat: false,
                                        timestamp: snapshot.timestamp,
                                        isEligible: true)
    }

    mutating func timeout(at timestamp: TimeInterval) {
        recognizer.timeout(at: timestamp)
    }

    mutating func reset() {
        recognizer.reset()
        pressedOptionSides.removeAll()
        heldNonModifierKeyCodes.removeAll()
    }

    private static func optionSide(for keyCode: UInt16) -> OptionKeySide? {
        switch keyCode {
        case 58: return .left
        case 61: return .right
        default: return nil
        }
    }
}

/// Small, pure routing model used by the application adapter and its tests.
struct OptionDoubleTapTargetDescriptor: Equatable {
    let identifier: String
    let isPlayerWindow: Bool
    let isKeyWindow: Bool
    let isTextEntryFocused: Bool

    static func keyPlayerIdentifier(applicationIsActive: Bool,
                                    targets: [OptionDoubleTapTargetDescriptor]) -> String? {
        guard applicationIsActive else { return nil }
        return targets.first {
            $0.isPlayerWindow && $0.isKeyWindow && !$0.isTextEntryFocused
        }?.identifier
    }
}

/// Application-scoped gesture coordinator. Exactly one instance exists, owned by
/// the custom `NSApplication` subclass, which feeds it every event from
/// `sendEvent(_:)` before normal AppKit routing and then always forwards the
/// original event. The coordinator never consumes or rewrites events.
///
/// A local `NSEvent` monitor was the previous interception layer. It is not used
/// any more: it added a failure surface without adding reach, and `sendEvent` is
/// the earliest application-local point that cannot be bypassed by responder,
/// menu, or field-editor handling. Neither path requires Accessibility or Input
/// Monitoring permission.
final class OptionDoubleTapCoordinator {
    private var adapter = OptionDoubleTapEventAdapter()
    private var observerTokens: [NSObjectProtocol] = []
    private var timeoutWorkItem: DispatchWorkItem?
    private var isStarted = false
    private let notificationCenter: NotificationCenter
    private let targetIsEligible: () -> Bool
    private let onToggle: () -> Void

    init(notificationCenter: NotificationCenter = .default,
         targetIsEligible: @escaping () -> Bool,
         onToggle: @escaping () -> Void) {
        self.notificationCenter = notificationCenter
        self.targetIsEligible = targetIsEligible
        self.onToggle = onToggle
    }

    var isInstalled: Bool { isStarted }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        for name in [NSApplication.didResignActiveNotification,
                     NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeKeyNotification,
                     NSWindow.willCloseNotification] {
            observerTokens.append(notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reset()
            })
        }
    }

    func stop() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        observerTokens.forEach(notificationCenter.removeObserver)
        observerTokens.removeAll()
        adapter.reset()
        isStarted = false
    }

    deinit { stop() }

    /// Called from `sendEvent(_:)` for every event. Returns true when this event
    /// completed a double tap, purely so tests can assert the dispatch contract;
    /// the caller forwards the event regardless of the result.
    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard let snapshot = OptionDoubleTapEventSnapshot(event: event) else { return false }
        return handle(snapshot)
    }

    @discardableResult
    func handle(_ snapshot: OptionDoubleTapEventSnapshot) -> Bool {
        let didToggle = adapter.handle(snapshot, targetIsEligible: targetIsEligible())
        if didToggle { onToggle() }
        scheduleTimeoutIfNeeded(after: snapshot)
        return didToggle
    }

    func reset() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        adapter.reset()
    }

    private func scheduleTimeoutIfNeeded(after snapshot: OptionDoubleTapEventSnapshot) {
        timeoutWorkItem?.cancel()
        guard let deadline = adapter.waitingDeadline else { return }
        let delay = max(0, deadline - snapshot.timestamp)
        let workItem = DispatchWorkItem { [weak self] in
            self?.adapter.timeout(at: deadline)
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
