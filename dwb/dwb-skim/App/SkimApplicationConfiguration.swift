import Cocoa

/// The body of `SkimApplication.sendEvent(_:)`, extracted so the "observe, then
/// always forward" contract is testable without instantiating a second
/// NSApplication in the test process.
enum SkimApplicationEventDispatch {
    static func dispatch(_ event: NSEvent,
                         to coordinator: OptionDoubleTapCoordinator?,
                         forward: (NSEvent) -> Void) {
        // Observation must never be able to drop an event, so the forward is not
        // conditional on the coordinator existing or on the gesture outcome.
        coordinator?.handle(event)
        forward(event)
    }
}

/// Names the principal application class in one place so `main.swift`, the
/// Info.plist `NSPrincipalClass` entry, and the tests that guard them cannot
/// drift apart. The Swift module name is part of the Objective-C runtime name,
/// so both components are asserted separately by the tests.
enum SkimApplicationConfiguration {
    static let moduleName = "dwb_skim"
    static let className = "SkimApplication"
    static let principalClassName = "\(moduleName).\(className)"
}
