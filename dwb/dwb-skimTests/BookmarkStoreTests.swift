import Foundation
import XCTest

final class BookmarkStoreTests: XCTestCase {

    private var store: BookmarkStore!
    private var defaults: UserDefaults!
    private let suiteName = "com.dwb.skimTests.BookmarkStoreTests"
    private let key = "testBookmarkedPaths"

    override func setUp() {
        super.setUp()
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
        store = BookmarkStore(defaults: defaults, key: key)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Toggle

    func testToggleAddsBookmark() {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        XCTAssertFalse(store.isBookmarked(url: url))
        store.toggleBookmark(url: url)
        XCTAssertTrue(store.isBookmarked(url: url))
    }

    func testToggleRemovesExistingBookmark() {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        store.toggleBookmark(url: url)
        XCTAssertTrue(store.isBookmarked(url: url))
        store.toggleBookmark(url: url)
        XCTAssertFalse(store.isBookmarked(url: url))
    }

    func testMultipleBookmarks() {
        let a = URL(fileURLWithPath: "/tmp/a.mp4")
        let b = URL(fileURLWithPath: "/tmp/b.mp4")
        store.toggleBookmark(url: a)
        store.toggleBookmark(url: b)
        XCTAssertTrue(store.isBookmarked(url: a))
        XCTAssertTrue(store.isBookmarked(url: b))
        XCTAssertEqual(store.bookmarkedPaths().count, 2)
    }

    // MARK: - Persistence

    func testBookmarksPersistedToDefaults() {
        let url = URL(fileURLWithPath: "/tmp/persist.mp4")
        store.toggleBookmark(url: url)
        let stored = defaults.stringArray(forKey: key) ?? []
        XCTAssertFalse(stored.isEmpty, "Path should be persisted to UserDefaults")
    }

    // MARK: - clearAll

    func testClearAllEmptiesStore() {
        let a = URL(fileURLWithPath: "/tmp/a.mp4")
        let b = URL(fileURLWithPath: "/tmp/b.mp4")
        store.toggleBookmark(url: a)
        store.toggleBookmark(url: b)
        XCTAssertEqual(store.bookmarkedPaths().count, 2)
        store.clearAll()
        XCTAssertTrue(store.bookmarkedPaths().isEmpty)
    }

    func testClearAllRemovesFromDefaults() {
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        store.toggleBookmark(url: url)
        store.clearAll()
        let stored = defaults.stringArray(forKey: key) ?? []
        XCTAssertTrue(stored.isEmpty, "Defaults should be empty after clearAll")
    }

    func testClearAllOnEmptyStoreIsNoop() {
        XCTAssertTrue(store.bookmarkedPaths().isEmpty)
        store.clearAll()
        XCTAssertTrue(store.bookmarkedPaths().isEmpty)
    }

    func testClearAllPostsNotification() {
        let expectation = XCTestExpectation(description: "bookmarkDidChange posted")
        let observer = NotificationCenter.default.addObserver(
            forName: .bookmarkDidChange,
            object: nil,
            queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.clearAll()
        wait(for: [expectation], timeout: 1.0)
    }

    func testClearAllDoesNotAffectOtherKeys() {
        defaults.set(["sentinel"], forKey: "unrelatedKey")
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        store.toggleBookmark(url: url)
        store.clearAll()
        let sentinel = defaults.stringArray(forKey: "unrelatedKey")
        XCTAssertEqual(sentinel, ["sentinel"], "clearAll must not touch unrelated defaults keys")
    }
}
