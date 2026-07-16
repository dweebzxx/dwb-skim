import Foundation
import XCTest

final class PlaybackCompletionPolicyTests: XCTestCase {

    func testRepeatOneReturnsRepeatCurrent() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityOverLoopQueue() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isLoopQueueEnabled: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityWhenMidQueue() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 0,
            displayOrderCount: 3,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testMidQueueReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 1,
            displayOrderCount: 5,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testFirstOfTwoItemsReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 2,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testLastItemNoEndlessReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testSingleItemQueueNoModifiersReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isLoopQueueEnabled: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testLoopQueueWithItemsReturnsLoopQueueNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isLoopQueueEnabled: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .loopQueueNext)
    }

    func testLoopQueueEmptyQueueReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isLoopQueueEnabled: true,
            queueIsEmpty: true
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testLoopQueueMidQueueStillAdvancesNormally() {
        // loop queue only fires when at the last item; mid-queue uses playNext.
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isLoopQueueEnabled: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }
}
