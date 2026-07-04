import Foundation
import XCTest

final class PlaybackCompletionPolicyTests: XCTestCase {

    func testRepeatOneReturnsRepeatCurrent() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityOverEndlessShuffle() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testRepeatOneTakesPriorityWhenMidQueue() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: true,
            currentDisplayIndex: 0,
            displayOrderCount: 3,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .repeatCurrent)
    }

    func testMidQueueReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 1,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testFirstOfTwoItemsReturnsPlayNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 2,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }

    func testLastItemNoEndlessReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testSingleItemQueueNoModifiersReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isEndlessShuffleOn: false,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testEndlessShuffleWithItemsReturnsEndlessShuffleNext() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 4,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .endlessShuffleNext)
    }

    func testEndlessShuffleEmptyQueueReturnsStopLastItem() {
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 0,
            displayOrderCount: 1,
            isEndlessShuffleOn: true,
            queueIsEmpty: true
        )
        XCTAssertEqual(policy.action, .stopLastItem)
    }

    func testEndlessShuffleMidQueueStillAdvancesNormally() {
        // Endless shuffle only fires when at the last item; mid-queue uses playNext.
        let policy = PlaybackCompletionPolicy(
            isRepeatOne: false,
            currentDisplayIndex: 2,
            displayOrderCount: 5,
            isEndlessShuffleOn: true,
            queueIsEmpty: false
        )
        XCTAssertEqual(policy.action, .playNext)
    }
}
