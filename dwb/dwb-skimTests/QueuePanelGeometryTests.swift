import AppKit
import XCTest

/// Geometry of the active queue look (design system 10), from plain numbers.
///
/// "Outer" widths are the panel including the 1 pt separator the controller draws as its own view; the Queue Page itself
/// is one point narrower ("inner"). The supported outer widths are 200 (minimum), 260, 280 (default floor), 335 and 360
/// (maximum), so inner widths 199, 259, 279, 334 and 359. 389 / 390 / 540 are exercised only here, as isolated presentation
/// inputs: the shipped width rule is unchanged.
final class QueuePanelGeometryTests: XCTestCase {

    private let supportedOuterWidths: [CGFloat] = [200, 260, 280, 335, 360]
    private var supportedInnerWidths: [CGFloat] { supportedOuterWidths.map { QueuePanelGeometry.innerWidth(forOuterPanelWidth: $0) } }

    private func overlap(_ a: CGRect, _ b: CGRect) -> Bool { !a.intersection(b).isNull && a.intersection(b).width > 0 && a.intersection(b).height > 0 }

    // MARK: - Compact breakpoint

    func testCompactBelowThreeHundredNinety() {
        XCTAssertTrue(QueuePanelGeometry.isCompact(innerWidth: 199))
        XCTAssertTrue(QueuePanelGeometry.isCompact(innerWidth: 359))
        XCTAssertTrue(QueuePanelGeometry.isCompact(innerWidth: 389))
        XCTAssertFalse(QueuePanelGeometry.isCompact(innerWidth: 390))
        XCTAssertFalse(QueuePanelGeometry.isCompact(innerWidth: 540))
    }

    func testEverySupportedPanelWidthIsCompact() {
        // Skim's maximum is 360 pt, so the expanded forms never show in the app; they are not a reason to widen it.
        for width in supportedInnerWidths { XCTAssertTrue(QueuePanelGeometry.isCompact(innerWidth: width), "\(width)") }
        XCTAssertLessThan(QueuePanelWidthPolicy.defaultCeiling, DWBMetrics.queueCompactBelow)
    }

    // MARK: - Header: one row, every action, every width

    func testHeaderIsOneFiftyTwoPointRowAtEverySupportedWidth() {
        for width in supportedInnerWidths {
            let header = QueueHeaderLayout.make(width: width, hasSearchText: false)
            XCTAssertEqual(QueueHeaderLayout.height, 52)
            XCTAssertEqual(header.rule, CGRect(x: 0, y: 0, width: width, height: 1), "1 pt gridLine rule at the bottom")
            for frame in header.controlFrames {
                XCTAssertGreaterThan(frame.width, 0, "\(width)")
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width)
                XCTAssertGreaterThanOrEqual(frame.minY, header.rule.maxY, "controls sit above the rule")
                XCTAssertLessThanOrEqual(frame.maxY, QueueHeaderLayout.height)
                XCTAssertEqual(frame.height, 28)
            }
        }
    }

    func testHeaderControlsNeverOverlapAndAllFourAreAlwaysPresent() {
        for width in supportedInnerWidths + [389, 390, 540] {
            let header = QueueHeaderLayout.make(width: width, hasSearchText: true, sortLabelWidth: 90)
            let frames = header.controlFrames
            for i in 0..<frames.count {
                for j in (i + 1)..<frames.count {
                    XCTAssertFalse(overlap(frames[i], frames[j]), "\(width): \(i) vs \(j)")
                }
            }
            XCTAssertGreaterThan(header.sortButton.width, 0, "the sort action is never hidden")
            XCTAssertGreaterThan(header.searchBox.width, 0)
        }
    }

    func testCompactHeaderUsesInsetSevenGapZeroAndATwentyFourPointSortButton() {
        let header = QueueHeaderLayout.make(width: 199, hasSearchText: false)
        XCTAssertTrue(header.isCompact)
        XCTAssertEqual(header.searchBox.minX, 7)
        XCTAssertEqual(header.closeButton.maxX, 199 - 7)
        XCTAssertEqual(header.closeButton.width, 24)
        XCTAssertEqual(header.filterButton.width, 24)
        XCTAssertEqual(header.filterButton.maxX, header.closeButton.minX, "gap 0")
        XCTAssertEqual(header.sortButton.width, 24, "arrow.up.arrow.down in a 24 pt wide button")
        XCTAssertEqual(header.sortButton.maxX, header.filterButton.minX, "gap 0")
        XCTAssertEqual(header.searchBox.maxX, header.sortButton.minX - QueueHeaderLayout.compactSortLeadingMargin)
    }

    func testSearchStaysUsableAtTheMinimumPanel() {
        // 199 inner: 199 - 7 - 7 - 3 × 24 - 2 = 111 pt for the search box.
        XCTAssertEqual(QueueHeaderLayout.make(width: 199, hasSearchText: false).searchBox.width, 111)
        let wider = QueueHeaderLayout.make(width: 359, hasSearchText: false).searchBox.width
        XCTAssertEqual(wider, 271)
    }

    func testExpandedHeaderUsesInsetTwelveGapFourAndTheSortLabel() {
        let header = QueueHeaderLayout.make(width: 540, hasSearchText: false, sortLabelWidth: 40)
        XCTAssertFalse(header.isCompact)
        XCTAssertEqual(header.searchBox.minX, 12)
        XCTAssertEqual(header.closeButton.maxX, 540 - 12)
        XCTAssertEqual(header.filterButton.maxX, header.closeButton.minX - 4)
        XCTAssertEqual(header.sortButton.maxX, header.filterButton.minX - 4)
        XCTAssertEqual(header.sortButton.width, 4 * 2 + 40 + 6 + 10, "padding, label, gap, chevron")
        XCTAssertEqual(header.searchBox.maxX, header.sortButton.minX - 4)
    }

    func testSortLabelIsCappedAtOneHundredTwentyInTheExpandedForm() {
        let header = QueueHeaderLayout.make(width: 540, hasSearchText: false, sortLabelWidth: 400)
        XCTAssertEqual(header.sortButton.width, 4 * 2 + 120 + 6 + 10)
    }

    func testTheHeaderSwitchesFormExactlyAtThreeHundredNinety() {
        let compact = QueueHeaderLayout.make(width: 389, hasSearchText: false, sortLabelWidth: 40)
        let expanded = QueueHeaderLayout.make(width: 390, hasSearchText: false, sortLabelWidth: 40)
        XCTAssertTrue(compact.isCompact)
        XCTAssertEqual(compact.sortButton.width, 24)
        XCTAssertFalse(expanded.isCompact)
        XCTAssertGreaterThan(expanded.sortButton.width, 24)
    }

    func testControlsAreCenteredInTheRowAboveTheRule() {
        let header = QueueHeaderLayout.make(width: 259, hasSearchText: false)
        let content = QueueHeaderLayout.height - 1
        let expectedY = 1 + floor((content - 28) / 2)
        XCTAssertEqual(header.searchBox.minY, expectedY)
        XCTAssertEqual(header.closeButton.minY, expectedY)
        // Whole points, so a 1× display shows crisp edges and a 2× display shows exact ones.
        XCTAssertEqual(header.searchBox.minY, header.searchBox.minY.rounded())
    }

    func testClearButtonSitsInsideTheRightEndOfTheSearchBoxOnlyWhileThereIsText() throws {
        XCTAssertNil(QueueHeaderLayout.make(width: 199, hasSearchText: false).clearButton)
        let header = QueueHeaderLayout.make(width: 199, hasSearchText: true)
        let clear = try XCTUnwrap(header.clearButton)
        XCTAssertEqual(clear.size, CGSize(width: 20, height: 22))
        XCTAssertTrue(header.searchBox.contains(clear))
        XCTAssertEqual(header.searchBox.maxX - clear.maxX, 2)
    }

    // MARK: - Footer: exactly two rows

    func testFooterIsSeventyEightPointsOfOneRuleAndTwoRowsAtEverySupportedWidth() {
        for width in supportedInnerWidths + [389, 390, 540] {
            let footer = QueueFooterLayout.make(width: width)
            XCTAssertEqual(QueueFooterLayout.height, 78)
            XCTAssertEqual(footer.topRule, CGRect(x: 0, y: 77, width: width, height: 1), "top rule 1")
            XCTAssertEqual(footer.actionRule, CGRect(x: 0, y: 38, width: width, height: 1), "the action row's own rule")
            // Actions 39 = 38 + its rule; status 38; top rule 1: 78 in all.
            for cell in footer.actionCells {
                XCTAssertEqual(cell.minY, 39)
                XCTAssertEqual(cell.height, 38)
                XCTAssertEqual(cell.maxY, 77)
            }
            for cell in [footer.rescanCell, footer.totalCell, footer.clearCell] {
                XCTAssertEqual(cell.minY, 0)
                XCTAssertEqual(cell.height, 38)
            }
            XCTAssertEqual(DWBMetrics.queueActionRowHeight + DWBMetrics.queueStatusRowHeight + 1, DWBMetrics.queueFooterHeight)
        }
    }

    func testFourActionSectionsTileTheRowExactlyAndAreEqualToWithinAPoint() {
        for width in supportedInnerWidths + [389, 390, 540] {
            let cells = QueueFooterLayout.make(width: width).actionCells
            XCTAssertEqual(cells.count, 4)
            XCTAssertEqual(cells.first?.minX, 0)
            XCTAssertEqual(cells.last?.maxX, width)
            for index in 0..<3 { XCTAssertEqual(cells[index].maxX, cells[index + 1].minX, "no gap, no overlap at \(width)") }
            let widths = cells.map(\.width)
            XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 1, "\(width): \(widths)")
            for cell in cells { XCTAssertEqual(cell.minX, cell.minX.rounded(), "whole-point edges") }
        }
    }

    func testEverySectionIsTheCompleteHitBoxAndSectionsNeverOverlap() {
        for width in supportedInnerWidths {
            let footer = QueueFooterLayout.make(width: width)
            let sections = footer.sections
            let bounds = CGRect(x: 0, y: 0, width: width, height: QueueFooterLayout.height)
            for section in sections {
                XCTAssertTrue(bounds.contains(section), "\(width)")
                XCTAssertGreaterThan(section.width, 0)
                XCTAssertGreaterThanOrEqual(section.minX, 0)
            }
            for i in 0..<sections.count {
                for j in (i + 1)..<sections.count { XCTAssertFalse(overlap(sections[i], sections[j]), "\(width)") }
            }
            // The status row is tiled edge to edge by Rescan, the total and Clear queue.
            XCTAssertEqual(footer.rescanCell.maxX, footer.totalCell.minX)
            XCTAssertEqual(footer.totalCell.maxX, footer.clearCell.minX)
            XCTAssertEqual(footer.clearCell.maxX, width)
        }
    }

    func testActionDividersAreHalfPointByEighteenAtTheLeadingEdgeOfSectionsTwoToFour() {
        let footer = QueueFooterLayout.make(width: 259)
        XCTAssertEqual(footer.actionDividers.count, 3)
        for (divider, cell) in zip(footer.actionDividers, footer.actionCells.dropFirst()) {
            XCTAssertEqual(divider.size, CGSize(width: 0.5, height: 18))
            XCTAssertEqual(divider.minX, cell.minX)
            // 10 pt below the top of the section (flipped y 10…28 → y-up 49…67 in a 77 pt tall footer).
            XCTAssertEqual(footer.actionCells[0].maxY - divider.maxY, 10)
        }
    }

    func testStatusColumnsAreOneHundredFlexibleOneTenCompactThirtyFourFlexibleThirtyFour() {
        let compact = QueueFooterLayout.make(width: 199)
        XCTAssertTrue(compact.isCompact)
        XCTAssertEqual(compact.rescanCell.width, 34)
        XCTAssertEqual(compact.clearCell.width, 34)
        XCTAssertEqual(compact.totalCell.width, 199 - 68)

        let expanded = QueueFooterLayout.make(width: 540)
        XCTAssertFalse(expanded.isCompact)
        XCTAssertEqual(expanded.rescanCell.width, 100)
        XCTAssertEqual(expanded.clearCell.width, 110)
        XCTAssertEqual(expanded.totalCell.width, 540 - 210)
    }

    func testTotalDividersAreHalfPointByEighteenAtTheTotalCellEdges() {
        let footer = QueueFooterLayout.make(width: 259)
        XCTAssertEqual(footer.totalDividers.count, 2)
        XCTAssertEqual(footer.totalDividers[0].minX, footer.totalCell.minX)
        XCTAssertEqual(footer.totalDividers[1].maxX, footer.totalCell.maxX)
        for divider in footer.totalDividers {
            XCTAssertEqual(divider.size, CGSize(width: 0.5, height: 18))
            XCTAssertEqual(divider.midY, 19, "centered in the 38 pt status row")
        }
    }

    func testTotalFitWidthIsTheCenterCellMinusSixteen() {
        XCTAssertEqual(QueueFooterLayout.make(width: 199).totalFitWidth, 131 - 16)
        XCTAssertEqual(QueueFooterLayout.make(width: 359).totalFitWidth, 359 - 68 - 16)
    }

    func testFooterNeverGainsAThirdRowAtAnyWidth() {
        // No row above the actions, none between the rows and none below the status row.
        for width in supportedInnerWidths + [389, 390, 540] {
            let footer = QueueFooterLayout.make(width: width)
            let ys = Set(footer.sections.map(\.minY))
            XCTAssertEqual(ys, [0, 39], "\(width)")
        }
    }

    // MARK: - Marker cell content (long prefix, state mark)

    func testStateMarkIsFourPointsAtTopSevenRightSeven() {
        let mark = QueueMarkerCellGeometry.markFrame(sectionWidth: 50)
        XCTAssertEqual(mark, CGRect(x: 50 - 7 - 4, y: 7, width: 4, height: 4))
    }

    func testTheLabelLineBoxClearsTheMarkVertically() {
        let font = QueueFonts.marker
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let label = QueueMarkerCellGeometry.labelFrame(sectionSize: CGSize(width: 49, height: 38), labelWidth: 30, lineHeight: lineHeight)
        let mark = QueueMarkerCellGeometry.markFrame(sectionWidth: 49)
        // Flipped coordinates: the mark ends above where the label's line box begins.
        XCTAssertGreaterThanOrEqual(label.minY, mark.maxY, "the mark never sits on the label")
        XCTAssertEqual(label.midX, 24.5, accuracy: 1, "centered")
    }

    func testLongPrefixFitsItsSectionAtTheActualMinimumPanel() {
        // 199 pt inner: the narrowest section is 49 pt, so the label may use 49 - 2 × 4 = 41 pt.
        let narrowest = QueueFooterLayout.make(width: 199).actionCells.map(\.width).min() ?? 0
        XCTAssertEqual(narrowest, 49)
        let limit = QueueMarkerCellGeometry.labelWidthLimit(sectionWidth: narrowest, isCompact: true)
        XCTAssertEqual(limit, 41)
        for prefix in ["keep_", "delete_", "a_very_long_review_prefix_", "review-needed_", "WWWWWWWW_", "—"] {
            let shown = QueuePrefixLabelFitting.fit(prefix, maxWidth: limit)
            XCTAssertLessThanOrEqual(QueueFonts.width(of: shown, font: QueueFonts.marker), limit, "\(prefix) → \(shown)")
            if shown != prefix {
                XCTAssertTrue(shown.hasSuffix("…"), "a shortened label is marked with an ellipsis")
                XCTAssertTrue(prefix.hasPrefix(String(shown.dropLast())), "only the end is cut")
            }
        }
        XCTAssertEqual(QueuePrefixLabelFitting.fit("a", maxWidth: limit), "a")
    }

    func testPrefixLabelFallsBackToJustTheEllipsisWhenNothingFits() {
        XCTAssertEqual(QueuePrefixLabelFitting.fit("abcdef", maxWidth: 1), "…")
    }

    func testPrefixLabelKeepsTheLongestPartThatFits() {
        // A synthetic measure of one point per character: 5 points fit "abcd…".
        XCTAssertEqual(QueuePrefixLabelFitting.fit("abcdefgh", maxWidth: 5) { CGFloat($0.count) }, "abcd…")
        XCTAssertEqual(QueuePrefixLabelFitting.fit("abcde", maxWidth: 5) { CGFloat($0.count) }, "abcde")
    }

    func testWiderSectionsKeepMoreOfALongPrefix() {
        let prefix = "review-needed_"
        let narrow = QueuePrefixLabelFitting.fit(prefix, maxWidth: QueueMarkerCellGeometry.labelWidthLimit(sectionWidth: 49, isCompact: true))
        let wide = QueuePrefixLabelFitting.fit(prefix, maxWidth: QueueMarkerCellGeometry.labelWidthLimit(sectionWidth: 89, isCompact: true))
        XCTAssertGreaterThan(wide.count, narrow.count)
    }

    // MARK: - Rows: heights

    func testFlatRowsAreFortyFourAndThePlayingRowIsFiftyTwo() {
        XCTAssertEqual(QueueRowMetrics.height(isCurrent: false), 44)
        XCTAssertEqual(QueueRowMetrics.height(isCurrent: true), 52)
        XCTAssertEqual(QueueRowMetrics.cardHeight(isCurrent: true), 48, "48 pt card plus a 4 pt gap")
        XCTAssertEqual(DWBMetrics.queuePlayingCardHeight + DWBMetrics.queuePlayingCardGap, DWBMetrics.queuePlayingRowHeight)
        // The classic 56 pt row with 4 pt insets no longer drives the list.
        XCTAssertNotEqual(QueueRowMetrics.height(isCurrent: false), DWBMetrics.queueRowHeight + DWBMetrics.queueRowInset * 2)
    }

    func testMovingTheCurrentItemChangesTheHeightsOfExactlyTheOldAndNewRows() {
        func heights(current: Int, count: Int) -> [CGFloat] {
            (0..<count).map { QueueRowMetrics.height(isCurrent: $0 == current) }
        }
        let before = heights(current: 1, count: 5)
        let after = heights(current: 3, count: 5)
        XCTAssertEqual(before, [44, 52, 44, 44, 44])
        XCTAssertEqual(after, [44, 44, 44, 52, 44])
        let changed = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        XCTAssertEqual(changed, [1, 3], "the old and the new current rows are re-measured")
        XCTAssertEqual(after.reduce(0, +) - before.reduce(0, +), 0, "total list height is unchanged")
    }

    // MARK: - Rows: card, separator, strip and edges at 1× and 2×

    func testCardIsSixPointsInFromTheLeftAndTenFromTheRightAtEverySupportedWidth() {
        for width in supportedInnerWidths {
            for current in [false, true] {
                let card = QueueRowMetrics.cardFrame(rowWidth: width, isCurrent: current)
                XCTAssertEqual(card.minX, 6)
                XCTAssertEqual(width - card.maxX, 10, "6 list padding + 4 row margin")
                XCTAssertEqual(card.minY, 0)
                XCTAssertEqual(card.height, current ? 48 : 44)
                // Whole-point edges: the card, and so its 1 pt selected edge, is pixel exact at 1× and 2×.
                XCTAssertEqual(card.minX, card.minX.rounded())
                XCTAssertEqual(card.width, card.width.rounded())
            }
        }
        XCTAssertEqual(QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: false).width, 183)
    }

    func testInnerEdgesStayInsideTheCardSoNothingOverhangs() {
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: true)
        for width in [0.5, 1.0] as [CGFloat] {
            let path = QueueRowMetrics.edgeRect(card: card, width: width)
            // A stroke of `width` centered on `path` covers exactly the card's outer `width` points.
            XCTAssertEqual(path.insetBy(dx: -width / 2, dy: -width / 2), card)
        }
    }

    func testSeparatorIsHalfAPointInsetFiveAndSevenOnTheFlatRowsBottomEdge() {
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: false)
        let separator = QueueRowMetrics.separatorFrame(card: card)
        XCTAssertEqual(separator.height, 0.5)
        XCTAssertEqual(separator.minX, card.minX + 5)
        XCTAssertEqual(card.maxX - separator.maxX, 7)
        XCTAssertEqual(separator.maxY, card.maxY, "the line is the last half point of its own row")
        XCTAssertLessThanOrEqual(separator.maxY, QueueRowMetrics.height(isCurrent: false))
        // On a 2× display 0.5 pt is exactly one pixel; on 1× it is a half-covered pixel, as specified.
        XCTAssertEqual(separator.height * 2, 1)
    }

    func testPlayingStripIsThreePointsFlushLeftAndFullCardHeight() {
        let card = QueueRowMetrics.cardFrame(rowWidth: 259, isCurrent: true)
        let strip = QueueRowMetrics.playingStripFrame(card: card)
        XCTAssertEqual(strip, CGRect(x: card.minX, y: card.minY, width: 3, height: 48))
        XCTAssertTrue(card.contains(strip), "the strip never overhangs the card")
    }

    // MARK: - Rows: state precedence

    func testFlatRowAtRestHasNoFillNoEdgeAndASeparator() {
        let a = QueueRowAppearance.resolve(isCurrent: false, isSelected: false, isHovering: false)
        XCTAssertEqual(a.fill, .none)
        XCTAssertEqual(a.edge, .none)
        XCTAssertTrue(a.showsSeparator)
        XCTAssertFalse(a.showsPlayingStrip)
        XCTAssertEqual(a.cornerRadius, 6)
    }

    func testFlatHoverIsTheHoverOverlayAndKeepsTheSeparator() {
        let a = QueueRowAppearance.resolve(isCurrent: false, isSelected: false, isHovering: true)
        XCTAssertEqual(a.fill, .overlayHover)
        XCTAssertEqual(a.edge, .none)
        XCTAssertTrue(a.showsSeparator)
    }

    func testSelectedFlatRowHasAOnePointStrongEdgeAndHidesItsSeparator() {
        let a = QueueRowAppearance.resolve(isCurrent: false, isSelected: true, isHovering: false)
        XCTAssertEqual(a.fill, .overlaySelected)
        XCTAssertEqual(a.edge, .borderStrong)
        XCTAssertEqual(a.edgeWidth, 1)
        XCTAssertFalse(a.showsSeparator, "nothing overwrites the bottom of the selection outline")
    }

    func testSelectionWinsOverHoverOnAFlatRow() {
        XCTAssertEqual(QueueRowAppearance.resolve(isCurrent: false, isSelected: true, isHovering: true),
                       QueueRowAppearance.resolve(isCurrent: false, isSelected: true, isHovering: false))
    }

    func testPlayingCardIsAUniformStrongTintWithAStripAndNoSeparator() {
        let a = QueueRowAppearance.resolve(isCurrent: true, isSelected: false, isHovering: false)
        XCTAssertEqual(a.fill, .accentTintStrong)
        XCTAssertEqual(a.edge, .border)
        XCTAssertEqual(a.edgeWidth, 0.5)
        XCTAssertTrue(a.showsPlayingStrip)
        XCTAssertFalse(a.showsSeparator)
        XCTAssertEqual(a.cornerRadius, 7)
    }

    func testPlayingCardEdgeBecomesStrongOnHoverAndOnePointWhenSelected() {
        let hover = QueueRowAppearance.resolve(isCurrent: true, isSelected: false, isHovering: true)
        XCTAssertEqual(hover.edge, .borderStrong)
        XCTAssertEqual(hover.edgeWidth, 0.5)
        XCTAssertEqual(hover.fill, .accentTintStrong, "hover does not change the playing card's fill")

        let selected = QueueRowAppearance.resolve(isCurrent: true, isSelected: true, isHovering: true)
        XCTAssertEqual(selected.edge, .borderStrong)
        XCTAssertEqual(selected.edgeWidth, 1)
        XCTAssertEqual(selected.fill, .accentTintStrong, "a selected playing card keeps its tint")
        XCTAssertTrue(selected.showsPlayingStrip)
    }

    // MARK: - Rows: text geometry and accessories

    func testTextInsetsAreFiveTwentySevenAndThirtySeven() {
        XCTAssertEqual(QueueRowMetrics.textInset(isCurrent: false, isFailed: false), 5)
        XCTAssertEqual(QueueRowMetrics.textInset(isCurrent: false, isFailed: true), 27)
        XCTAssertEqual(QueueRowMetrics.textInset(isCurrent: true, isFailed: false), 37)
        XCTAssertEqual(QueueRowMetrics.textInset(isCurrent: true, isFailed: true), 37, "the playing glyph wins")
    }

    func testNameLineIsEighteenAndMetadataLineSixteenCenteredInTheCard() {
        let flat = QueueRowMetrics.frames(card: QueueRowMetrics.cardFrame(rowWidth: 259, isCurrent: false),
                                          isCurrent: false, isFailed: false, hasBookmark: false)
        XCTAssertEqual(flat.name.height, 18)
        XCTAssertEqual(flat.meta.height, 16)
        XCTAssertEqual(flat.name.minY, 5)
        XCTAssertEqual(flat.meta.minY, flat.name.maxY)
        XCTAssertEqual(flat.meta.maxY, 39)

        let current = QueueRowMetrics.frames(card: QueueRowMetrics.cardFrame(rowWidth: 259, isCurrent: true),
                                             isCurrent: true, isFailed: false, hasBookmark: false)
        XCTAssertEqual(current.name.minY, 7)
        XCTAssertEqual(current.meta.maxY, 41, "the 48 pt card has room for the descenders")
        XCTAssertLessThanOrEqual(current.meta.maxY, 48)
    }

    func testTextRightPaddingIsTenAndNoFrameIsNegativeAtAnySupportedWidth() {
        for width in supportedInnerWidths {
            for current in [false, true] {
                for failed in [false, true] {
                    for bookmark in [false, true] {
                        let card = QueueRowMetrics.cardFrame(rowWidth: width, isCurrent: current)
                        let frames = QueueRowMetrics.frames(card: card, isCurrent: current, isFailed: failed, hasBookmark: bookmark)
                        XCTAssertEqual(card.maxX - frames.meta.maxX, 10)
                        for frame in [frames.name, frames.meta] + [frames.bookmark, frames.leadingGlyph].compactMap({ $0 }) {
                            XCTAssertGreaterThanOrEqual(frame.minX, card.minX, "\(width)")
                            XCTAssertGreaterThanOrEqual(frame.width, 0)
                            XCTAssertGreaterThanOrEqual(frame.minY, 0)
                            XCTAssertLessThanOrEqual(frame.maxX, card.maxX)
                            XCTAssertLessThanOrEqual(frame.maxY, card.maxY)
                        }
                    }
                }
            }
        }
    }

    func testBookmarkIsReservedBeforeTheNameIsMeasured() throws {
        let card = QueueRowMetrics.cardFrame(rowWidth: 199, isCurrent: false)
        let plain = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: false, hasBookmark: false)
        let marked = QueueRowMetrics.frames(card: card, isCurrent: false, isFailed: false, hasBookmark: true)
        let bookmark = try XCTUnwrap(marked.bookmark)
        XCTAssertNil(plain.bookmark)
        XCTAssertEqual(plain.name.width - marked.name.width, 10 + 6, "the 10 pt glyph and the 6 pt gap")
        XCTAssertLessThanOrEqual(marked.name.maxX + 6, bookmark.minX, "the name never runs under the bookmark")
        XCTAssertEqual(card.maxX - bookmark.maxX, 10)
        XCTAssertEqual(plain.meta.width, marked.meta.width, "the metadata line keeps the whole width")
    }

    func testLeadingGlyphsAreThePlayTriangleAndTheWarningTriangle() {
        let currentCard = QueueRowMetrics.cardFrame(rowWidth: 259, isCurrent: true)
        let play = QueueRowMetrics.frames(card: currentCard, isCurrent: true, isFailed: false, hasBookmark: false).leadingGlyph
        XCTAssertEqual(play?.minX, currentCard.minX + 14)
        XCTAssertEqual(play?.width, 13)
        XCTAssertLessThan(play?.maxX ?? 0, currentCard.minX + 37, "the glyph ends before the text starts")

        let flatCard = QueueRowMetrics.cardFrame(rowWidth: 259, isCurrent: false)
        let warning = QueueRowMetrics.frames(card: flatCard, isCurrent: false, isFailed: true, hasBookmark: false).leadingGlyph
        XCTAssertEqual(warning?.minX, flatCard.minX + 9)
        XCTAssertLessThan(warning?.maxX ?? 0, flatCard.minX + 27)

        XCTAssertNil(QueueRowMetrics.frames(card: flatCard, isCurrent: false, isFailed: false, hasBookmark: false).leadingGlyph)
    }

    // MARK: - Rows: drag line

    func testDropLineSitsOnTheSharedEdgeBetweenRows() {
        XCTAssertEqual(QueueRowMetrics.dropLineBoundaryY(rowMinY: 88, previousRowMaxY: 88, previousIsCurrent: false), 88)
    }

    func testDropLineAfterTheLastRowSitsOnItsBottomEdge() {
        XCTAssertEqual(QueueRowMetrics.dropLineBoundaryY(rowMinY: nil, previousRowMaxY: 440, previousIsCurrent: false), 440)
    }

    func testDropLineAfterThePlayingRowSitsOnTheCardsBottomEdgeAboveItsGap() {
        XCTAssertEqual(QueueRowMetrics.dropLineBoundaryY(rowMinY: nil, previousRowMaxY: 140, previousIsCurrent: true), 136)
    }

    // MARK: - Empty states

    private func assertInside(_ frames: [CGRect], _ container: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        let bounds = CGRect(origin: .zero, size: container)
        for frame in frames {
            XCTAssertTrue(bounds.contains(frame), "\(frame) outside \(bounds)", file: file, line: line)
        }
    }

    func testEmptyQueueStacksIconTitleDetailAndButtonWithTheSpecifiedGaps() throws {
        let container = CGSize(width: 199, height: 500)
        let model = QueueEmptyStateLayout.make(lead: .appIcon, container: container, detailHeight: 28, buttonSize: CGSize(width: 90, height: 26))
        XCTAssertEqual(model.lead.size, CGSize(width: 96, height: 96))
        XCTAssertEqual(model.title.height, 20)
        let detail = try XCTUnwrap(model.detail)
        XCTAssertEqual(model.lead.minY - model.title.maxY, 10, "icon → title")
        XCTAssertEqual(model.title.minY - detail.maxY, 6, "title → detail")
        XCTAssertEqual(detail.minY - model.button.maxY, 10, "detail → button")
        XCTAssertEqual(model.button.height, 26)
        assertInside([model.lead, model.title, detail, model.button], container)
    }

    func testEmptyQueueColumnIsCenteredAndVerticallyBalanced() {
        let container = CGSize(width: 259, height: 600)
        let model = QueueEmptyStateLayout.make(lead: .appIcon, container: container, detailHeight: 14, buttonSize: CGSize(width: 90, height: 26))
        for frame in [model.lead, model.title, model.button] { XCTAssertEqual(frame.midX, container.width / 2, accuracy: 1) }
        let top = model.lead.maxY, bottom = model.button.minY
        XCTAssertEqual(container.height - top, bottom, accuracy: 1, "equal space above and below")
    }

    func testDetailWrapsWithinThreeHundredTwentyAndNeverWiderThanThePanel() {
        XCTAssertEqual(QueueEmptyStateLayout.textWidth(containerWidth: 199), 199 - 30)
        XCTAssertEqual(QueueEmptyStateLayout.textWidth(containerWidth: 359), 320, "329 would exceed the 320 maximum")
        XCTAssertEqual(QueueEmptyStateLayout.textWidth(containerWidth: 335), 305)
        XCTAssertEqual(QueueEmptyStateLayout.textWidth(containerWidth: 540), 320)
        XCTAssertEqual(QueueEmptyStateLayout.textWidth(containerWidth: 1200), 320)
    }

    func testFilteredStateIsACircleTitleAndOneButtonWithThirteenPointGaps() {
        let container = CGSize(width: 199, height: 500)
        let model = QueueEmptyStateLayout.make(lead: .glyphCircle, container: container, detailHeight: 0, buttonSize: CGSize(width: 90, height: 29))
        XCTAssertEqual(model.lead.size, CGSize(width: 44, height: 44))
        XCTAssertNil(model.detail, "no helper line, and no app icon")
        XCTAssertEqual(model.lead.minY - model.title.maxY, 13)
        XCTAssertEqual(model.title.minY - model.button.maxY, 13)
        assertInside([model.lead, model.title, model.button], container)
    }

    func testEmptyStatesFitTheShortestPanelsWeSupport() {
        for width in supportedInnerWidths {
            let container = CGSize(width: width, height: 420)
            let empty = QueueEmptyStateLayout.make(lead: .appIcon, container: container, detailHeight: 42, buttonSize: CGSize(width: 90, height: 26))
            assertInside([empty.lead, empty.title, empty.button] + [empty.detail].compactMap { $0 }, container)
            let filtered = QueueEmptyStateLayout.make(lead: .glyphCircle, container: container, detailHeight: 0, buttonSize: CGSize(width: 110, height: 29))
            assertInside([filtered.lead, filtered.title, filtered.button], container)
        }
    }

    func testEmptyStateTitlesFitOneLineAtTheMinimumPanel() {
        // Real measurement: "No media in queue" in 14 pt semibold against the 169 pt column at 199 pt inner width.
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let column = QueueEmptyStateLayout.textWidth(containerWidth: 199)
        for state in [QueueEmptyState.emptyQueue, .noMatches, .noBookmarks] {
            XCTAssertLessThanOrEqual(QueueFonts.width(of: state.title, font: font), column, state.title)
        }
    }

    func testAddMediaPillAndFilteredButtonFitTheMinimumPanel() {
        let pill = NSFont.systemFont(ofSize: 12, weight: .semibold)
        XCTAssertLessThanOrEqual(QueueFonts.width(of: "Add Media", font: pill) + 24, 199 - 30)
        let filtered = NSFont.systemFont(ofSize: 11)
        for title in ["Clear Search", "Show All Media"] {
            XCTAssertLessThanOrEqual(QueueFonts.width(of: title, font: filtered) + 26, 199 - 30, title)
        }
    }

    // MARK: - Metrics ported from the handoff

    func testActiveQueueMetricsMatchTheDesignSystem() {
        XCTAssertEqual(DWBMetrics.queueFlatRowHeight, 44)
        XCTAssertEqual(DWBMetrics.queuePlayingRowHeight, 52)
        XCTAssertEqual(DWBMetrics.queueHeaderHeight, 52)
        XCTAssertEqual(DWBMetrics.queueFooterHeight, 78)
        XCTAssertEqual(DWBMetrics.queueActionRowHeight, 39)
        XCTAssertEqual(DWBMetrics.queueStatusRowHeight, 38)
        XCTAssertEqual(DWBMetrics.queueCompactBelow, 390)
        XCTAssertEqual(DWBMetrics.queuePanelMinWidth, 200)
        XCTAssertEqual(DWBMetrics.queueCellHoverAlpha, 0.035)
        XCTAssertEqual(DWBMetrics.queueCellPressedAlpha, 0.075)
        XCTAssertEqual(DWBMetrics.queueFooterDisabledAlpha, 0.4)
        XCTAssertEqual(DWBMetrics.queueDividerLineAlpha, 0.7)
        XCTAssertEqual(DWBMetrics.queueEmptyIconAlpha, 0.32)
        XCTAssertEqual(DWBMetrics.queueEmptyIconSaturation, 0.6)
    }

    func testFooterHoverAndPressedAlphasAreFooterSpecific() {
        // The generic overlay tokens are untouched: 6% hover, 14% pressed.
        XCTAssertEqual(DWBColor.overlayHover.alphaComponent, 0.06, accuracy: 0.0001)
        XCTAssertEqual(DWBColor.overlayPressed.alphaComponent, 0.14, accuracy: 0.0001)
        XCTAssertNotEqual(DWBMetrics.queueCellHoverAlpha, DWBColor.overlayHover.alphaComponent)
    }

    func testClassicRowMetricsRemainButNoLongerDriveTheList() {
        XCTAssertEqual(DWBMetrics.queueRowHeight, 56)
        XCTAssertEqual(DWBMetrics.queueRowInset, 4)
    }
}
