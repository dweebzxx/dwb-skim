import XCTest

/// Test-only harness reproducing `PlayerWindowController`'s preview auto-advance deadline
/// orchestration (`scheduleSkimPreviewDeadline` / `bindSkimStartIntent` / `fireSkimPreviewDeadline`)
/// using the same production types the controller composes: `SkimPreviewSessionScheduler`,
/// `SkimMediaAssignmentRegistry`, `SkimPreviewDeadlineBinding`, and `SkimDeadlineGuard`.
///
/// There is no seam to unit test `PlayerWindowController` itself — it requires a live VLCKit
/// player — so this harness is the closest practical regression coverage for the P26 bug: a
/// scheduled preview deadline was silently orphaned after a same-session VLCKit player rebuild
/// (playback-start handshake recovery) minted a new `SkimMediaAssignmentToken`, causing
/// `fireSkimPreviewDeadline` to reject the callback as `deadline-context-mismatch` with no
/// replacement ever scheduled. It mirrors `fireSkimPreviewDeadline`'s guard sequence exactly; a
/// regression in the real controller's sequencing would not be caught here, but a regression in
/// the underlying primitives' behavior — the actual site of the P26 bug — would be.
private final class PreviewDeadlineHarness {
    var scheduler = SkimPreviewSessionScheduler()
    var assignments = SkimMediaAssignmentRegistry()
    var binding = SkimPreviewDeadlineBinding()

    var isSkimEnabled = true
    var isPaused = false
    var isWindowClosing = false
    /// Mirrors `currentPlaybackSessionID` / `currentMediaURL` — the window's live session/item,
    /// independent of what any particular armed timer captured at schedule time.
    var currentSessionID: Int?
    var currentQueueItemID: String?

    enum FireOutcome: Equatable {
        case advanced
        case rejected(String)
    }

    struct ArmedTimer {
        let sessionID: Int
        let queueItemID: String
        let deadlineUptime: TimeInterval
        let generation: Int
    }

    /// Mirrors the start of `executePlayCurrentItem`: `resetPlaybackCompletionSignals` cancels the
    /// prior preview session (and, with the P26 fix, the deadline binding) before the new session
    /// begins.
    func beginSession(sessionID: Int, queueItemID: String, plannedDuration: TimeInterval?, now: TimeInterval) {
        binding.clear()
        currentSessionID = sessionID
        currentQueueItemID = queueItemID
        scheduler.begin(sessionID: sessionID, queueItemID: queueItemID,
                        plannedDurationSeconds: plannedDuration, createdUptime: now,
                        metadataRetryWindow: 2)
    }

    /// Mirrors `bindSkimStartIntent`, optionally preceded by `installFreshPlayer` — both a fresh
    /// session start and a handshake-recovery rebuild call `installPlayer()` before `assign()`.
    /// Returns whether this bind rebound an already-armed deadline (same session/queue item).
    @discardableResult
    func bindMedia(sessionID: Int, queueItemID: String, freshPlayer: Bool) -> Bool {
        if freshPlayer { _ = assignments.installPlayer() }
        let assignment = assignments.assign()
        return binding.rebind(sessionID: sessionID, queueItemID: queueItemID, assignment: assignment)
    }

    /// Mirrors `scheduleSkimPreviewDeadline`. Returns the "timer" as a value so a test can hold an
    /// old one and fire it after a later reschedule supersedes it — the same as a DispatchWorkItem
    /// closure holding its own captured generation.
    func armTimer(sessionID: Int, queueItemID: String, deadlineUptime: TimeInterval) -> ArmedTimer {
        let generation = binding.scheduled(sessionID: sessionID, queueItemID: queueItemID,
                                           assignment: assignments.current)
        return ArmedTimer(sessionID: sessionID, queueItemID: queueItemID,
                          deadlineUptime: deadlineUptime, generation: generation)
    }

    /// Mirrors `fireSkimPreviewDeadline`'s guard sequence.
    func fire(_ timer: ArmedTimer, now: TimeInterval) -> FireOutcome {
        guard binding.isCurrentGeneration(timer.generation) else { return .rejected("deadline-superseded") }
        guard !isWindowClosing else { return .rejected("deadline-window-closing") }
        guard isSkimEnabled else { return .rejected("deadline-skim-disabled") }
        guard !isPaused else { return .rejected("deadline-session-paused") }
        guard timer.sessionID == currentSessionID, timer.queueItemID == currentQueueItemID else {
            return .rejected("deadline-session-replaced")
        }

        let deadlineGuard = SkimDeadlineGuard(isSkimEnabled: isSkimEnabled,
                                              scheduledAssignment: binding.assignment,
                                              currentAssignment: assignments.current)
        if !deadlineGuard.mayAdvance {
            guard let current = assignments.current,
                  binding.rebind(sessionID: timer.sessionID, queueItemID: timer.queueItemID, assignment: current)
            else {
                return .rejected("deadline-context-mismatch")
            }
        }

        switch scheduler.claimDeadline(sessionID: timer.sessionID, queueItemID: timer.queueItemID,
                                       expectedDeadlineUptime: timer.deadlineUptime, now: now) {
        case .fired:
            return .advanced
        case .rejected(let reason):
            return .rejected("deadline-\(reason)")
        }
    }
}

final class SkimPreviewDeadlineReliabilityTests: XCTestCase {
    private let item = "/queue/a.mp4"

    // 1. Initial deadline fires once and advances.
    func testInitialDeadlineFiresOnceAndAdvances() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        XCTAssertEqual(harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item,
                                                            source: .playing, now: 0),
                       .scheduled(deadlineUptime: 5))
        let timer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)

        XCTAssertEqual(harness.fire(timer, now: 5), .advanced)
        // Firing the same timer twice must not double-advance.
        XCTAssertEqual(harness.fire(timer, now: 5), .rejected("deadline-not-scheduled"))
    }

    // 2. Relocation replaces a deadline; the old callback is rejected without disturbing the
    //    replacement; the replacement fires once.
    func testRelocationReplacesDeadlineOldCallbackRejectedReplacementFiresOnce() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 10, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let originalTimer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 10)

        XCTAssertEqual(harness.scheduler.replaceDeadlineForRelocation(sessionID: 1, queueItemID: item,
                                                                       now: 2, durationSeconds: 6),
                       .replaced(previousDeadlineUptime: 10, deadlineUptime: 8))
        let relocatedTimer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 8)

        XCTAssertEqual(harness.fire(originalTimer, now: 10), .rejected("deadline-superseded"))
        XCTAssertEqual(harness.fire(relocatedTimer, now: 8), .advanced)
    }

    // 3. Multiple rapid relocations leave only the newest effective deadline.
    func testMultipleRapidRelocationsLeaveOnlyNewestEffectiveDeadline() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 20, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let t1 = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 20)

        _ = harness.scheduler.replaceDeadlineForRelocation(sessionID: 1, queueItemID: item,
                                                            now: 1, durationSeconds: 10)
        let t2 = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 11)

        _ = harness.scheduler.replaceDeadlineForRelocation(sessionID: 1, queueItemID: item,
                                                            now: 2, durationSeconds: 4)
        let t3 = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 6)

        XCTAssertEqual(harness.fire(t1, now: 20), .rejected("deadline-superseded"))
        XCTAssertEqual(harness.fire(t2, now: 11), .rejected("deadline-superseded"))
        XCTAssertEqual(harness.fire(t3, now: 6), .advanced)
    }

    // 4. Handshake-recovery reassignment for the same logical session preserves deadline
    //    ownership. This directly reproduces the P26 evidence (sessions 21/23/33: deadline
    //    confirmed, media rebound during handshake recovery, then staleCallbackRejected
    //    deadline-context-mismatch with no replacement ever firing).
    func testHandshakeRecoveryReassignmentPreservesDeadlineOwnership() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 21, queueItemID: item, plannedDuration: 30, now: 0)
        harness.bindMedia(sessionID: 21, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 21, queueItemID: item, source: .playing, now: 0)
        let timer = harness.armTimer(sessionID: 21, queueItemID: item, deadlineUptime: 30)

        // Playback stalled; handshake recovery rebuilds the VLCKit player for the SAME session and
        // queue item mid-startup, minting a new assignment token without changing the session.
        let rebound = harness.bindMedia(sessionID: 21, queueItemID: item, freshPlayer: true)
        XCTAssertTrue(rebound, "a same-session player rebuild must rebind the pending deadline")

        XCTAssertEqual(harness.fire(timer, now: 30), .advanced,
                       "without the P26 rebind fix this incorrectly rejects with deadline-context-mismatch")
    }

    // 5. Genuine assignment/session replacement rejects the old callback.
    func testGenuineSessionReplacementRejectsOldCallback() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let timer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)

        // Manual Next: a genuinely new session/queue item, not a same-session rebuild.
        let nextItem = "/queue/b.mp4"
        harness.beginSession(sessionID: 2, queueItemID: nextItem, plannedDuration: 5, now: 1)
        let rebound = harness.bindMedia(sessionID: 2, queueItemID: nextItem, freshPlayer: true)
        XCTAssertFalse(rebound, "a different session must never rebind a stale timer's binding")

        XCTAssertEqual(harness.fire(timer, now: 5), .rejected("deadline-session-replaced"))
    }

    // 6. Pause after relocation, then resume, preserves remaining duration and fires once.
    func testPauseAfterRelocationThenResumePreservesRemainingDurationAndFiresOnce() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 10, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        _ = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 10)

        _ = harness.scheduler.replaceDeadlineForRelocation(sessionID: 1, queueItemID: item,
                                                            now: 2, durationSeconds: 6)
        let relocatedTimer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 8)

        XCTAssertEqual(harness.scheduler.pause(sessionID: 1, queueItemID: item, now: 4),
                       .suspended(remainingSeconds: 4))
        harness.isPaused = true
        XCTAssertEqual(harness.fire(relocatedTimer, now: 8), .rejected("deadline-session-paused"))

        harness.isPaused = false
        XCTAssertEqual(harness.scheduler.resume(sessionID: 1, queueItemID: item, now: 10),
                       .resumed(deadlineUptime: 14))
        let resumedTimer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 14)

        XCTAssertEqual(harness.fire(resumedTimer, now: 14), .advanced)
    }

    // 7. Stale callback arrival after cancellation cannot advance the current session.
    func testStaleCallbackAfterCancellationCannotAdvanceCurrentSession() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let timer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)

        // Window close / user-stop: resetPlaybackCompletionSignals cancels the session and clears
        // the live session/item the controller tracks.
        XCTAssertTrue(harness.scheduler.cancel(reason: "window-close"))
        harness.currentSessionID = nil
        harness.currentQueueItemID = nil
        harness.binding.clear()

        XCTAssertEqual(harness.fire(timer, now: 5), .rejected("deadline-session-replaced"))
    }

    // 8. Short-media natural end and deadline arbitration remain correct (scheduler-level; the
    //    deadline-binding changes do not touch the natural-end path).
    func testShortMediaNaturalEndWinsAndBlocksLaterDeadlineClaim() {
        var scheduler = SkimPreviewSessionScheduler()
        scheduler.begin(sessionID: 1, queueItemID: item, plannedDurationSeconds: 30,
                        createdUptime: 0, metadataRetryWindow: 2)
        _ = scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        XCTAssertEqual(scheduler.claimNaturalEnd(sessionID: 1, queueItemID: item), .won)
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 1, queueItemID: item,
                                               expectedDeadlineUptime: 30, now: 30),
                       .rejected("not-scheduled"))
    }

    // 9. An active playing session cannot remain without either a live deadline or suspended
    //    remaining duration: even if some future code path mints a new assignment token for the
    //    live session without going through `bindSkimStartIntent`'s proactive rebind,
    //    `fireSkimPreviewDeadline`'s self-heal must still advance rather than orphan the deadline.
    func testInvariantSelfHealsAssignmentDriftWithoutProactiveRebind() {
        let harness = PreviewDeadlineHarness()
        harness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        harness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = harness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let timer = harness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)

        // Bypass the proactive rebind hook entirely — simulates an uncovered future call site.
        _ = harness.assignments.installPlayer()
        _ = harness.assignments.assign()
        XCTAssertNotEqual(harness.binding.assignment, harness.assignments.current)

        XCTAssertEqual(harness.fire(timer, now: 5), .advanced,
                       "an active playing session must never be silently left without a live deadline")
    }

    // 10. Window closing and skim-disabled must still cleanly reject rather than advance.
    func testWindowClosingAndSkimDisabledRejectWithoutAdvancing() {
        let closingHarness = PreviewDeadlineHarness()
        closingHarness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        closingHarness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = closingHarness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let closingTimer = closingHarness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)
        closingHarness.isWindowClosing = true
        XCTAssertEqual(closingHarness.fire(closingTimer, now: 5), .rejected("deadline-window-closing"))

        let disabledHarness = PreviewDeadlineHarness()
        disabledHarness.beginSession(sessionID: 1, queueItemID: item, plannedDuration: 5, now: 0)
        disabledHarness.bindMedia(sessionID: 1, queueItemID: item, freshPlayer: true)
        _ = disabledHarness.scheduler.registerReadiness(sessionID: 1, queueItemID: item, source: .playing, now: 0)
        let disabledTimer = disabledHarness.armTimer(sessionID: 1, queueItemID: item, deadlineUptime: 5)
        disabledHarness.isSkimEnabled = false
        XCTAssertEqual(disabledHarness.fire(disabledTimer, now: 5), .rejected("deadline-skim-disabled"))
    }
}
