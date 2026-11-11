import XCTest

final class QueueEmptyStatePresentationTests: XCTestCase {

    func testRowsVisibleMeansNoEmptyState() {
        XCTAssertNil(QueueEmptyState.resolve(itemCount: 3, visibleCount: 2, query: "a", bookmarkFilterEnabled: false))
    }

    func testEmptyQueue() {
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 0, visibleCount: 0, query: "", bookmarkFilterEnabled: false),
                       .emptyQueue)
        // An empty queue stays an empty queue even with a stale filter.
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 0, visibleCount: 0, query: "x", bookmarkFilterEnabled: true),
                       .emptyQueue)
    }

    func testSearchWithNoMatches() {
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 3, visibleCount: 0, query: "zzz", bookmarkFilterEnabled: false),
                       .noMatches)
    }

    func testBookmarkFilterAloneWithNoBookmarks() {
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 3, visibleCount: 0, query: "", bookmarkFilterEnabled: true),
                       .noBookmarks)
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 3, visibleCount: 0, query: "  ", bookmarkFilterEnabled: true),
                       .noBookmarks)
    }

    func testSearchWinsWhenBothFiltersAreOn() {
        XCTAssertEqual(QueueEmptyState.resolve(itemCount: 3, visibleCount: 0, query: "zzz", bookmarkFilterEnabled: true),
                       .noMatches)
    }

    func testFilteredStatesUseTheDesignSystemTitleAndButton() {
        XCTAssertEqual(QueueEmptyState.noMatches.title, "No matching files")
        XCTAssertEqual(QueueEmptyState.noMatches.actionTitle, "Clear Search")
        XCTAssertEqual(QueueEmptyState.noBookmarks.title, "No bookmarked media")
        XCTAssertEqual(QueueEmptyState.noBookmarks.actionTitle, "Show All Media")
    }

    func testFilteredStatesUseTheNeutralGlyphs() {
        XCTAssertEqual(QueueEmptyState.noMatches.glyphName, "magnifyingglass")
        XCTAssertEqual(QueueEmptyState.noBookmarks.glyphName, "bookmark.slash")
        // The empty queue shows the app icon instead of a glyph.
        XCTAssertNil(QueueEmptyState.emptyQueue.glyphName)
    }

    func testEmptyQueueKeepsSkimsExistingText() {
        XCTAssertEqual(QueueEmptyState.emptyQueue.title, "No media in queue")
        XCTAssertEqual(QueueEmptyState.emptyQueue.detail, "Add files or folders to build the queue.")
        XCTAssertEqual(QueueEmptyState.emptyQueue.actionTitle, "Add Media")
    }
}
