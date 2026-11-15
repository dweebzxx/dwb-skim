import AppKit
import XCTest

/// The status row's total (design system 10.5): "111:32:18 · 280 items" → "111:32:18" → "111h 32m", fitted to the center cell
/// minus 16 pt with real native font measurement. The classic wrap plan (`markerGroupPlan`) and the "Total: … | …" text
/// are retired with the classic footer.
final class QueueTotalPresentationTests: XCTestCase {

    private func measure(_ text: String) -> CGFloat {
        QueueFonts.width(of: text, font: QueueFonts.total)
    }

    private func fit(_ duration: String, count: String = "280 items", width: CGFloat) -> String {
        QueueTotalPresentation.fit(durationText: duration, countText: count, availableWidth: width, measure: measure)
    }

    // MARK: - Parsing

    func testParsesKnownPartialAndUnknownTotals() {
        XCTAssertEqual(QueueTotalPresentation.parse("00:12:34"), .init(seconds: 754, isPartial: false))
        XCTAssertEqual(QueueTotalPresentation.parse("111:32:18"), .init(seconds: 111 * 3600 + 32 * 60 + 18, isPartial: false))
        XCTAssertEqual(QueueTotalPresentation.parse("01:00:00 +"), .init(seconds: 3600, isPartial: true))
        XCTAssertEqual(QueueTotalPresentation.parse("--:--"), .init(seconds: nil, isPartial: false))
        XCTAssertEqual(QueueTotalPresentation.parse("garbage"), .init(seconds: nil, isPartial: false))
    }

    func testParsesHugeValues() {
        XCTAssertEqual(QueueTotalPresentation.parse("99999:59:59").seconds, 99_999 * 3600 + 59 * 60 + 59)
        XCTAssertEqual(QueueTotalPresentation.parse("1234:05:06 +"), .init(seconds: 1234 * 3600 + 5 * 60 + 6, isPartial: true))
    }

    // MARK: - Count text

    func testCountTextForTheWholeQueue() {
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 280, visibleCount: 280, isFiltered: false), "280 items")
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 1, visibleCount: 1, isFiltered: false), "1 item")
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 0, visibleCount: 0, isFiltered: false), "0 items")
    }

    func testFilteredCountReadsVisibleOfTotal() {
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 280, visibleCount: 12, isFiltered: true), "12 of 280 items")
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 280, visibleCount: 0, isFiltered: true), "0 of 280 items")
        XCTAssertEqual(QueueTotalPresentation.countText(itemCount: 1, visibleCount: 1, isFiltered: true), "1 of 1 item")
    }

    func testFilteringNeverChangesTheDurationShown() {
        // The duration comes from the window's whole-queue total; only the count follows the filter.
        let count = QueueTotalPresentation.countText(itemCount: 280, visibleCount: 12, isFiltered: true)
        let all = QueueTotalPresentation.candidates(durationText: "111:32:18", countText: count)
        XCTAssertEqual(all[0], "111:32:18 · 12 of 280 items")
        XCTAssertEqual(all[1], "111:32:18")
    }

    // MARK: - Candidates

    func testCandidatesShortenInTheDocumentedOrder() {
        XCTAssertEqual(QueueTotalPresentation.candidates(durationText: "111:32:18", countText: "280 items"),
                       ["111:32:18 · 280 items", "111:32:18", "111h 32m", "111h"])
    }

    func testPartialTotalsKeepTheirPlusInEveryCandidate() {
        let all = QueueTotalPresentation.candidates(durationText: "01:02:03 +", countText: "5 items")
        XCTAssertEqual(all, ["01:02:03 + · 5 items", "01:02:03 +", "1h 2m +", "1h +"])
        XCTAssertTrue(all.allSatisfy { $0.contains("+") })
    }

    func testAllUnknownTotalsStayDashesAndAreNeverShownAsZero() {
        let all = QueueTotalPresentation.candidates(durationText: "--:--", countText: "5 items")
        XCTAssertEqual(all, ["--:-- · 5 items", "--:--"])
        XCTAssertFalse(all.contains { $0.contains("0h") || $0.contains("00:00") })
    }

    func testAnEmptyQueueIsAKnownZero() {
        XCTAssertEqual(QueueTotalPresentation.candidates(durationText: "00:00:00", countText: "0 items"),
                       ["00:00:00 · 0 items", "00:00:00", "0h 0m", "0h"])
    }

    func testFullTextForTheTooltipAndAccessibilityValue() {
        XCTAssertEqual(QueueTotalPresentation.fullText(durationText: "111:32:18", countText: "280 items"),
                       "Total: 111:32:18 · 280 items")
        XCTAssertEqual(QueueTotalPresentation.fullText(durationText: "01:00:00 +", countText: "12 of 280 items"),
                       "Total: 01:00:00 + · 12 of 280 items")
        XCTAssertEqual(QueueTotalPresentation.fullText(durationText: "--:--", countText: "3 items"),
                       "Total: --:-- · 3 items")
    }

    // MARK: - Fitting (real font measurement)

    func testTheFullCandidateWinsWhenItFits() {
        let full = "111:32:18 · 280 items"
        XCTAssertEqual(fit("111:32:18", width: measure(full)), full)
        XCTAssertEqual(fit("111:32:18", width: 400), full)
    }

    func testEachStepDownIsTakenExactlyWhenTheCandidateStopsFitting() {
        let all = QueueTotalPresentation.candidates(durationText: "111:32:18", countText: "280 items")
        for candidate in all.dropLast() {
            // One point narrower than this candidate: the result is the first later candidate that fits.
            let width = measure(candidate) - 1
            let expected = all.first { measure($0) <= width } ?? all[all.count - 1]
            XCTAssertEqual(fit("111:32:18", width: width), expected, "width \(width)")
            XCTAssertNotEqual(fit("111:32:18", width: width), candidate)
        }
        // The count is always the first thing dropped.
        XCTAssertLessThan(measure(all[1]), measure(all[0]))
    }

    func testNothingFittingFallsBackToTheShortestKnownForm() {
        XCTAssertEqual(fit("111:32:18", width: 1), "111h")
        XCTAssertEqual(fit("--:--", width: 1), "--:--")
    }

    func testActualCenterCellAtTheCompactPanelMinimum() {
        // 199 pt inner width: the center cell is 199 - 34 - 34 = 131 pt, so 115 pt for the text.
        let footer = QueueFooterLayout.make(width: 199)
        XCTAssertEqual(footer.totalCell.width, 131)
        XCTAssertEqual(footer.totalFitWidth, 115)
        let shown = fit("111:32:18", width: footer.totalFitWidth)
        XCTAssertLessThanOrEqual(measure(shown), footer.totalFitWidth, "real measurement, not a constant")
        XCTAssertTrue(shown.hasPrefix("111:32:18"), "the duration is never dropped before the count")
    }

    func testHugeTotalsAndCountsStillFitTheCompactMinimum() {
        let footer = QueueFooterLayout.make(width: 199)
        let count = QueueTotalPresentation.countText(itemCount: 123_456, visibleCount: 98_765, isFiltered: true)
        for duration in ["99999:59:59", "99999:59:59 +", "--:--", "00:00:00"] {
            let shown = fit(duration, count: count, width: footer.totalFitWidth)
            XCTAssertLessThanOrEqual(measure(shown), footer.totalFitWidth, "\(duration) → \(shown)")
        }
        XCTAssertTrue(fit("99999:59:59 +", count: count, width: footer.totalFitWidth).contains("+"),
                      "uncertainty survives shortening")
    }

    func testTheCenterCellGrowsWithThePanel() {
        // Outer widths 260, 280, 335, 360 (inner 259…359) all keep the full duration.
        for inner: CGFloat in [259, 279, 334, 359] {
            let footer = QueueFooterLayout.make(width: inner)
            let shown = fit("12:34:56", width: footer.totalFitWidth)
            XCTAssertLessThanOrEqual(measure(shown), footer.totalFitWidth)
            XCTAssertTrue(shown.hasPrefix("12:34:56"))
        }
    }
}
