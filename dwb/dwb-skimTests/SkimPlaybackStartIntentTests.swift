import XCTest

final class SkimPlaybackStartIntentTests: XCTestCase {
    private let firstItem = "/queue/a.mp4"
    private let secondItem = "/queue/b.mp4"

    private let assignmentA = SkimMediaAssignmentToken(playerGeneration: 1, assignmentGeneration: 1)
    private let assignmentB = SkimMediaAssignmentToken(playerGeneration: 1, assignmentGeneration: 2)

    // MARK: - P15.1 regression: wrapper instability must not reject the current assignment

    /// The exact defect P15 shipped. VLCKit hands back a different `VLCMedia` wrapper for an
    /// unchanged assignment once it processes `MediaPlayerMediaChanged`, so P15 — which bound
    /// `ObjectIdentifier(player.media)` — rejected every readiness callback with
    /// `seek-media-identity-mismatch` and never issued a seek. Ownership is now the token, and the
    /// wrapper is free to change underneath it.
    func testDistinctWrappersForOneLogicalAssignmentStillReachSeekRequest() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        XCTAssertTrue(coordinator.bindAssignment(playbackSessionID: 1, queueItemID: firstItem,
                                                 assignment: assignmentA,
                                                 wrapperDiagnostic: "wrapper-assigned"))
        XCTAssertTrue(coordinator.updateMetadata(playbackSessionID: 1, queueItemID: firstItem,
                                                 durationSeconds: 100, readiness: .final))

        // VLCKit replaces its wrapper here; the assignment itself is unchanged.
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .requestSeek(offsetSeconds: 45, attempt: 1, reason: "initial"))
    }

    /// A nonzero desired offset must be reachable and confirmable across a wrapper swap.
    func testNonzeroOffsetConfirmsDespiteWrapperReplacement() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100, wrapper: "wrapper-1")
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 45.1, now: 0.4),
                       .confirmed(observedOffsetSeconds: 45.1))
    }

    /// The wrapper identifier is diagnostics only: rebinding the same assignment with a different
    /// wrapper must not reset request/confirmation progress.
    func testWrapperDiagnosticChangeDoesNotResetConfirmedSeek() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100, wrapper: "wrapper-1")
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 20, now: 0.3)
        XCTAssertTrue(coordinator.state?.seekWasConfirmed == true)

        XCTAssertTrue(coordinator.bindAssignment(playbackSessionID: 1, queueItemID: firstItem,
                                                 assignment: assignmentA,
                                                 wrapperDiagnostic: "wrapper-2"))
        XCTAssertTrue(coordinator.state?.seekWasConfirmed == true)
        XCTAssertEqual(coordinator.state?.boundWrapperDiagnostic, "wrapper-2")
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 30, now: 1),
                       .none("already-confirmed"))
    }

    // MARK: - Stale ownership is still rejected

    func testStaleAssignmentTokenIsRejected() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentB, duration: 100)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .stale("assignment-generation-mismatch"))
    }

    func testCallbackFromReplacedPlayerIsRejectedAsPlayerGenerationMismatch() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        let recovered = SkimMediaAssignmentToken(playerGeneration: 2, assignmentGeneration: 2)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: recovered, duration: 100)
        // Readiness from the player the recovery replaced.
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .stale("player-generation-mismatch"))
    }

    func testUnboundIntentRejectsCallbacksRatherThanSeeking() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .stale("assignment-unbound"))
    }

    func testOldSessionAndOldItemCallbacksCannotSeekReplacement() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        coordinator = makeCoordinator(item: secondItem, sessionID: 2, mode: .beginning,
                                      skipIntro: 20, previewDuration: 10)
        bindAndResolve(&coordinator, item: secondItem, sessionID: 2,
                       assignment: assignmentB, duration: 100)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .stale("session-or-item-mismatch"))
    }

    /// Two queue rows pointing at the same file are separate sessions with separate assignments,
    /// so a callback for the earlier one cannot drive the later one.
    func testDuplicateQueueEntriesForSameURLRemainDistinctAssignments() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 0, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)

        // Same URL re-queued as a new session with its own assignment.
        coordinator = makeCoordinator(item: firstItem, sessionID: 2, mode: .random,
                                      skipIntro: 0, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 2,
                       assignment: assignmentB, duration: 100)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .stale("session-or-item-mismatch"))
        XCTAssertEqual(coordinator.state?.assignment, assignmentB)
    }

    // MARK: - P15 behaviour preserved

    func testSkipIntroIntentRequestsThenConfirmsObservedOffset() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .requestSeek(offsetSeconds: 20, attempt: 1, reason: "initial"))
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 20.2, now: 0.3),
                       .confirmed(observedOffsetSeconds: 20.2))
        XCTAssertTrue(coordinator.state?.seekWasRequested == true)
        XCTAssertTrue(coordinator.state?.seekWasConfirmed == true)
    }

    func testSeekRequestBeforeConfirmationRetriesSameOffsetAfterResetToZero() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        let desired = coordinator.state?.desiredOffsetSeconds ?? -1
        XCTAssertEqual(desired, 45, accuracy: 0.001)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0.3),
                       .requestSeek(offsetSeconds: desired, attempt: 2, reason: "reset-to-zero"))
        XCTAssertEqual(coordinator.state?.desiredOffsetSeconds, desired)
    }

    func testRetriesAreBoundedForOneSession() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10, maximumAttempts: 2)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0.3)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0.6), .exhausted)
    }

    func testManualNextCreatesIndependentRandomChoice() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.1)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        let firstDesired = coordinator.state?.desiredOffsetSeconds
        coordinator = makeCoordinator(item: secondItem, sessionID: 2, mode: .random,
                                      skipIntro: 10, previewDuration: 20, randomValue: 0.9)
        bindAndResolve(&coordinator, item: secondItem, sessionID: 2,
                       assignment: assignmentB, duration: 100)
        XCTAssertNotEqual(firstDesired, coordinator.state?.desiredOffsetSeconds)
        XCTAssertEqual(coordinator.state?.playbackSessionID, 2)
        XCTAssertEqual(coordinator.state?.assignment, assignmentB)
    }

    func testAutomaticTransitionCreatesIndependentStartIntent() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.25)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        coordinator = makeCoordinator(item: secondItem, sessionID: 2, mode: .random,
                                      skipIntro: 10, previewDuration: 20, randomValue: 0.75)
        bindAndResolve(&coordinator, item: secondItem, sessionID: 2,
                       assignment: assignmentB, duration: 100)
        XCTAssertEqual(coordinator.state?.queueItemID, secondItem)
        XCTAssertEqual(coordinator.state?.playbackSessionID, 2)
        XCTAssertEqual(coordinator.state?.desiredOffsetSeconds ?? -1, 62.5, accuracy: 0.001)
    }

    func testProvisionalMetadataDoesNotLockIntentToZero() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        XCTAssertTrue(coordinator.bindAssignment(playbackSessionID: 1, queueItemID: firstItem,
                                                 assignment: assignmentA))
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .none("metadata-unavailable"))
        XCTAssertTrue(coordinator.updateMetadata(playbackSessionID: 1, queueItemID: firstItem,
                                                 durationSeconds: 100, readiness: .provisional))
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0.1),
                       .requestSeek(offsetSeconds: 45, attempt: 1, reason: "initial"))
    }

    func testConfirmationPreventsRepeatedSeekAndManualScrubIsPreserved() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .beginning,
                                          skipIntro: 20, previewDuration: 10)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 20, now: 0.3)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 35, now: 1),
                       .none("already-confirmed"))
        XCTAssertTrue(coordinator.noteUserSeek(playbackSessionID: 1, queueItemID: firstItem))
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 50, now: 2),
                       .none("terminal"))
    }

    /// A genuinely new assignment (recovery rebuild) keeps the session's one desired offset but
    /// must earn its own confirmation.
    func testRecoveryAssignmentReusesDesiredOffsetButRequiresNewConfirmation() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        let desired = coordinator.state?.desiredOffsetSeconds ?? 0
        _ = evaluate(&coordinator, item: firstItem, sessionID: 1, assignment: assignmentA,
                     observed: 0, now: 0)

        let rebuilt = SkimMediaAssignmentToken(playerGeneration: 2, assignmentGeneration: 2)
        XCTAssertTrue(coordinator.bindAssignment(playbackSessionID: 1, queueItemID: firstItem,
                                                 assignment: rebuilt))
        XCTAssertEqual(coordinator.state?.desiredOffsetSeconds, desired)
        XCTAssertFalse(coordinator.state?.seekWasConfirmed == true)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: rebuilt, observed: 0, now: 0.3),
                       .requestSeek(offsetSeconds: desired, attempt: 1, reason: "initial"))
    }

    /// Navigation while paused: the new item keeps its own assignment and desired offset across
    /// pause and resume rather than being discarded or re-rolled.
    func testPausedAssignmentRetainsIdentityAndDesiredOffsetThroughResume() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        let desired = coordinator.state?.desiredOffsetSeconds ?? -1
        XCTAssertTrue(coordinator.pause(playbackSessionID: 1, queueItemID: firstItem, now: 1))
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, isPaused: true, now: 20),
                       .none("session-paused"))
        XCTAssertTrue(coordinator.resume(playbackSessionID: 1, queueItemID: firstItem, now: 20))
        XCTAssertEqual(coordinator.state?.assignment, assignmentA)
        XCTAssertEqual(coordinator.state?.desiredOffsetSeconds, desired)
        XCTAssertEqual(coordinator.state?.retryDeadlineUptime ?? -1, 22, accuracy: 0.001)
        XCTAssertEqual(evaluate(&coordinator, item: firstItem, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 20.1),
                       .requestSeek(offsetSeconds: desired, attempt: 1, reason: "initial"))
    }

    func testRenameKeepsAssignmentAndDesiredOffset() {
        var coordinator = makeCoordinator(item: firstItem, sessionID: 1, mode: .random,
                                          skipIntro: 10, previewDuration: 20, randomValue: 0.5)
        bindAndResolve(&coordinator, item: firstItem, sessionID: 1,
                       assignment: assignmentA, duration: 100)
        let desired = coordinator.state?.desiredOffsetSeconds
        let renamed = "/queue/keep_a.mp4"
        XCTAssertTrue(coordinator.updateQueueItemID(playbackSessionID: 1, from: firstItem, to: renamed))
        XCTAssertEqual(coordinator.state?.assignment, assignmentA)
        XCTAssertEqual(coordinator.state?.desiredOffsetSeconds, desired)
        XCTAssertEqual(evaluate(&coordinator, item: renamed, sessionID: 1,
                                assignment: assignmentA, observed: 0, now: 0),
                       .requestSeek(offsetSeconds: desired ?? -1, attempt: 1, reason: "initial"))
    }

    // MARK: - Helpers

    private func makeCoordinator(item: String,
                                 sessionID: Int,
                                 mode: SkimPreviewStartMode,
                                 skipIntro: Double,
                                 previewDuration: Double?,
                                 randomValue: Double = 0,
                                 maximumAttempts: Int = 3) -> SkimPlaybackStartIntentCoordinator {
        var coordinator = SkimPlaybackStartIntentCoordinator()
        coordinator.begin(windowID: "window-1", queueItemID: item,
                          playbackSessionID: sessionID, startMode: mode,
                          skipIntroSeconds: skipIntro, previewDurationSeconds: previewDuration,
                          startRandomValue: randomValue, createdUptime: 0,
                          retryWindow: 3, maximumSeekAttempts: maximumAttempts)
        return coordinator
    }

    private func bindAndResolve(_ coordinator: inout SkimPlaybackStartIntentCoordinator,
                                item: String,
                                sessionID: Int,
                                assignment: SkimMediaAssignmentToken,
                                duration: Double,
                                wrapper: String? = nil) {
        XCTAssertTrue(coordinator.bindAssignment(playbackSessionID: sessionID, queueItemID: item,
                                                 assignment: assignment,
                                                 wrapperDiagnostic: wrapper))
        XCTAssertTrue(coordinator.updateMetadata(playbackSessionID: sessionID, queueItemID: item,
                                                 durationSeconds: duration, readiness: .final))
    }

    private func evaluate(_ coordinator: inout SkimPlaybackStartIntentCoordinator,
                          item: String,
                          sessionID: Int,
                          assignment: SkimMediaAssignmentToken,
                          observed: Double,
                          isPaused: Bool = false,
                          now: Double) -> SkimStartIntentAction {
        coordinator.evaluate(playbackSessionID: sessionID, queueItemID: item,
                             assignment: assignment, observedOffsetSeconds: observed,
                             isSeekable: true, isPaused: isPaused, now: now)
    }
}
