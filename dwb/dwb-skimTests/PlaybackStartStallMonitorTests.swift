import XCTest

final class PlaybackStartStallMonitorTests: XCTestCase {

    // MARK: - Single-start decision

    private func decide(startTime: TimeInterval = 100,
                        now: TimeInterval,
                        sawPlaying: Bool = false,
                        watched: Int = 7,
                        current: Int = 7,
                        paused: Bool = false,
                        alreadyWarned: Bool = false) -> Bool {
        PlaybackStartStallMonitor.shouldWarnStalledStart(startTime: startTime,
                                                         now: now,
                                                         sawPlaying: sawPlaying,
                                                         watchedSessionID: watched,
                                                         currentSessionID: current,
                                                         isPaused: paused,
                                                         alreadyWarned: alreadyWarned)
    }

    func testNoWarningBeforeFiveSeconds() {
        XCTAssertFalse(decide(now: 100.0))
        XCTAssertFalse(decide(now: 104.999))
    }

    func testWarnsAtFiveSecondsWithoutPlaying() {
        XCTAssertTrue(decide(now: 105.0))
    }

    func testWarnsAfterFiveSecondsWithoutPlaying() {
        XCTAssertTrue(decide(now: 130.0))
    }

    func testNoWarningWhenPlayingWasSeen() {
        XCTAssertFalse(decide(now: 110, sawPlaying: true))
    }

    func testNoWarningForADifferentSession() {
        XCTAssertFalse(decide(now: 110, watched: 7, current: 8))
    }

    func testNoWarningWhilePaused() {
        XCTAssertFalse(decide(now: 110, paused: true))
    }

    func testNoSecondWarningOnceWarned() {
        XCTAssertFalse(decide(now: 110, alreadyWarned: true))
    }

    func testThresholdValuesAreFiveSecondsAndThree() {
        XCTAssertEqual(PlaybackStartStallMonitor.stallSeconds, 5.0)
        XCTAssertEqual(PlaybackStartStallMonitor.streakWarningCount, 3)
    }

    // MARK: - Monitor flow

    private var monitor = PlaybackStartStallMonitor()
    private var session = 0
    private var clock: TimeInterval = 1_000

    /// Begins a video start. Returns the outcome from ending the previous session.
    @discardableResult
    private func begin(paused: Bool = false) -> PlaybackStartStallMonitor.Outcome {
        session += 1
        clock += 1
        return monitor.beginVideoSession(id: session, filePath: "/v/\(session).mp4",
                                         fileName: "\(session).mp4", startTime: clock, isPaused: paused)
    }

    private func firePastTheLimit() -> PlaybackStartStallMonitor.Outcome {
        monitor.watchdogFired(now: clock + 5.0, currentSessionID: session, isPaused: false)
    }

    func testWatchdogWarnsOnceForAStalledStart() {
        begin()
        let first = firePastTheLimit()
        XCTAssertEqual(first.stalledStart?.sessionID, session)
        XCTAssertEqual(first.stalledStart?.fileName, "\(session).mp4")
        XCTAssertEqual(first.stalledStart?.secondsSinceStart ?? 0, 5.0, accuracy: 0.001)

        XCTAssertNil(firePastTheLimit().stalledStart, "A session warns once")
    }

    func testWatchdogDoesNotWarnAfterPlayingIsSeen() {
        begin()
        XCTAssertTrue(monitor.notePlaying(mediaPath: "/v/\(session).mp4", isPaused: false))
        XCTAssertEqual(firePastTheLimit(), PlaybackStartStallMonitor.Outcome())
    }

    func testPlayingForAnotherFileIsIgnored() {
        begin()
        XCTAssertFalse(monitor.notePlaying(mediaPath: "/v/other.mp4", isPaused: false))
        XCTAssertNotNil(firePastTheLimit().stalledStart)
    }

    func testPlayingWhilePausedIsIgnored() {
        begin()
        XCTAssertFalse(monitor.notePlaying(mediaPath: "/v/\(session).mp4", isPaused: true))
    }

    func testWatchdogDoesNotWarnWhenTheSessionMovedOn() {
        begin()
        let watchedSession = session
        begin()
        let outcome = monitor.watchdogFired(now: clock + 5.0, currentSessionID: watchedSession,
                                            isPaused: false)
        XCTAssertNil(outcome.stalledStart)
    }

    func testPausedSessionNeverWarnsEvenAfterResume() {
        begin()
        monitor.notePaused()
        XCTAssertNil(firePastTheLimit().stalledStart)
        // Resume does not restart the watch: the window passes isPaused false, the session stays paused.
        XCTAssertNil(monitor.watchdogFired(now: clock + 60, currentSessionID: session,
                                           isPaused: false).stalledStart)
    }

    func testStartedWhilePausedNeverWarnsOrCounts() {
        begin(paused: true)
        XCTAssertNil(firePastTheLimit().stalledStart)
        _ = monitor.endActiveSession()
        XCTAssertEqual(monitor.failedStartStreak, 0)
    }

    // MARK: - Streak

    func testTwoFailedStartsDoNotWarn() {
        begin(); XCTAssertNil(firePastTheLimit().streakWarning)
        begin(); XCTAssertNil(firePastTheLimit().streakWarning)
        XCTAssertEqual(monitor.failedStartStreak, 2)
    }

    func testThirdFailedStartWarnsOnceWithItsDetails() {
        begin(); _ = firePastTheLimit()
        begin(); _ = firePastTheLimit()
        begin()
        let third = firePastTheLimit()
        XCTAssertEqual(third.streakWarning,
                       PlaybackStartStallMonitor.Outcome.StreakWarning(count: 3,
                                                                       sessionID: session,
                                                                       fileName: "\(session).mp4"))
    }

    func testFourthFailedStartDoesNotWarnAgain() {
        for _ in 1...3 { begin(); _ = firePastTheLimit() }
        begin()
        XCTAssertNil(firePastTheLimit().streakWarning)
        XCTAssertEqual(monitor.failedStartStreak, 4)
    }

    func testStreakCountsStartsReplacedBeforeAnyTimeout() {
        // Keeps pressing Next: no start lives 5 s, but each replaced start counts.
        begin()
        XCTAssertNil(begin().streakWarning)   // ends #1 -> count 1
        XCTAssertNil(begin().streakWarning)   // ends #2 -> count 2
        let third = begin()                   // ends #3 -> count 3
        XCTAssertEqual(third.streakWarning?.count, 3)
        XCTAssertEqual(third.streakWarning?.sessionID, session - 1)
        XCTAssertNil(begin().streakWarning, "Count 4 does not warn again")
    }

    func testPlayingResetsTheCountAndThreeMoreWarnAgain() {
        for _ in 1...3 { begin(); _ = firePastTheLimit() }
        begin()
        XCTAssertTrue(monitor.notePlaying(mediaPath: "/v/\(session).mp4", isPaused: false))
        XCTAssertEqual(monitor.failedStartStreak, 0)

        begin(); XCTAssertNil(firePastTheLimit().streakWarning)
        begin(); XCTAssertNil(firePastTheLimit().streakWarning)
        begin(); XCTAssertEqual(firePastTheLimit().streakWarning?.count, 3)
    }

    func testASessionThatTimedOutAndWasReplacedCountsOnce() {
        begin()
        _ = firePastTheLimit()
        XCTAssertEqual(monitor.failedStartStreak, 1)
        _ = begin()   // ends the timed-out session
        XCTAssertEqual(monitor.failedStartStreak, 1)
    }

    func testAPausedSessionDoesNotCount() {
        begin(); _ = firePastTheLimit()
        begin(); _ = firePastTheLimit()
        begin()
        monitor.notePaused()
        _ = firePastTheLimit()
        let ended = monitor.endActiveSession()
        XCTAssertNil(ended.streakWarning)
        XCTAssertEqual(monitor.failedStartStreak, 2)
    }

    func testPlayedSessionEndingDoesNotCount() {
        begin()
        monitor.notePlaying(mediaPath: "/v/\(session).mp4", isPaused: false)
        _ = monitor.endActiveSession()
        XCTAssertEqual(monitor.failedStartStreak, 0)
    }

    func testEndingWithNoActiveSessionIsHarmless() {
        XCTAssertEqual(monitor.endActiveSession(), PlaybackStartStallMonitor.Outcome())
        begin()
        _ = monitor.endActiveSession()
        XCTAssertEqual(monitor.endActiveSession(), PlaybackStartStallMonitor.Outcome())
        XCTAssertEqual(monitor.failedStartStreak, 1)
    }

    func testTimeoutAndStreakCanFireTogether() {
        begin(); _ = firePastTheLimit()
        begin(); _ = firePastTheLimit()
        begin()
        let outcome = firePastTheLimit()
        XCTAssertNotNil(outcome.stalledStart)
        XCTAssertNotNil(outcome.streakWarning)
    }
}
