import AppKit

// Pure geometry for the active queue look (design system section 10). It owns no views, so the
// header, the two footer rows, the rows and the empty states can be checked from plain numbers.
//
// "Inner width" is the width of the Queue Page itself. The controller places the page at
// `queueW - 1` because the 1 pt separator between the video and the panel is a separate view,
// so a 200 pt outer panel has a 199 pt inner width.

enum QueuePanelGeometry {

    /// The header and footer switch to their compact forms below 390 pt (section 10.1). Every
    /// supported panel (200–360 pt) is compact; the expanded forms exist for the shared contract.
    static func isCompact(innerWidth: CGFloat) -> Bool {
        innerWidth < DWBMetrics.queueCompactBelow
    }

    /// The inner width of the page for an outer panel width (panel plus its 1 pt separator).
    static func innerWidth(forOuterPanelWidth outer: CGFloat) -> CGFloat {
        max(0, outer - 1)
    }
}

// MARK: - Header (section 10.2)

/// One 52 pt row: search, sort, bookmark filter and close. No title at any width.
/// Frames are in the header's own coordinates (y up). The bottom 1 pt is the gridLine rule.
struct QueueHeaderLayout: Equatable {
    let isCompact: Bool
    let rule: CGRect
    let searchBox: CGRect
    /// The clear-search button inside the right end of the search box; nil while the field is empty.
    let clearButton: CGRect?
    let sortButton: CGRect
    let filterButton: CGRect
    let closeButton: CGRect

    static let height = DWBMetrics.queueHeaderHeight
    static let clearButtonSize = CGSize(width: 20, height: 22)
    /// The expanded sort button: 4 pt padding, label, 6 pt gap, a 10 pt chevron, 4 pt padding.
    static let sortButtonPadding: CGFloat = 4
    static let sortLabelChevronGap: CGFloat = 6
    static let sortChevron: CGFloat = 10
    /// The compact sort button keeps 2 pt of space from the search box (section 10.2 and the approved layout).
    static let compactSortLeadingMargin: CGFloat = 2

    /// - Parameter sortLabelWidth: the measured width of the current sort title (expanded form only).
    static func make(width: CGFloat, hasSearchText: Bool, sortLabelWidth: CGFloat = 0) -> QueueHeaderLayout {
        let compact = QueuePanelGeometry.isCompact(innerWidth: width)
        let inset = compact ? DWBMetrics.queueHeaderInsetCompact : DWBMetrics.queueHeaderInset
        let gap = compact ? 0 : DWBMetrics.queueHeaderGap
        let rule = CGRect(x: 0, y: 0, width: width, height: 1)
        // The row's content sits above the rule; controls are centered in it.
        let contentHeight = height - 1
        let controlY = rule.maxY + floor((contentHeight - DWBMetrics.queueHeaderButton) / 2)
        let buttonH = DWBMetrics.queueHeaderButton
        let compactW = DWBMetrics.queueHeaderButtonCompactWidth

        let close = CGRect(x: width - inset - compactW, y: controlY, width: compactW, height: buttonH)
        let filter = CGRect(x: close.minX - gap - compactW, y: controlY, width: compactW, height: buttonH)

        let sortW: CGFloat
        let sortMargin: CGFloat
        if compact {
            sortW = compactW
            sortMargin = compactSortLeadingMargin
        } else {
            let label = min(max(0, sortLabelWidth), DWBMetrics.queueSortLabelMaxWidth)
            sortW = max(compactW, sortButtonPadding * 2 + label + sortLabelChevronGap + sortChevron)
            sortMargin = 0
        }
        let sort = CGRect(x: filter.minX - gap - sortW, y: controlY, width: sortW, height: buttonH)

        let searchW = max(0, sort.minX - sortMargin - gap - inset)
        let search = CGRect(x: inset, y: controlY, width: searchW, height: DWBMetrics.queueSearchHeight)
        var clear: CGRect?
        if hasSearchText, searchW >= clearButtonSize.width + 2 {
            clear = CGRect(x: search.maxX - 2 - clearButtonSize.width,
                           y: search.minY + floor((search.height - clearButtonSize.height) / 2),
                           width: clearButtonSize.width,
                           height: clearButtonSize.height)
        }
        return QueueHeaderLayout(isCompact: compact, rule: rule, searchBox: search, clearButton: clear,
                                 sortButton: sort, filterButton: filter, closeButton: close)
    }

    /// Every control, for overlap and bounds checks.
    var controlFrames: [CGRect] { [searchBox, sortButton, filterButton, closeButton] }
}

// MARK: - Footer (section 10.5)

/// Two rows at every width: four equal action sections over a 100 / flexible / 110 status row
/// (34 / flexible / 34 compact). Frames are in the footer's own coordinates (y up).
///
///     y 77…78  top rule (1)
///     y 39…77  action cells (38) — a 1 pt gridLine rule closes the row at y 38…39
///     y  0…38  status row (38)
struct QueueFooterLayout: Equatable {
    let isCompact: Bool
    let topRule: CGRect
    let actionRule: CGRect
    /// Remove, primary prefix, secondary prefix, Undo. Each is the complete hit target of its section.
    let actionCells: [CGRect]
    /// 0.5 × 18 dividers at the leading edge of sections 2…4.
    let actionDividers: [CGRect]
    let rescanCell: CGRect
    let totalCell: CGRect
    let clearCell: CGRect
    /// 0.5 × 18 dividers at the two edges of the total cell.
    let totalDividers: [CGRect]

    static let height = DWBMetrics.queueFooterHeight

    /// The total shortens until it fits the center cell minus 16 pt (section 10.5).
    var totalFitWidth: CGFloat { max(0, totalCell.width - DWBMetrics.queueTotalFitInset) }

    static func make(width: CGFloat) -> QueueFooterLayout {
        let compact = QueuePanelGeometry.isCompact(innerWidth: width)
        let statusH = DWBMetrics.queueStatusRowHeight
        let actionH = DWBMetrics.queueActionRowHeight
        let divider = DWBMetrics.queueCellDivider

        let actionRule = CGRect(x: 0, y: statusH, width: width, height: 1)
        let cellsY = actionRule.maxY
        let cellsH = actionH - 1
        let topRule = CGRect(x: 0, y: height - 1, width: width, height: 1)

        // Four equal sections, edges snapped to whole points so the sections tile the row exactly
        // at 1× and 2×.
        let edges = (0...4).map { (CGFloat($0) * width / 4).rounded() }
        let cells = (0..<4).map { CGRect(x: edges[$0], y: cellsY, width: edges[$0 + 1] - edges[$0], height: cellsH) }
        let dividerY = cellsY + cellsH - DWBMetrics.queueCellDividerTop - divider.height
        let actionDividers = (1..<4).map {
            CGRect(x: edges[$0], y: dividerY, width: divider.width, height: divider.height)
        }

        let columns = compact ? DWBMetrics.queueStatusColumnsCompact : DWBMetrics.queueStatusColumns
        let leadingW = min(columns.leading, width)
        let trailingW = min(columns.trailing, max(0, width - leadingW))
        let rescan = CGRect(x: 0, y: 0, width: leadingW, height: statusH)
        let clear = CGRect(x: width - trailingW, y: 0, width: trailingW, height: statusH)
        let total = CGRect(x: rescan.maxX, y: 0, width: max(0, clear.minX - rescan.maxX), height: statusH)
        let totalDividerY = floor((statusH - divider.height) / 2)
        let totalDividers = [
            CGRect(x: total.minX, y: totalDividerY, width: divider.width, height: divider.height),
            CGRect(x: total.maxX - divider.width, y: totalDividerY, width: divider.width, height: divider.height),
        ]
        return QueueFooterLayout(isCompact: compact, topRule: topRule, actionRule: actionRule,
                                 actionCells: cells, actionDividers: actionDividers,
                                 rescanCell: rescan, totalCell: total, clearCell: clear,
                                 totalDividers: totalDividers)
    }

    /// Every interactive section, for overlap and bounds checks.
    var sections: [CGRect] { actionCells + [rescanCell, clearCell] }
}

/// Where a footer marker's label and state mark sit inside its section (flipped coordinates:
/// y down from the top of the section).
enum QueueMarkerCellGeometry {
    /// Horizontal room for the label: the section minus its own padding (7 pt, 4 pt compact).
    static func labelWidthLimit(sectionWidth: CGFloat, isCompact: Bool) -> CGFloat {
        max(0, sectionWidth - 2 * (isCompact ? 4 : 7))
    }

    /// The 4 pt applied dot / mixed ring: top 7, right 7.
    static func markFrame(sectionWidth: CGFloat) -> CGRect {
        let mark = DWBMetrics.queueMarkerStateMark
        let inset = DWBMetrics.queueMarkerStateInset
        return CGRect(x: sectionWidth - inset - mark, y: inset, width: mark, height: mark)
    }

    /// The label's line box, centered in the section.
    static func labelFrame(sectionSize: CGSize, labelWidth: CGFloat, lineHeight: CGFloat) -> CGRect {
        CGRect(x: floor((sectionSize.width - labelWidth) / 2),
               y: floor((sectionSize.height - lineHeight) / 2),
               width: labelWidth, height: lineHeight)
    }
}

// MARK: - Rows (section 10.4)

enum QueueRowFillRole: Equatable { case none, overlayHover, overlaySelected, accentTintStrong }
enum QueueRowEdgeRole: Equatable { case none, border, borderStrong }

/// What a row draws for its state. Selected and hover edges, the playing strip and the separator
/// are decided here so the precedence is one rule, not scattered drawing code.
struct QueueRowAppearance: Equatable {
    let fill: QueueRowFillRole
    let edge: QueueRowEdgeRole
    /// The inner edge's width: 0.5 pt quiet edge, 1 pt selected edge.
    let edgeWidth: CGFloat
    let showsPlayingStrip: Bool
    /// The 0.5 pt gridLine under the row. Hidden on selected rows and on the playing card.
    let showsSeparator: Bool
    let cornerRadius: CGFloat

    static func resolve(isCurrent: Bool, isSelected: Bool, isHovering: Bool) -> QueueRowAppearance {
        if isCurrent {
            let edge: QueueRowEdgeRole = (isSelected || isHovering) ? .borderStrong : .border
            return QueueRowAppearance(fill: .accentTintStrong,
                                      edge: edge,
                                      edgeWidth: isSelected ? 1 : DWBMetrics.queuePlayingEdge,
                                      showsPlayingStrip: true,
                                      showsSeparator: false,
                                      cornerRadius: DWBMetrics.queuePlayingCardRadius)
        }
        if isSelected {
            return QueueRowAppearance(fill: .overlaySelected, edge: .borderStrong, edgeWidth: 1,
                                      showsPlayingStrip: false, showsSeparator: false,
                                      cornerRadius: DWBMetrics.queueFlatRowRadius)
        }
        return QueueRowAppearance(fill: isHovering ? .overlayHover : .none,
                                  edge: .none, edgeWidth: 0,
                                  showsPlayingStrip: false, showsSeparator: true,
                                  cornerRadius: DWBMetrics.queueFlatRowRadius)
    }
}

/// Row geometry in the row's flipped coordinates (y down from the top).
enum QueueRowMetrics {

    /// 44 pt for a flat row; 52 pt for the playing row (48 pt card + 4 pt gap below).
    static func height(isCurrent: Bool) -> CGFloat {
        isCurrent ? DWBMetrics.queuePlayingRowHeight : DWBMetrics.queueFlatRowHeight
    }

    static func cardHeight(isCurrent: Bool) -> CGFloat {
        isCurrent ? DWBMetrics.queuePlayingCardHeight : DWBMetrics.queueFlatRowHeight
    }

    /// The row's visible shape: 6 pt in from the list's left edge, and 6 + 4 pt in from its right edge.
    static func cardFrame(rowWidth: CGFloat, isCurrent: Bool) -> CGRect {
        let side = DWBMetrics.queueListSidePadding
        let trailing = side + DWBMetrics.queueRowTrailingMargin
        return CGRect(x: side, y: 0, width: max(0, rowWidth - side - trailing), height: cardHeight(isCurrent: isCurrent))
    }

    /// Where the text starts, from the card's leading edge.
    static func textInset(isCurrent: Bool, isFailed: Bool) -> CGFloat {
        if isCurrent { return DWBMetrics.queuePlayingTextInset }
        return isFailed ? DWBMetrics.queueRowTextInsetFailed : DWBMetrics.queueRowTextInset
    }

    static let bookmarkGlyph = CGSize(width: 10, height: 12)
    static let metaLine: CGFloat = 16

    struct Frames: Equatable {
        let name: CGRect
        let meta: CGRect
        let bookmark: CGRect?
        let leadingGlyph: CGRect?
    }

    /// The name line (18), the metadata line (16), the bookmark at the end of the name line, and the
    /// leading glyph (play.fill on the playing card, the warning triangle on a failed row).
    /// The accessory is reserved before the name is measured, so the name never runs under it.
    static func frames(card: CGRect, isCurrent: Bool, isFailed: Bool, hasBookmark: Bool) -> Frames {
        let x = card.minX + textInset(isCurrent: isCurrent, isFailed: isFailed)
        let right = card.maxX - DWBMetrics.queueRowTextTrailing
        let width = max(0, right - x)
        let blockH = DWBMetrics.queueRowNameLine + metaLine
        let top = card.minY + floor((card.height - blockH) / 2)

        var bookmark: CGRect?
        var nameWidth = width
        if hasBookmark {
            let glyph = bookmarkGlyph
            bookmark = CGRect(x: right - glyph.width, y: top + floor((DWBMetrics.queueRowNameLine - glyph.height) / 2),
                              width: glyph.width, height: glyph.height)
            nameWidth = max(0, width - glyph.width - DWBMetrics.queueRowNameGap)
        }
        var leading: CGRect?
        if isCurrent {
            let h: CGFloat = 15
            leading = CGRect(x: card.minX + DWBMetrics.queuePlayingGlyphLeading,
                             y: card.minY + floor((card.height - h) / 2),
                             width: DWBMetrics.queuePlayingGlyph, height: h)
        } else if isFailed {
            let h: CGFloat = 14
            leading = CGRect(x: card.minX + 9, y: card.minY + floor((card.height - h) / 2), width: 12, height: h)
        }
        return Frames(name: CGRect(x: x, y: top, width: nameWidth, height: DWBMetrics.queueRowNameLine),
                      meta: CGRect(x: x, y: top + DWBMetrics.queueRowNameLine, width: width, height: metaLine),
                      bookmark: bookmark,
                      leadingGlyph: leading)
    }

    /// The 0.5 pt separator under a flat row: inset 5 leading / 7 trailing from the card.
    static func separatorFrame(card: CGRect) -> CGRect {
        CGRect(x: card.minX + DWBMetrics.queueRowSeparatorInsetLeading,
               y: card.maxY - DWBMetrics.queueRowSeparator,
               width: max(0, card.width - DWBMetrics.queueRowSeparatorInsetLeading - DWBMetrics.queueRowSeparatorInsetTrailing),
               height: DWBMetrics.queueRowSeparator)
    }

    /// The 3 pt strip flush with the left edge of the playing card, full card height.
    static func playingStripFrame(card: CGRect) -> CGRect {
        CGRect(x: card.minX, y: card.minY, width: DWBMetrics.queuePlayingBar, height: card.height)
    }

    /// The path rect for an inner edge of `width`: drawn inside the card so nothing overhangs it.
    static func edgeRect(card: CGRect, width: CGFloat) -> CGRect {
        card.insetBy(dx: width / 2, dy: width / 2)
    }

    /// The drop insertion line's y in the table's coordinates: on the shared edge between two rows. After
    /// the playing row the line sits on the card's bottom edge, above its 4 pt gap.
    static func dropLineBoundaryY(rowMinY: CGFloat?, previousRowMaxY: CGFloat?, previousIsCurrent: Bool) -> CGFloat {
        if let rowMinY { return rowMinY }
        guard let previousRowMaxY else { return 0 }
        return previousIsCurrent ? previousRowMaxY - DWBMetrics.queuePlayingCardGap : previousRowMaxY
    }
}

// MARK: - Empty states (section 10.6)

/// Frames for the centered empty-state column (y up, in the list area).
struct QueueEmptyStateLayout: Equatable {
    enum Lead: Equatable { case appIcon, glyphCircle }

    let lead: CGRect
    let title: CGRect
    /// The detail line; only the genuine empty queue has one.
    let detail: CGRect?
    let button: CGRect

    static let titleLine: CGFloat = 20

    /// The width the column's text may use: the 320 max, and never wider than the area minus its padding.
    static func textWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, min(DWBMetrics.queueEmptyDetailMaxWidth, containerWidth - 2 * DWBMetrics.queueEmptyPadding))
    }

    /// - Parameters:
    ///   - detailHeight: the wrapped detail height at `textWidth` (empty queue only).
    ///   - buttonSize: the action button's size.
    static func make(lead: Lead, container: CGSize, detailHeight: CGFloat, buttonSize: CGSize) -> QueueEmptyStateLayout {
        let textW = textWidth(containerWidth: container.width)
        let leadSize = lead == .appIcon ? DWBMetrics.queueEmptyIcon : DWBMetrics.queueEmptyCircle
        let hasDetail = lead == .appIcon
        let total: CGFloat
        if hasDetail {
            total = leadSize + DWBMetrics.queueEmptyIconToTitle + titleLine + DWBMetrics.queueEmptyTitleToDetail
                + detailHeight + DWBMetrics.queueEmptyDetailToButton + buttonSize.height
        } else {
            total = leadSize + DWBMetrics.queueEmptyGap + titleLine + DWBMetrics.queueEmptyGap + buttonSize.height
        }
        var y = floor((container.height + total) / 2)   // top of the block

        y -= leadSize
        let leadFrame = CGRect(x: floor((container.width - leadSize) / 2), y: y, width: leadSize, height: leadSize)
        y -= (hasDetail ? DWBMetrics.queueEmptyIconToTitle : DWBMetrics.queueEmptyGap) + titleLine
        let titleFrame = CGRect(x: floor((container.width - textW) / 2), y: y, width: textW, height: titleLine)
        var detailFrame: CGRect?
        if hasDetail {
            y -= DWBMetrics.queueEmptyTitleToDetail + detailHeight
            detailFrame = CGRect(x: titleFrame.minX, y: y, width: textW, height: detailHeight)
            y -= DWBMetrics.queueEmptyDetailToButton + buttonSize.height
        } else {
            y -= DWBMetrics.queueEmptyGap + buttonSize.height
        }
        let buttonW = min(buttonSize.width, max(0, container.width - 2 * DWBMetrics.queueEmptyPadding))
        let buttonFrame = CGRect(x: floor((container.width - buttonW) / 2), y: y, width: buttonW, height: buttonSize.height)
        return QueueEmptyStateLayout(lead: leadFrame, title: titleFrame, detail: detailFrame, button: buttonFrame)
    }
}
