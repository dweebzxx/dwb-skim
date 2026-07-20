import XCTest

final class SkimMediaAssignmentTests: XCTestCase {
    // MARK: - Token stability

    func testAssignmentTokenIsStableWhileWrapperObjectsChange() {
        var registry = SkimMediaAssignmentRegistry()
        registry.installPlayer()
        let token = registry.assign()

        // Model VLCKit handling MediaPlayerMediaChanged: it allocates a replacement VLCMedia
        // wrapper for the same libvlc media and overwrites its own `media` ivar. Nothing about
        // the logical assignment changed, so the registry must not move.
        let wrappers = [FakeMediaWrapper(), FakeMediaWrapper(), FakeMediaWrapper()]
        XCTAssertEqual(Set(wrappers.map { ObjectIdentifier($0) }).count, 3,
                       "wrappers must be distinct objects for this test to mean anything")

        XCTAssertEqual(registry.current, token)
        XCTAssertTrue(registry.isCurrent(token))
    }

    func testEachLogicalAssignmentGetsADistinctToken() {
        var registry = SkimMediaAssignmentRegistry()
        registry.installPlayer()
        let first = registry.assign()
        let second = registry.assign()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(registry.current, second)
        XCTAssertFalse(registry.isCurrent(first))
    }

    /// Replaying the same file must not reuse the previous token, otherwise a late callback from
    /// the earlier play could be accepted against the new one.
    func testReassigningSameURLMintsANewToken() {
        var registry = SkimMediaAssignmentRegistry()
        registry.installPlayer()
        let first = registry.assign()   // /queue/a.mp4
        let second = registry.assign()  // /queue/a.mp4 again
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.assignmentGeneration, first.assignmentGeneration + 1)
    }

    func testInstallingFreshPlayerReplacesOwnershipAndDropsCurrentAssignment() {
        var registry = SkimMediaAssignmentRegistry()
        registry.installPlayer()
        let onOldPlayer = registry.assign()

        registry.installPlayer()
        XCTAssertNil(registry.current, "a new player carries no assignment until one is made")
        XCTAssertFalse(registry.isCurrent(onOldPlayer))

        let onNewPlayer = registry.assign()
        XCTAssertEqual(onNewPlayer.playerGeneration, onOldPlayer.playerGeneration + 1)
        XCTAssertNotEqual(onNewPlayer, onOldPlayer)
    }

    func testClearDropsCurrentAssignmentWithoutRewindingGenerations() {
        var registry = SkimMediaAssignmentRegistry()
        registry.installPlayer()
        let token = registry.assign()
        registry.clear()
        XCTAssertNil(registry.current)
        XCTAssertFalse(registry.isCurrent(token))
        XCTAssertNotEqual(registry.assign(), token)
    }

    func testRegistriesAreIndependentPerWindow() {
        var first = SkimMediaAssignmentRegistry()
        var second = SkimMediaAssignmentRegistry()
        first.installPlayer()
        second.installPlayer()
        _ = first.assign()
        _ = first.assign()
        let secondToken = second.assign()

        // A second window's counters must not be advanced by the first window's activity.
        XCTAssertEqual(secondToken.assignmentGeneration, 1)
        XCTAssertNotEqual(first.current, second.current)
    }

    // MARK: - Integration seam: assignment → readiness → seek

    /// Mirrors PlayerWindowController's ordering with a fake player whose wrapper VLCKit swaps
    /// mid-assignment, proving the token minted at assignment time is the one readiness uses and
    /// that a wrapper lookup is never needed to rediscover ownership.
    func testAssignmentTokenFlowsFromAssignmentIntoReadinessAndReachesSeekRequest() {
        var harness = AssignmentHarness()
        harness.installPlayer()
        harness.beginSession(item: "/queue/a.mp4", sessionID: 1, previewDuration: 20, randomValue: 0.5)
        let assigned = harness.assignMedia(item: "/queue/a.mp4", sessionID: 1)
        harness.resolveMetadata(item: "/queue/a.mp4", sessionID: 1, duration: 100)

        // VLCKit replaces its wrapper before the first readiness observation lands.
        harness.simulateVLCKitWrapperReplacement()

        let observedByReadiness = harness.currentAssignmentForReadiness()
        XCTAssertEqual(observedByReadiness, assigned,
                       "readiness must see the token minted at assignment time")

        let action = harness.processReadiness(item: "/queue/a.mp4", sessionID: 1, observed: 0, now: 0)
        guard case .requestSeek(let offset, _, _) = action else {
            return XCTFail("current assignment must reach seekRequested, got \(action)")
        }
        XCTAssertEqual(offset, 45, accuracy: 0.001)
    }

    func testRecoveryReplacementInvalidatesCallbacksFromTheReplacedPlayer() {
        var harness = AssignmentHarness()
        harness.installPlayer()
        harness.beginSession(item: "/queue/a.mp4", sessionID: 1, previewDuration: 20, randomValue: 0.5)
        let original = harness.assignMedia(item: "/queue/a.mp4", sessionID: 1)
        harness.resolveMetadata(item: "/queue/a.mp4", sessionID: 1, duration: 100)

        // Handshake recovery rebuilds the player and reassigns the same URL. The session is not
        // restarted, so its already-resolved desired offset survives.
        harness.installPlayer()
        let rebuilt = harness.assignMedia(item: "/queue/a.mp4", sessionID: 1)
        XCTAssertNotEqual(rebuilt, original)

        XCTAssertEqual(harness.evaluate(item: "/queue/a.mp4", sessionID: 1,
                                        assignment: original, observed: 0, now: 0),
                       .stale("player-generation-mismatch"))
        guard case .requestSeek = harness.processReadiness(item: "/queue/a.mp4", sessionID: 1,
                                                           observed: 0, now: 0.5) else {
            return XCTFail("the rebuilt assignment must still be able to seek")
        }
    }

    func testFreshAndReusedPlayerPathsProduceEquivalentOwnership() {
        // Fresh player: install then assign.
        var fresh = AssignmentHarness()
        fresh.installPlayer()
        fresh.beginSession(item: "/queue/a.mp4", sessionID: 1, previewDuration: 20, randomValue: 0.5)
        let freshToken = fresh.assignMedia(item: "/queue/a.mp4", sessionID: 1)
        fresh.resolveMetadata(item: "/queue/a.mp4", sessionID: 1, duration: 100)

        // Reused player: no install, just a new session and assignment on the existing player.
        var reused = AssignmentHarness()
        reused.installPlayer()
        reused.beginSession(item: "/queue/old.mp4", sessionID: 1, previewDuration: 20, randomValue: 0.5)
        reused.assignMedia(item: "/queue/old.mp4", sessionID: 1)
        reused.beginSession(item: "/queue/a.mp4", sessionID: 2, previewDuration: 20, randomValue: 0.5)
        let reusedToken = reused.assignMedia(item: "/queue/a.mp4", sessionID: 2)
        reused.resolveMetadata(item: "/queue/a.mp4", sessionID: 2, duration: 100)

        XCTAssertEqual(fresh.currentAssignmentForReadiness(), freshToken)
        XCTAssertEqual(reused.currentAssignmentForReadiness(), reusedToken)

        for (harness, session) in [(fresh, 1), (reused, 2)] {
            var harness = harness
            guard case .requestSeek(let offset, _, _) =
                    harness.processReadiness(item: "/queue/a.mp4", sessionID: session,
                                             observed: 0, now: 0) else {
                return XCTFail("both assignment paths must reach seekRequested")
            }
            XCTAssertEqual(offset, 45, accuracy: 0.001)
        }
    }

    // MARK: - Fixtures

    private final class FakeMediaWrapper {}

    /// Pure stand-in for PlayerWindowController's assignment logic: the registry and the start
    /// intent wired in the same order, with a wrapper that can be swapped the way VLCKit swaps it.
    private struct AssignmentHarness {
        private var registry = SkimMediaAssignmentRegistry()
        private var intent = SkimPlaybackStartIntentCoordinator()
        private var wrapper = FakeMediaWrapper()

        mutating func installPlayer() {
            registry.installPlayer()
        }

        /// The controller creates the session and its start intent before any media exists.
        mutating func beginSession(item: String,
                                   sessionID: Int,
                                   previewDuration: Double,
                                   randomValue: Double) {
            intent.begin(windowID: "window-1", queueItemID: item, playbackSessionID: sessionID,
                         startMode: .random, skipIntroSeconds: 10,
                         previewDurationSeconds: previewDuration, startRandomValue: randomValue,
                         createdUptime: 0, retryWindow: 3, maximumSeekAttempts: 3)
        }

        /// Ordering under test: create the assignment → mint the token → bind the intent to it.
        /// Recovery reuses this without re-beginning the session, so the session keeps its one
        /// resolved desired offset.
        @discardableResult
        mutating func assignMedia(item: String, sessionID: Int) -> SkimMediaAssignmentToken {
            wrapper = FakeMediaWrapper()
            let token = registry.assign()
            XCTAssertTrue(intent.bindAssignment(playbackSessionID: sessionID, queueItemID: item,
                                                assignment: token,
                                                wrapperDiagnostic: wrapperDiagnostic))
            return token
        }

        mutating func resolveMetadata(item: String, sessionID: Int, duration: Double) {
            XCTAssertTrue(intent.updateMetadata(playbackSessionID: sessionID, queueItemID: item,
                                                durationSeconds: duration, readiness: .final))
        }

        /// VLCKit's MediaPlayerMediaChanged handler allocating a replacement wrapper.
        mutating func simulateVLCKitWrapperReplacement() {
            let previous = wrapperDiagnostic
            wrapper = FakeMediaWrapper()
            XCTAssertNotEqual(previous, wrapperDiagnostic,
                              "the replacement must be a genuinely different object")
        }

        func currentAssignmentForReadiness() -> SkimMediaAssignmentToken? {
            registry.current
        }

        /// The readiness path: ownership is read from the registry, never from the wrapper.
        mutating func processReadiness(item: String,
                                       sessionID: Int,
                                       observed: Double,
                                       now: Double) -> SkimStartIntentAction {
            guard let assignment = registry.current else {
                return .stale("no-current-assignment")
            }
            return evaluate(item: item, sessionID: sessionID, assignment: assignment,
                            observed: observed, now: now)
        }

        mutating func evaluate(item: String,
                               sessionID: Int,
                               assignment: SkimMediaAssignmentToken,
                               observed: Double,
                               now: Double) -> SkimStartIntentAction {
            intent.evaluate(playbackSessionID: sessionID, queueItemID: item,
                            assignment: assignment, observedOffsetSeconds: observed,
                            isSeekable: true, isPaused: false, now: now)
        }

        private var wrapperDiagnostic: String {
            String(UInt(bitPattern: ObjectIdentifier(wrapper).hashValue), radix: 16)
        }
    }
}
