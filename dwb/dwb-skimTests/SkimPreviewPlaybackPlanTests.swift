import XCTest

final class SkimPreviewPlaybackPlanTests: XCTestCase {

    func testBeginningModeWithSkipIntroOnLongFileStartsAtSkipIntro() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                 skipIntroSeconds: 5,
                                                 clipDurationSeconds: nil,
                                                 mediaDurationSeconds: 120)
        XCTAssertEqual(plan.startOffsetSeconds, 5, accuracy: 0.001)
        XCTAssertNil(plan.effectiveClipDurationSeconds)
        XCTAssertFalse(plan.shouldAutoAdvance)
    }

    func testBeginningModeOnShortFileClampsSafely() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                 skipIntroSeconds: 5,
                                                 clipDurationSeconds: nil,
                                                 mediaDurationSeconds: 1)
        XCTAssertGreaterThanOrEqual(plan.startOffsetSeconds, 0)
        XCTAssertLessThan(plan.startOffsetSeconds, 1)
    }

    func testRandomModeRespectsSkipIntroLowerBound() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                 skipIntroSeconds: 10,
                                                 clipDurationSeconds: nil,
                                                 mediaDurationSeconds: 100,
                                                 randomValue: 0)
        XCTAssertEqual(plan.startOffsetSeconds, 10, accuracy: 0.001)
    }

    func testRandomModeRespectsClipDurationAndMediaDurationUpperBound() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                 skipIntroSeconds: 0,
                                                 clipDurationSeconds: 20,
                                                 mediaDurationSeconds: 100,
                                                 randomValue: 1)
        // Latest safe start must still leave room for the full 20s clip.
        XCTAssertEqual(plan.startOffsetSeconds, 80, accuracy: 0.001)
        XCTAssertEqual(plan.effectiveClipDurationSeconds, 20)
        XCTAssertTrue(plan.shouldAutoAdvance)
    }

    func testRandomModeMidRandomValueInterpolatesWithinBounds() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                 skipIntroSeconds: 10,
                                                 clipDurationSeconds: 20,
                                                 mediaDurationSeconds: 100,
                                                 randomValue: 0.5)
        // lower bound 10, upper bound 100-20=80 -> midpoint 45.
        XCTAssertEqual(plan.startOffsetSeconds, 45, accuracy: 0.001)
    }

    func testUnknownDurationDoesNotCrashAndProducesSafeStart() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                  skipIntroSeconds: 10,
                                                  clipDurationSeconds: 20,
                                                  mediaDurationSeconds: nil)
        XCTAssertEqual(plan.startOffsetSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(plan.effectiveClipDurationSeconds, 20)
    }

    func testZeroDurationDoesNotCrashAndProducesSafeStart() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  skipIntroSeconds: 10,
                                                  clipDurationSeconds: nil,
                                                  mediaDurationSeconds: 0)
        XCTAssertEqual(plan.startOffsetSeconds, 0, accuracy: 0.001)
    }

    func testConfiguredClipDurationProducesAutoAdvanceDuration() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  skipIntroSeconds: 0,
                                                  clipDurationSeconds: 15,
                                                  mediaDurationSeconds: 120)
        XCTAssertEqual(plan.effectiveClipDurationSeconds, 15)
        XCTAssertTrue(plan.shouldAutoAdvance)
    }

    func testFixedDurationResolverPreservesFullFileForZero() {
        let duration = SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(mode: .fixed,
                                                                           fixedDurationSeconds: 0,
                                                                           randomMinimumSeconds: 5,
                                                                           randomMaximumSeconds: 30,
                                                                           randomValue: 0.5)
        XCTAssertNil(duration)
    }

    func testRandomDurationResolverUsesInjectedRandomness() {
        let duration = SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(mode: .random,
                                                                           fixedDurationSeconds: 10,
                                                                           randomMinimumSeconds: 5,
                                                                           randomMaximumSeconds: 30,
                                                                           randomValue: 0.4)
        XCTAssertEqual(duration ?? 0, 15, accuracy: 0.001)
    }

    func testRandomDurationResolverNormalizesBounds() {
        let duration = SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(mode: .random,
                                                                           fixedDurationSeconds: nil,
                                                                           randomMinimumSeconds: -10,
                                                                           randomMaximumSeconds: -5,
                                                                           randomValue: 0.9)
        XCTAssertEqual(duration ?? 0, 1, accuracy: 0.001)
    }

    func testRandomDurationEqualBoundsActsFixed() {
        let duration = SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(mode: .random,
                                                                           fixedDurationSeconds: 10,
                                                                           randomMinimumSeconds: 12,
                                                                           randomMaximumSeconds: 12,
                                                                           randomValue: 0.1)
        XCTAssertEqual(duration ?? 0, 12, accuracy: 0.001)
    }

    func testRandomDurationPlanUsesChosenDurationForStartWindow() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                durationMode: .random,
                                                skipIntroSeconds: 0,
                                                fixedClipDurationSeconds: 10,
                                                randomMinimumSeconds: 5,
                                                randomMaximumSeconds: 25,
                                                mediaDurationSeconds: 100,
                                                startRandomValue: 1,
                                                durationRandomValue: 0.5)
        XCTAssertEqual(plan.effectiveClipDurationSeconds ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(plan.startOffsetSeconds, 85, accuracy: 0.001)
    }

    func testRandomDurationIsResolvedOncePerPlan() {
        let first = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                 durationMode: .random,
                                                 skipIntroSeconds: 0,
                                                 fixedClipDurationSeconds: 10,
                                                 randomMinimumSeconds: 5,
                                                 randomMaximumSeconds: 30,
                                                 mediaDurationSeconds: 100,
                                                 startRandomValue: 0,
                                                 durationRandomValue: 0)
        let second = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  durationMode: .random,
                                                  skipIntroSeconds: 0,
                                                  fixedClipDurationSeconds: 10,
                                                  randomMinimumSeconds: 5,
                                                  randomMaximumSeconds: 30,
                                                  mediaDurationSeconds: 100,
                                                  startRandomValue: 0,
                                                  durationRandomValue: 1)
        XCTAssertEqual(first.effectiveClipDurationSeconds ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(second.effectiveClipDurationSeconds ?? 0, 30, accuracy: 0.001)
    }

    func testZeroClipDurationPreservesFullFileBehavior() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  skipIntroSeconds: 0,
                                                  clipDurationSeconds: 0,
                                                  mediaDurationSeconds: 120)
        XCTAssertNil(plan.effectiveClipDurationSeconds)
        XCTAssertFalse(plan.shouldAutoAdvance)
    }

    func testNegativeClipDurationPreservesFullFileBehavior() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  skipIntroSeconds: 0,
                                                  clipDurationSeconds: -5,
                                                  mediaDurationSeconds: 120)
        XCTAssertNil(plan.effectiveClipDurationSeconds)
    }

    /// P10: mirrors the app's default skim preview settings (clip duration 10s,
    /// start position random, skip intro 5s) against a representative media length.
    func testDefaultSettingsProduceValidAutoAdvanceClipWindow() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .random,
                                                  skipIntroSeconds: 5,
                                                  clipDurationSeconds: 10,
                                                  mediaDurationSeconds: 60,
                                                  randomValue: 0.5)
        XCTAssertEqual(plan.effectiveClipDurationSeconds, 10)
        XCTAssertTrue(plan.shouldAutoAdvance)
        // Start must leave the full 10s clip playable before end-of-file, and never
        // start before the 5s skip-intro floor.
        XCTAssertGreaterThanOrEqual(plan.startOffsetSeconds, 5)
        XCTAssertLessThanOrEqual(plan.startOffsetSeconds + 10, 60)
    }

    func testNegativeSkipIntroTreatedAsZero() {
        let plan = SkimPreviewPlaybackPlan.plan(mode: .beginning,
                                                  skipIntroSeconds: -5,
                                                  clipDurationSeconds: nil,
                                                  mediaDurationSeconds: 120)
        XCTAssertEqual(plan.startOffsetSeconds, 0, accuracy: 0.001)
    }
}
