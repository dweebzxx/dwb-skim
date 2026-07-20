import Foundation

/// Presentation-only constants for the AppKit Settings controller.
/// Persistence and side effects remain owned by their existing stores.
enum SettingsPresentation {
    static let selectedPaneDefaultsKey = "dwb.settings.selectedPane"

    static let paneIdentifiers = [
        "playback", "skimPreview", "skimPlus", "controls",
        "queueFiles", "shortcuts", "advanced", "about",
    ]

    static let minimumWindowSize = CGSize(width: 760, height: 480)
    static let defaultWindowSize = CGSize(width: 840, height: 560)
    static let sidebarWidth: CGFloat = 210
    static let pageInset: CGFloat = 22
    static let maximumContentWidth: CGFloat = 560
    static let labelColumnWidth: CGFloat = 150
    static let columnSpacing: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 24

    static func validatedPaneIdentifier(_ value: String?) -> String {
        guard let value, paneIdentifiers.contains(value) else { return paneIdentifiers[0] }
        return value
    }

    /// Every interactive or informational settings row, retained for inventory and regression tests.
    static let representedSettingLabels = [
        "Playback speed", "Show title overlay on playback start", "Image duration", "GIF loops",
        "Normalize video audio", "Video", "Images", "GIF", "Clip duration", "Fixed duration",
        "Random minimum", "Random maximum", "Start position", "Skip intro", "Audio track", "Selected",
        "Audio mix", "Background audio volume", "Auto-hide playback overlay", "Hide delay",
        "Reduce overlay motion", "Auto-hide titlebar", "Complete video mode in windowed playback", "Window opacity",
        "Primary custom prefix", "Secondary custom prefix", "Queue order", "Loop queue",
        "Open queue panel when a player window opens", "Show debug console", "Verbose autoplay diagnostics",
        "Clear All Bookmarks...", "Restore All Settings to Default",
    ]
}
