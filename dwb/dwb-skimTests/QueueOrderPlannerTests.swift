import Foundation
import XCTest

final class QueueOrderPlannerTests: XCTestCase {

    private func items(_ names: [String], lastPlayed: [String: Int] = [:]) -> [QueueOrderPlannerItem] {
        names.map {
            QueueOrderPlannerItem(id: "/tmp/\($0)",
                                  displayName: $0,
                                  lastPlayedOrdinal: lastPlayed[$0])
        }
    }

    func testSequentialPreservesNaturalOrder() {
        let order = QueueOrderPlanner.cycleOrder(mode: .sequential,
                                                 items: items(["a.mov", "b.mov", "c.mov"]),
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order, [0, 1, 2])
    }

    func testShuffleUsesInjectedRandomnessWithoutRepeats() {
        var picks = [0, 1]
        let order = QueueOrderPlanner.cycleOrder(mode: .shuffle,
                                                 items: items(["a.mov", "b.mov", "c.mov"]),
                                                 randomInt: { _ in picks.removeFirst() })
        XCTAssertEqual(Set(order), Set([0, 1, 2]))
        XCTAssertEqual(order.count, 3)
    }

    func testShuffleCanKeepCurrentItemFirst() {
        let queue = items(["a.mov", "b.mov", "c.mov"])
        let order = QueueOrderPlanner.cycleOrder(mode: .shuffle,
                                                 items: queue,
                                                 currentID: queue[1].id,
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order.first, 1)
        XCTAssertEqual(Set(order), Set([0, 1, 2]))
    }

    func testNewLoopCycleAvoidsImmediateRepeatWhenPossible() {
        let queue = items(["a.mov", "b.mov", "c.mov"])
        let order = QueueOrderPlanner.cycleOrder(mode: .shuffle,
                                                 items: queue,
                                                 avoidingFirstID: queue[0].id,
                                                 randomInt: { _ in 0 })
        XCTAssertNotEqual(order.first, 0)
        XCTAssertEqual(Set(order), Set([0, 1, 2]))
    }

    func testWeightedWaitedOrderDoesNotRepeatWithinCycle() {
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: items(["clip.mov", "delete_clip.mov", "keep_clip.mov"]),
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(Set(order), Set([0, 1, 2]))
        XCTAssertEqual(order.count, 3)
    }

    func testWeightedWaitedOrderFavorsLongestWaitedItems() {
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: items(["recent.mov", "old.mov", "middle.mov"],
                                                              lastPlayed: [
                                                                "recent.mov": 30,
                                                                "old.mov": 10,
                                                                "middle.mov": 20,
                                                              ]),
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order, [1, 2, 0])
    }

    func testWeightedWaitedOrderTreatsNeverPlayedAsLongestWaited() {
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: items(["played.mov", "new.mov", "older.mov"],
                                                              lastPlayed: [
                                                                "played.mov": 20,
                                                                "older.mov": 10,
                                                              ]),
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order, [1, 2, 0])
    }

    func testWeightedWaitedOrderKeepsOriginalOrderForEqualWaitTie() {
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: items(["a.mov", "b.mov", "c.mov"],
                                                              lastPlayed: [
                                                                "a.mov": 5,
                                                                "b.mov": 5,
                                                                "c.mov": 5,
                                                              ]),
                                                 randomInt: { _ in 2 })
        XCTAssertEqual(order, [0, 1, 2])
    }

    func testWeightedCanKeepCurrentItemFirstForDeterministicPreviousHistory() {
        let queue = items(["old.mov", "current.mov", "recent.mov"],
                          lastPlayed: [
                            "old.mov": 1,
                            "current.mov": 10,
                            "recent.mov": 20,
                          ])
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: queue,
                                                 currentID: queue[1].id,
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order, [1, 0, 2])
        XCTAssertEqual(Set(order), Set([0, 1, 2]))
    }

    func testWeightedLoopCycleStartsAfterExhaustionWithRecentlyPlayedLast() {
        let queue = items(["first.mov", "second.mov", "third.mov"],
                          lastPlayed: [
                            "first.mov": 1,
                            "second.mov": 2,
                            "third.mov": 3,
                          ])
        let order = QueueOrderPlanner.cycleOrder(mode: .weighted,
                                                 items: queue,
                                                 avoidingFirstID: queue[2].id,
                                                 randomInt: { _ in 0 })
        XCTAssertEqual(order, [0, 1, 2])
    }

    func testEmptyAndSingleItemQueuesAreSafe() {
        XCTAssertEqual(QueueOrderPlanner.cycleOrder(mode: .shuffle, items: [], randomInt: { _ in 0 }), [])
        XCTAssertEqual(QueueOrderPlanner.cycleOrder(mode: .weighted, items: items(["only.mov"]), randomInt: { _ in 0 }), [0])
    }

    func testQueueMutationResetIncludesNewItems() {
        let original = items(["a.mov", "b.mov"])
        let originalOrder = QueueOrderPlanner.cycleOrder(mode: .shuffle, items: original, randomInt: { _ in 0 })
        XCTAssertEqual(Set(originalOrder), Set([0, 1]))

        let mutated = items(["a.mov", "b.mov", "c.mov"])
        let resetOrder = QueueOrderPlanner.cycleOrder(mode: .shuffle, items: mutated, randomInt: { _ in 0 })
        XCTAssertEqual(Set(resetOrder), Set([0, 1, 2]))
    }
}
