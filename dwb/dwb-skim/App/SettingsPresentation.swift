import Foundation

/// Presentation-only constants for the AppKit Settings controller.
/// Persistence and side effects remain owned by their existing stores.
enum SettingsPresentation {
    /// Semantic accent roles used only by the Settings surface. The color lookup
    /// remains in the AppKit controller so this presentation model stays pure
    /// and straightforward to regression-test.
    enum AccentRole: CaseIterable, Equatable {
        case primaryEmphasis
        case selectedSidebarFill
        case focusKeyline
        case structuralSeparator
        case informationalLink
        case shortcutKeyline
    }

    enum BrandToken: Equatable {
        case darkTeal
        case darkTeal500
    }
    struct Pane: Equatable {
        let identifier: String
        let title: String
    }

    struct AboutDisplayValues: Equatable {
        let productName: String
        let version: String
        let build: String
        let minimumSystemVersion: String
    }

    static let selectedPaneDefaultsKey = "dwb.settings.selectedPane"
    static let windowTitle = "Settings"

    static let panes = [
        Pane(identifier: "playback", title: "Playback"),
        Pane(identifier: "skimPreview", title: "Skim Preview"),
        Pane(identifier: "skimPlus", title: "Skim+"),
        Pane(identifier: "controls", title: "Controls"),
        Pane(identifier: "queueFiles", title: "Queue & Files"),
        Pane(identifier: "shortcuts", title: "Shortcuts"),
        Pane(identifier: "advanced", title: "Advanced"),
        Pane(identifier: "about", title: "About"),
    ]
    static let paneIdentifiers = panes.map(\.identifier)
    static let sidebarUsesSymbols = false
    static let usesPlayerPeriwinkleAsPrimaryAccent = false

    static let minimumWindowSize = CGSize(width: 760, height: 500)
    static let defaultWindowSize = CGSize(width: 820, height: 550)
    static let sidebarWidth: CGFloat = 188
    static let sidebarRowHeight: CGFloat = 32
    static let pageLeadingInset: CGFloat = 30
    static let pageTrailingInset: CGFloat = 26
    static let pageTopInset: CGFloat = 54
    static let pageBottomInset: CGFloat = 28
    static let maximumContentWidth: CGFloat = 620
    static let labelColumnWidth: CGFloat = 156
    static let columnSpacing: CGFloat = 14
    static let rowSpacing: CGFloat = 13
    static let sectionSpacing: CGFloat = 26
    static let helperMaximumWidth: CGFloat = 390
    static let sliderWidth: CGFloat = 190

    /// dwb skim owns dark teal; periwinkle remains a dwb player identity color.
    static func brandToken(for accentRole: AccentRole) -> BrandToken {
        switch accentRole {
        case .structuralSeparator:
            return .darkTeal
        case .primaryEmphasis, .selectedSidebarFill, .focusKeyline,
             .informationalLink, .shortcutKeyline:
            return .darkTeal500
        }
    }

    static func validatedPaneIdentifier(_ value: String?) -> String {
        guard let value, paneIdentifiers.contains(value) else { return paneIdentifiers[0] }
        return value
    }

    /// Resolves the pane a Settings open request should select.
    /// An explicit, known request wins; otherwise the stored pane is restored so
    /// reopening Settings returns to the category the user left it on.
    static func resolvedPaneIdentifier(requested: String?, stored: String?) -> String {
        if let requested, paneIdentifiers.contains(requested) { return requested }
        return validatedPaneIdentifier(stored)
    }

    static func paneHeading(for identifier: String) -> String {
        panes.first(where: { $0.identifier == validatedPaneIdentifier(identifier) })?.title ?? panes[0].title
    }

    static func aboutDisplayValues(infoDictionary: [String: Any]?) -> AboutDisplayValues {
        let productName = (infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (infoDictionary?["CFBundleName"] as? String)
            ?? "dwb skim"
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        let minimumSystemVersion = infoDictionary?["LSMinimumSystemVersion"] as? String ?? "13.0"
        return AboutDisplayValues(productName: productName,
                                  version: version,
                                  build: build,
                                  minimumSystemVersion: minimumSystemVersion)
    }

    static let productDescription = "A focused, non-destructive skim-review app for local video, images, and GIFs."

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

    // MARK: - Progressive Random Skim Coverage Intensity

    static let progressiveRandomSkimIntensityOptions: [ProgressiveRandomSkimIntensity] = ProgressiveRandomSkimIntensity.allCases
    static let progressiveRandomSkimIntensityLabels: [String] = progressiveRandomSkimIntensityOptions.map(\.displayTitle)
    static let progressiveRandomSkimCoverageHelperText = "How many Progressive Random Skim segments to sample across the video.\nSnippet lengths follow the Clip Duration settings above."

    static func intensitySegment(for intensity: ProgressiveRandomSkimIntensity) -> Int {
        switch intensity {
        case .light: return 0
        case .standard: return 1
        case .thorough: return 2
        case .ultra: return 3
        case .max: return 4
        }
    }

    static func intensity(forSegment segment: Int) -> ProgressiveRandomSkimIntensity {
        switch segment {
        case 0: return .light
        case 1: return .standard
        case 2: return .thorough
        case 3: return .ultra
        case 4: return .max
        default: return .standard
        }
    }
}
