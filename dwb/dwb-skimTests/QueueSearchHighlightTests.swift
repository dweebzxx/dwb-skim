import XCTest

final class QueueSearchHighlightTests: XCTestCase {

    private func match(_ name: String, _ query: String) -> String? {
        QueueSearchHighlight.matchRange(in: name, query: query).map { (name as NSString).substring(with: $0) }
    }

    func testFirstMatchIsFound() {
        let range = QueueSearchHighlight.matchRange(in: "holiday_holiday.mp4", query: "holiday")
        XCTAssertEqual(range, NSRange(location: 0, length: 7))
    }

    func testMatchIsCaseInsensitiveAndKeepsTheNamesSpelling() {
        XCTAssertEqual(match("Beach_Day.MP4", "beach"), "Beach")
        XCTAssertEqual(match("beach_day.mp4", "DAY"), "day")
    }

    func testMatchIsDiacriticInsensitiveLikeTheQueueFilter() {
        XCTAssertEqual(match("café.mp4", "cafe"), "café")
    }

    func testBlankQueryHasNoMatch() {
        XCTAssertNil(QueueSearchHighlight.matchRange(in: "a.mp4", query: ""))
        XCTAssertNil(QueueSearchHighlight.matchRange(in: "a.mp4", query: "   "))
    }

    func testAbsentQueryHasNoMatch() {
        XCTAssertNil(QueueSearchHighlight.matchRange(in: "a.mp4", query: "zzz"))
    }

    func testQueryIsTrimmed() {
        XCTAssertEqual(match("a.mp4", " mp4 "), "mp4")
    }

    func testEveryRowTheFilterKeepsHasAMatch() {
        let names = ["Holiday.mp4", "résumé.mov", "x.gif"]
        for query in ["holiday", "RESUME", "gif"] {
            let kept = QueueDisplayProjection.filteredPairs(from: names,
                                                            displayName: { $0 },
                                                            urlPath: { $0 },
                                                            query: query,
                                                            bookmarkedPaths: [],
                                                            bookmarkFilterEnabled: false)
            XCTAssertFalse(kept.isEmpty, query)
            for (_, name) in kept {
                XCTAssertNotNil(QueueSearchHighlight.matchRange(in: name, query: query), "\(query) in \(name)")
            }
        }
    }
}
