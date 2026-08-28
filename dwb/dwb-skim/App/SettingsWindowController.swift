import Cocoa
import UniformTypeIdentifiers
import VLCKitSPM

extension Notification.Name {
    static let autoHideSettingChanged = Notification.Name("dwb.autoHideSettingChanged")
    static let transportVisibilityChanged = Notification.Name("dwb.transportVisibilityChanged")
    static let autoHideTitlebarChanged = Notification.Name("dwb.autoHideTitlebarChanged")
    static let completeVideoWindowModeChanged = Notification.Name("dwb.completeVideoWindowModeChanged")
    static let acceptedMediaTypesChanged = Notification.Name("dwb.acceptedMediaTypesChanged")
    static let titleOverlaySettingChanged = Notification.Name("dwb.titleOverlaySettingChanged")
    static let customPrefixValueChanged = Notification.Name("dwb.customPrefixValueChanged")
    static let debugConsoleSettingChanged = Notification.Name("dwb.debugConsoleSettingChanged")
    static let playbackSpeedChanged = Notification.Name("dwb.playbackSpeedChanged")
}

final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {
    fileprivate enum SettingsColors {
        static func color(for role: SettingsPresentation.AccentRole) -> NSColor {
            switch SettingsPresentation.brandToken(for: role) {
            case .darkTeal:
                return SkimColors.darkTeal
            case .darkTeal500:
                return SkimColors.darkTeal500
            }
        }

        static let primaryEmphasis = color(for: .primaryEmphasis)
        static let selectedSidebarFill = color(for: .selectedSidebarFill)
        static let focusKeyline = color(for: .focusKeyline)
        static let structuralSeparator = color(for: .structuralSeparator)
        static let informationalLink = color(for: .informationalLink)
        static let shortcutKeyline = color(for: .shortcutKeyline)
    }

    private enum LayoutMetrics {
        static let maximumContentWidth = SettingsPresentation.maximumContentWidth
        static let labelWidth = SettingsPresentation.labelColumnWidth
        static let columnSpacing = SettingsPresentation.columnSpacing
        static let rowSpacing = SettingsPresentation.rowSpacing
        static let sectionSpacing = SettingsPresentation.sectionSpacing
        static let helperMaximumWidth = SettingsPresentation.helperMaximumWidth
    }

    enum Section: Int, CaseIterable {
        case playback
        case skimPreview
        case skimPlus
        case controls
        case queueFiles
        case shortcuts
        case advanced
        case about

        var title: String {
            SettingsPresentation.panes[rawValue].title
        }

        var identifier: String { SettingsPresentation.paneIdentifiers[rawValue] }

        static func restored() -> Section {
            let identifier = SettingsPresentation.validatedPaneIdentifier(
                UserDefaults.standard.string(forKey: SettingsPresentation.selectedPaneDefaultsKey)
            )
            return allCases.first(where: { $0.identifier == identifier }) ?? .playback
        }
    }

    static let shared = SettingsWindowController()
    fileprivate static let suiteAccent = SettingsColors.primaryEmphasis

    static let autoHideKey = SettingsDefaultsRegistry.Keys.autoHideTransportWindowed
    static let persistedVolumeKey = SettingsDefaultsRegistry.Keys.persistedVolume
    static let autoHideTitlebarKey = SettingsDefaultsRegistry.Keys.autoHideTitlebar
    static let completeVideoWindowModeKey = SettingsDefaultsRegistry.Keys.completeVideoWindowMode
    static let imageDurationKey = SettingsDefaultsRegistry.Keys.imageDurationSeconds
    static let gifLoopCountKey = SettingsDefaultsRegistry.Keys.gifLoopCount
    static let acceptVideoKey = SettingsDefaultsRegistry.Keys.acceptVideoMedia
    static let acceptImagesKey = SettingsDefaultsRegistry.Keys.acceptImageMedia
    static let acceptGIFKey = SettingsDefaultsRegistry.Keys.acceptGIFMedia
    static let showTitleOverlayKey = SettingsDefaultsRegistry.Keys.showTitleOverlay
    static let customPrefixValueKey = SettingsDefaultsRegistry.Keys.customPrefixValue
    static let customPrefixSecondaryValueKey = SettingsDefaultsRegistry.Keys.customPrefixSecondaryValue
    static let debugConsoleKey = SettingsDefaultsRegistry.Keys.debugConsoleEnabled
    static let verboseAutoplayTraceKey = SettingsDefaultsRegistry.Keys.verboseAutoplayTrace
    static let chromeAutohideThresholdKey = SettingsDefaultsRegistry.Keys.chromeAutohideThreshold
    static let chromeReducedMotionKey = SettingsDefaultsRegistry.Keys.chromeReducedMotion
    static let queuePanelOpenAtLaunchKey = SettingsDefaultsRegistry.Keys.queuePanelOpenAtLaunch
    static let playerWindowOpacityKey = SettingsDefaultsRegistry.Keys.playerWindowOpacity
    static let playerWindowOpacityMin = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacityMin)
    static let playerWindowOpacityMax = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacityMax)
    static let defaultPlayerWindowOpacityValue = CGFloat(SettingsDefaultsRegistry.Defaults.playerWindowOpacity)

    static let clipDurationKey = SettingsDefaultsRegistry.Keys.clipDurationSeconds
    static let skimEnabledKey = SettingsDefaultsRegistry.Keys.skimEnabled
    static let previewDurationModeKey = SettingsDefaultsRegistry.Keys.previewDurationMode
    static let previewDurationModeFixed = SettingsDefaultsRegistry.Defaults.previewDurationModeFixed
    static let previewDurationModeRandom = SettingsDefaultsRegistry.Defaults.previewDurationModeRandom
    static let randomPreviewMinimumKey = SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds
    static let randomPreviewMaximumKey = SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds
    static let startPositionModeKey = SettingsDefaultsRegistry.Keys.startPositionMode
    static let startPositionModeBeginning = SettingsDefaultsRegistry.Defaults.startPositionModeBeginning
    static let startPositionModeRandom = SettingsDefaultsRegistry.Defaults.startPositionModeRandom
    static let skipIntroKey = SettingsDefaultsRegistry.Keys.skipIntroSeconds
    static let queueOrderModeKey = SettingsDefaultsRegistry.Keys.queueOrderMode
    static let loopQueueEnabledKey = SettingsDefaultsRegistry.Keys.loopQueueEnabled

    static let githubURLString = "https://github.com/dweebzxx/dwb-skim"
    static let githubIssuesURLString = "https://github.com/dweebzxx/dwb-skim/issues"

    static let chromeThresholdOptions: [(seconds: Double, title: String)] = [
        (1, "1 second"), (1.5, "1.5 seconds"), (2, "2 seconds"),
        (3, "3 seconds"), (5, "5 seconds"), (8, "8 seconds"),
    ]

    static func registerDefaults() {
        SettingsDefaultsRegistry.register(
            reduceMotionDefault: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    static func clampedPlayerWindowOpacity(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultPlayerWindowOpacityValue }
        return min(playerWindowOpacityMax, max(playerWindowOpacityMin, value))
    }

    static func defaultPlayerWindowOpacity() -> CGFloat {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: playerWindowOpacityKey) != nil else { return defaultPlayerWindowOpacityValue }
        let value = clampedPlayerWindowOpacity(CGFloat(defaults.double(forKey: playerWindowOpacityKey)))
        defaults.set(Double(value), forKey: playerWindowOpacityKey)
        return value
    }

    static func playerWindowOpacityPercent(_ value: CGFloat) -> Int {
        Int((clampedPlayerWindowOpacity(value) * 100).rounded())
    }

    static func isVerboseAutoplayTraceEnabled() -> Bool { UserDefaults.standard.bool(forKey: verboseAutoplayTraceKey) }
    static func isAutoHideTitlebarEnabled() -> Bool { UserDefaults.standard.bool(forKey: autoHideTitlebarKey) }
    static func isCompleteVideoWindowModeEnabled() -> Bool { UserDefaults.standard.bool(forKey: completeVideoWindowModeKey) }
    static func isShowTitleOverlayEnabled() -> Bool { UserDefaults.standard.bool(forKey: showTitleOverlayKey) }
    static func isDebugConsoleEnabled() -> Bool { UserDefaults.standard.bool(forKey: debugConsoleKey) }
    static func customPrefixValue() -> String { normalizedCustomPrefix(UserDefaults.standard.string(forKey: customPrefixValueKey) ?? "") }
    static func customPrefixSecondaryValue() -> String { normalizedCustomPrefix(UserDefaults.standard.string(forKey: customPrefixSecondaryValueKey) ?? "") }

    /// The authoritative form of a configured custom prefix: leading/trailing
    /// whitespace removed, and a single trailing `_` guaranteed so a rename
    /// always produces `prefix_<filename>`. An empty/whitespace-only value
    /// stays empty (the feature is off for that slot).
    static func normalizedCustomPrefix(_ raw: String) -> String {
        SkimFileRenamer.normalizedCustomPrefix(raw)
    }
    static func acceptsVideoMedia() -> Bool { UserDefaults.standard.bool(forKey: acceptVideoKey) }
    static func acceptsImageMedia() -> Bool { UserDefaults.standard.bool(forKey: acceptImagesKey) }
    static func acceptsGIFMedia() -> Bool { UserDefaults.standard.bool(forKey: acceptGIFKey) }

    static func acceptedMediaKinds() -> Set<MediaFileSupport.MediaKind> {
        var result = Set<MediaFileSupport.MediaKind>()
        if acceptsVideoMedia() { result.insert(.video) }
        if acceptsImageMedia() { result.insert(.image) }
        if acceptsGIFMedia() { result.insert(.gif) }
        return result
    }

    static func currentImageDurationSeconds() -> Double { SkimSettingsStore.shared.snapshot().imageDurationSeconds }
    static func currentGIFLoopCount() -> Int { SkimSettingsStore.shared.snapshot().gifLoopCount }
    static func isVideoAudioNormalizationEnabled() -> Bool { SkimSettingsStore.shared.snapshot().videoAudioNormalizationEnabled }

    static func currentClipDurationSeconds() -> Int { SkimSettingsStore.shared.snapshot().fixedDurationSeconds }
    static func isSkimEnabled() -> Bool { SkimSettingsStore.shared.snapshot().skimEnabled }
    static func currentPreviewDurationModeValue() -> String { SkimSettingsStore.shared.snapshot().previewDurationMode }
    static func currentSkimPreviewDurationMode() -> SkimPreviewDurationMode {
        currentPreviewDurationModeValue() == previewDurationModeRandom ? .random : .fixed
    }
    static func currentRandomPreviewDurationRange() -> ClosedRange<Int> { SkimSettingsStore.shared.snapshot().randomDurationRange }
    static func currentSkipIntroSeconds() -> Int { SkimSettingsStore.shared.snapshot().skipIntroSeconds }
    static func isProgressiveRandomSkimEnabled() -> Bool { SkimSettingsStore.shared.snapshot().progressiveRandomSkimEnabled }
    static func currentProgressiveRandomSkimIntensity() -> ProgressiveRandomSkimIntensity { SkimSettingsStore.shared.snapshot().progressiveRandomSkimIntensity }
    static func setProgressiveRandomSkimIntensity(_ intensity: ProgressiveRandomSkimIntensity) { SkimSettingsStore.shared.setProgressiveRandomSkimIntensity(intensity) }
    static func currentStartPositionMode() -> String { SkimSettingsStore.shared.snapshot().startPositionMode }
    static func currentSkimPreviewStartMode() -> SkimPreviewStartMode {
        currentStartPositionMode() == startPositionModeBeginning ? .beginning : .random
    }
    static func currentQueueOrderMode() -> QueueOrderMode { SkimSettingsStore.shared.snapshot().queueOrderMode }
    static func isLoopQueueEnabled() -> Bool { SkimSettingsStore.shared.snapshot().loopQueueEnabled }
    static func setPreviewDurationMode(_ value: String) { SkimSettingsStore.shared.setPreviewDurationMode(value) }
    static func setSkimEnabled(_ enabled: Bool) { SkimSettingsStore.shared.setSkimEnabled(enabled) }
    static func setClipDurationSeconds(_ value: Int) { SkimSettingsStore.shared.setFixedDurationSeconds(value) }
    static func setRandomPreviewMinimumSeconds(_ value: Int) { SkimSettingsStore.shared.setRandomMinimumSeconds(value) }
    static func setRandomPreviewMaximumSeconds(_ value: Int) { SkimSettingsStore.shared.setRandomMaximumSeconds(value) }
    static func setStartPositionMode(_ value: String) { SkimSettingsStore.shared.setStartPositionMode(value) }
    static func setSkipIntroSeconds(_ value: Int) { SkimSettingsStore.shared.setSkipIntroSeconds(value) }
    static func setQueueOrderMode(_ mode: QueueOrderMode) { SkimSettingsStore.shared.setQueueOrderMode(mode) }
    static func setLoopQueueEnabled(_ enabled: Bool) { SkimSettingsStore.shared.setLoopQueueEnabled(enabled) }
    static func setImageDurationSeconds(_ value: Double) { SkimSettingsStore.shared.setImageDurationSeconds(value) }
    static func setGIFLoopCount(_ value: Int) { SkimSettingsStore.shared.setGIFLoopCount(value) }
    static func setVideoAudioNormalizationEnabled(_ enabled: Bool) { SkimSettingsStore.shared.setVideoAudioNormalizationEnabled(enabled) }

    static func vlcBackendVersionText() -> String {
        let version = VLCLibrary.shared().version.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "Unavailable" : version
    }

    private let sidebarStack = NSStackView()
    private let detailContainer = NSView()
    private var sidebarButtons: [SettingsSidebarButton] = []
    private var sectionViews: [NSView] = []
    private var selectedSection: Section = .playback
    private var isSynchronizing = false

    private let playbackSpeedPopup = NSPopUpButton()
    private let showTitleOverlayCheckbox = NSButton()
    private let imageDurationField = NSTextField()
    private let imageDurationStepper = NSStepper()
    private let gifLoopCountField = NSTextField()
    private let gifLoopCountStepper = NSStepper()
    private let normalizeVideoAudioCheckbox = NSButton()
    private let acceptVideoCheckbox = NSButton()
    private let acceptImagesCheckbox = NSButton()
    private let acceptGIFCheckbox = NSButton()

    private let previewDurationModeControl = NSSegmentedControl()
    private let fixedDurationField = NSTextField()
    private let randomMinimumField = NSTextField()
    private let randomMaximumField = NSTextField()
    private let startPositionControl = NSSegmentedControl()
    private let skipIntroField = NSTextField()
    private let progressiveRandomSkimCheckbox = NSButton()
    private let progressiveRandomSkimIntensityControl = NSSegmentedControl()

    private let audioSelectedLabel = NSTextField(labelWithString: "No audio track selected")
    private let audioUnavailableLabel = NSTextField(labelWithString: "")
    private let chooseAudioButton = NSButton()
    private let clearAudioButton = NSButton()
    private let audioMixControl = NSSegmentedControl()
    private let backgroundVolumeSlider = NSSlider()
    private let backgroundVolumeLabel = NSTextField(labelWithString: "75%")

    private let autoHideCheckbox = NSButton()
    private let chromeThresholdPopup = NSPopUpButton()
    private let reducedMotionCheckbox = NSButton()
    private let autoHideTitlebarCheckbox = NSButton()
    private let completeVideoCheckbox = NSButton()
    private let opacitySlider = NSSlider()
    private let opacityLabel = NSTextField(labelWithString: "100%")

    private let primaryPrefixField = NSTextField()
    private let secondaryPrefixField = NSTextField()
    private let queueOrderPopup = NSPopUpButton()
    private let loopQueueSwitch = NSSwitch()
    private let openQueueCheckbox = NSButton()

    private let debugCheckbox = NSButton()
    private let verboseCheckbox = NSButton()
    private let clearBookmarksButton = NSButton()
    private let restoreDefaultsButton = NSButton()

    private init() {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: SettingsPresentation.defaultWindowSize),
                            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                            backing: .buffered,
                            defer: false)
        panel.title = SettingsPresentation.windowTitle
        panel.minSize = SettingsPresentation.minimumWindowSize
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .visible
        panel.tabbingMode = .disallowed
        super.init(window: panel)
        buildUI()
        observeChanges()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func observeChanges() {
        for name in [Notification.Name.skimPreviewSettingsChanged,
                     .playbackSettingsChanged,
                     .queueBehaviorSettingsChanged,
                     .skimPlusSettingsChanged,
                     .playbackSpeedChanged] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(sharedSettingsDidChange(_:)),
                                                   name: name,
                                                   object: nil)
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)

        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        for section in Section.allCases {
            let button = SettingsSidebarButton(title: section.title,
                                               section: section,
                                               target: self,
                                               action: #selector(sidebarTapped(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            sidebarStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: sidebarStack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: SettingsPresentation.sidebarRowHeight).isActive = true
            sidebarButtons.append(button)
        }

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.wantsLayer = true
        detailContainer.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.addSubview(detailContainer)

        // The detail surface runs underneath the divider so the sidebar's
        // translucency can never expose a one-point desktop slit at the seam.
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = SettingsColors.structuralSeparator.withAlphaComponent(0.36).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsPresentation.sidebarWidth),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 13),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -13),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 48),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: content.topAnchor),
            separator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            detailContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: content.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        sectionViews = [
            buildPlaybackPage(), buildSkimPreviewPage(), buildSkimPlusPage(), buildControlsPage(),
            buildQueueFilesPage(), buildShortcutsPage(), buildAdvancedPage(), buildAboutPage(),
        ]
        for view in sectionViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            detailContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
            ])
        }
        select(.restored())
        syncUIFromDefaults()
        window?.recalculateKeyViewLoop()
    }

    private func buildPlaybackPage() -> NSView {
        configureCheckbox(showTitleOverlayCheckbox, title: "Show title overlay on playback start")
        configureCheckbox(normalizeVideoAudioCheckbox, title: "Normalize video audio")
        configurePopup(playbackSpeedPopup, action: #selector(playbackSpeedChanged(_:)))
        PlaybackSpeedOption.all.forEach {
            playbackSpeedPopup.addItem(withTitle: $0.title)
            playbackSpeedPopup.lastItem?.tag = $0.tag
        }
        configureNumericField(imageDurationField,
                              placeholder: "3",
                              allowsFloats: true,
                              minimum: SettingsDefaultsRegistry.Defaults.imageDurationMinimumSeconds,
                              maximum: SettingsDefaultsRegistry.Defaults.imageDurationMaximumSeconds)
        configureStepper(imageDurationStepper,
                         minimum: SettingsDefaultsRegistry.Defaults.imageDurationMinimumSeconds,
                         maximum: SettingsDefaultsRegistry.Defaults.imageDurationMaximumSeconds,
                         increment: 0.25,
                         action: #selector(imageDurationStepperChanged(_:)))
        configureNumericField(gifLoopCountField,
                              placeholder: "1",
                              allowsFloats: false,
                              minimum: 1,
                              maximum: Double(SettingsDefaultsRegistry.Defaults.gifLoopCountMaximum))
        configureStepper(gifLoopCountStepper,
                         minimum: 1,
                         maximum: Double(SettingsDefaultsRegistry.Defaults.gifLoopCountMaximum),
                         increment: 1,
                         action: #selector(gifLoopCountStepperChanged(_:)))
        configureCheckbox(acceptVideoCheckbox, title: "Video")
        configureCheckbox(acceptImagesCheckbox, title: "Images")
        configureCheckbox(acceptGIFCheckbox, title: "GIF")
        playbackSpeedPopup.setAccessibilityLabel("Playback speed")
        imageDurationField.setAccessibilityLabel("Image duration in seconds")
        imageDurationStepper.setAccessibilityLabel("Adjust image duration")
        gifLoopCountField.setAccessibilityLabel("GIF loop count")
        gifLoopCountStepper.setAccessibilityLabel("Adjust GIF loop count")
        // The three acceptance checkboxes read as bare "Video"/"Images"/"GIF"
        // without their section heading; qualify them for VoiceOver.
        acceptVideoCheckbox.setAccessibilityLabel("Accept video media")
        acceptImagesCheckbox.setAccessibilityLabel("Accept image media")
        acceptGIFCheckbox.setAccessibilityLabel("Accept GIF media")
        let accept = NSStackView(views: [acceptVideoCheckbox, acceptImagesCheckbox, acceptGIFCheckbox])
        accept.orientation = .horizontal
        accept.spacing = 16
        return page(sections: [
            section("PLAYBACK", rows: [
                row("Playback speed", playbackSpeedPopup, helper: "Applies to the frontmost player window."),
                row(nil, showTitleOverlayCheckbox),
            ]),
            section("MEDIA DURATION", rows: [
                row("Image duration", numericStepperControl(imageDurationField,
                                                              stepper: imageDurationStepper,
                                                              suffix: "s"),
                    helper: "Still images advance after the selected number of seconds."),
                row("GIF loops", numericStepperControl(gifLoopCountField,
                                                        stepper: gifLoopCountStepper),
                    helper: "GIFs advance after the selected number of completed animation loops."),
            ]),
            section("VIDEO AUDIO", rows: [
                row(nil, normalizeVideoAudioCheckbox,
                    helper: "Adjusts video audio in real time. Skim+ background audio is never processed."),
            ]),
            section("ACCEPTED MEDIA", rows: [row(nil, accept)]),
        ])
    }

    private func buildSkimPreviewPage() -> NSView {
        previewDurationModeControl.segmentCount = 2
        previewDurationModeControl.setLabel("Fixed", forSegment: 0)
        previewDurationModeControl.setLabel("Random", forSegment: 1)
        previewDurationModeControl.target = self
        previewDurationModeControl.action = #selector(previewModeChanged(_:))

        configureNumericField(fixedDurationField, placeholder: "10")
        configureNumericField(randomMinimumField, placeholder: "5")
        configureNumericField(randomMaximumField, placeholder: "15")
        configureNumericField(skipIntroField, placeholder: "5")
        configureCheckbox(progressiveRandomSkimCheckbox, title: "Progressive Random Skim")

        progressiveRandomSkimIntensityControl.segmentCount = 3
        progressiveRandomSkimIntensityControl.setLabel("Light", forSegment: 0)
        progressiveRandomSkimIntensityControl.setLabel("Standard", forSegment: 1)
        progressiveRandomSkimIntensityControl.setLabel("Thorough", forSegment: 2)
        progressiveRandomSkimIntensityControl.target = self
        progressiveRandomSkimIntensityControl.action = #selector(progressiveRandomSkimIntensityChanged(_:))
        progressiveRandomSkimIntensityControl.setAccessibilityLabel("Progressive Random Skim coverage intensity")

        // The visual grid label is a sibling view, so AppKit does not associate it
        // with the field; each control carries its own human-facing label.
        previewDurationModeControl.setAccessibilityLabel("Clip duration mode")
        fixedDurationField.setAccessibilityLabel("Fixed clip duration in seconds")
        randomMinimumField.setAccessibilityLabel("Minimum random clip duration in seconds")
        randomMaximumField.setAccessibilityLabel("Maximum random clip duration in seconds")
        startPositionControl.setAccessibilityLabel("Start position")
        skipIntroField.setAccessibilityLabel("Skip intro in seconds")

        startPositionControl.segmentCount = 2
        startPositionControl.setLabel("Beginning", forSegment: 0)
        startPositionControl.setLabel("Random", forSegment: 1)
        startPositionControl.target = self
        startPositionControl.action = #selector(startPositionChanged(_:))

        return page(sections: [
            section("SKIM PREVIEW", rows: [
                row("Clip duration", previewDurationModeControl),
                row("Fixed duration", secondsControl(fixedDurationField), helper: "0 plays the full file."),
                row("Random minimum", secondsControl(randomMinimumField)),
                row("Random maximum", secondsControl(randomMaximumField)),
                row("Start position", startPositionControl),
                row("Skip intro", secondsControl(skipIntroField)),
                row(nil, progressiveRandomSkimCheckbox,
                    helper: "Samples several short, randomized segments spread across videos 30 seconds or longer, always starting no earlier than Skip Intro."),
                row("Coverage intensity", progressiveRandomSkimIntensityControl,
                    helper: "How many Progressive Random Skim segments to sample. Standard matches the default behavior; Light samples fewer, Thorough samples more."),
            ]),
        ])
    }

    private func buildSkimPlusPage() -> NSView {
        chooseAudioButton.title = "Choose Audio Track..."
        chooseAudioButton.bezelStyle = .rounded
        chooseAudioButton.target = self
        chooseAudioButton.action = #selector(chooseAudioTrack(_:))
        chooseAudioButton.setAccessibilityLabel("Choose Background Audio Track")

        clearAudioButton.title = "Clear"
        clearAudioButton.bezelStyle = .rounded
        clearAudioButton.target = self
        clearAudioButton.action = #selector(clearAudioTrack(_:))

        audioSelectedLabel.lineBreakMode = .byTruncatingMiddle
        audioSelectedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        audioUnavailableLabel.textColor = .secondaryLabelColor
        audioUnavailableLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        audioUnavailableLabel.lineBreakMode = .byWordWrapping

        let selection = NSStackView(views: [audioSelectedLabel, clearAudioButton])
        selection.orientation = .horizontal
        selection.spacing = 12

        audioMixControl.segmentCount = 2
        audioMixControl.setLabel(BackgroundAudioMixMode.uploadedOnly.title, forSegment: 0)
        audioMixControl.setLabel(BackgroundAudioMixMode.videoAndUploaded.title, forSegment: 1)
        audioMixControl.target = self
        audioMixControl.action = #selector(audioMixChanged(_:))

        backgroundVolumeSlider.minValue = 0
        backgroundVolumeSlider.maxValue = 1
        backgroundVolumeSlider.isContinuous = true
        backgroundVolumeSlider.target = self
        backgroundVolumeSlider.action = #selector(backgroundVolumeChanged(_:))
        backgroundVolumeSlider.widthAnchor.constraint(equalToConstant: SettingsPresentation.sliderWidth).isActive = true
        backgroundVolumeSlider.setAccessibilityLabel("Background audio volume")
        audioMixControl.setAccessibilityLabel("Audio mix")
        audioSelectedLabel.setAccessibilityLabel("Selected background audio track")
        clearAudioButton.setAccessibilityLabel("Clear background audio track")
        backgroundVolumeLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        backgroundVolumeLabel.alignment = .left
        backgroundVolumeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let volume = NSStackView(views: [backgroundVolumeSlider, backgroundVolumeLabel])
        volume.orientation = .horizontal
        volume.spacing = 10

        return page(sections: [
            section("BACKGROUND AUDIO", rows: [
                row("Audio track", chooseAudioButton),
                row("Selected", selection),
                row(nil, audioUnavailableLabel),
            ]),
            section("AUDIO MIX", rows: [
                row(nil, audioMixControl),
                row("Background audio volume", volume),
            ]),
        ])
    }

    private func buildControlsPage() -> NSView {
        configureCheckbox(autoHideCheckbox, title: "Auto-hide playback overlay")
        configureCheckbox(reducedMotionCheckbox, title: "Reduce overlay motion")
        configureCheckbox(autoHideTitlebarCheckbox, title: "Auto-hide titlebar")
        configureCheckbox(completeVideoCheckbox, title: "Complete video mode in windowed playback")
        configurePopup(chromeThresholdPopup, action: #selector(chromeThresholdChanged(_:)))
        Self.chromeThresholdOptions.forEach {
            chromeThresholdPopup.addItem(withTitle: $0.title)
            chromeThresholdPopup.lastItem?.tag = Int(($0.seconds * 10).rounded())
        }
        opacitySlider.minValue = Double(Self.playerWindowOpacityMin * 100)
        opacitySlider.maxValue = Double(Self.playerWindowOpacityMax * 100)
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.widthAnchor.constraint(equalToConstant: SettingsPresentation.sliderWidth).isActive = true
        opacitySlider.setAccessibilityLabel("Window opacity")
        chromeThresholdPopup.setAccessibilityLabel("Playback overlay hide delay")
        opacityLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        opacityLabel.alignment = .left
        let opacity = NSStackView(views: [opacitySlider, opacityLabel])
        opacity.orientation = .horizontal
        opacity.spacing = 10
        return page(sections: [
            section("PLAYBACK OVERLAY", rows: [
                row(nil, autoHideCheckbox), row("Hide delay", chromeThresholdPopup), row(nil, reducedMotionCheckbox),
            ]),
            section("WINDOW", rows: [
                row(nil, autoHideTitlebarCheckbox), row(nil, completeVideoCheckbox), row("Window opacity", opacity),
            ]),
        ])
    }

    private func buildQueueFilesPage() -> NSView {
        configureTextField(primaryPrefixField, placeholder: "e.g. select_")
        configureTextField(secondaryPrefixField, placeholder: "e.g. later_")
        primaryPrefixField.textColor = PrefixBrandColors.primaryCustomPrefixColor
        secondaryPrefixField.textColor = PrefixBrandColors.secondaryCustomPrefixColor
        configurePopup(queueOrderPopup, action: #selector(queueOrderChanged(_:)))
        QueueOrderMode.allCases.forEach {
            queueOrderPopup.addItem(withTitle: $0.rawValue.capitalized)
            queueOrderPopup.lastItem?.representedObject = $0.rawValue
        }
        loopQueueSwitch.target = self
        loopQueueSwitch.action = #selector(loopQueueSwitchChanged(_:))
        loopQueueSwitch.setAccessibilityLabel("Loop queue")
        primaryPrefixField.setAccessibilityLabel("Primary custom prefix")
        secondaryPrefixField.setAccessibilityLabel("Secondary custom prefix")
        queueOrderPopup.setAccessibilityLabel("Queue order")
        configureCheckbox(openQueueCheckbox, title: "Open queue panel when a player window opens")
        return page(sections: [
            section("PREFIX RENAME", rows: [
                row("Primary custom prefix", primaryPrefixField),
                row("Secondary custom prefix", secondaryPrefixField,
                    helper: "Custom prefixes rename immediately in the same directory and preserve the extension."),
            ]),
            section("QUEUE BEHAVIOR", rows: [
                row("Queue order", queueOrderPopup,
                    helper: "Weighted favors items that have waited longest since playback."),
                row("Loop queue", loopQueueSwitch), row(nil, openQueueCheckbox),
            ]),
        ])
    }

    private func buildShortcutsPage() -> NSView {
        let groups: [(String, [(String, String)])] = [
            ("REVIEW ACTIONS", [("keep_", "K"), ("delete_", "D"), ("Rename", "R"), ("Undo", "Z")]),
            ("PREFIX RENAME", [("Primary prefix (toggle / replace)", "N"), ("Secondary prefix (toggle / replace)", "M")]),
            ("QUEUE NAVIGATION", [("Previous item", ","), ("Next item", "."), ("Toggle queue panel", "Q")]),
            ("PLAYBACK", [("Play/Pause", "Space"), ("Fullscreen", "F"), ("Next Progressive Random Skim segment", "\u{2192}")]),
            ("APP AND WINDOW", [("Open media or folder", "Command-O"), ("Open Settings", "Command-,"), ("Close window", "Command-W")]),
        ]
        return page(sections: groups.map { title, items in
            section(title, rows: items.map(shortcutRow))
        })
    }

    private func buildAdvancedPage() -> NSView {
        configureCheckbox(debugCheckbox, title: "Show debug console")
        configureCheckbox(verboseCheckbox, title: "Verbose autoplay diagnostics")
        clearBookmarksButton.title = "Clear All Bookmarks..."
        clearBookmarksButton.bezelStyle = .rounded
        clearBookmarksButton.target = self
        clearBookmarksButton.action = #selector(clearAllBookmarks(_:))
        clearBookmarksButton.contentTintColor = SkimColors.burntOrange300
        restoreDefaultsButton.title = "Restore All Settings to Default"
        restoreDefaultsButton.bezelStyle = .rounded
        restoreDefaultsButton.target = self
        restoreDefaultsButton.action = #selector(restoreDefaults(_:))
        restoreDefaultsButton.contentTintColor = SkimColors.burntOrange300
        return page(sections: [
            section("DIAGNOSTICS", rows: [row(nil, debugCheckbox), row(nil, verboseCheckbox)]),
            section("BOOKMARKS", rows: [row(nil, clearBookmarksButton, helper: "This cannot be undone.")]),
            section("RESET", rows: [row(nil, restoreDefaultsButton, helper: "Media files, queues, and bookmarks are not deleted.")]),
        ])
    }

    private func buildAboutPage() -> NSView {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: Bundle.main.infoDictionary)
        let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("dwb skim application icon")
        icon.widthAnchor.constraint(equalToConstant: 112).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 112).isActive = true

        let productName = NSTextField(labelWithString: values.productName)
        productName.font = .systemFont(ofSize: 26, weight: .semibold)
        let version = NSTextField(labelWithString: "Version \(values.version)  •  Build \(values.build)")
        version.textColor = .secondaryLabelColor
        let description = NSTextField(wrappingLabelWithString: SettingsPresentation.productDescription)
        description.font = .systemFont(ofSize: 13)
        description.textColor = .labelColor
        description.preferredMaxLayoutWidth = 390

        let metadataSeparator = NSView()
        metadataSeparator.wantsLayer = true
        metadataSeparator.layer?.backgroundColor = SettingsColors.structuralSeparator.withAlphaComponent(0.48).cgColor
        metadataSeparator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let facts = aboutFacts([
            ("License", "MIT License"),
            ("Platform", "macOS \(values.minimumSystemVersion) or later"),
            ("Interface", "AppKit"),
            ("Playback", "VLCKit"),
            ("VLC backend", Self.vlcBackendVersionText()),
        ])
        let repo = NSButton(title: "GitHub Repository", target: self, action: #selector(openRepository(_:)))
        let issues = NSButton(title: "Report an Issue", target: self, action: #selector(openIssues(_:)))
        repo.bezelStyle = .inline
        issues.bezelStyle = .inline
        repo.setAccessibilityLabel("Open dwb skim GitHub repository")
        repo.setAccessibilityHelp(Self.githubURLString)
        issues.setAccessibilityLabel("Open dwb skim issue tracker")
        issues.setAccessibilityHelp(Self.githubIssuesURLString)
        repo.contentTintColor = SettingsColors.informationalLink
        issues.contentTintColor = SettingsColors.informationalLink
        let links = NSStackView(views: [repo, issues])
        links.orientation = .horizontal
        links.spacing = 14
        let identityText = NSStackView(views: [productName, version, description, metadataSeparator, facts, links])
        identityText.orientation = .vertical
        identityText.alignment = .leading
        identityText.spacing = 9
        identityText.setCustomSpacing(18, after: description)
        identityText.setCustomSpacing(18, after: metadataSeparator)
        identityText.setCustomSpacing(16, after: facts)
        metadataSeparator.widthAnchor.constraint(equalTo: identityText.widthAnchor).isActive = true
        let identity = NSStackView(views: [icon, identityText])
        identity.orientation = .horizontal
        identity.alignment = .top
        identity.spacing = 24
        return aboutPage(identity: identity)
    }

    private func aboutFacts(_ facts: [(String, String)]) -> NSView {
        let views = facts.map { label, value -> [NSView] in
            let name = NSTextField(labelWithString: label)
            name.textColor = .secondaryLabelColor
            name.alignment = .left
            let detail = NSTextField(wrappingLabelWithString: value)
            detail.textColor = .labelColor
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return [name, detail]
        }
        let grid = NSGridView(views: views)
        grid.columnSpacing = 12
        grid.rowSpacing = 7
        grid.column(at: 0).width = 82
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        return grid
    }

    private func aboutPage(identity: NSView) -> NSView {
        let content = NSStackView(views: [identity])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false

        let copyright = NSTextField(labelWithString: "© dwb")
        copyright.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        copyright.textColor = .tertiaryLabelColor
        copyright.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(scroll)
        container.addSubview(copyright)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: SettingsPresentation.pageTopInset),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: SettingsPresentation.pageLeadingInset),
            content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor,
                                              constant: -SettingsPresentation.pageTrailingInset),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutMetrics.maximumContentWidth),
            content.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor,
                                            constant: -(SettingsPresentation.pageBottomInset + 32)),
            copyright.trailingAnchor.constraint(equalTo: container.trailingAnchor,
                                                 constant: -SettingsPresentation.pageTrailingInset),
            copyright.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        return container
    }

    private struct FormRow {
        let label: String?
        let control: NSView
        let helper: String?
    }

    private func page(sections: [NSView]) -> NSView {
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = LayoutMetrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        sections.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: SettingsPresentation.pageTopInset),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: SettingsPresentation.pageLeadingInset),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -SettingsPresentation.pageTrailingInset),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutMetrics.maximumContentWidth),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor,
                                          constant: -SettingsPresentation.pageBottomInset),
        ])
        let fillWidth = stack.widthAnchor.constraint(equalTo: document.widthAnchor,
                                                     constant: -(SettingsPresentation.pageLeadingInset + SettingsPresentation.pageTrailingInset))
        fillWidth.priority = .defaultHigh
        fillWidth.isActive = true
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor).isActive = true
        return scroll
    }

    private func section(_ title: String, rows: [FormRow]) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = Self.suiteAccent

        let rowViews = rows.map { item -> NSView in
            let label = NSTextField(wrappingLabelWithString: item.label ?? "")
            label.alignment = .left
            label.textColor = item.label == nil ? .clear : .labelColor
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = LayoutMetrics.labelWidth
            label.setAccessibilityElement(item.label != nil)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)

            var controls: [NSView] = [item.control]
            if let helper = item.helper {
                let note = NSTextField(wrappingLabelWithString: helper)
                note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                note.textColor = .secondaryLabelColor
                note.preferredMaxLayoutWidth = LayoutMetrics.helperMaximumWidth
                note.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutMetrics.helperMaximumWidth).isActive = true
                controls.append(note)
            }
            let controlColumn = NSStackView(views: controls)
            controlColumn.orientation = .vertical
            controlColumn.alignment = .leading
            controlColumn.spacing = 4
            guard item.label != nil else { return controlColumn }

            let grid = NSGridView(views: [[label, controlColumn]])
            grid.columnSpacing = LayoutMetrics.columnSpacing
            grid.column(at: 0).width = LayoutMetrics.labelWidth
            grid.column(at: 0).xPlacement = .leading
            grid.column(at: 1).xPlacement = .leading
            grid.row(at: 0).yPlacement = .top
            return grid
        }

        let rowStack = NSStackView(views: rowViews)
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = LayoutMetrics.rowSpacing

        let stack = NSStackView(views: [heading, rowStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        return stack
    }

    private func row(_ label: String?, _ control: NSView, helper: String? = nil) -> FormRow {
        FormRow(label: label, control: control, helper: helper)
    }

    private func shortcutRow(_ item: (String, String)) -> FormRow {
        let key = SettingsShortcutBadge(shortcut: item.1)
        key.setAccessibilityElement(false)
        let semantic = NSStackView(views: [key])
        semantic.orientation = .horizontal
        semantic.setAccessibilityElement(true)
        semantic.setAccessibilityLabel("\(item.0), \(item.1)")
        return row(item.0, semantic)
    }

    private func configureCheckbox(_ button: NSButton, title: String) {
        button.setButtonType(.switch)
        button.title = title
        button.target = self
        button.action = #selector(checkboxChanged(_:))
        button.contentTintColor = .labelColor
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
    }

    private func configureNumericField(_ field: NSTextField,
                                       placeholder: String,
                                       allowsFloats: Bool = false,
                                       minimum: Double = 0,
                                       maximum: Double? = nil) {
        field.placeholderString = placeholder
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true
        field.alignment = .left
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = allowsFloats
        formatter.minimum = NSNumber(value: minimum)
        formatter.maximumFractionDigits = allowsFloats ? 2 : 0
        if let maximum { formatter.maximum = NSNumber(value: maximum) }
        field.formatter = formatter
    }

    private func configureStepper(_ stepper: NSStepper,
                                  minimum: Double,
                                  maximum: Double,
                                  increment: Double,
                                  action: Selector) {
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = action
    }

    private func numericStepperControl(_ field: NSTextField,
                                       stepper: NSStepper,
                                       suffix: String? = nil) -> NSView {
        var views: [NSView] = [field, stepper]
        if let suffix {
            let label = NSTextField(labelWithString: suffix)
            label.textColor = .secondaryLabelColor
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 5
        return stack
    }

    private func secondsControl(_ field: NSTextField) -> NSView {
        let suffix = NSTextField(labelWithString: "s")
        suffix.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [field, suffix])
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 5
        return stack
    }

    private func select(_ section: Section) {
        selectedSection = section
        for (index, view) in sectionViews.enumerated() { view.isHidden = index != section.rawValue }
        sidebarButtons.forEach { $0.isSelected = $0.section == section }
        window?.title = SettingsPresentation.windowTitle
        UserDefaults.standard.set(section.identifier, forKey: SettingsPresentation.selectedPaneDefaultsKey)
    }

    @objc private func sidebarTapped(_ sender: SettingsSidebarButton) { select(sender.section) }

    @objc private func sharedSettingsDidChange(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        syncUIFromDefaults()
    }

    private func syncUIFromDefaults() {
        isSynchronizing = true
        defer { isSynchronizing = false }
        let defaults = UserDefaults.standard
        let skim = SkimSettingsStore.shared.snapshot()

        playbackSpeedPopup.selectItem(withTag: PlaybackSpeedOption.validated(targetPlayerWindowController()?.currentPlaybackSpeed ?? 1).tag)
        showTitleOverlayCheckbox.state = Self.isShowTitleOverlayEnabled() ? .on : .off
        imageDurationField.doubleValue = skim.imageDurationSeconds
        imageDurationStepper.doubleValue = skim.imageDurationSeconds
        gifLoopCountField.integerValue = skim.gifLoopCount
        gifLoopCountStepper.integerValue = skim.gifLoopCount
        normalizeVideoAudioCheckbox.state = skim.videoAudioNormalizationEnabled ? .on : .off
        acceptVideoCheckbox.state = Self.acceptsVideoMedia() ? .on : .off
        acceptImagesCheckbox.state = Self.acceptsImageMedia() ? .on : .off
        acceptGIFCheckbox.state = Self.acceptsGIFMedia() ? .on : .off

        previewDurationModeControl.selectedSegment = skim.previewDurationMode == Self.previewDurationModeRandom ? 1 : 0
        fixedDurationField.stringValue = String(skim.fixedDurationSeconds)
        randomMinimumField.stringValue = String(skim.randomDurationRange.lowerBound)
        randomMaximumField.stringValue = String(skim.randomDurationRange.upperBound)
        startPositionControl.selectedSegment = skim.startPositionMode == Self.startPositionModeBeginning ? 0 : 1
        skipIntroField.stringValue = String(skim.skipIntroSeconds)
        progressiveRandomSkimCheckbox.state = skim.progressiveRandomSkimEnabled ? .on : .off
        progressiveRandomSkimIntensityControl.selectedSegment = Self.intensitySegment(for: skim.progressiveRandomSkimIntensity)
        updatePreviewRowVisibility()

        let audio = BackgroundAudioSettingsStore.shared.snapshot()
        audioSelectedLabel.stringValue = audio.selection.displayName ?? "No audio track selected"
        audioSelectedLabel.toolTip = audio.selection.displayName
        if case .unavailable(_, let reason) = audio.selection {
            audioUnavailableLabel.stringValue = "Unavailable: \(reason)"
        } else {
            audioUnavailableLabel.stringValue = audio.selection.isAvailable ? "" : "Choose one MP3 or M4A file."
        }
        clearAudioButton.isEnabled = audio.selection.displayName != nil
        let audioEnabled = audio.selection.isAvailable
        audioMixControl.isEnabled = audioEnabled
        backgroundVolumeSlider.isEnabled = audioEnabled
        audioMixControl.selectedSegment = audio.mixMode == .uploadedOnly ? 0 : 1
        backgroundVolumeSlider.doubleValue = audio.volume
        backgroundVolumeLabel.stringValue = "\(Int((audio.volume * 100).rounded()))%"

        autoHideCheckbox.state = defaults.bool(forKey: Self.autoHideKey) ? .on : .off
        reducedMotionCheckbox.state = defaults.bool(forKey: Self.chromeReducedMotionKey) ? .on : .off
        autoHideTitlebarCheckbox.state = Self.isAutoHideTitlebarEnabled() ? .on : .off
        completeVideoCheckbox.state = Self.isCompleteVideoWindowModeEnabled() ? .on : .off
        let threshold = defaults.double(forKey: Self.chromeAutohideThresholdKey)
        chromeThresholdPopup.selectItem(withTag: Int(((threshold > 0 ? threshold : 3) * 10).rounded()))
        let opacity = targetPlayerWindowController()?.currentWindowOpacity ?? Self.defaultPlayerWindowOpacity()
        opacitySlider.doubleValue = Double(opacity * 100)
        opacityLabel.stringValue = "\(Self.playerWindowOpacityPercent(opacity))%"

        primaryPrefixField.stringValue = Self.customPrefixValue()
        secondaryPrefixField.stringValue = Self.customPrefixSecondaryValue()
        queueOrderPopup.selectItem(where: { $0.representedObject as? String == skim.queueOrderMode.rawValue })
        loopQueueSwitch.state = skim.loopQueueEnabled ? .on : .off
        openQueueCheckbox.state = defaults.bool(forKey: Self.queuePanelOpenAtLaunchKey) ? .on : .off
        debugCheckbox.state = Self.isDebugConsoleEnabled() ? .on : .off
        verboseCheckbox.state = Self.isVerboseAutoplayTraceEnabled() ? .on : .off
    }

    private func updatePreviewRowVisibility() {
        let random = previewDurationModeControl.selectedSegment == 1
        fixedDurationField.isEnabled = !random
        randomMinimumField.isEnabled = random
        randomMaximumField.isEnabled = random
        fixedDurationField.alphaValue = random ? 0.48 : 1
        randomMinimumField.alphaValue = random ? 1 : 0.48
        randomMaximumField.alphaValue = random ? 1 : 0.48
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        guard !isSynchronizing else { return }
        let enabled = sender.state == .on
        let defaults = UserDefaults.standard
        switch sender {
        case showTitleOverlayCheckbox:
            defaults.set(enabled, forKey: Self.showTitleOverlayKey)
            NotificationCenter.default.post(name: .titleOverlaySettingChanged, object: self)
        case normalizeVideoAudioCheckbox:
            Self.setVideoAudioNormalizationEnabled(enabled)
        case acceptVideoCheckbox:
            defaults.set(enabled, forKey: Self.acceptVideoKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: self)
        case acceptImagesCheckbox:
            defaults.set(enabled, forKey: Self.acceptImagesKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: self)
        case acceptGIFCheckbox:
            defaults.set(enabled, forKey: Self.acceptGIFKey)
            NotificationCenter.default.post(name: .acceptedMediaTypesChanged, object: self)
        case autoHideCheckbox:
            defaults.set(enabled, forKey: Self.autoHideKey)
            NotificationCenter.default.post(name: .autoHideSettingChanged, object: self)
        case reducedMotionCheckbox:
            defaults.set(enabled, forKey: Self.chromeReducedMotionKey)
            NotificationCenter.default.post(name: .transportVisibilityChanged, object: self)
        case autoHideTitlebarCheckbox:
            defaults.set(enabled, forKey: Self.autoHideTitlebarKey)
            NotificationCenter.default.post(name: .autoHideTitlebarChanged, object: self)
        case completeVideoCheckbox:
            defaults.set(enabled, forKey: Self.completeVideoWindowModeKey)
            NotificationCenter.default.post(name: .completeVideoWindowModeChanged, object: self)
        case openQueueCheckbox:
            defaults.set(enabled, forKey: Self.queuePanelOpenAtLaunchKey)
        case debugCheckbox:
            defaults.set(enabled, forKey: Self.debugConsoleKey)
            NotificationCenter.default.post(name: .debugConsoleSettingChanged, object: self)
        case verboseCheckbox:
            defaults.set(enabled, forKey: Self.verboseAutoplayTraceKey)
        case progressiveRandomSkimCheckbox:
            SkimSettingsStore.shared.setProgressiveRandomSkimEnabled(enabled)
        default: break
        }
    }

    @objc private func loopQueueSwitchChanged(_ sender: NSSwitch) {
        guard !isSynchronizing else { return }
        Self.setLoopQueueEnabled(sender.state == .on)
    }

    @objc private func playbackSpeedChanged(_ sender: NSPopUpButton) {
        guard let option = PlaybackSpeedOption.option(forTag: sender.selectedTag()) else { return }
        targetPlayerWindowController()?.setPlaybackSpeed(option.rate, source: "settings")
    }

    @objc private func imageDurationStepperChanged(_ sender: NSStepper) {
        Self.setImageDurationSeconds(sender.doubleValue)
    }

    @objc private func gifLoopCountStepperChanged(_ sender: NSStepper) {
        Self.setGIFLoopCount(sender.integerValue)
    }

    @objc private func previewModeChanged(_ sender: NSSegmentedControl) {
        Self.setPreviewDurationMode(sender.selectedSegment == 1 ? Self.previewDurationModeRandom : Self.previewDurationModeFixed)
        updatePreviewRowVisibility()
    }

    @objc private func startPositionChanged(_ sender: NSSegmentedControl) {
        Self.setStartPositionMode(sender.selectedSegment == 0 ? Self.startPositionModeBeginning : Self.startPositionModeRandom)
    }

    private static func intensitySegment(for intensity: ProgressiveRandomSkimIntensity) -> Int {
        switch intensity {
        case .light: return 0
        case .standard: return 1
        case .thorough: return 2
        }
    }

    @objc private func progressiveRandomSkimIntensityChanged(_ sender: NSSegmentedControl) {
        let intensity: ProgressiveRandomSkimIntensity
        switch sender.selectedSegment {
        case 0: intensity = .light
        case 2: intensity = .thorough
        default: intensity = .standard
        }
        Self.setProgressiveRandomSkimIntensity(intensity)
    }

    @objc private func queueOrderChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = QueueOrderMode(rawValue: raw) else { return }
        Self.setQueueOrderMode(mode)
    }

    @objc private func chromeThresholdChanged(_ sender: NSPopUpButton) {
        UserDefaults.standard.set(Double(sender.selectedTag()) / 10, forKey: Self.chromeAutohideThresholdKey)
        NotificationCenter.default.post(name: .transportVisibilityChanged, object: self)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let value = Self.clampedPlayerWindowOpacity(CGFloat(sender.doubleValue / 100))
        UserDefaults.standard.set(Double(value), forKey: Self.playerWindowOpacityKey)
        opacityLabel.stringValue = "\(Self.playerWindowOpacityPercent(value))%"
        targetPlayerWindowController()?.setWindowOpacityFromSettings(value)
    }

    @objc private func chooseAudioTrack(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.title = "Choose Background Audio"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = BackgroundAudioFilePolicy.supportedExtensions.sorted().compactMap {
            UTType(filenameExtension: $0, conformingTo: .audio) ?? UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try BackgroundAudioSettingsStore.shared.select(url)
            syncUIFromDefaults()
        } catch {
            presentError(title: "Unsupported Audio Track", message: error.localizedDescription)
        }
    }

    @objc private func clearAudioTrack(_ sender: NSButton) {
        BackgroundAudioSettingsStore.shared.clearSelection()
        syncUIFromDefaults()
    }

    @objc private func audioMixChanged(_ sender: NSSegmentedControl) {
        BackgroundAudioSettingsStore.shared.setMixMode(sender.selectedSegment == 0 ? .uploadedOnly : .videoAndUploaded)
    }

    @objc private func backgroundVolumeChanged(_ sender: NSSlider) {
        BackgroundAudioSettingsStore.shared.setVolume(sender.doubleValue)
        backgroundVolumeLabel.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isSynchronizing, let field = notification.object as? NSTextField else { return }
        switch field {
        case primaryPrefixField, secondaryPrefixField:
            guard !field.stringValue.contains("/"), !field.stringValue.contains("\0") else { return }
            let key = field === primaryPrefixField ? Self.customPrefixValueKey : Self.customPrefixSecondaryValueKey
            UserDefaults.standard.set(field.stringValue, forKey: key)
            NotificationCenter.default.post(name: .customPrefixValueChanged, object: self)
        default: break
        }
    }

    /// Numeric preferences commit when editing ends rather than per keystroke.
    /// Committing live forced a `syncUIFromDefaults()` that rewrote `stringValue`
    /// mid-edit and moved the insertion point; this matches the inline strip.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isSynchronizing, let field = notification.object as? NSTextField else { return }
        switch field {
        case imageDurationField:
            Self.setImageDurationSeconds(field.doubleValue)
        case gifLoopCountField:
            Self.setGIFLoopCount(field.integerValue)
        case fixedDurationField:
            Self.setClipDurationSeconds(field.integerValue)
        case randomMinimumField:
            Self.setRandomPreviewMinimumSeconds(field.integerValue)
        case randomMaximumField:
            Self.setRandomPreviewMaximumSeconds(field.integerValue)
        case skipIntroField:
            Self.setSkipIntroSeconds(field.integerValue)
        default:
            return
        }
        syncUIFromDefaults()
    }

    @objc private func clearAllBookmarks(_ sender: NSButton) {
        confirm(title: "Clear all bookmarks?",
                message: "Bookmarks are stored locally and may include full file paths. This cannot be undone.",
                actionTitle: "Clear Bookmarks") {
            BookmarkStore.shared.clearAll()
        }
    }

    @objc private func restoreDefaults(_ sender: NSButton) {
        confirm(title: "Restore all settings to default?",
                message: "This resets preferences and the selected background-audio track. It does not delete media files, queues, or bookmarks.",
                actionTitle: "Restore Defaults") { [weak self] in
            let defaults = UserDefaults.standard
            SettingsDefaultsRegistry.defaultValues(
                reduceMotionDefault: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ).forEach { defaults.set($0.value, forKey: $0.key) }
            BackgroundAudioSettingsStore.shared.clearSelection()
            [.autoHideSettingChanged, .transportVisibilityChanged, .autoHideTitlebarChanged,
             .completeVideoWindowModeChanged, .playbackSettingsChanged,
             .acceptedMediaTypesChanged, .titleOverlaySettingChanged, .customPrefixValueChanged,
             .debugConsoleSettingChanged, .skimPreviewSettingsChanged, .queueBehaviorSettingsChanged,
             .skimPlusSettingsChanged].forEach { NotificationCenter.default.post(name: $0, object: self) }
            self?.syncUIFromDefaults()
        }
    }

    private func confirm(title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { action() }
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window { alert.beginSheetModal(for: window) }
    }

    @objc private func openRepository(_ sender: Any) {
        if let url = URL(string: Self.githubURLString) { NSWorkspace.shared.open(url) }
    }

    @objc private func openIssues(_ sender: Any) {
        if let url = URL(string: Self.githubIssuesURLString) { NSWorkspace.shared.open(url) }
    }

    private func targetPlayerWindowController() -> PlayerWindowController? {
        for window in NSApp.orderedWindows where window !== self.window {
            if let controller = window.windowController as? PlayerWindowController, window.isVisible { return controller }
        }
        return (NSApp.delegate as? AppDelegate)?.windowControllers.last { $0.window?.isVisible == true }
    }

    /// Opens Settings, restoring the last selected category unless a caller asks
    /// for a specific one. Passing a section here also persists it as the
    /// restored category, so callers should only do so deliberately.
    func openSettings(section: Section? = nil) {
        syncUIFromDefaults()
        let identifier = SettingsPresentation.resolvedPaneIdentifier(
            requested: section?.identifier,
            stored: UserDefaults.standard.string(forKey: SettingsPresentation.selectedPaneDefaultsKey)
        )
        select(Section.allCases.first(where: { $0.identifier == identifier }) ?? .playback)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsSidebarButton: NSButton {
    let section: SettingsWindowController.Section
    var isSelected = false { didSet { updateAppearance() } }
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String,
         section: SettingsWindowController.Section,
         target: AnyObject?,
         action: Selector) {
        self.section = section
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        alignment = .left
        focusRingType = .default
        setAccessibilityLabel(title)
        setAccessibilityIdentifier(section.identifier)
        toolTip = title
        wantsLayer = true
        layer?.cornerRadius = 6
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self,
                                      userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    private func updateAppearance() {
        setAccessibilityValue(isSelected ? "selected" : "not selected")
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.firstLineHeadIndent = 6
        paragraph.headIndent = 6
        let background: NSColor
        if isSelected {
            background = SettingsWindowController.SettingsColors.selectedSidebarFill.withAlphaComponent(0.34)
        } else if isHovering {
            background = NSColor.white.withAlphaComponent(0.055)
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }
}

private final class SettingsShortcutBadge: NSTextField {
    init(shortcut: String) {
        super.init(frame: .zero)
        stringValue = shortcut
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        alignment = .center
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        textColor = .labelColor
        wantsLayer = true
        layer?.backgroundColor = SettingsWindowController.SettingsColors.selectedSidebarFill.withAlphaComponent(0.20).cgColor
        layer?.borderColor = SettingsWindowController.SettingsColors.shortcutKeyline.withAlphaComponent(0.36).cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 4
        let width = max(30, ceil(intrinsicContentSize.width) + 14)
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

private extension NSPopUpButton {
    func selectItem(where predicate: (NSMenuItem) -> Bool) {
        if let item = itemArray.first(where: predicate) { select(item) }
    }
}
