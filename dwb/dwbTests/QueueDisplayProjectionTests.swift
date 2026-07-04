import Foundation
import XCTest

final class QueueDisplayProjectionTests: XCTestCase {

    // Minimal stand-in for queue items — no AppKit dependency required.
    private struct Item {
        let displayName: String
        let path: String
    }

    private func makeItems(_ names: [(String, String)]) -> [Item] {
        names.map { Item(displayName: $0.0, path: $0.1) }
    }

    private func filteredPairs(
        from items: [Item],
        query: String,
        bookmarkedPaths: Set<String> = [],
        bookmarkFilterEnabled: Bool = false
    ) -> [(Int, Item)] {
        QueueDisplayProjection.filteredPairs(
            from: items,
            displayName: \.displayName,
            urlPath: \.path,
            query: query,
            bookmarkedPaths: bookmarkedPaths,
            bookmarkFilterEnabled: bookmarkFilterEnabled
        )
    }

    // MARK: - filteredPairs — search

    func testEmptyQueryReturnsAll() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b"), ("gamma.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "")
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs.map(\.0), [0, 1, 2])
    }

    func testQueryFiltersToMatchingItems() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b"), ("alphabet.mov", "/c")])
        let pairs = filteredPairs(from: items, query: "alpha")
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 0) // alpha.mp4 at display index 0
        XCTAssertEqual(pairs[1].0, 2) // alphabet.mov at display index 2
    }

    func testQueryIsCaseInsensitive() {
        let items = makeItems([("MOVIE.mp4", "/a"), ("movie.mp4", "/b"), ("other.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "movie")
        XCTAssertEqual(pairs.count, 2)
    }

    func testQueryMatchesNone() {
        let items = makeItems([("alpha.mp4", "/a"), ("beta.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "zzz")
        XCTAssertTrue(pairs.isEmpty)
    }

    func testQueryOnEmptyItemsReturnsEmpty() {
        let pairs = filteredPairs(from: [], query: "anything")
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - filteredPairs — bookmark filter

    func testBookmarkFilterDisabledReturnsAll() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: ["/a"], bookmarkFilterEnabled: false)
        XCTAssertEqual(pairs.count, 2)
    }

    func testBookmarkFilterEnabledReturnsOnlyBookmarked() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b"), ("c.mp4", "/c")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: ["/b", "/c"], bookmarkFilterEnabled: true)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 1)
        XCTAssertEqual(pairs[1].0, 2)
    }

    func testBookmarkFilterEnabledWithNoBookmarksReturnsEmpty() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b")])
        let pairs = filteredPairs(from: items, query: "", bookmarkedPaths: [], bookmarkFilterEnabled: true)
        XCTAssertTrue(pairs.isEmpty)
    }

    // MARK: - filteredPairs — combined search + bookmark filter

    func testCombinedSearchAndBookmarkFilter() {
        let items = makeItems([
            ("alpha.mp4", "/a"),
            ("alpha_bookmarked.mp4", "/b"),
            ("beta.mp4", "/c"),
        ])
        let pairs = filteredPairs(
            from: items,
            query: "alpha",
            bookmarkedPaths: ["/b"],
            bookmarkFilterEnabled: true
        )
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, 1)
        XCTAssertEqual(pairs[0].1.displayName, "alpha_bookmarked.mp4")
    }

    // MARK: - filteredPairs — display index stability

    func testDisplayIndicesReflectOriginalPosition() {
        let items = makeItems([("a.mp4", "/a"), ("b.mp4", "/b"), ("c.mp4", "/c"), ("d.mp4", "/d")])
        let pairs = filteredPairs(from: items, query: "b")
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].0, 1) // "b.mp4" is at original index 1
    }

    // MARK: - allowsManualReorder

    func testAllowsReorderWhenManualSortAndNoFilters() {
        XCTAssertTrue(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenNotManualSort() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: false, query: "", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenQueryActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "foo", bookmarkFilterEnabled: false
        ))
    }

    func testDisallowsReorderWhenBookmarkFilterActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "", bookmarkFilterEnabled: true
        ))
    }

    func testDisallowsReorderWhenBothFiltersActive() {
        XCTAssertFalse(QueueDisplayProjection.allowsManualReorder(
            isManualSort: true, query: "foo", bookmarkFilterEnabled: true
        ))
    }
}
