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

    /// The design-system token a role resolves to (`DWBColor.border`, or the theme's accent tokens).
    enum DesignToken: Equatable {
        case border
        case accentText
        case accentTintStrong
        case accentFill
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

        /// The version line, for example `Version 1.2 · Build 3`.
        var versionLine: String { "Version \(version) \u{00B7} Build \(build)" }
    }

    /// One label and value pair in the About fact list.
    struct AboutFact: Equatable {
        let label: String
        let value: String
    }

    static let selectedPaneDefaultsKey = "dwb.settings.selectedPane"
    static let windowTitle = "Settings"

    /// A labeled run of sidebar pages. The standard is one sidebar order in every dwb app:
    /// General, then the app's own group (accent-labelled), then System.
    struct SidebarGroup: Equatable {
        let label: String
        /// The label is drawn in `accentText` instead of `textTertiary`.
        let isAccented: Bool
        let paneIdentifiers: [String]
    }

    private static let paneTitles: [String: String] = [
        "playback": "Playback",
        "controls": "Appearance & Controls",
        "queueFiles": "Queue & Files",
        "shortcuts": "Shortcuts",
        "skimPreview": "Skim Preview",
        "skimPlus": "dwb+",
        "advanced": "Advanced",
        "about": "About",
    ]

    static let sidebarGroups: [SidebarGroup] = [
        SidebarGroup(label: "General", isAccented: false,
                     paneIdentifiers: ["playback", "controls", "queueFiles", "shortcuts"]),
        SidebarGroup(label: "dwb skim", isAccented: true,
                     paneIdentifiers: ["skimPreview", "skimPlus"]),
        SidebarGroup(label: "System", isAccented: false,
                     paneIdentifiers: ["advanced", "about"]),
    ]

    /// The pages in sidebar order. Arrow-key and Tab order follow this list.
    static let panes: [Pane] = sidebarGroups
        .flatMap(\.paneIdentifiers)
        .map { Pane(identifier: $0, title: paneTitles[$0] ?? $0) }

    /// The one-sentence page description under the page title (`KIT_DESC`). Empty for About,
    /// which has no page header.
    static let pageDescriptions: [String: String] = [
        "playback": "Video playback, image timing, and GIF loops.",
        "controls": "Customize playback controls and window appearance.",
        "queueFiles": "Choose accepted media, queue behavior, and filename prefixes.",
        "shortcuts": ShortcutsPresentation.pageDescription,
        "skimPreview": "Choose preview duration, start position, and video coverage.",
        "skimPlus": "Play a background track on its own or alongside video audio.",
        "advanced": "Diagnostics, bookmarks, and default settings.",
        "about": "",
    ]

    static func pageDescription(for identifier: String) -> String {
        pageDescriptions[validatedPaneIdentifier(identifier)] ?? ""
    }

    /// Every page except About starts with a title, its description, and a hairline.
    static func showsPageHeader(for identifier: String) -> Bool {
        validatedPaneIdentifier(identifier) != "about"
    }

    static let paneIdentifiers = panes.map(\.identifier)
    static let sidebarUsesSymbols = false

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

    /// Emphasis, section headers, and links are `accentText`; the selected sidebar row is
    /// `accentTintStrong`; focus and shortcut keylines are `accentFill`; the structural
    /// separator is the neutral `border`.
    static func designToken(for accentRole: AccentRole) -> DesignToken {
        switch accentRole {
        case .structuralSeparator:
            return .border
        case .primaryEmphasis, .informationalLink:
            return .accentText
        case .selectedSidebarFill:
            return .accentTintStrong
        case .focusKeyline, .shortcutKeyline:
            return .accentFill
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

    static let productDescription = "Quickly review local videos with short previews, alongside images and GIFs."

    /// The About fact list, in display order. Every value comes from the bundle or the running
    /// VLC library; nothing is a fixed sample. `vlcBackendVersion` is the runtime library version.
    static func aboutFacts(values: AboutDisplayValues, vlcBackendVersion: String) -> [AboutFact] {
        [
            AboutFact(label: "License", value: "MIT License"),
            AboutFact(label: "Requires", value: "macOS \(values.minimumSystemVersion) or later"),
            AboutFact(label: "Interface", value: "AppKit"),
            AboutFact(label: "Playback framework", value: "VLCKit"),
            AboutFact(label: "VLC backend", value: vlcBackendVersion),
        ]
    }

    static let aboutRepositoryLinkTitle = "View on GitHub"
    static let aboutIssuesLinkTitle = "Report an Issue"

    /// Every interactive or informational settings row, retained for inventory and regression tests.
    static let representedSettingLabels = [
        "Playback speed", "Show filename when playback starts", "Image duration", "GIF loops",
        "Normalize video audio", "Videos", "Images", "GIFs", "Clip duration", "Fixed duration",
        "Minimum duration", "Maximum duration", "Start previews", "Skip intro", "Coverage",
        "Enable background audio", "Audio track", "Selected",
        "Audio mix", "Background audio volume", "Automatically hide playback controls", "Hide delay",
        "Reduce motion in playback controls", "Automatically hide title bar", "Hide title bar", "Window opacity",
        "Primary prefix", "Secondary prefix", "Advance after applying a prefix", "Queue order", "Loop queue",
        "Show queue panel in new player windows", "Show debug console", "Detailed autoplay logging",
        "Clear All Bookmarks\u{2026}", "Restore Default Settings\u{2026}",
    ]

    // MARK: - Playback, Appearance & Controls, and Queue & Files text

    /// The section headings, rows, and supporting text of the three General pages that carry
    /// the suite settings design. Sentence case throughout.
    enum Text {
        // Playback
        static let playbackSections = ["Video", "Images & GIFs", "Audio"]
        static let playbackSpeedLabel = "Playback speed"
        static let playbackSpeedHelper = "Affects video only. Applies to the most recently active player window."
        static let showFilenameTitle = "Show filename when playback starts"
        static let imageDurationLabel = "Image duration"
        static let imageDurationUnit = "seconds"
        static let imageDurationHelper = "Advance to the next item after this duration."
        static let gifLoopsLabel = "GIF loops"
        static let gifLoopsUnit = "loops"
        static let gifLoopsHelper = "Advance after this many complete animation loops."
        static let normalizeVideoAudioTitle = "Normalize video audio"
        static let normalizeVideoAudioHelper = "Adjusts video loudness in real time. Does not affect dwb+ background audio."

        // Appearance & Controls
        static let controlsSections = ["Playback controls", "Window"]
        static let autoHidePlaybackControlsTitle = "Automatically hide playback controls"
        static let hideDelayLabel = "Hide delay"
        static let reduceMotionTitle = "Reduce motion in playback controls"
        static let autoHideTitleBarTitle = "Automatically hide title bar"
        static let hideTitleBarTitle = "Hide title bar"
        static let hideTitleBarHelper = "Removes the title bar while keeping the player windowed."
        static let windowOpacityLabel = "Window opacity"
        static let windowOpacityHelper = "Applies to the most recently active player window."

        // Queue & Files
        static let queueFilesSections = ["Accepted media", "Queue behavior", "Filename prefixes"]
        static let acceptedMediaTitles = ["Videos", "Images", "GIFs"]
        static let acceptedMediaHelper = "Choose which media types can be added to the queue."
        static let queueOrderLabel = "Queue order"
        static let queueOrderHelper = "Sequential follows the queue order. Shuffle randomizes each cycle. Weighted prioritizes unplayed items, then those played least recently."
        static let loopQueueTitle = "Loop queue"
        static let showQueuePanelTitle = "Show queue panel in new player windows"
        static let filenamePrefixesDescription = "Applying a prefix renames the actual file in its current folder. The file extension is preserved."
        static let primaryPrefixLabel = "Primary prefix"
        static let secondaryPrefixLabel = "Secondary prefix"
        static let primaryPrefixPlaceholder = "e.g. select_"
        static let secondaryPrefixPlaceholder = "e.g. later_"
        static let prefixGuidance = "Leave a prefix blank to disable its action. Prefixes replace each other rather than stack. Each prefix ends in exactly one underscore."
        static let advanceAfterPrefixTitle = "Advance after applying a prefix"
        static let advanceAfterPrefixHelper = "Play the next item after the primary or secondary prefix shortcut adds or replaces a prefix on the current item. Removing a prefix, marking multiple files, or using queue footer actions does not advance playback."

        // Skim Preview
        static let skimPreviewSections = ["Preview duration", "Start position", "Progressive sampling"]
        static let clipDurationLabel = "Clip duration"
        static let clipDurationModeTitles = ["Fixed", "Random"]
        static let fixedDurationLabel = "Fixed duration"
        static let fixedDurationHelper = "Enter 0 to play the full file."
        static let minimumDurationLabel = "Minimum duration"
        static let maximumDurationLabel = "Maximum duration"
        static let startPreviewsLabel = "Start previews"
        static let startPreviewsTitles = ["Beginning", "Random"]
        static let skipIntroLabel = "Skip intro"
        static let skipIntroHelper = "Sets the earliest point where a preview can begin."
        static let progressiveRandomSkimTitle = "Progressive Random Skim"
        static let progressiveRandomSkimHelper = "Sample several non-overlapping segments in chronological order before advancing to the next file. Short videos use a single preview."
        static let coverageLabel = "Coverage"
        static let coverageHelper = "Controls how many segments are sampled. Segment lengths follow the preview duration settings above."

        // dwb+
        static let skimPlusSections = ["Background audio", "Audio mix"]
        static let enableBackgroundAudioTitle = "Enable background audio"
        static let enableBackgroundAudioHelper = "Turning this off keeps your selected track and audio settings."
        static let audioTrackLabel = "Audio track"
        static let chooseAudioTrackTitle = "Choose Audio Track\u{2026}"
        static let selectedTrackLabel = "Selected"
        static let noAudioTrackSelected = "No audio track selected"
        static let clearAudioTrackTitle = "Clear"
        static let audioTrackHelper = "Choose one local MP3 or M4A file."
        static let backgroundAudioOnlyHelper = "Play the background track without video audio."
        static let videoAndBackgroundAudioHelper = "Play video audio and background audio together."
        static let backgroundAudioVolumeLabel = "Background audio volume"

        // Advanced
        static let advancedSections = ["Diagnostics", "Bookmarks", "Reset"]
        static let showDebugConsoleTitle = "Show debug console"
        static let detailedAutoplayLoggingTitle = "Detailed autoplay logging"
        /// The autoplay trace runs only inside `#if DEBUG` (`PlayerWindowController`).
        static let detailedAutoplayLoggingHelper = "Records additional autoplay diagnostics in debug builds only."
        static let clearAllBookmarksTitle = "Clear All Bookmarks\u{2026}"
        static let clearAllBookmarksHelper = "Clears this app's bookmarks without deleting media files. This cannot be undone."
        static let clearBookmarksConfirmTitle = "Clear all bookmarks for dwb skim?"
        static let clearBookmarksConfirmMessage = "This removes all bookmarks saved by this app. Media files are not deleted. This cannot be undone."
        static let clearBookmarksConfirmAction = "Clear All Bookmarks"
        static let restoreDefaultSettingsTitle = "Restore Default Settings\u{2026}"
        static let restoreDefaultSettingsHelper = "Restores this app's settings and keyboard shortcuts. Media files, queues, and bookmarks are not deleted."
        static let restoreConfirmTitle = "Restore default settings for dwb skim?"
        static let restoreConfirmMessage = "This resets this app's settings and customized keyboard shortcuts. Media files, queues, and bookmarks are not deleted."
        static let restoreConfirmAction = "Restore Defaults"
    }

    // MARK: - Dependent rows

    /// Hide delay applies only while playback controls hide automatically. Off disables the
    /// popup; the saved delay is kept.
    static func hideDelayIsEnabled(automaticallyHidesPlaybackControls: Bool) -> Bool {
        automaticallyHidesPlaybackControls
    }

    /// Automatically hide title bar does not apply while Hide title bar is on. On disables the
    /// checkbox; its saved value is kept.
    static func automaticTitleBarHidingIsEnabled(hidesTitleBar: Bool) -> Bool {
        !hidesTitleBar
    }

    /// Fixed duration applies in Fixed mode. Off disables the field; its value is kept.
    static func fixedDurationIsEnabled(previewDurationMode: String) -> Bool {
        SettingsDefaultsRegistry.validatedPreviewDurationMode(previewDurationMode)
            == SettingsDefaultsRegistry.Defaults.previewDurationModeFixed
    }

    /// Minimum and Maximum duration apply in Random mode. Off disables the fields; their values are kept.
    static func randomDurationIsEnabled(previewDurationMode: String) -> Bool {
        !fixedDurationIsEnabled(previewDurationMode: previewDurationMode)
    }

    /// Coverage applies while Progressive Random Skim is on. Off disables the menu; the choice is kept.
    static func coverageIsEnabled(progressiveRandomSkimEnabled: Bool) -> Bool {
        progressiveRandomSkimEnabled
    }

    /// The mix control and the volume slider apply only while background audio is on and the
    /// selected track is available. Disabled, they keep their values.
    static func audioMixControlsAreEnabled(backgroundAudioEnabled: Bool, trackIsAvailable: Bool) -> Bool {
        backgroundAudioEnabled && trackIsAvailable
    }

    static func audioMixHelperText(for mode: BackgroundAudioMixMode) -> String {
        switch mode {
        case .uploadedOnly: return Text.backgroundAudioOnlyHelper
        case .videoAndUploaded: return Text.videoAndBackgroundAudioHelper
        }
    }

    // MARK: - Playback speed popup

    /// The title of a speed in the Settings popup: `0.25×`, `1.00× (Normal)`. The menus keep
    /// `PlaybackSpeedOption.title`. Normal speed is a rate of 1 (`PlaybackSpeedOption.normalRate`).
    static func speedPopupTitle(forRate rate: Float) -> String {
        let value = String(format: "%.2f\u{00D7}", rate)
        return rate == 1 ? "\(value) (Normal)" : value
    }

    // MARK: - Prefix shortcut text

    /// The supporting text under a prefix field. One key reads `Shortcut: N`, several read
    /// `Shortcuts: N, H` in assignment order, and none reads `Shortcut: Unassigned`.
    static func prefixShortcutText(keys: [String]) -> String {
        switch keys.count {
        case 0: return "Shortcut: Unassigned"
        case 1: return "Shortcut: \(keys[0])"
        default: return "Shortcuts: \(keys.joined(separator: ", "))"
        }
    }

    /// The supporting line under a prefix field, from the keys currently in use for its action
    /// (the defaults, or the user's own). `ShortcutStore` is the one place those are read.
    static func prefixShortcutLine(for shortcut: SkimKeyboardShortcut, store: ShortcutStore = .shared) -> String {
        prefixShortcutText(keys: store.activeKeys(for: shortcut.commandID).map(\.capText))
    }

    // MARK: - Progressive Random Skim Coverage

    static let progressiveRandomSkimIntensityOptions: [ProgressiveRandomSkimIntensity] = ProgressiveRandomSkimIntensity.allCases
    static let progressiveRandomSkimIntensityLabels: [String] = progressiveRandomSkimIntensityOptions.map(\.displayTitle)

    private static let segmentLineTail = "moves to a later progressive segment. At the final segment, it does not advance to the next file."

    /// The second supporting line under Progressive Random Skim. It names the keys now assigned to
    /// Next Progressive Random Skim segment by their spoken names, joined with ` or `.
    static func nextSkimSegmentLine(keys: [ShortcutKey]) -> String {
        guard !keys.isEmpty else {
            return "Next Progressive Random Skim segment has no shortcut. When assigned, it \(segmentLineTail)"
        }
        return "\(keys.map(\.spokenText).joined(separator: " or ")) \(segmentLineTail)"
    }

    /// The same line from the keys currently in use (the defaults, or the user's own).
    static func nextSkimSegmentLine(store: ShortcutStore = .shared) -> String {
        nextSkimSegmentLine(keys: store.activeKeys(for: .nextSkimSegment))
    }

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
