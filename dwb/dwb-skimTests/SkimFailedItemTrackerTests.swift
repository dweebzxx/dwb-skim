import XCTest

final class SkimFailedItemTrackerTests: XCTestCase {

    // MARK: - Marking

    func testItemIsNotFailedByDefault() {
        let tracker = SkimFailedItemTracker()
        XCTAssertFalse(tracker.isFailed("a"))
    }

    func testMarkFailedRecordsItem() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        XCTAssertTrue(tracker.isFailed("a"))
    }

    func testMarkFailedReturnsTrueOnlyOnFirstMark() {
        var tracker = SkimFailedItemTracker()
        XCTAssertTrue(tracker.markFailed("a"))
        XCTAssertFalse(tracker.markFailed("a"))
        XCTAssertFalse(tracker.markFailed("a"))
    }

    func testMultipleFailedItemsAreTrackedIndependently() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("c")
        XCTAssertTrue(tracker.isFailed("a"))
        XCTAssertFalse(tracker.isFailed("b"))
        XCTAssertTrue(tracker.isFailed("c"))
    }

    // MARK: - Suppression / explicit retry

    func testClearFailedAllowsRetryOfOneItemOnly() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("b")
        tracker.clearFailed("a")
        XCTAssertFalse(tracker.isFailed("a"))
        XCTAssertTrue(tracker.isFailed("b"))
    }

    func testClearFailedOnNeverFailedItemIsNoOp() {
        var tracker = SkimFailedItemTracker()
        tracker.clearFailed("a")
        XCTAssertFalse(tracker.isFailed("a"))
    }

    // MARK: - Session scope

    func testResetClearsAllFailuresForNewSession() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("b")
        tracker.reset()
        XCTAssertFalse(tracker.isFailed("a"))
        XCTAssertFalse(tracker.isFailed("b"))
        XCTAssertTrue(tracker.failedItemIDs.isEmpty)
    }

    // MARK: - All-failed queue

    func testAllFailedIsFalseForEmptyCandidateList() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        XCTAssertFalse(tracker.allFailed(among: []))
    }

    func testAllFailedIsFalseWhenAtLeastOneCandidateIsPlayable() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("b")
        XCTAssertFalse(tracker.allFailed(among: ["a", "b", "c"]))
    }

    func testAllFailedIsTrueWhenEveryCandidateIsMarked() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("b")
        tracker.markFailed("c")
        XCTAssertTrue(tracker.allFailed(among: ["a", "b", "c"]))
    }

    func testAllFailedAfterExplicitRetryClearsIsFalse() {
        var tracker = SkimFailedItemTracker()
        tracker.markFailed("a")
        tracker.markFailed("b")
        tracker.clearFailed("a")
        XCTAssertFalse(tracker.allFailed(among: ["a", "b"]))
    }
}
