import Foundation

enum ShortcutFocusRouting {
    enum Control { case footerSection, queueDivider, button, other }

    static func focusedControlTakesKey(_ control: Control, keyCode: UInt16,
                                      modifiers: ShortcutModifiers = []) -> Bool {
        guard modifiers.isEmpty else { return false }
        switch control {
        case .footerSection: return keyCode == 49 || keyCode == 36
        case .queueDivider: return keyCode == 123 || keyCode == 124 || keyCode == 115
        case .button: return keyCode == 49
        case .other: return false
        }
    }
}
