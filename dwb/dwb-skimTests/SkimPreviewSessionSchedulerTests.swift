import XCTest

final class SkimPreviewSessionSchedulerTests: XCTestCase {
    private let item = "/queue/a.mp4"

    func testOnePlayingReadinessCreatesOneDeadline() {
        var scheduler = makeScheduler(duration: 5)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .playing, now: 10),
                       .scheduled(deadlineUptime: 15))
    }

    func testRepeatedPlayingReadinessConfirmsExistingDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 10)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .playing, now: 11),
                       .confirmed(deadlineUptime: 15))
    }

    func testMissingPlayingUsesBoundedFallback() {
        var scheduler = makeScheduler(duration: 5)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .fallback, now: 0.75),
                       .scheduled(deadlineUptime: 5.75))
    }

    func testReusedPlayerReplacementSessionGetsIndependentFallbackDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        scheduler.begin(sessionID: 2, queueItemID: "/queue/b.mp4", plannedDurationSeconds: 5,
                        createdUptime: 5, metadataRetryWindow: 2)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 2, queueItemID: "/queue/b.mp4",
                                                   source: .fallback, now: 5.75),
                       .scheduled(deadlineUptime: 10.75))
    }

    func testOldSessionCallbackCannotFireAfterReplacement() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        scheduler.begin(sessionID: 2, queueItemID: "/queue/b.mp4", plannedDurationSeconds: 5,
                        createdUptime: 1, metadataRetryWindow: 2)
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 5, now: 5),
                       .rejected("session-or-item-mismatch"))
    }

    func testManualNextCancellationRejectsPriorCallback() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertTrue(scheduler.cancel(reason: "manual-next"))
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 5, now: 5),
                       .rejected("not-scheduled"))
    }

    func testNaturalEndAndDeadlineRaceCanBeClaimedOnlyOnce() {
        var naturalFirst = makeScheduler(duration: 5)
        _ = naturalFirst.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertEqual(naturalFirst.claimNaturalEnd(sessionID: 1, queueItemID: item), .won)
        XCTAssertEqual(naturalFirst.claimDeadline(sessionID: 1, queueItemID: item,
                                                  expectedDeadlineUptime: 5, now: 5),
                       .rejected("not-scheduled"))

        var deadlineFirst = makeScheduler(duration: 5)
        _ = deadlineFirst.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertEqual(deadlineFirst.claimDeadline(sessionID: 1, queueItemID: item,
                                                   expectedDeadlineUptime: 5, now: 5), .fired)
        XCTAssertEqual(deadlineFirst.claimNaturalEnd(sessionID: 1, queueItemID: item),
                       .rejected("deadline-already-fired"))
    }

    func testUnadvancableLastItemCanStillFinishNaturallyAfterDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 5, now: 5), .fired)
        XCTAssertTrue(scheduler.allowNaturalEndAfterUnadvancableDeadline(sessionID: 1,
                                                                         queueItemID: item))
        XCTAssertEqual(scheduler.claimNaturalEnd(sessionID: 1, queueItemID: item), .notEligible)
    }

    func testLateDurationMetadataShortensRatherThanStrandsDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .fallback, now: 0.75)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .metadata, now: 1,
                                                   effectiveDurationSeconds: 2),
                       .replaced(previousDeadlineUptime: 5.75, deadlineUptime: 2.75))
    }

    func testSeekOrNormalizerReconfigurationDoesNotCancelDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertTrue(scheduler.markSeekApplied(sessionID: 1, queueItemID: item))
        XCTAssertEqual(scheduler.state?.deadlineUptime, 5)
        XCTAssertEqual(scheduler.state?.status, .scheduled)
    }

    func testPauseFreezesRemainingDurationAndResumeUsesOnlyRemainder() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertEqual(scheduler.pause(sessionID: 1, queueItemID: item, now: 2),
                       .suspended(remainingSeconds: 3))
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 5, now: 20),
                       .rejected("session-paused"))
        XCTAssertEqual(scheduler.resume(sessionID: 1, queueItemID: item, now: 20),
                       .resumed(deadlineUptime: 23))
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 23, now: 23), .fired)
    }

    func testPauseAndResumeAreIdempotentWithoutDuplicateDeadline() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        _ = scheduler.pause(sessionID: 1, queueItemID: item, now: 2)
        XCTAssertEqual(scheduler.pause(sessionID: 1, queueItemID: item, now: 10),
                       .confirmedPaused(remainingSeconds: 3))
        _ = scheduler.resume(sessionID: 1, queueItemID: item, now: 20)
        XCTAssertEqual(scheduler.resume(sessionID: 1, queueItemID: item, now: 21),
                       .confirmedRunning(deadlineUptime: 23))
    }

    func testNaturalEndCannotAdvanceWhilePaused() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        _ = scheduler.pause(sessionID: 1, queueItemID: item, now: 2)
        XCTAssertEqual(scheduler.claimNaturalEnd(sessionID: 1, queueItemID: item),
                       .rejected("session-paused"))
    }

    func testNewItemLoadedWhilePausedWaitsForResume() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.pause(sessionID: 1, queueItemID: item, now: 0)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .fallback, now: 1),
                       .suspended(remainingSeconds: 5))
        XCTAssertNil(scheduler.state?.deadlineUptime)
        XCTAssertEqual(scheduler.resume(sessionID: 1, queueItemID: item, now: 10),
                       .resumed(deadlineUptime: 15))
    }

    func testReplacingPausedSessionRejectsOldCallbacks() {
        var scheduler = makeScheduler(duration: 5)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        _ = scheduler.pause(sessionID: 1, queueItemID: item, now: 2)
        scheduler.begin(sessionID: 2, queueItemID: "/queue/b.mp4", plannedDurationSeconds: 5,
                        createdUptime: 3, metadataRetryWindow: 2)
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 5, now: 5),
                       .rejected("session-or-item-mismatch"))
    }

    func testFixedAndRandomPreviewDurationsBothSchedule() {
        var fixed = makeScheduler(duration: SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(
            mode: .fixed, fixedDurationSeconds: 5, randomMinimumSeconds: 2,
            randomMaximumSeconds: 8, randomValue: 0.5))
        XCTAssertEqual(fixed.registerReadiness(sessionID: 1, queueItemID: item,
                                               source: .playing, now: 0),
                       .scheduled(deadlineUptime: 5))

        let randomDuration = SkimPreviewPlaybackPlan.resolvedClipDurationSeconds(
            mode: .random, fixedDurationSeconds: nil, randomMinimumSeconds: 2,
            randomMaximumSeconds: 8, randomValue: 0.5)
        var random = makeScheduler(duration: randomDuration)
        XCTAssertEqual(random.registerReadiness(sessionID: 1, queueItemID: item,
                                                source: .playing, now: 0),
                       .scheduled(deadlineUptime: 5))
    }

    func testZeroFullFileModeNeverSchedulesPreviewDeadline() {
        var scheduler = makeScheduler(duration: nil)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .playing, now: 0),
                       .ignored("full-file"))
        XCTAssertEqual(scheduler.state?.status, .ineligible)
        XCTAssertNil(scheduler.state?.deadlineUptime)
    }

    func testShortMediaClampsEffectiveDeadlineDuration() {
        var scheduler = makeScheduler(duration: 5)
        XCTAssertEqual(scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                   source: .playing, now: 10,
                                                   effectiveDurationSeconds: 0.25),
                       .scheduled(deadlineUptime: 10.25))
    }

    private func makeScheduler(duration: TimeInterval?) -> SkimPreviewSessionScheduler {
        var scheduler = SkimPreviewSessionScheduler()
        scheduler.begin(sessionID: 1, queueItemID: item, plannedDurationSeconds: duration,
                        createdUptime: 0, metadataRetryWindow: 2)
        return scheduler
    }
}
