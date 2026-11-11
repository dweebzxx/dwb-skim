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
    private enum LayoutMetrics {
        static let maximumContentWidth = SettingsPresentation.maximumContentWidth
        static let labelWidth = SettingsPresentation.labelColumnWidth
        static let columnSpacing = SettingsPresentation.columnSpacing
        static let rowSpacing = SettingsPresentation.rowSpacing
        static let sectionSpacing = SettingsPresentation.sectionSpacing
        static let helperMaximumWidth = SettingsPresentation.helperMaximumWidth
    }

    /// The pages in sidebar order. The raw value is the page's index in
    /// `SettingsPresentation.panes`, which holds the same order.
    enum Section: Int, CaseIterable {
        case playback
        case controls
        case queueFiles
        case shortcuts
        case skimPreview
        case skimPlus
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

    private var sidebar: SettingsSidebarView?
    private let detailContainer = NSView()
    private var sectionViews: [NSView] = []
    private var selectedSection: Section = .playback
    private var isSynchronizing = false

    private let playbackSpeedPopup = DWBPopUpButton()
    private let showTitleOverlayCheckbox = NSButton()
    private let imageDurationField = DWBInlineTextField()
    private let imageDurationStepper = NSStepper()
    private let gifLoopCountField = DWBInlineTextField()
    private let gifLoopCountStepper = NSStepper()
    private let normalizeVideoAudioCheckbox = NSButton()
    private let acceptVideoCheckbox = NSButton()
    private let acceptImagesCheckbox = NSButton()
    private let acceptGIFCheckbox = NSButton()

    private let previewDurationModeControl = DWBSegmentedControl()
    private let fixedDurationField = DWBInlineTextField()
    private let randomMinimumField = DWBInlineTextField()
    private let randomMaximumField = DWBInlineTextField()
    private let startPositionControl = DWBSegmentedControl()
    private let skipIntroField = DWBInlineTextField()
    private let progressiveRandomSkimCheckbox = NSButton()
    private let progressiveRandomSkimIntensityControl = DWBSegmentedControl()
    private var fixedDurationRow: SettingsFormRow?
    private var randomMinimumRow: SettingsFormRow?
    private var randomMaximumRow: SettingsFormRow?

    private let audioSelectedLabel = DWBLabel("No audio track selected", size: 12, tone: .tertiary)
    private let audioUnavailableLabel = DWBLabel("", size: 11, tone: .secondary)
    private let chooseAudioButton = DWBButton(title: "Choose Audio Track...", style: .neutral)
    private let clearAudioButton = DWBButton(title: "Clear", style: .plain, size: .small)
    private let audioMixControl = DWBSegmentedControl()
    private let backgroundVolumeSlider = NSSlider()
    private let backgroundVolumeLabel = DWBLabel("75%", size: 13, tabularDigits: true)
    private var audioSelectionWell: SettingsAudioWellView?
    private var audioMixRow: SettingsFormRow?
    private var backgroundVolumeRow: SettingsFormRow?

    private let autoHideCheckbox = NSButton()
    private let chromeThresholdPopup = DWBPopUpButton()
    private let reducedMotionCheckbox = NSButton()
    private let autoHideTitlebarCheckbox = NSButton()
    private let completeVideoCheckbox = NSButton()
    private let opacitySlider = NSSlider()
    private let opacityLabel = DWBLabel("100%", size: 13, tabularDigits: true)

    private let primaryPrefixField = DWBInlineTextField()
    private let secondaryPrefixField = DWBInlineTextField()
    private let queueOrderPopup = DWBPopUpButton()
    private let loopQueueSwitch = NSSwitch()
    private let openQueueCheckbox = NSButton()

    private let debugCheckbox = NSButton()
    private let verboseCheckbox = NSButton()
    private let clearBookmarksButton = DWBButton(title: "Clear All Bookmarks...", style: .neutralDestructive)
    private let restoreDefaultsButton = DWBButton(title: "Restore All Settings to Default", style: .neutral)

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
        panel.backgroundColor = DWBColor.surface
        panel.isOpaque = true
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
        content.layer?.backgroundColor = DWBColor.surface.cgColor

        // A solid `canvas` sidebar: Increase Contrast has no translucency to remove.
        let sidebar = SettingsSidebarView(groups: SettingsPresentation.sidebarGroups,
                                          sections: Section.allCases,
                                          target: self,
                                          action: #selector(sidebarTapped(_:)))
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sidebar)
        self.sidebar = sidebar

        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.wantsLayer = true
        detailContainer.layer?.backgroundColor = DWBColor.surface.cgColor
        content.addSubview(detailContainer)

        let separator = DWBRuleView(kind: .border, vertical: true)
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(separator)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: SettingsPresentation.sidebarWidth),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: content.topAnchor),
            separator.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            detailContainer.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: content.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // Built in `Section` (sidebar) order so `sectionViews[section.rawValue]` is the page.
        sectionViews = [
            buildPlaybackPage(), buildControlsPage(), buildQueueFilesPage(), buildShortcutsPage(),
            buildSkimPreviewPage(), buildSkimPlusPage(), buildAdvancedPage(), buildAboutPage(),
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
        return page(identifier: "playback", sections: [
            section("Playback", rows: [
                row("Playback speed", playbackSpeedPopup, helper: "Applies to the frontmost player window."),
                row(nil, showTitleOverlayCheckbox),
            ]),
            section("Media duration", rows: [
                row("Image duration", numericStepperControl(imageDurationField,
                                                              stepper: imageDurationStepper,
                                                              suffix: "s"),
                    helper: "Still images advance after the selected number of seconds."),
                row("GIF loops", numericStepperControl(gifLoopCountField,
                                                        stepper: gifLoopCountStepper),
                    helper: "GIFs advance after the selected number of completed animation loops."),
            ]),
            section("Video audio", rows: [
                row(nil, normalizeVideoAudioCheckbox,
                    helper: "Adjusts video audio in real time. dwb+ background audio is never processed."),
            ]),
            section("Accepted media", rows: [row(nil, accept)]),
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

        progressiveRandomSkimIntensityControl.segmentCount = SettingsPresentation.progressiveRandomSkimIntensityOptions.count
        for (index, label) in SettingsPresentation.progressiveRandomSkimIntensityLabels.enumerated() {
            progressiveRandomSkimIntensityControl.setLabel(label, forSegment: index)
        }
        progressiveRandomSkimIntensityControl.target = self
        progressiveRandomSkimIntensityControl.action = #selector(progressiveRandomSkimIntensityChanged(_:))
        progressiveRandomSkimIntensityControl.setAccessibilityLabel("Progressive Random Skim coverage intensity")

        // The visual grid label is a sibling view, so AppKit does not associate it
        // with the field; each control carries its own human-facing label.
        previewDurationModeControl.setAccessibilityLabel("Clip duration mode")
        fixedDurationField.setAccessibilityLabel("Fixed clip duration in seconds")
        fixedDurationField.toolTip = "Controls Progressive segment length in Fixed mode."
        randomMinimumField.setAccessibilityLabel("Minimum random clip duration in seconds")
        randomMinimumField.toolTip = "Bounds Progressive segment length in Random mode."
        randomMaximumField.setAccessibilityLabel("Maximum random clip duration in seconds")
        randomMaximumField.toolTip = "Bounds Progressive segment length in Random mode."
        startPositionControl.setAccessibilityLabel("Start position")
        skipIntroField.setAccessibilityLabel("Skip intro in seconds")

        startPositionControl.segmentCount = 2
        startPositionControl.setLabel("Beginning", forSegment: 0)
        startPositionControl.setLabel("Random", forSegment: 1)
        startPositionControl.target = self
        startPositionControl.action = #selector(startPositionChanged(_:))

        let fixed = row("Fixed duration", secondsControl(fixedDurationField),
                        helper: "0 plays the full file. Controls Progressive segment length in Fixed mode.")
        let minimum = row("Random minimum", secondsControl(randomMinimumField),
                          helper: "Bounds Progressive segment length in Random mode.")
        let maximum = row("Random maximum", secondsControl(randomMaximumField),
                          helper: "Bounds Progressive segment length in Random mode.")
        fixedDurationRow = fixed
        randomMinimumRow = minimum
        randomMaximumRow = maximum

        return page(identifier: "skimPreview", sections: [
            section("Skim preview", rows: [
                row("Clip duration", previewDurationModeControl),
                fixed,
                minimum,
                maximum,
                row("Start position", startPositionControl),
                row("Skip intro", secondsControl(skipIntroField)),
                row(nil, progressiveRandomSkimCheckbox,
                    helper: "Samples several short, randomized segments spread across videos 30 seconds or longer, always starting no earlier than Skip Intro."),
                row("Coverage intensity", progressiveRandomSkimIntensityControl,
                    helper: SettingsPresentation.progressiveRandomSkimCoverageHelperText),
            ]),
        ])
    }

    private func buildSkimPlusPage() -> NSView {
        chooseAudioButton.target = self
        chooseAudioButton.action = #selector(chooseAudioTrack(_:))
        chooseAudioButton.setAccessibilityLabel("Choose Background Audio Track")

        clearAudioButton.target = self
        clearAudioButton.action = #selector(clearAudioTrack(_:))

        let selectionWell = SettingsAudioWellView(label: audioSelectedLabel)
        audioSelectionWell = selectionWell
        audioSelectedLabel.lineBreakMode = .byTruncatingMiddle
        audioSelectedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        audioUnavailableLabel.lineBreakMode = .byWordWrapping

        let selection = NSStackView(views: [selectionWell, clearAudioButton])
        selection.orientation = .horizontal
        selection.alignment = .centerY
        selection.spacing = 8

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
        backgroundVolumeLabel.alignment = .left
        backgroundVolumeLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let volume = NSStackView(views: [backgroundVolumeSlider, backgroundVolumeLabel])
        volume.orientation = .horizontal
        volume.alignment = .centerY
        volume.spacing = 10

        let mix = row(nil, audioMixControl)
        let backgroundVolume = row("Background audio volume", volume)
        audioMixRow = mix
        backgroundVolumeRow = backgroundVolume

        return page(identifier: "skimPlus", sections: [
            section("Background audio", rows: [
                row("Audio track", chooseAudioButton),
                row("Selected", selection),
                row(nil, audioUnavailableLabel),
            ]),
            section("Audio mix", rows: [
                mix,
                backgroundVolume,
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
        opacity.alignment = .centerY
        opacity.spacing = 10
        return page(identifier: "controls", sections: [
            section("Playback overlay", rows: [
                row(nil, autoHideCheckbox), row("Hide delay", chromeThresholdPopup), row(nil, reducedMotionCheckbox),
            ]),
            section("Window", rows: [
                row(nil, autoHideTitlebarCheckbox), row(nil, completeVideoCheckbox), row("Window opacity", opacity),
            ]),
        ])
    }

    private func buildQueueFilesPage() -> NSView {
        configureTextField(primaryPrefixField, placeholder: "e.g. select_")
        configureTextField(secondaryPrefixField, placeholder: "e.g. later_")
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
        return page(identifier: "queueFiles", sections: [
            section("Prefix rename", rows: [
                row("Primary custom prefix", prefixFieldChrome(primaryPrefixField), swatch: theme.markerPrimary),
                row("Secondary custom prefix", prefixFieldChrome(secondaryPrefixField),
                    helper: "Custom prefixes rename immediately in the same directory and preserve the extension.",
                    swatch: theme.markerSecondary),
            ]),
            section("Queue behavior", rows: [
                row("Queue order", queueOrderPopup,
                    helper: "Weighted favors items that have waited longest since playback."),
                row("Loop queue", loopQueueSwitch), row(nil, openQueueCheckbox),
            ]),
        ])
    }

    private func buildShortcutsPage() -> NSView {
        let shortcuts = ShortcutsPageView()
        shortcuts.translatesAutoresizingMaskIntoConstraints = false
        return page(identifier: "shortcuts", sections: [shortcuts])
    }

    private func buildAdvancedPage() -> NSView {
        configureCheckbox(debugCheckbox, title: "Show debug console")
        configureCheckbox(verboseCheckbox, title: "Verbose autoplay diagnostics")
        clearBookmarksButton.target = self
        clearBookmarksButton.action = #selector(clearAllBookmarks(_:))
        restoreDefaultsButton.target = self
        restoreDefaultsButton.action = #selector(restoreDefaults(_:))
        return page(identifier: "advanced", sections: [
            section("Diagnostics", rows: [row(nil, debugCheckbox), row(nil, verboseCheckbox)]),
            section("Bookmarks", rows: [row(nil, clearBookmarksButton, helper: "This cannot be undone.")]),
            section("Reset", rows: [row(nil, restoreDefaultsButton, helper: "Media files, queues, and bookmarks are not deleted.")]),
        ])
    }

    private func buildAboutPage() -> NSView {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: Bundle.main.infoDictionary)
        let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("dwb skim application icon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: DWBMetrics.aboutIcon).isActive = true
        icon.heightAnchor.constraint(equalToConstant: DWBMetrics.aboutIcon).isActive = true

        // "dwb" in `textPrimary` and the app word in `accentText`.
        let productName = DWBLabel("", size: DWBMetrics.aboutTitle, weight: .semibold, tone: .primary)
        let nameParts = values.productName.split(separator: " ", maxSplits: 1).map(String.init)
        let nameText = NSMutableAttributedString(string: nameParts.first ?? values.productName, attributes: [
            .font: NSFont.systemFont(ofSize: DWBMetrics.aboutTitle, weight: .semibold),
            .foregroundColor: DWBColor.textPrimary,
        ])
        if nameParts.count > 1 {
            nameText.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: DWBMetrics.aboutTitle, weight: .semibold),
            ]))
            nameText.append(NSAttributedString(string: nameParts[1], attributes: [
                .font: NSFont.systemFont(ofSize: DWBMetrics.aboutTitle, weight: .semibold),
                .foregroundColor: theme.accentText,
            ]))
        }
        productName.attributedStringValue = nameText
        productName.setAccessibilityLabel(values.productName)

        let version = DWBLabel("Version \(values.version) \u{2022} Build \(values.build)",
                               size: 13, tone: .secondary, tabularDigits: true)
        let description = DWBLabel(SettingsPresentation.productDescription, size: 13, tone: .primary)
        description.lineBreakMode = .byWordWrapping
        description.maximumNumberOfLines = 0
        description.cell?.wraps = true
        description.preferredMaxLayoutWidth = 420

        let rule = DWBRuleView(kind: .border)
        rule.translatesAutoresizingMaskIntoConstraints = false

        let facts = aboutFacts([
            ("License", "MIT License"),
            ("Platform", "macOS \(values.minimumSystemVersion) or later"),
            ("Interface", "AppKit"),
            ("Playback", "VLCKit"),
            ("VLC backend", Self.vlcBackendVersionText()),
        ])
        let repo = DWBButton(title: "GitHub Repository", style: .link,
                             target: self, action: #selector(openRepository(_:)))
        let issues = DWBButton(title: "Report an Issue", style: .link,
                               target: self, action: #selector(openIssues(_:)))
        repo.setAccessibilityLabel("Open dwb skim GitHub repository")
        repo.setAccessibilityHelp(Self.githubURLString)
        issues.setAccessibilityLabel("Open dwb skim issue tracker")
        issues.setAccessibilityHelp(Self.githubIssuesURLString)
        let links = NSStackView(views: [repo, issues])
        links.orientation = .horizontal
        links.spacing = 8
        let identityText = NSStackView(views: [productName, version, description, rule, facts, links])
        identityText.orientation = .vertical
        identityText.alignment = .leading
        identityText.spacing = 6
        identityText.setCustomSpacing(10, after: version)
        identityText.setCustomSpacing(12, after: description)
        identityText.setCustomSpacing(10, after: rule)
        identityText.setCustomSpacing(14, after: facts)
        rule.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true
        let ruleFill = rule.widthAnchor.constraint(equalTo: identityText.widthAnchor)
        ruleFill.priority = .defaultHigh
        ruleFill.isActive = true
        let identity = NSStackView(views: [icon, identityText])
        identity.orientation = .horizontal
        identity.alignment = .top
        identity.spacing = 24
        return aboutPage(identity: identity)
    }

    private func aboutFacts(_ facts: [(String, String)]) -> NSView {
        let views = facts.map { label, value -> [NSView] in
            let name = DWBLabel(label, size: 12.5, tone: .tertiary)
            let detail = DWBLabel(value, size: 12.5, tone: .primary, tabularDigits: true)
            detail.lineBreakMode = .byTruncatingTail
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return [name, detail]
        }
        let grid = NSGridView(views: views)
        grid.columnSpacing = 12
        grid.rowSpacing = 7
        grid.column(at: 0).width = 110
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

        let copyright = DWBLabel("\u{00A9} dwb", size: 10.5, tone: .tertiary)
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

        // About has no page header, so its content starts at the page's top inset.
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

    // MARK: - Page structure

    /// A label and control row, kept so a dependent row can be disabled rather than hidden.
    private final class SettingsFormRow {
        let view: NSView
        private let label: DWBLabel?
        private let control: NSView

        init(view: NSView, label: DWBLabel?, control: NSView) {
            self.view = view
            self.label = label
            self.control = control
        }

        /// Design system 9.5: the label is `textDisabled` and the control sits at 0.32 alpha.
        /// Whether each control still accepts input stays with the controller.
        func setDisabled(_ disabled: Bool) {
            label?.tone = disabled ? .disabled : .primary
            control.alphaValue = disabled ? DWBMetrics.disabledAlpha : 1
        }
    }

    /// A page: its header (title, description, hairline) followed by the sections.
    private func page(identifier: String, sections: [NSView]) -> NSView {
        var content: [NSView] = []
        if SettingsPresentation.showsPageHeader(for: identifier) {
            content.append(pageHeader(identifier: identifier))
        }
        content.append(contentsOf: sections)

        let stack = NSStackView(views: content)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = LayoutMetrics.sectionSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedSettingsView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        content.forEach { $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        // The 54 pt top inset is measured from the window top; the page scrolls under the
        // transparent title bar, so the document's own top is the window top.
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

    /// The page title (20 pt semibold), its one-sentence description (`textSecondary`), and a hairline.
    private func pageHeader(identifier: String) -> NSView {
        let title = DWBLabel(SettingsPresentation.paneHeading(for: identifier),
                             size: 20, weight: .semibold, tone: .primary)
        title.setAccessibilityRole(.staticText)
        let description = DWBLabel(SettingsPresentation.pageDescription(for: identifier),
                                   size: 11.5, tone: .secondary)
        description.lineBreakMode = .byWordWrapping
        description.maximumNumberOfLines = 0
        description.cell?.wraps = true
        description.preferredMaxLayoutWidth = LayoutMetrics.maximumContentWidth
        let rule = DWBRuleView(kind: .gridLine)
        rule.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [title, description, rule])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(14, after: description)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func section(_ title: String, rows: [SettingsFormRow]) -> NSView {
        let heading = DWBLabel(title, size: 11, weight: .semibold, tone: .accent)
        heading.setAccessibilityRole(.staticText)

        let rowStack = NSStackView(views: rows.map(\.view))
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = LayoutMetrics.rowSpacing

        let stack = NSStackView(views: [heading, rowStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = LayoutMetrics.rowSpacing
        return stack
    }

    private func row(_ label: String?,
                     _ control: NSView,
                     helper: String? = nil,
                     swatch: NSColor? = nil) -> SettingsFormRow {
        var controls: [NSView] = [control]
        if let helper {
            let note = DWBLabel(helper, size: 11, tone: .tertiary)
            note.lineBreakMode = .byWordWrapping
            note.maximumNumberOfLines = 0
            note.cell?.wraps = true
            note.preferredMaxLayoutWidth = LayoutMetrics.helperMaximumWidth
            note.widthAnchor.constraint(lessThanOrEqualToConstant: LayoutMetrics.helperMaximumWidth).isActive = true
            controls.append(note)
        }
        let controlColumn = NSStackView(views: controls)
        controlColumn.orientation = .vertical
        controlColumn.alignment = .leading
        controlColumn.spacing = 5
        controlColumn.translatesAutoresizingMaskIntoConstraints = false
        controlColumn.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

        guard let label else {
            return SettingsFormRow(view: controlColumn, label: nil, control: control)
        }

        let labelView = DWBLabel(label, size: 13, tone: .primary)
        labelView.lineBreakMode = .byWordWrapping
        labelView.maximumNumberOfLines = 2
        labelView.cell?.wraps = true
        labelView.preferredMaxLayoutWidth = LayoutMetrics.labelWidth - (swatch == nil ? 0 : DWBMetrics.prefixSwatch + 6)
        labelView.setContentCompressionResistancePriority(.required, for: .horizontal)

        var labelParts: [NSView] = [labelView]
        if let swatch {
            // An 8 pt marker-color dot, then the neutral label text.
            labelParts.insert(SettingsSwatchView(color: swatch), at: 0)
        }
        let labelStack = NSStackView(views: labelParts)
        labelStack.orientation = .horizontal
        labelStack.alignment = .centerY
        labelStack.spacing = 6
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        let labelHolder = NSView()
        labelHolder.translatesAutoresizingMaskIntoConstraints = false
        labelHolder.addSubview(labelStack)
        NSLayoutConstraint.activate([
            labelStack.leadingAnchor.constraint(equalTo: labelHolder.leadingAnchor),
            labelStack.trailingAnchor.constraint(lessThanOrEqualTo: labelHolder.trailingAnchor),
            labelStack.topAnchor.constraint(equalTo: labelHolder.topAnchor, constant: 4),
            labelStack.bottomAnchor.constraint(equalTo: labelHolder.bottomAnchor),
        ])

        let grid = NSGridView(views: [[labelHolder, controlColumn]])
        grid.columnSpacing = LayoutMetrics.columnSpacing
        grid.column(at: 0).width = LayoutMetrics.labelWidth
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .leading
        grid.row(at: 0).yPlacement = .top
        return SettingsFormRow(view: grid, label: labelView, control: control)
    }

    private func configureCheckbox(_ button: NSButton, title: String) {
        button.setButtonType(.switch)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: DWBColor.textPrimary,
        ])
        button.target = self
        button.action = #selector(checkboxChanged(_:))
        // The box itself is tinted by the app's `AccentColor`.
        button.contentTintColor = nil
    }

    private func configurePopup(_ popup: NSPopUpButton, action: Selector) {
        popup.target = self
        popup.action = action
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        popup.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func configureTextField(_ field: DWBInlineTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.delegate = self
    }

    /// A monospaced, 220 pt wide prefix field.
    private func prefixFieldChrome(_ field: DWBInlineTextField) -> NSView {
        let chrome = DWBFieldChrome(field: field, width: 220, monospaced: true)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.widthAnchor.constraint(equalToConstant: 220).isActive = true
        chrome.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return chrome
    }

    private func configureNumericField(_ field: DWBInlineTextField,
                                       placeholder: String,
                                       allowsFloats: Bool = false,
                                       minimum: Double = 0,
                                       maximum: Double? = nil) {
        field.placeholderString = placeholder
        field.delegate = self
        field.alignment = .left
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

    /// A 72 pt number field on `surfaceSunken` with tabular digits.
    private func numberFieldChrome(_ field: DWBInlineTextField) -> DWBFieldChrome {
        let chrome = DWBFieldChrome(field: field, width: 72)
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.widthAnchor.constraint(equalToConstant: 72).isActive = true
        chrome.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return chrome
    }

    private func unitLabel(_ text: String) -> NSView {
        DWBLabel(text, size: 11, tone: .secondary)
    }

    private func numericStepperControl(_ field: DWBInlineTextField,
                                       stepper: NSStepper,
                                       suffix: String? = nil) -> NSView {
        var views: [NSView] = [numberFieldChrome(field), stepper]
        if let suffix { views.append(unitLabel(suffix)) }
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        return stack
    }

    private func secondsControl(_ field: DWBInlineTextField) -> NSView {
        let stack = NSStackView(views: [numberFieldChrome(field), unitLabel("s")])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        return stack
    }

    private func select(_ section: Section) {
        selectedSection = section
        for (index, view) in sectionViews.enumerated() { view.isHidden = index != section.rawValue }
        sidebar?.select(section)
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
        audioSelectedLabel.tone = audio.selection.displayName == nil ? .tertiary : .primary
        audioSelectionWell?.hasSelection = audio.selection.displayName != nil
        if case .unavailable(_, let reason) = audio.selection {
            audioUnavailableLabel.stringValue = "Unavailable: \(reason)"
        } else {
            audioUnavailableLabel.stringValue = audio.selection.isAvailable ? "" : "Choose one MP3 or M4A file."
        }
        clearAudioButton.isEnabled = audio.selection.displayName != nil
        let audioEnabled = audio.selection.isAvailable
        audioMixControl.isEnabled = audioEnabled
        backgroundVolumeSlider.isEnabled = audioEnabled
        // Dependent rows are disabled, not hidden (design system 9.5).
        audioMixRow?.setDisabled(!audioEnabled)
        backgroundVolumeRow?.setDisabled(!audioEnabled)
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

    /// The Fixed row applies in Fixed mode and the Random rows in Random mode. The other
    /// rows are disabled, not hidden.
    private func updatePreviewRowVisibility() {
        let random = previewDurationModeControl.selectedSegment == 1
        fixedDurationField.isEnabled = !random
        randomMinimumField.isEnabled = random
        randomMaximumField.isEnabled = random
        fixedDurationRow?.setDisabled(random)
        randomMinimumRow?.setDisabled(!random)
        randomMaximumRow?.setDisabled(!random)
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

    @objc private func previewModeChanged(_ sender: DWBSegmentedControl) {
        Self.setPreviewDurationMode(sender.selectedSegment == 1 ? Self.previewDurationModeRandom : Self.previewDurationModeFixed)
        updatePreviewRowVisibility()
    }

    @objc private func startPositionChanged(_ sender: DWBSegmentedControl) {
        Self.setStartPositionMode(sender.selectedSegment == 0 ? Self.startPositionModeBeginning : Self.startPositionModeRandom)
    }

    private static func intensitySegment(for intensity: ProgressiveRandomSkimIntensity) -> Int {
        SettingsPresentation.intensitySegment(for: intensity)
    }

    @objc private func progressiveRandomSkimIntensityChanged(_ sender: DWBSegmentedControl) {
        let intensity = SettingsPresentation.intensity(forSegment: sender.selectedSegment)
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

    @objc private func audioMixChanged(_ sender: DWBSegmentedControl) {
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

    /// The destructive confirmation sheet: Cancel is the default and focused button.
    private func confirm(title: String, message: String, actionTitle: String, action: @escaping () -> Void) {
        guard let window else { return }
        ConfirmSheetController(title: title,
                               message: message,
                               actionTitle: actionTitle,
                               onConfirm: action).present(on: window)
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

/// An 8 pt dot in a marker color, before a prefix row's label.
private final class SettingsSwatchView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: DWBMetrics.prefixSwatch, height: DWBMetrics.prefixSwatch)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// The selected background-audio path well: 24 pt tall, `surfaceSunken`, 1 pt `border`,
/// a `music.note` glyph, at most 300 pt wide.
private final class SettingsAudioWellView: NSView {
    private let label: DWBLabel
    private let icon = NSImageView()

    var hasSelection = false {
        didSet { applyIcon() }
    }

    init(label: DWBLabel) {
        self.label = label
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyIcon()
        DWBAccessibility.observe(self, selector: #selector(accessibilityDidChange))
    }

    required init?(coder: NSCoder) { fatalError("programmatic only") }

    private func applyIcon() {
        let color = hasSelection ? theme.accentText : DWBColor.textDisabled
        icon.image = NSImage.dwbSymbol("music.note", pointSize: 11, weight: .regular, color: color)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        DWBColor.surfaceSunken.setFill()
        path.fill()
        DWBAccessibility.border.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func accessibilityDidChange() {
        applyIcon()
        needsDisplay = true
    }
}

private final class FlippedSettingsView: NSView {
    override var isFlipped: Bool { true }
}

private extension NSPopUpButton {
    func selectItem(where predicate: (NSMenuItem) -> Bool) {
        if let item = itemArray.first(where: predicate) { select(item) }
    }
}
