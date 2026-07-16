import Foundation
import XCTest

final class SettingsDefaultsRegistryTests: XCTestCase {

    func testDefaultValuesPreserveSettingsDefaults() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: true)
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertEqual(defaults[keys.autoHideTransportWindowed] as? Bool, false)
        XCTAssertEqual(defaults[keys.skipDurationSeconds] as? Int, 10)
        XCTAssertEqual(defaults[keys.imageDurationSeconds] as? Int, 3)
        XCTAssertEqual(defaults[keys.gifLoopCount] as? Int, 1)
        XCTAssertEqual(defaults[keys.acceptVideoMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.acceptImageMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.acceptGIFMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.autoHideTitlebar] as? Bool, false)
        XCTAssertEqual(defaults[keys.completeVideoWindowMode] as? Bool, false)
        XCTAssertEqual(defaults[keys.showTitleOverlay] as? Bool, true)
        XCTAssertEqual(defaults[keys.deletePrefixRenameEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.videoPageDButtonEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.customPrefixValue] as? String, "")
        XCTAssertEqual(defaults[keys.customPrefixSecondaryValue] as? String, "")
        XCTAssertEqual(defaults[keys.debugConsoleEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.verboseAutoplayTrace] as? Bool, false)
        XCTAssertEqual(defaults[keys.chromeAutohideThreshold] as? Double, 3.0)
        XCTAssertEqual(defaults[keys.chromeReducedMotion] as? Bool, true)
        XCTAssertEqual(defaults[keys.queuePanelOpenAtLaunch] as? Bool, false)
        XCTAssertEqual(defaults[keys.bottomRailShowXButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowShuffleButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowReplayButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowVolumeButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowBookmarkButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.playerWindowOpacity] as? Double, 1.0)
        XCTAssertEqual(defaults[keys.clipDurationSeconds] as? Int, 10)
        XCTAssertEqual(defaults[keys.previewDurationMode] as? String, "fixed")
        XCTAssertEqual(defaults[keys.randomPreviewMinimumSeconds] as? Int, 5)
        XCTAssertEqual(defaults[keys.randomPreviewMaximumSeconds] as? Int, 30)
        XCTAssertEqual(defaults[keys.startPositionMode] as? String, "random")
        XCTAssertEqual(defaults[keys.skipIntroSeconds] as? Int, 5)
        XCTAssertEqual(defaults[keys.queueOrderMode] as? String, "sequential")
        XCTAssertEqual(defaults[keys.loopQueueEnabled] as? Bool, false)
    }

    func testDefaultValuesPreserveOptionalTransportAndQueueDefaults() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)

        XCTAssertEqual(defaults["showStopButton"] as? Bool, false)
        XCTAssertEqual(defaults["showVolumeButton"] as? Bool, false)
        XCTAssertEqual(defaults["showShuffleButton"] as? Bool, false)
        XCTAssertEqual(defaults["showRepeatButton"] as? Bool, false)
        XCTAssertEqual(defaults["com.dwb.queueColumnDurationVisible"] as? Bool, true)
        XCTAssertEqual(defaults["com.dwb.queueColumnSizeVisible"] as? Bool, true)
        XCTAssertEqual(defaults["com.dwb.queueColumnDurationWidth"] as? Double, 92.0)
        XCTAssertEqual(defaults["com.dwb.queueColumnSizeWidth"] as? Double, 104.0)
    }

    func testDefaultValuesKeepMigratedKeysUnset() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertNil(defaults[keys.customPrefixQueuePageEnabled])
        XCTAssertNil(defaults[keys.customPrefixVideoPageEnabled])
        XCTAssertNil(defaults[keys.persistedVolume])
    }

    func testReduceMotionDefaultComesFromCaller() {
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertEqual(
            SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: true)[keys.chromeReducedMotion] as? Bool,
            true
        )
        XCTAssertEqual(
            SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)[keys.chromeReducedMotion] as? Bool,
            false
        )
    }

    func testRegisterDefaultsUsesRegistrationDomainWithoutOverwritingStoredValues() {
        let suiteName = "com.dwb.skimTests.SettingsDefaultsRegistryTests"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)

        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 10)
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.acceptVideoMedia), true)
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.chromeReducedMotion), false)

        defaults.set(30, forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: true)

        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 30)
    }

    // MARK: - Skim preview settings (P10)

    func testValidatedClipDurationSecondsRejectsNegative() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedClipDurationSeconds(-5), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedClipDurationSeconds(0), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedClipDurationSeconds(10), 10)
    }

    func testValidatedPreviewDurationModeFallsBackToFixed() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedPreviewDurationMode("fixed"), "fixed")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedPreviewDurationMode("random"), "random")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedPreviewDurationMode("garbage"), "fixed")
    }

    func testValidatedRandomPreviewDurationRangeNormalizesSafely() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewMinimumSeconds(-1), 1)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewMinimumSeconds(0), 1)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewMinimumSeconds(5), 5)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewMaximumSeconds(minimum: 10, maximum: 3), 10)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: -5, maximum: -1), 1...1)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: 8, maximum: 12), 8...12)
    }

    func testValidatedSkipIntroSecondsRejectsNegative() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedSkipIntroSeconds(-1), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedSkipIntroSeconds(0), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedSkipIntroSeconds(5), 5)
    }

    func testValidatedStartPositionModeRoundTripsBeginningAndRandom() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedStartPositionMode("beginning"), "beginning")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedStartPositionMode("random"), "random")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedStartPositionMode("garbage"), "random")
    }

    func testSkimPreviewSettingsRoundTripThroughUserDefaults() {
        let suiteName = "com.dwb.skimTests.SettingsDefaultsRegistryTests.skimPreview"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds), 10)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.previewDurationMode), "fixed")
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds), 5)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds), 30)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.startPositionMode), "random")
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds), 5)

        defaults.set(SettingsDefaultsRegistry.validatedStartPositionMode("beginning"), forKey: SettingsDefaultsRegistry.Keys.startPositionMode)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.startPositionMode), "beginning")

        defaults.set(SettingsDefaultsRegistry.validatedStartPositionMode("random"), forKey: SettingsDefaultsRegistry.Keys.startPositionMode)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.startPositionMode), "random")

        defaults.set(SettingsDefaultsRegistry.validatedClipDurationSeconds(-8), forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.clipDurationSeconds), 0)

        defaults.set(SettingsDefaultsRegistry.validatedPreviewDurationMode("random"), forKey: SettingsDefaultsRegistry.Keys.previewDurationMode)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.previewDurationMode), "random")

        let normalizedRange = SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: 0, maximum: -10)
        defaults.set(normalizedRange.lowerBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds)
        defaults.set(normalizedRange.upperBound, forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMinimumSeconds), 1)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.randomPreviewMaximumSeconds), 1)

        defaults.set(SettingsDefaultsRegistry.validatedSkipIntroSeconds(-3), forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipIntroSeconds), 0)
    }

    // MARK: - Queue behavior settings (P11)

    func testValidatedQueueOrderModeAcceptsKnownModesAndFallsBackToSequential() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("sequential"), "sequential")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("shuffle"), "shuffle")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("weighted"), "weighted")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("garbage"), "sequential")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode(""), "sequential")
    }

    func testQueueBehaviorSettingsRoundTripThroughUserDefaults() {
        let suiteName = "com.dwb.skimTests.SettingsDefaultsRegistryTests.queueBehavior"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.queueOrderMode), "sequential")
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled), false)

        defaults.set(SettingsDefaultsRegistry.validatedQueueOrderMode("shuffle"), forKey: SettingsDefaultsRegistry.Keys.queueOrderMode)
        defaults.set(true, forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.queueOrderMode), "shuffle")
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled), true)

        defaults.set(SettingsDefaultsRegistry.validatedQueueOrderMode("weighted"), forKey: SettingsDefaultsRegistry.Keys.queueOrderMode)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.queueOrderMode), "weighted")

        defaults.set(SettingsDefaultsRegistry.validatedQueueOrderMode("invalid"), forKey: SettingsDefaultsRegistry.Keys.queueOrderMode)
        XCTAssertEqual(defaults.string(forKey: SettingsDefaultsRegistry.Keys.queueOrderMode), "sequential")
    }
}
