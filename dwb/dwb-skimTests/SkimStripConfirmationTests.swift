import XCTest

final class SkimStripConfirmationTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func makeStore(_ name: String) -> SkimSettingsStore {
        let suite = "com.dwb.skimTests.SkimStripConfirmation.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        return SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())
    }

    /// What the strip does on a commit: snapshot, write, snapshot, then ask for a confirmation.
    private func confirmation(_ setting: SkimStripSetting,
                              in store: SkimSettingsStore,
                              edit: () -> Void) -> SkimStripConfirmation? {
        let before = store.snapshot()
        edit()
        return SkimStripConfirmation.make(for: setting, before: before, after: store.snapshot(), locale: locale)
    }

    func testClipDurationFixedShowsTheStoredSeconds() {
        let store = makeStore("fixed")
        let result = confirmation(.clipDuration, in: store) { store.setFixedDurationSeconds(12) }
        XCTAssertEqual(result?.name, "Clip duration")
        XCTAssertEqual(result?.value, "Fixed 12 s")
        XCTAssertEqual(result?.text, "Clip duration · Fixed 12 s")
    }

    func testSwitchingToRandomShowsBothStoredBounds() {
        let store = makeStore("randomMode")
        store.setRandomDurationRange(minimum: 7, maximum: 15)
        let result = confirmation(.clipDuration, in: store) {
            store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        }
        XCTAssertEqual(result?.text, "Clip duration · Random 7–15 s")
    }

    func testEditingOnlyTheRandomMinimumShowsTheMinimumAndMaximumTogether() {
        let store = makeStore("randomMinimum")
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setRandomDurationRange(minimum: 5, maximum: 15)
        let result = confirmation(.clipDuration, in: store) { store.setRandomMinimumSeconds(7) }
        XCTAssertEqual(result?.value, "Random 7–15 s")
    }

    func testEditingOnlyTheRandomMaximumShowsTheMinimumAndMaximumTogether() {
        let store = makeStore("randomMaximum")
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setRandomDurationRange(minimum: 5, maximum: 15)
        let result = confirmation(.clipDuration, in: store) { store.setRandomMaximumSeconds(30) }
        XCTAssertEqual(result?.value, "Random 5–30 s")
    }

    func testRandomMinimumAboveTheMaximumShowsTheNormalizedRangeThatPersisted() {
        let store = makeStore("randomNormalized")
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setRandomDurationRange(minimum: 5, maximum: 15)
        let result = confirmation(.clipDuration, in: store) { store.setRandomMinimumSeconds(20) }
        XCTAssertEqual(result?.value, "Random 20–20 s")
        XCTAssertEqual(store.snapshot().randomDurationRange, 20...20)
    }

    func testRandomMinimumBelowOneShowsTheClampedMinimum() {
        let store = makeStore("randomClamped")
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setRandomDurationRange(minimum: 5, maximum: 15)
        let result = confirmation(.clipDuration, in: store) { store.setRandomMinimumSeconds(0) }
        XCTAssertEqual(result?.value, "Random 1–15 s")
    }

    func testStartPositionShowsTheStoredMode() {
        let store = makeStore("start")
        store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeRandom)
        let beginning = confirmation(.startPosition, in: store) {
            store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeBeginning)
        }
        XCTAssertEqual(beginning?.text, "Start position · Beginning")
        let random = confirmation(.startPosition, in: store) {
            store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeRandom)
        }
        XCTAssertEqual(random?.text, "Start position · Random")
    }

    func testSkipIntroShowsTheStoredSeconds() {
        let store = makeStore("skip")
        let result = confirmation(.skipIntro, in: store) { store.setSkipIntroSeconds(8) }
        XCTAssertEqual(result?.text, "Skip intro · 8 s")
    }

    func testSkipIntroNegativeEntryShowsThePersistedZeroNotTheTypedValue() {
        let store = makeStore("skipNegative")
        let result = confirmation(.skipIntro, in: store) { store.setSkipIntroSeconds(-40) }
        XCTAssertEqual(result?.value, "0 s")
    }

    func testEntryThatNormalizesToTheCurrentValueShowsNoConfirmation() {
        let store = makeStore("skipNoChange")
        store.setSkipIntroSeconds(0)
        XCTAssertNil(confirmation(.skipIntro, in: store) { store.setSkipIntroSeconds(-9) })
    }

    func testImageDurationBelowTheMinimumShowsTheClampedValue() {
        let store = makeStore("imageMinimum")
        let result = confirmation(.imageDuration, in: store) { store.setImageDurationSeconds(0.01) }
        XCTAssertEqual(result?.text, "Image duration · 0.25 s")
    }

    func testImageDurationReadsWholeAndFractionalSeconds() {
        let store = makeStore("imageFormat")
        store.setImageDurationSeconds(1)
        XCTAssertEqual(confirmation(.imageDuration, in: store) { store.setImageDurationSeconds(2.5) }?.value, "2.5 s")
        XCTAssertEqual(confirmation(.imageDuration, in: store) { store.setImageDurationSeconds(4) }?.value, "4 s")
    }

    func testImageDurationAboveTheMaximumShowsTheClampedValue() {
        let store = makeStore("imageMaximum")
        let result = confirmation(.imageDuration, in: store) { store.setImageDurationSeconds(99_999) }
        XCTAssertEqual(result?.value, "3600 s")
    }

    func testGIFLoopsShowsTheClampedCountWithASingularForOne() {
        let store = makeStore("gif")
        store.setGIFLoopCount(3)
        XCTAssertEqual(confirmation(.gifLoops, in: store) { store.setGIFLoopCount(5_000) }?.text, "GIF loops · 1000 loops")
        XCTAssertEqual(confirmation(.gifLoops, in: store) { store.setGIFLoopCount(0) }?.text, "GIF loops · 1 loop")
    }

    func testQueueOrderShowsTheStoredMode() {
        let store = makeStore("queue")
        XCTAssertEqual(confirmation(.queueOrder, in: store) { store.setQueueOrderMode(.shuffle) }?.text,
                       "Queue order · Shuffle")
        XCTAssertEqual(confirmation(.queueOrder, in: store) { store.setQueueOrderMode(.weighted) }?.text,
                       "Queue order · Weighted")
    }

    func testLoopQueueAndProgressiveSkimShowOnAndOff() {
        let store = makeStore("switches")
        XCTAssertEqual(confirmation(.loopQueue, in: store) { store.setLoopQueueEnabled(true) }?.text, "Loop queue · On")
        XCTAssertEqual(confirmation(.loopQueue, in: store) { store.setLoopQueueEnabled(false) }?.text, "Loop queue · Off")
        XCTAssertEqual(confirmation(.progressiveSkim, in: store) { store.setProgressiveRandomSkimEnabled(true) }?.text,
                       "Progressive skim · On")
        XCTAssertEqual(confirmation(.progressiveSkim, in: store) { store.setProgressiveRandomSkimEnabled(false) }?.text,
                       "Progressive skim · Off")
    }

    func testRewritingTheSameValueShowsNoConfirmationForAnySetting() {
        let store = makeStore("unchanged")
        let snapshot = store.snapshot()
        for setting in SkimStripSetting.allCases {
            XCTAssertNil(SkimStripConfirmation.make(for: setting, before: snapshot, after: snapshot, locale: locale),
                         setting.name)
        }
    }

    func testAChangeToAnotherSettingIsNotConfirmedForThisOne() {
        let store = makeStore("other")
        let before = store.snapshot()
        store.setLoopQueueEnabled(true)
        let after = store.snapshot()
        XCTAssertNotNil(SkimStripConfirmation.make(for: .loopQueue, before: before, after: after, locale: locale))
        for setting in SkimStripSetting.allCases where setting != .loopQueue {
            XCTAssertNil(SkimStripConfirmation.make(for: setting, before: before, after: after, locale: locale),
                         setting.name)
        }
    }

    func testEverySettingHasADistinctPlainName() {
        let names = SkimStripSetting.allCases.map(\.name)
        XCTAssertEqual(names.count, 8)
        XCTAssertEqual(Set(names).count, 8)
        XCTAssertEqual(Set(names), ["Clip duration", "Start position", "Skip intro", "Image duration",
                                    "GIF loops", "Queue order", "Loop queue", "Progressive skim"])
    }

    func testSavedDescriptionUsesTheSameValueAsTheConfirmation() {
        let store = makeStore("saved")
        store.setQueueOrderMode(.shuffle)
        let snapshot = store.snapshot()
        XCTAssertEqual(SkimStripSetting.queueOrder.savedDescription(in: snapshot, locale: locale), "Saved: Shuffle")
        XCTAssertEqual(SkimStripSetting.clipDuration.savedDescription(in: snapshot, locale: locale), "Saved: Fixed 10 s")
    }

    // MARK: - Rule in force

    func testRuleNamesProgressiveSkimClipsSkipQueueOrderAndLooping() {
        let store = makeStore("ruleProgressive")
        store.setProgressiveRandomSkimEnabled(true)
        store.setPreviewDurationMode(SettingsDefaultsRegistry.Defaults.previewDurationModeRandom)
        store.setRandomDurationRange(minimum: 7, maximum: 15)
        store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeBeginning)
        store.setSkipIntroSeconds(4)
        store.setQueueOrderMode(.shuffle)
        store.setLoopQueueEnabled(true)
        // Progressive segments are spread across the video, so Start Position is not part of the rule.
        XCTAssertEqual(SkimStripRuleSummary.make(store.snapshot()),
                       "Progressive skim · random 7–15 s clips · skip 4 s · shuffle · loop queue")
    }

    func testRuleForPlainSkimIncludesTheStartPosition() {
        let store = makeStore("rulePlain")
        store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeBeginning)
        store.setSkipIntroSeconds(4)
        XCTAssertEqual(SkimStripRuleSummary.make(store.snapshot()), "Skim · 10 s clips · from start · skip 4 s · in order")
        store.setStartPositionMode(SettingsDefaultsRegistry.Defaults.startPositionModeRandom)
        store.setSkipIntroSeconds(0)
        XCTAssertEqual(SkimStripRuleSummary.make(store.snapshot()), "Skim · 10 s clips · random start · in order")
    }

    func testRuleOmitsLoopingWhenOffAndNamesWeightedOrder() {
        let store = makeStore("ruleQueue")
        store.setQueueOrderMode(.weighted)
        XCTAssertTrue(SkimStripRuleSummary.make(store.snapshot()).hasSuffix("· weighted"))
        store.setLoopQueueEnabled(true)
        XCTAssertTrue(SkimStripRuleSummary.make(store.snapshot()).hasSuffix("· weighted · loop queue"))
    }

    func testRuleWithSkimOffSaysItPlaysInFullAndDropsTheSkimOnlyPart() {
        let store = makeStore("ruleSkimOff")
        store.setSkimEnabled(false)
        store.setProgressiveRandomSkimEnabled(true)
        store.setQueueOrderMode(.shuffle)
        XCTAssertEqual(SkimStripRuleSummary.make(store.snapshot()), "Skim off · plays in full · shuffle")
    }

    func testConfirmationCarriesTheRuleAfterTheEditAndASpokenForm() {
        let store = makeStore("ruleConfirmation")
        let result = confirmation(.queueOrder, in: store) { store.setQueueOrderMode(.shuffle) }
        XCTAssertEqual(result?.rule, SkimStripRuleSummary.make(store.snapshot()))
        XCTAssertEqual(result?.text, "Queue order · Shuffle")
        XCTAssertEqual(result?.spoken, "Queue order, Shuffle. Skim, 10 s clips, random start, skip 5 s, shuffle")
    }

    // MARK: - Inactive groups

    func testSkimOffGreysOnlyClipDurationAndStartPosition() {
        let activity = SkimStripActivity(skimEnabled: false, acceptsImages: true, acceptsGIFs: true)
        XCTAssertFalse(activity.isActive(.clipDuration))
        XCTAssertFalse(activity.isActive(.startPosition))
        XCTAssertEqual(activity.inactiveReason(.clipDuration), "Unavailable while Skim is off.")
        for setting in [SkimStripSetting.skipIntro, .imageDuration, .gifLoops, .queueOrder, .loopQueue, .progressiveSkim] {
            XCTAssertTrue(activity.isActive(setting), setting.name)
        }
    }

    func testImagesNotAcceptedGreysOnlyImageDuration() {
        let activity = SkimStripActivity(skimEnabled: true, acceptsImages: false, acceptsGIFs: true)
        XCTAssertFalse(activity.isActive(.imageDuration))
        XCTAssertEqual(activity.inactiveReason(.imageDuration), "Unavailable while Images are off in Settings > Playback.")
        XCTAssertTrue(activity.isActive(.gifLoops))
        XCTAssertTrue(activity.isActive(.clipDuration))
    }

    func testGIFNotAcceptedGreysOnlyGIFLoops() {
        let activity = SkimStripActivity(skimEnabled: true, acceptsImages: true, acceptsGIFs: false)
        XCTAssertFalse(activity.isActive(.gifLoops))
        XCTAssertEqual(activity.inactiveReason(.gifLoops), "Unavailable while GIF is off in Settings > Playback.")
        XCTAssertTrue(activity.isActive(.imageDuration))
    }

    func testEveryGroupIsActiveWhenSkimAndAllMediaTypesAreOn() {
        let activity = SkimStripActivity(skimEnabled: true, acceptsImages: true, acceptsGIFs: true)
        for setting in SkimStripSetting.allCases {
            XCTAssertTrue(activity.isActive(setting), setting.name)
            XCTAssertNil(activity.inactiveReason(setting), setting.name)
        }
    }
}
