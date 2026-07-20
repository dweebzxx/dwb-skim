import Cocoa

/// Custom `NSApplication` subclass used purely as the Double-tap Option
/// interception point.
///
/// `sendEvent(_:)` is the earliest application-local place every keyboard event
/// passes through, ahead of key-equivalent handling, responder-chain dispatch,
/// and field editors, and it needs no Accessibility or Input Monitoring
/// permission. The coordinator observes; it never consumes. `super.sendEvent`
/// is called unconditionally so no event is ever swallowed, including when the
/// coordinator is absent or throws off a gesture.
final class SkimApplication: NSApplication {

    /// The single application-scoped recognizer. Assigned once by AppDelegate
    /// during launch; there are no per-window monitors.
    var optionDoubleTapCoordinator: OptionDoubleTapCoordinator?

    override func sendEvent(_ event: NSEvent) {
        SkimApplicationEventDispatch.dispatch(event, to: optionDoubleTapCoordinator) { event in
            super.sendEvent(event)
        }
    }
}
