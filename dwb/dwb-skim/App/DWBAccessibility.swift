import AppKit

/// The one shared place for Increase Contrast and Reduce Motion (design system sections 6 and 7).
/// Views read the values here, and observe `didChange` to update live when the system setting flips.
enum DWBAccessibility {
    /// Posted once on the main queue whenever the system's display accessibility options change.
    static let didChange = Notification.Name("dwb.accessibilityDidChange")

    private static var observer: NSObjectProtocol?

    /// Starts forwarding the system notification as `didChange`. Safe to call more than once.
    static func install() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// The in-app "Reduce overlay motion" setting (which defaults to the system value) together
    /// with the system flag. Hold times never change; only fades and growth do.
    static var reduceMotion: Bool {
        UserDefaults.standard.bool(forKey: SettingsWindowController.chromeReducedMotionKey)
            || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A fade duration that is zero under Reduce Motion.
    static func duration(_ base: TimeInterval = DWBMotion.fade) -> TimeInterval {
        DWBMotion.duration(base, reduceMotion: reduceMotion)
    }

    // MARK: - Increase Contrast color variants (section 6)

    static var backingChrome: NSColor { increaseContrast ? DWBColor.canvas : DWBColor.backingChrome }
    static var backingHUD: NSColor { increaseContrast ? DWBColor.canvas : DWBColor.backingHUD }
    static var backingTitle: NSColor { increaseContrast ? DWBColor.canvas : DWBColor.backingTitle }
    static var backingBadge: NSColor { increaseContrast ? DWBColor.canvas : DWBColor.backingBadge }

    static var border: NSColor { increaseContrast ? DWBColor.borderStrong : DWBColor.border }
    static var textSecondary: NSColor { increaseContrast ? DWBColor.textPrimary : DWBColor.textSecondary }
    static var textTertiary: NSColor { increaseContrast ? DWBColor.textSecondary : DWBColor.textTertiary }

    static var track: NSColor { increaseContrast ? DWBColor.track.withAlphaComponent(0.40) : DWBColor.track }
    static var tick: NSColor { increaseContrast ? DWBColor.tick.withAlphaComponent(0.85) : DWBColor.tick }

    /// Accent tint: 18%, or 28% under Increase Contrast.
    static var accentTint: NSColor { increaseContrast ? theme.accentTintStrong : theme.accentTint }

    static var focusRing: NSColor { theme.focusRing(increaseContrast: increaseContrast) }
    static var focusWidth: CGFloat { increaseContrast ? DWBMetrics.focusWidthIC : DWBMetrics.focusWidth }
}
