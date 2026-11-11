import XCTest

final class QueueFooterPresentationTests: XCTestCase {

    // A representative footer: Remove 26 pt, group 240 pt (full Undo) or 180 pt (glyph-only Undo), 8 pt gap.
    private func plan(available: CGFloat,
                      remove: CGFloat = 26,
                      full: CGFloat = 240,
                      compact: CGFloat = 180,
                      gap: CGFloat = 8) -> QueueFooterPresentation.MarkerGroupPlan {
        QueueFooterPresentation.markerGroupPlan(availableWidth: available,
                                                removeWidth: remove,
                                                fullGroupWidth: full,
                                                compactGroupWidth: compact,
                                                itemGap: gap)
    }

    // MARK: - Marker group plan (R9)

    func testWideRowKeepsRemoveAndTheFullGroupOnOneRow() {
        XCTAssertEqual(plan(available: 400), .sharedRow)
    }

    func testBoundaryWhereTheFullGroupStopsFitting() {
        // 26 + 8 + 240 = 274 is the widest row that still fits the full group.
        XCTAssertEqual(plan(available: 274), .sharedRow)
        XCTAssertEqual(plan(available: 273.5), .sharedRowCompactUndo)
    }

    func testMediumRowKeepsOneRowWithGlyphOnlyUndo() {
        XCTAssertEqual(plan(available: 250), .sharedRowCompactUndo)
    }

    func testBoundaryWhereTheCompactGroupStopsFitting() {
        // 26 + 8 + 180 = 214.
        XCTAssertEqual(plan(available: 214), .sharedRowCompactUndo)
        XCTAssertEqual(plan(available: 213.5), .ownRow(compactUndo: true))
    }

    func testNarrowRowWrapsTheGroupBelowRemoveWithGlyphOnlyUndoWhenTheFullGroupDoesNotFitItsRow() {
        XCTAssertEqual(plan(available: 200), .ownRow(compactUndo: true))
    }

    func testWrappedGroupKeepsFullUndoWhenItFitsItsOwnRow() {
        // A wide Remove button keeps even the glyph-only group off Remove's row (100 + 8 + 180 = 288),
        // but the 240 pt full group fits a 240 pt row on its own.
        XCTAssertEqual(plan(available: 240, remove: 100), .ownRow(compactUndo: false))
        XCTAssertEqual(plan(available: 239, remove: 100), .ownRow(compactUndo: true))
    }

    func testPlanFlagsFollowThePlacement() {
        XCTAssertFalse(QueueFooterPresentation.MarkerGroupPlan.sharedRow.isUndoCompact)
        XCTAssertFalse(QueueFooterPresentation.MarkerGroupPlan.sharedRow.wrapsMarkerGroup)
        XCTAssertTrue(QueueFooterPresentation.MarkerGroupPlan.sharedRowCompactUndo.isUndoCompact)
        XCTAssertFalse(QueueFooterPresentation.MarkerGroupPlan.sharedRowCompactUndo.wrapsMarkerGroup)
        XCTAssertFalse(QueueFooterPresentation.MarkerGroupPlan.ownRow(compactUndo: false).isUndoCompact)
        XCTAssertTrue(QueueFooterPresentation.MarkerGroupPlan.ownRow(compactUndo: false).wrapsMarkerGroup)
        XCTAssertTrue(QueueFooterPresentation.MarkerGroupPlan.ownRow(compactUndo: true).isUndoCompact)
    }

    // MARK: - Highlight shape

    func testMarkerGroupHighlightsUseThePillRadiusOfTheGroupOutline() {
        // The group outline, the applied chip fill and edge, the chip hover fill and Undo's hover fill
        // all read this one constant, so they cannot drift to the control radius (6).
        XCTAssertEqual(QueueFooterPresentation.markerGroupCornerRadius, DWBMetrics.radiusPill)
        XCTAssertEqual(QueueFooterPresentation.markerGroupCornerRadius, 12)
        XCTAssertNotEqual(QueueFooterPresentation.markerGroupCornerRadius, DWBMetrics.radiusControl)
    }

    // MARK: - Total text (R10)

    func testEmptyQueueReadsZeroItems() {
        XCTAssertEqual(QueueFooterPresentation.totalText(duration: "00:00:00", itemCount: 0,
                                                         visibleCount: 0, isFiltered: false),
                       "Total: 00:00:00 | 0 items")
    }

    func testOneItemIsSingular() {
        XCTAssertEqual(QueueFooterPresentation.totalText(duration: "00:01:05", itemCount: 1,
                                                         visibleCount: 1, isFiltered: false),
                       "Total: 00:01:05 | 1 item")
    }

    func testSeveralItemsArePlural() {
        XCTAssertEqual(QueueFooterPresentation.totalText(duration: "01:02:03", itemCount: 12,
                                                         visibleCount: 12, isFiltered: false),
                       "Total: 01:02:03 | 12 items")
    }

    func testFilteredQueueReadsVisibleOverTotalShown() {
        XCTAssertEqual(QueueFooterPresentation.totalText(duration: "01:02:03", itemCount: 12,
                                                         visibleCount: 3, isFiltered: true),
                       "Total: 01:02:03 | 3/12 shown")
    }

    func testFilteredWithNoMatchesReadsZeroShown() {
        XCTAssertEqual(QueueFooterPresentation.totalText(duration: "00:05:00", itemCount: 4,
                                                         visibleCount: 0, isFiltered: true),
                       "Total: 00:05:00 | 0/4 shown")
    }
}
