import XCTest

final class PlayerWindowReactivationPlannerTests: XCTestCase {

    // MARK: - Creating vs raising

    func testNoExistingPlayerCreatesExactlyOneNewWindow() {
        XCTAssertEqual(PlayerWindowReactivationPlanner.plan(candidates: []),
                       .createNewPlayerWindow)
    }

    func testReopenWithVisiblePlayerRaisesItAndCreatesNone() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-1", isKeyWindow: true)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-1",
                                            needsDeminiaturize: false,
                                            needsOrderFront: false))
    }

    /// The duplicate-window regression: a minimized window reports
    /// isVisible == false, so an isVisible-based existence check saw no player
    /// and built a second one.
    func testReopenWithMinimizedPlayerDeminiaturizesAndRaisesRatherThanCreating() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-1", isMiniaturized: true, isOnScreen: false)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-1",
                                            needsDeminiaturize: true,
                                            needsOrderFront: true))
    }

    func testReopenWithOrderedOutPlayerShowsAndRaisesRatherThanCreating() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-1", isOnScreen: false)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-1",
                                            needsDeminiaturize: false,
                                            needsOrderFront: true))
    }

    /// Settings or the Debug Console being key means no player is key. The
    /// existing player must still be raised.
    func testReopenWhileSettingsIsKeyRaisesTheExistingPlayer() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-1", isKeyWindow: false, activationRank: 0)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-1",
                                            needsDeminiaturize: false,
                                            needsOrderFront: true))
    }

    // MARK: - Selection among several players

    func testMultiplePlayersPrefersTheKeyWindow() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-1", activationRank: 0),
            candidate("player-2", isKeyWindow: true, activationRank: 2)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-2",
                                            needsDeminiaturize: false,
                                            needsOrderFront: false))
    }

    func testMultiplePlayersWithNoKeyWindowChoosesMostRecentlyActive() {
        let selected = PlayerWindowReactivationPlanner.select(from: [
            candidate("player-1", activationRank: 2),
            candidate("player-2", activationRank: 0),
            candidate("player-3", activationRank: 1)
        ])
        XCTAssertEqual(selected?.identifier, "player-2")
    }

    /// A key-but-minimized window is not a usable front target; recency wins.
    func testMinimizedKeyWindowDoesNotOutrankAnAvailableRecentWindow() {
        let selected = PlayerWindowReactivationPlanner.select(from: [
            candidate("player-1", isKeyWindow: true, isMiniaturized: true, isOnScreen: false, activationRank: 1),
            candidate("player-2", activationRank: 0)
        ])
        XCTAssertEqual(selected?.identifier, "player-2")
    }

    func testSelectionIsDeterministicWhenRecencyTies() {
        let selected = PlayerWindowReactivationPlanner.select(from: [
            candidate("player-3", activationRank: 0),
            candidate("player-1", activationRank: 0)
        ])
        XCTAssertEqual(selected?.identifier, "player-1")
    }

    // MARK: - Stability

    func testRepeatedReopenKeepsRaisingTheSameWindowAndNeverCreates() {
        let candidates = [candidate("player-1", isKeyWindow: true)]
        for _ in 0..<5 {
            let plan = PlayerWindowReactivationPlanner.plan(candidates: candidates)
            XCTAssertEqual(plan, .raiseExisting(identifier: "player-1",
                                                needsDeminiaturize: false,
                                                needsOrderFront: false))
            XCTAssertNotEqual(plan, .createNewPlayerWindow)
        }
    }

    /// Closing one of several players must not strand reopen on the closed one.
    /// Closed windows are absent from the candidate list entirely.
    func testClosingOnePlayerStillSelectsAnotherExistingPlayer() {
        let plan = PlayerWindowReactivationPlanner.plan(candidates: [
            candidate("player-2", activationRank: 0)
        ])
        XCTAssertEqual(plan, .raiseExisting(identifier: "player-2",
                                            needsDeminiaturize: false,
                                            needsOrderFront: true))
    }

    func testClosingEveryPlayerCreatesExactlyOneWindowOnNextReopen() {
        XCTAssertEqual(PlayerWindowReactivationPlanner.plan(candidates: []),
                       .createNewPlayerWindow)
    }

    private func candidate(_ identifier: String,
                           isKeyWindow: Bool = false,
                           isMiniaturized: Bool = false,
                           isOnScreen: Bool = true,
                           activationRank: Int = 0) -> PlayerWindowReactivationCandidate {
        PlayerWindowReactivationCandidate(identifier: identifier,
                                          isKeyWindow: isKeyWindow,
                                          isMiniaturized: isMiniaturized,
                                          isOnScreen: isOnScreen,
                                          activationRank: activationRank)
    }
}
