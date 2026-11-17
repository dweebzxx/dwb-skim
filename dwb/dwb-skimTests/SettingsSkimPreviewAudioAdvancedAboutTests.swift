import Foundation
import XCTest

/// P57: the Skim Preview, dwb+, Advanced, and About Settings pages. The copy, the dependent
/// states, the Next Progressive Random Skim segment line, the new `backgroundAudioEnabled`
/// default, the reset contract, and the About fact list.
final class SettingsSkimPreviewAudioAdvancedAboutTests: XCTestCase {
    private typealias Text = SettingsPresentation.Text

    // MARK: - Page descriptions and section order

    func testTheFourPagesHaveTheApprovedDescriptions() {
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "skimPreview"),
                       "Choose preview duration, start position, and video coverage.")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "skimPlus"),
                       "Play a background track on its own or alongside video audio.")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "advanced"),
                       "Diagnostics, bookmarks, and default settings.")
        XCTAssertEqual(SettingsPresentation.pageDescription(for: "about"), "")
        XCTAssertFalse(SettingsPresentation.showsPageHeader(for: "about"))
    }

    func testTheFourPagesListTheirSectionsInOrder() {
        XCTAssertEqual(Text.skimPreviewSections, ["Preview duration", "Start position", "Progressive sampling"])
        XCTAssertEqual(Text.skimPlusSections, ["Background audio", "Audio mix"])
        XCTAssertEqual(Text.advancedSections, ["Diagnostics", "Bookmarks", "Reset"])
    }

    // MARK: - Skim Preview (R2, R3)

    func testSkimPreviewLabelsAndSupportingText() {
        XCTAssertEqual(Text.clipDurationLabel, "Clip duration")
        XCTAssertEqual(Text.clipDurationModeTitles, ["Fixed", "Random"])
        XCTAssertEqual(Text.fixedDurationLabel, "Fixed duration")
        XCTAssertEqual(Text.fixedDurationHelper, "Enter 0 to play the full file.")
        XCTAssertEqual(Text.minimumDurationLabel, "Minimum duration")
        XCTAssertEqual(Text.maximumDurationLabel, "Maximum duration")
        XCTAssertEqual(Text.startPreviewsLabel, "Start previews")
        XCTAssertEqual(Text.startPreviewsTitles, ["Beginning", "Random"])
        XCTAssertEqual(Text.skipIntroLabel, "Skip intro")
        XCTAssertEqual(Text.skipIntroHelper, "Sets the earliest point where a preview can begin.")
        XCTAssertEqual(Text.progressiveRandomSkimTitle, "Progressive Random Skim")
        XCTAssertEqual(Text.progressiveRandomSkimHelper,
                       "Sample several non-overlapping segments in chronological order before advancing to the next file. Short videos use a single preview.")
        XCTAssertEqual(Text.coverageLabel, "Coverage")
        XCTAssertEqual(Text.coverageHelper,
                       "Controls how many segments are sampled. Segment lengths follow the preview duration settings above.")
    }

    func testDurationFieldsAreEnabledPerMode() {
        let fixed = SettingsDefaultsRegistry.Defaults.previewDurationModeFixed
        let random = SettingsDefaultsRegistry.Defaults.previewDurationModeRandom
        XCTAssertTrue(SettingsPresentation.fixedDurationIsEnabled(previewDurationMode: fixed))
        XCTAssertFalse(SettingsPresentation.randomDurationIsEnabled(previewDurationMode: fixed))
        XCTAssertFalse(SettingsPresentation.fixedDurationIsEnabled(previewDurationMode: random))
        XCTAssertTrue(SettingsPresentation.randomDurationIsEnabled(previewDurationMode: random))
        // An unknown stored mode reads as Fixed, as `validatedPreviewDurationMode` does.
        XCTAssertTrue(SettingsPresentation.fixedDurationIsEnabled(previewDurationMode: "other"))
        XCTAssertFalse(SettingsPresentation.randomDurationIsEnabled(previewDurationMode: "other"))
    }

    func testSwitchingDurationModeKeepsEveryStoredValue() {
        let suite = "com.dwb.skimTests.SkimPreviewValues.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let store = SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
        store.setFixedDurationSeconds(22)
        store.setRandomMinimumSeconds(7)
        store.setRandomMaximumSeconds(31)
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeFixed)
        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.fixedDurationSeconds, 22)
        XCTAssertEqual(snapshot.randomDurationRange, 7...31)
    }

    func testABoundEditNeverLeavesAnInvalidRange() {
        let suite = "com.dwb.skimTests.SkimPreviewRange.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let store = SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
        store.setRandomMinimumSeconds(5)
        store.setRandomMaximumSeconds(15)
        store.setRandomMinimumSeconds(40)
        let range = store.snapshot().randomDurationRange
        XCTAssertLessThanOrEqual(range.lowerBound, range.upperBound)
        store.setRandomMaximumSeconds(2)
        let next = store.snapshot().randomDurationRange
        XCTAssertLessThanOrEqual(next.lowerBound, next.upperBound)
    }

    // MARK: - Coverage and the segment line (R4)

    func testCoverageOptionsAreInOrder() {
        XCTAssertEqual(SettingsPresentation.progressiveRandomSkimIntensityLabels,
                       ["Light", "Standard", "Thorough", "Ultra", "Max"])
    }

    func testCoverageFollowsProgressiveRandomSkim() {
        XCTAssertTrue(SettingsPresentation.coverageIsEnabled(progressiveRandomSkimEnabled: true))
        XCTAssertFalse(SettingsPresentation.coverageIsEnabled(progressiveRandomSkimEnabled: false))
    }

    func testTheSegmentLineForTheDefaultKeyUsesTheSpokenName() {
        let (store, _, _) = makeShortcutStore()
        XCTAssertEqual(SettingsPresentation.nextSkimSegmentLine(store: store),
                       "Right Arrow moves to a later progressive segment. At the final segment, it does not advance to the next file.")
    }

    func testTheSegmentLineJoinsSeveralKeysWithOr() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(nil, with: .bare("l"), for: .nextSkimSegment)
        XCTAssertEqual(SettingsPresentation.nextSkimSegmentLine(store: store),
                       "Right Arrow or L moves to a later progressive segment. At the final segment, it does not advance to the next file.")
    }

    func testTheSegmentLineForNoKey() {
        let (store, _, _) = makeShortcutStore()
        store.setKeys([], for: .nextSkimSegment)
        XCTAssertEqual(SettingsPresentation.nextSkimSegmentLine(store: store),
                       "Next Progressive Random Skim segment has no shortcut. When assigned, it moves to a later progressive segment. At the final segment, it does not advance to the next file.")
    }

    func testTheSegmentLineFollowsAReassignedKeyAndTheDefaultsReturn() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(ShortcutKey.rightArrow), with: .bare("k"), for: .nextSkimSegment)
        XCTAssertTrue(SettingsPresentation.nextSkimSegmentLine(store: store).hasPrefix("K moves to"))
        store.restoreDefaults()
        XCTAssertTrue(SettingsPresentation.nextSkimSegmentLine(store: store).hasPrefix("Right Arrow moves to"))
    }

    // MARK: - dwb+ (R8, R9, R12)

    func testBackgroundAudioLabelsAndSupportingText() {
        XCTAssertEqual(Text.enableBackgroundAudioTitle, "Enable background audio")
        XCTAssertEqual(Text.enableBackgroundAudioHelper, "Turning this off keeps your selected track and audio settings.")
        XCTAssertEqual(Text.audioTrackLabel, "Audio track")
        XCTAssertEqual(Text.chooseAudioTrackTitle, "Choose Audio Track\u{2026}")
        XCTAssertEqual(Text.selectedTrackLabel, "Selected")
        XCTAssertEqual(Text.noAudioTrackSelected, "No audio track selected")
        XCTAssertEqual(Text.clearAudioTrackTitle, "Clear")
        XCTAssertEqual(Text.audioTrackHelper, "Choose one local MP3 or M4A file.")
        XCTAssertEqual(Text.backgroundAudioVolumeLabel, "Background audio volume")
    }

    func testMixHelperTextFollowsTheSelection() {
        XCTAssertEqual(SettingsPresentation.audioMixHelperText(for: .uploadedOnly),
                       "Play the background track without video audio.")
        XCTAssertEqual(SettingsPresentation.audioMixHelperText(for: .videoAndUploaded),
                       "Play video audio and background audio together.")
    }

    func testMixTitlesAndVisibleTextNeverSayUploaded() {
        XCTAssertEqual(BackgroundAudioMixMode.allCases.map(\.title),
                       ["Background Audio Only", "Video + Background Audio"])
        let visible = [Text.enableBackgroundAudioTitle, Text.enableBackgroundAudioHelper, Text.audioTrackLabel,
                       Text.chooseAudioTrackTitle, Text.audioTrackHelper, Text.backgroundAudioOnlyHelper,
                       Text.videoAndBackgroundAudioHelper, Text.backgroundAudioVolumeLabel]
            + BackgroundAudioMixMode.allCases.map(\.title)
        for text in visible { XCTAssertFalse(text.lowercased().contains("uploaded"), text) }
    }

    func testMixAndVolumeNeedBackgroundAudioOnAndAnAvailableTrack() {
        // Off: disabled whatever the track.
        XCTAssertFalse(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: false, trackIsAvailable: true))
        XCTAssertFalse(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: false, trackIsAvailable: false))
        // On with no track or an unavailable track: disabled.
        XCTAssertFalse(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: true, trackIsAvailable: false))
        // On with an available track: enabled.
        XCTAssertTrue(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: true, trackIsAvailable: true))
    }

    func testEnabledStateForNoTrackAndUnavailableTrackSelections() {
        let none = BackgroundAudioSelection.none
        let unavailable = BackgroundAudioSelection.unavailable(displayName: "gone.mp3", reason: "The selected audio file is unavailable.")
        let available = BackgroundAudioSelection.available(URL(fileURLWithPath: "/tmp/track.mp3"))
        XCTAssertFalse(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: true, trackIsAvailable: none.isAvailable))
        XCTAssertFalse(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: true, trackIsAvailable: unavailable.isAvailable))
        XCTAssertTrue(SettingsPresentation.audioMixControlsAreEnabled(backgroundAudioEnabled: true, trackIsAvailable: available.isAvailable))
    }

    func testBackgroundAudioEnabledIsRegisteredAsOn() {
        XCTAssertEqual(SettingsDefaultsRegistry.Keys.backgroundAudioEnabled, "backgroundAudioEnabled")
        XCTAssertEqual(SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)["backgroundAudioEnabled"] as? Bool, true)
        let suite = "com.dwb.skimTests.EnabledDefault.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        XCTAssertTrue(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioEnabled))
    }

    // MARK: - Advanced (R15, R16, R17)

    func testAdvancedDiagnosticsText() {
        XCTAssertEqual(Text.showDebugConsoleTitle, "Show debug console")
        XCTAssertEqual(Text.detailedAutoplayLoggingTitle, "Detailed autoplay logging")
        XCTAssertEqual(Text.detailedAutoplayLoggingHelper, "Records additional autoplay diagnostics in debug builds only.")
    }

    func testClearAllBookmarksTextNamesTheApp() {
        XCTAssertEqual(Text.clearAllBookmarksTitle, "Clear All Bookmarks\u{2026}")
        XCTAssertEqual(Text.clearAllBookmarksHelper,
                       "Clears this app's bookmarks without deleting media files. This cannot be undone.")
        XCTAssertEqual(Text.clearBookmarksConfirmTitle, "Clear all bookmarks for dwb skim?")
        XCTAssertEqual(Text.clearBookmarksConfirmMessage,
                       "This removes all bookmarks saved by this app. Media files are not deleted. This cannot be undone.")
        XCTAssertEqual(Text.clearBookmarksConfirmAction, "Clear All Bookmarks")
    }

    func testRestoreDefaultSettingsTextNamesTheApp() {
        XCTAssertEqual(Text.restoreDefaultSettingsTitle, "Restore Default Settings\u{2026}")
        XCTAssertEqual(Text.restoreDefaultSettingsHelper,
                       "Restores this app's settings and keyboard shortcuts. Media files, queues, and bookmarks are not deleted.")
        XCTAssertEqual(Text.restoreConfirmTitle, "Restore default settings for dwb skim?")
        XCTAssertEqual(Text.restoreConfirmMessage,
                       "This resets this app's settings and customized keyboard shortcuts. Media files, queues, and bookmarks are not deleted.")
        XCTAssertEqual(Text.restoreConfirmAction, "Restore Defaults")
    }

    func testRestoreResetsBackgroundAudioEnabledAndRemovesShortcutOverrides() {
        let (store, defaults, _) = makeShortcutStore()
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        defaults.set(false, forKey: SettingsDefaultsRegistry.Keys.backgroundAudioEnabled)
        store.replaceKey(.bare(ShortcutKey.rightArrow), with: .bare("k"), for: .nextSkimSegment)
        XCTAssertNotNil(defaults.object(forKey: ShortcutStore.defaultsKey))
        XCTAssertEqual(store.activeKeys(for: .nextSkimSegment), [.bare("k")])

        SettingsDefaultsRegistry.restoreAllSettings(defaults: defaults, reduceMotionDefault: false)
        store.reload()

        XCTAssertTrue(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.backgroundAudioEnabled))
        XCTAssertNil(defaults.object(forKey: ShortcutStore.defaultsKey))
        XCTAssertFalse(store.hasOverrides)
        XCTAssertEqual(store.activeKeys(for: .nextSkimSegment),
                       ShortcutCommandTable.command(.nextSkimSegment).defaultKeys)
        XCTAssertEqual(SettingsPresentation.nextSkimSegmentLine(store: store),
                       "Right Arrow moves to a later progressive segment. At the final segment, it does not advance to the next file.")
    }

    // MARK: - About (R18, R19, R20)

    func testTheVersionLineUsesAMiddleDotWithOneSpaceEachSide() {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: [
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "3",
        ])
        XCTAssertEqual(values.versionLine, "Version 1.2 \u{00B7} Build 3")
        XCTAssertFalse(values.versionLine.contains("\u{2022}"))
    }

    func testAboutDescriptionAndLinkTitles() {
        XCTAssertEqual(SettingsPresentation.productDescription,
                       "Quickly review local videos with short previews, alongside images and GIFs.")
        XCTAssertEqual(SettingsPresentation.aboutRepositoryLinkTitle, "View on GitHub")
        XCTAssertEqual(SettingsPresentation.aboutIssuesLinkTitle, "Report an Issue")
    }

    func testAboutFactsAreInOrderWithRequiresFromTheBundle() {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: [
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "3",
            "LSMinimumSystemVersion": "14.2",
        ])
        let facts = SettingsPresentation.aboutFacts(values: values, vlcBackendVersion: "3.0.21 Vetinari")
        XCTAssertEqual(facts.map(\.label), ["License", "Requires", "Interface", "Playback framework", "VLC backend"])
        XCTAssertEqual(facts.map(\.value), ["MIT License", "macOS 14.2 or later", "AppKit", "VLCKit", "3.0.21 Vetinari"])
    }

    func testAboutFactsHaveNoPlaceholderOrOldLabel() {
        let values = SettingsPresentation.aboutDisplayValues(infoDictionary: nil)
        let facts = SettingsPresentation.aboutFacts(values: values, vlcBackendVersion: "Unavailable")
        XCTAssertEqual(facts.first { $0.label == "Requires" }?.value, "macOS 13.0 or later")
        XCTAssertFalse(facts.contains { $0.label == "Platform" || $0.label == "Playback" })
        for fact in facts {
            XCTAssertFalse(fact.value.contains("["), fact.value)
            XCTAssertFalse(fact.value.contains("<"), fact.value)
        }
    }

    // MARK: - Old text is gone

    func testTheInventoryHoldsNoOldLabel() {
        let old = ["Random minimum", "Random maximum", "Start position", "Coverage intensity",
                   "Verbose autoplay diagnostics", "Clear All Bookmarks...", "Restore All Settings to Default"]
        for label in old {
            XCTAssertFalse(SettingsPresentation.representedSettingLabels.contains(label), label)
        }
    }
}
