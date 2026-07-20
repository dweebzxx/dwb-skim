import XCTest

final class PlaybackCompletionPolicyTests: XCTestCase {
    func testMidQueueAdvances() {
        XCTAssertEqual(policy(index: 1, count: 5, loop: false).action, .playNext)
    }

    func testLastItemStopsWithoutLoopQueue() {
        XCTAssertEqual(policy(index: 4, count: 5, loop: false).action, .stopLastItem)
    }

    func testSingleItemStopsWithoutLoopQueue() {
        XCTAssertEqual(policy(index: 0, count: 1, loop: false).action, .stopLastItem)
    }

    func testLastItemLoopsQueue() {
        XCTAssertEqual(policy(index: 4, count: 5, loop: true).action, .loopQueueNext)
    }

    func testLoopQueueDoesNotOverrideMidQueueAdvance() {
        XCTAssertEqual(policy(index: 2, count: 5, loop: true).action, .playNext)
    }

    func testEmptyQueueNeverLoops() {
        let result = PlaybackCompletionPolicy(currentDisplayIndex: 0,
                                              displayOrderCount: 1,
                                              isLoopQueueEnabled: true,
                                              queueIsEmpty: true)
        XCTAssertEqual(result.action, .stopLastItem)
    }

    private func policy(index: Int, count: Int, loop: Bool) -> PlaybackCompletionPolicy {
        PlaybackCompletionPolicy(currentDisplayIndex: index,
                                 displayOrderCount: count,
                                 isLoopQueueEnabled: loop,
                                 queueIsEmpty: false)
    }
}
