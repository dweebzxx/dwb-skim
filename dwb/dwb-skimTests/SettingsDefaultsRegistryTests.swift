import Foundation
import XCTest

final class SettingsDefaultsRegistryTests: XCTestCase {
    func testActiveDefaultsIncludePreviewQueueAndSkimPlus() {
        let values = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: true)
        let keys = SettingsDefaultsRegistry.Keys.self
        XCTAssertEqual(values[keys.clipDurationSeconds] as? Int, 10)
        XCTAssertEqual(values[keys.skimEnabled] as? Bool, true)
        XCTAssertEqual(values[keys.previewDurationMode] as? String, "fixed")
        XCTAssertEqual(values[keys.randomPreviewMinimumSeconds] as? Int, 5)
        XCTAssertEqual(values[keys.randomPreviewMaximumSeconds] as? Int, 15)
        XCTAssertEqual(values[keys.startPositionMode] as? String, "random")
        XCTAssertEqual(values[keys.skipIntroSeconds] as? Int, 5)
        XCTAssertEqual(values[keys.imageDurationSeconds] as? Double, 3.0)
        XCTAssertEqual(values[keys.gifLoopCount] as? Int, 1)
        XCTAssertEqual(values[keys.videoAudioNormalizationEnabled] as? Bool, false)
        XCTAssertEqual(values[keys.queueOrderMode] as? String, "sequential")
        XCTAssertEqual(values[keys.progressiveRandomSkimIntensity] as? String, "standard")
        XCTAssertEqual(values[keys.loopQueueEnabled] as? Bool, false)
        XCTAssertEqual(values[keys.backgroundAudioMixMode] as? String, "uploadedOnly")
        XCTAssertEqual(values[keys.backgroundAudioVolume] as? Double, 0.75)
        XCTAssertEqual(values[keys.chromeReducedMotion] as? Bool, true)
    }

    func testRemovedDonorDefaultsAreAbsent() {
        let values = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)
        for key in SettingsDefaultsRegistry.obsoleteKeys {
            XCTAssertNil(values[key], "Obsolete key must not have a registered default: \(key)")
        }
    }

    func testRegistrationClearsPersistedObsoleteKeys() {
        let suite = "com.dwb.skimTests.SettingsDefaultsRegistry.removal"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in SettingsDefaultsRegistry.obsoleteKeys { defaults.set(true, forKey: key) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)

        for key in SettingsDefaultsRegistry.obsoleteKeys {
            XCTAssertNil(defaults.object(forKey: key), "Obsolete persisted key was not removed: \(key)")
        }
    }

    func testPreviewValidationNormalizesBoundsAndModes() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedClipDurationSeconds(-5), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedPreviewDurationMode("random"), "random")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedPreviewDurationMode("invalid"), "fixed")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: 8, maximum: 3), 8...8)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedRandomPreviewDurationRange(minimum: -4, maximum: 12), 1...12)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedSkipIntroSeconds(-1), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedStartPositionMode("beginning"), "beginning")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedStartPositionMode("invalid"), "random")
    }

    func testProgressiveRandomSkimIntensityValidationDefaultsToStandard() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("light"), "light")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("standard"), "standard")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("thorough"), "thorough")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("ultra"), "ultra")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("max"), "max")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity("invalid"), "standard")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedProgressiveRandomSkimIntensity(""), "standard")
    }

    func testQueueModesRemainSequentialShuffleAndWeighted() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("sequential"), "sequential")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("shuffle"), "shuffle")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("weighted"), "weighted")
        XCTAssertEqual(SettingsDefaultsRegistry.validatedQueueOrderMode("invalid"), "sequential")
    }

    func testMediaDurationValidationRejectsMalformedAndOutOfRangeValues() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedImageDurationSeconds(.nan), 3.0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedImageDurationSeconds(.infinity), 3.0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedImageDurationSeconds(0), 0.25)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedImageDurationSeconds(2.75), 2.75)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedImageDurationSeconds(9_000), 3_600)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedGIFLoopCount(0), 1)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedGIFLoopCount(12), 12)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedGIFLoopCount(2_000), 1_000)
    }

    func testBackgroundVolumeClampsAndRejectsNonFiniteValues() {
        XCTAssertEqual(SettingsDefaultsRegistry.validatedBackgroundAudioVolume(-1), 0)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedBackgroundAudioVolume(0.4), 0.4)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedBackgroundAudioVolume(2), 1)
        XCTAssertEqual(SettingsDefaultsRegistry.validatedBackgroundAudioVolume(.infinity), 0.75)
    }
}
