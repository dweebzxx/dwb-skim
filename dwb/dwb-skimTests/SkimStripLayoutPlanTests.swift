import XCTest

final class SkimStripLayoutPlanTests: XCTestCase {
    private typealias Metrics = SkimStripLayoutPlan.Metrics

    /// Group widths measured from the AppKit controls in Random duration mode, in row order, with a
    /// divider before Image duration and before Queue order.
    private let groupWidths: [CGFloat] = [254, 151, 60, 79, 58, 104, 62, 88]
    private let leadingDividers: Set<Int> = [3, 5]

    private var advances: [CGFloat] {
        groupWidths.enumerated().map { index, width in
            SkimStripLayoutPlan.advance(groupWidth: width,
                                        leadingDivider: leadingDividers.contains(index),
                                        isFirst: index == 0)
        }
    }

    private var reserved: CGFloat {
        Metrics.leadingInset + Metrics.trailingInset + Metrics.collapseControl + Metrics.trailingGap
    }

    private var overflowSlot: CGFloat { Metrics.overflowControl + Metrics.trailingControlGap }

    func testAdvanceCountsGapAndLeadingDividerExceptForTheFirstGroup() {
        XCTAssertEqual(SkimStripLayoutPlan.advance(groupWidth: 100, leadingDivider: false, isFirst: true), 100)
        XCTAssertEqual(SkimStripLayoutPlan.advance(groupWidth: 100, leadingDivider: true, isFirst: true), 100)
        XCTAssertEqual(SkimStripLayoutPlan.advance(groupWidth: 100, leadingDivider: false, isFirst: false), 118)
        XCTAssertEqual(SkimStripLayoutPlan.advance(groupWidth: 100, leadingDivider: true, isFirst: false), 137)
    }

    func testWideStripKeepsEveryGroupInTheFullRow() {
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 1_400)
        XCTAssertEqual(plan.visibleCount, groupWidths.count)
        XCTAssertFalse(plan.hasOverflow)
    }

    func testRowStaysFullAtTheExactFitWidthAndOverflowsOnePointNarrower() {
        let exact = advances.reduce(0, +) + reserved
        XCTAssertFalse(SkimStripLayoutPlan.make(advances: advances, stripWidth: exact).hasOverflow)
        XCTAssertTrue(SkimStripLayoutPlan.make(advances: advances, stripWidth: exact - 1).hasOverflow)
    }

    func testMinimumWindowWidthMovesOnlyTheTrailingGroupsAndKeepsOrder() {
        // 980 pt is the player window's minimum content width; the Random-mode row needs 1,092 pt.
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 980)
        XCTAssertTrue(plan.hasOverflow)
        XCTAssertEqual(plan.visibleCount, 6)
        XCTAssertEqual(plan.overflowCount, 2)
    }

    func testNarrowerStripMovesMoreTrailingGroupsIntoOverflow() {
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 700)
        XCTAssertEqual(plan.visibleCount + plan.overflowCount, groupWidths.count)
        XCTAssertLessThan(plan.visibleCount, 6)
        XCTAssertGreaterThan(plan.visibleCount, 0)
    }

    func testNothingFittingStillLeavesEverySettingReachableInOverflow() {
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 120)
        XCTAssertEqual(plan.visibleCount, 0)
        XCTAssertEqual(plan.overflowCount, groupWidths.count)
        XCTAssertTrue(plan.hasOverflow)
    }

    func testVisibleGroupsNeverReachIntoTheTrailingSlotAtAnyWidth() {
        let advances = self.advances
        for width in stride(from: CGFloat(0), through: 1_500, by: 1) {
            let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: width)
            XCTAssertEqual(plan.visibleCount + plan.overflowCount, advances.count, "width \(width)")
            guard plan.visibleCount > 0 else { continue }
            let used = advances[0..<plan.visibleCount].reduce(0, +)
            let room = width - reserved - (plan.hasOverflow ? overflowSlot : 0)
            XCTAssertLessThanOrEqual(used, room, "width \(width)")
        }
    }

    func testWiderStripNeverKeepsFewerGroupsInTheRow() {
        let advances = self.advances
        var previous = 0
        for width in stride(from: CGFloat(0), through: 1_500, by: 1) {
            let visible = SkimStripLayoutPlan.make(advances: advances, stripWidth: width).visibleCount
            XCTAssertGreaterThanOrEqual(visible, previous, "width \(width)")
            previous = visible
        }
    }

    func testFixedModeRowIsNarrowerAndKeepsMoreGroupsAtTheSameWidth() {
        var fixedWidths = groupWidths
        fixedWidths[0] = 189   // Fixed mode drops one number field and the range separator.
        let fixedAdvances = fixedWidths.enumerated().map { index, width in
            SkimStripLayoutPlan.advance(groupWidth: width, leadingDivider: leadingDividers.contains(index), isFirst: index == 0)
        }
        let fixed = SkimStripLayoutPlan.make(advances: fixedAdvances, stripWidth: 980)
        let random = SkimStripLayoutPlan.make(advances: advances, stripWidth: 980)
        XCTAssertEqual(fixed.visibleCount, 7)
        XCTAssertGreaterThan(fixed.visibleCount, random.visibleCount)
    }

    func testEmptyRowHasNoOverflow() {
        let plan = SkimStripLayoutPlan.make(advances: [], stripWidth: 980)
        XCTAssertEqual(plan.visibleCount, 0)
        XCTAssertFalse(plan.hasOverflow)
    }
}

final class SkimRestoreHandleGeometryTests: XCTestCase {
    func testHandleIsCenteredAndFlushWithTheTopOfTheContentArea() {
        let frame = SkimRestoreHandleGeometry.frame(in: CGRect(x: 0, y: 0, width: 1_080, height: 620))
        XCTAssertEqual(frame.size, SkimRestoreHandleGeometry.size)
        XCTAssertEqual(frame.midX, 540)
        XCTAssertEqual(frame.maxY, 620)
    }

    func testHandleSizeIsLargerThanTheDesignSystemBaseline() {
        XCTAssertGreaterThan(SkimRestoreHandleGeometry.size.width, DWBMetrics.skimRestoreHandle.width)
        XCTAssertGreaterThan(SkimRestoreHandleGeometry.size.height, DWBMetrics.skimRestoreHandle.height)
    }

    func testHandleKeepsASideMarginInAVeryNarrowWindow() {
        let frame = SkimRestoreHandleGeometry.frame(in: CGRect(x: 0, y: 0, width: 30, height: 300))
        XCTAssertEqual(frame.minX, SkimRestoreHandleGeometry.minimumSideMargin)
        XCTAssertEqual(frame.maxY, 300)
    }

    func testHandleFollowsTheContentAreaOrigin() {
        let frame = SkimRestoreHandleGeometry.frame(in: CGRect(x: 10, y: 20, width: 400, height: 300))
        XCTAssertEqual(frame.midX, 210)
        XCTAssertEqual(frame.maxY, 320)
    }
}

final class SkimStripSpareWidthTests: XCTestCase {
    private typealias Metrics = SkimStripLayoutPlan.Metrics

    func testSpareWidthIsSharedEquallyBetweenVisibleGroups() {
        // Three groups: advances 100, 118, 118 (natural widths 100 with the 18 pt gaps).
        let advances: [CGFloat] = [100, 118, 118]
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 1000)
        XCTAssertEqual(plan.visibleCount, 3)
        // room = 1000 - (16 + 14 + 24 + 18) = 928; used = 336; two gaps share 592.
        XCTAssertEqual(plan.spareShare(advances: advances, stripWidth: 1000), 296, accuracy: 0.001)
    }

    func testTheRowEndsEighteenBeforeTheTrailingSlot() {
        let advances: [CGFloat] = [100, 118, 118]
        let width: CGFloat = 1000
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: width)
        let share = plan.spareShare(advances: advances, stripWidth: width)
        let rowEnd = Metrics.leadingInset + advances.reduce(0, +) + share * 2
        XCTAssertEqual(rowEnd, width - Metrics.trailingInset - Metrics.collapseControl - Metrics.trailingGap, accuracy: 0.001)
    }

    func testNoSpareWidthWhenTheRowIsFullOrHasOneGroup() {
        let advances: [CGFloat] = [100, 118, 118]
        // 336 pt of groups plus the 72 pt of insets and trailing slot fill a 408 pt strip exactly.
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: 408)
        XCTAssertEqual(plan.visibleCount, 3)
        XCTAssertEqual(plan.spareShare(advances: advances, stripWidth: 408), 0, accuracy: 0.001)
        let single = SkimStripLayoutPlan(visibleCount: 1, totalCount: 3)
        XCTAssertEqual(single.spareShare(advances: advances, stripWidth: 2000), 0, accuracy: 0.001)
    }

    func testOverflowButtonSlotIsReservedBeforeSharingSpareWidth() {
        let advances: [CGFloat] = [300, 318, 318]
        let width: CGFloat = 800
        let plan = SkimStripLayoutPlan.make(advances: advances, stripWidth: width)
        XCTAssertTrue(plan.hasOverflow)
        let share = plan.spareShare(advances: advances, stripWidth: width)
        let rowEnd = Metrics.leadingInset + advances.prefix(plan.visibleCount).reduce(0, +) + share * CGFloat(plan.visibleCount - 1)
        let limit = width - Metrics.trailingInset - Metrics.collapseControl - Metrics.trailingGap
            - Metrics.overflowControl - Metrics.trailingControlGap
        XCTAssertLessThanOrEqual(rowEnd, limit + 0.001)
    }
}
