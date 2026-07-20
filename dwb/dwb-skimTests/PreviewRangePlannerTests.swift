import XCTest

final class PreviewRangePlannerTests: XCTestCase {
    func testRangePreservesConfiguredDuration() throws {
        let range = try XCTUnwrap(PreviewRangePlanner.range(startSeconds: 58,
                                                            previewDurationSeconds: 10,
                                                            totalDurationSeconds: 120))
        XCTAssertEqual(range.startSeconds, 58)
        XCTAssertEqual(range.endSeconds, 68)
        XCTAssertEqual(range.durationSeconds, 10)
    }

    func testRangeClampsAtMediaEnd() throws {
        let range = try XCTUnwrap(PreviewRangePlanner.range(startSeconds: 118,
                                                            previewDurationSeconds: 10,
                                                            totalDurationSeconds: 120))
        XCTAssertEqual(range.startSeconds, 118)
        XCTAssertEqual(range.endSeconds, 120)
        XCTAssertEqual(range.durationSeconds, 2)
    }

    func testRelocationUsesFullTrackAndClampsSafely() throws {
        let middle = try XCTUnwrap(PreviewRangePlanner.relocated(normalizedStart: 0.5,
                                                                 preservingDurationSeconds: 15,
                                                                 totalDurationSeconds: 100))
        XCTAssertEqual(middle.startSeconds, 50)
        XCTAssertEqual(middle.endSeconds, 65)
        let end = try XCTUnwrap(PreviewRangePlanner.relocated(normalizedStart: 1,
                                                              preservingDurationSeconds: 15,
                                                              totalDurationSeconds: 100))
        XCTAssertEqual(end.startSeconds, 99.75)
        XCTAssertEqual(end.endSeconds, 100)
    }

    func testFullFileSemanticsUseRemainingDuration() throws {
        let range = try XCTUnwrap(PreviewRangePlanner.relocated(normalizedStart: 0.25,
                                                                 preservingDurationSeconds: nil,
                                                                 totalDurationSeconds: 80))
        XCTAssertEqual(range.startSeconds, 20)
        XCTAssertEqual(range.endSeconds, 80)
    }

    func testInvalidDurationHasNoSeekRange() {
        XCTAssertNil(PreviewRangePlanner.range(startSeconds: 0, previewDurationSeconds: 10, totalDurationSeconds: 0))
        XCTAssertNil(PreviewRangePlanner.range(startSeconds: 0, previewDurationSeconds: 10, totalDurationSeconds: .nan))
    }
}
