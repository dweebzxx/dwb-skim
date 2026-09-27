import Foundation
import XCTest

final class SkimSettingsStoreTests: XCTestCase {
    func testSkimDefaultsOnAndPropagatesAcrossStoresWithoutChangingValues() {
        let suite = "com.dwb.skimTests.SkimSettingsStore.enabled"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        let first = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        let second = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        let preserved = first.snapshot()
        XCTAssertTrue(preserved.skimEnabled)

        first.setSkimEnabled(false)
        let disabled = second.snapshot()
        XCTAssertFalse(disabled.skimEnabled)
        XCTAssertEqual(disabled.fixedDurationSeconds, preserved.fixedDurationSeconds)
        XCTAssertEqual(disabled.startPositionMode, preserved.startPositionMode)

        second.setSkimEnabled(true)
        let enabledAgain = first.snapshot()
        XCTAssertTrue(enabledAgain.skimEnabled)
        XCTAssertEqual(enabledAgain.fixedDurationSeconds, preserved.fixedDurationSeconds)
        XCTAssertEqual(enabledAgain.startPositionMode, preserved.startPositionMode)
    }

    func testTwoStoresShareNormalizedPersistentStateAndNotifications() {
        let suite = "com.dwb.skimTests.SkimSettingsStore.sync"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        let first = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        let second = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        var previewChanges = 0
        let token = center.addObserver(forName: .skimPreviewSettingsChanged, object: nil, queue: nil) { _ in
            previewChanges += 1
        }
        defer { center.removeObserver(token) }

        first.setPreviewDurationMode("random")
        first.setFixedDurationSeconds(12)
        first.setStartPositionMode("beginning")
        first.setSkipIntroSeconds(7)

        let snapshot = second.snapshot()
        XCTAssertEqual(snapshot.previewDurationMode, "random")
        XCTAssertEqual(snapshot.fixedDurationSeconds, 12)
        XCTAssertEqual(snapshot.startPositionMode, "beginning")
        XCTAssertEqual(snapshot.skipIntroSeconds, 7)
        XCTAssertEqual(previewChanges, 4)

        first.setSkipIntroSeconds(7)
        XCTAssertEqual(previewChanges, 4, "Writing the same value must not create an update loop")
    }

    func testProgressiveRandomSkimIntensityDefaultsToStandardAndPersistsAcrossRelaunch() {
        let (defaults, store, suite) = makeStore("intensity")
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(store.snapshot().progressiveRandomSkimIntensity, .standard)

        for intensity in ProgressiveRandomSkimIntensity.allCases {
            store.setProgressiveRandomSkimIntensity(intensity)
            XCTAssertEqual(store.snapshot().progressiveRandomSkimIntensity, intensity)

            // Simulate relaunch: a fresh store instance backed by the same persisted defaults.
            let relaunched = SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
            XCTAssertEqual(relaunched.snapshot().progressiveRandomSkimIntensity, intensity)
        }

        // Invalid persisted raw value falls back to standard default
        defaults.set("not_a_valid_intensity", forKey: SettingsDefaultsRegistry.Keys.progressiveRandomSkimIntensity)
        let fallbackStore = SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
        XCTAssertEqual(fallbackStore.snapshot().progressiveRandomSkimIntensity, .standard)
    }

    func testProgressiveRandomSkimIntensityChangeNotifiesOncePerChange() {
        let suite = "com.dwb.skimTests.SkimSettingsStore.intensityNotify"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        let store = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        var previewChanges = 0
        let token = center.addObserver(forName: .skimPreviewSettingsChanged, object: nil, queue: nil) { _ in
            previewChanges += 1
        }
        defer { center.removeObserver(token) }

        store.setProgressiveRandomSkimIntensity(.light)
        XCTAssertEqual(previewChanges, 1)
        store.setProgressiveRandomSkimIntensity(.light)
        XCTAssertEqual(previewChanges, 1, "Writing the same value must not create an update loop")
    }

    func testRandomBoundsStayOrdered() {
        let (defaults, store, suite) = makeStore("bounds")
        defer { defaults.removePersistentDomain(forName: suite) }
        store.setRandomDurationRange(minimum: 20, maximum: 4)
        XCTAssertEqual(store.snapshot().randomDurationRange, 20...20)
        store.setRandomDurationRange(minimum: -1, maximum: 9)
        XCTAssertEqual(store.snapshot().randomDurationRange, 1...9)
    }

    func testQueueSettingsSynchronizeAcrossStores() {
        let suite = "com.dwb.skimTests.SkimSettingsStore.queue"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        let first = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        let second = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        first.setQueueOrderMode(.weighted)
        first.setLoopQueueEnabled(true)
        XCTAssertEqual(second.snapshot().queueOrderMode, .weighted)
        XCTAssertTrue(second.snapshot().loopQueueEnabled)
    }

    func testPlaybackSettingsSynchronizeAndNotifyOncePerChange() {
        let suite = "com.dwb.skimTests.SkimSettingsStore.playback"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        let first = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        let second = SkimSettingsStore(defaults: defaults, notificationCenter: center)
        var playbackChanges = 0
        let token = center.addObserver(forName: .playbackSettingsChanged, object: nil, queue: nil) { _ in
            playbackChanges += 1
        }
        defer { center.removeObserver(token) }

        XCTAssertEqual(first.snapshot().imageDurationSeconds, 3.0)
        XCTAssertEqual(first.snapshot().gifLoopCount, 1)
        XCTAssertFalse(first.snapshot().videoAudioNormalizationEnabled)

        first.setImageDurationSeconds(4.5)
        first.setGIFLoopCount(3)
        first.setVideoAudioNormalizationEnabled(true)
        let snapshot = second.snapshot()
        XCTAssertEqual(snapshot.imageDurationSeconds, 4.5)
        XCTAssertEqual(snapshot.gifLoopCount, 3)
        XCTAssertTrue(snapshot.videoAudioNormalizationEnabled)
        XCTAssertEqual(playbackChanges, 3)

        first.setVideoAudioNormalizationEnabled(true)
        XCTAssertEqual(playbackChanges, 3, "Writing the same value must not create an update loop")
    }

    func testSnapshotPersistsNormalizedMediaDurationValues() {
        let (defaults, store, suite) = makeStore("media-normalization")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Double.nan, forKey: SettingsDefaultsRegistry.Keys.imageDurationSeconds)
        defaults.set(-8, forKey: SettingsDefaultsRegistry.Keys.gifLoopCount)

        let snapshot = store.snapshot()
        XCTAssertEqual(snapshot.imageDurationSeconds, 3.0)
        XCTAssertEqual(snapshot.gifLoopCount, 1)
        XCTAssertEqual(defaults.double(forKey: SettingsDefaultsRegistry.Keys.imageDurationSeconds), 3.0)
        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.gifLoopCount), 1)
    }

    private func makeStore(_ suffix: String) -> (UserDefaults, SkimSettingsStore, String) {
        let suite = "com.dwb.skimTests.SkimSettingsStore.\(suffix)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        return (defaults, SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter()), suite)
    }
}
