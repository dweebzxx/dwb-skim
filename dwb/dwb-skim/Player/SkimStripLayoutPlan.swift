import CoreGraphics

/// Decides which Skim strip groups stay in the single 54 pt row and which move into the overflow
/// popover. The collapse chevron (and the overflow button, when it is needed) sit in a fixed
/// trailing slot, so they are never part of the width the groups compete for.
struct SkimStripLayoutPlan: Equatable {
    enum Metrics {
        static let leadingInset: CGFloat = 16
        static let trailingInset: CGFloat = 14
        static let groupGap: CGFloat = 18
        static let dividerWidth: CGFloat = 1
        static let collapseControl: CGFloat = 24
        static let overflowControl: CGFloat = 24
        /// Between the last visible group and the trailing slot.
        static let trailingGap: CGFloat = 18
        /// Between the overflow button and the collapse chevron.
        static let trailingControlGap: CGFloat = 6
    }

    /// The first `visibleCount` groups stay in the row, in order; the rest move to the overflow popover.
    let visibleCount: Int
    let totalCount: Int

    var overflowCount: Int { totalCount - visibleCount }
    var hasOverflow: Bool { overflowCount > 0 }

    /// The width a group adds to the row: its own width, the gap before it unless it is first,
    /// and its leading divider (with the gap after the divider) when it starts a cluster.
    static func advance(groupWidth: CGFloat, leadingDivider: Bool, isFirst: Bool) -> CGFloat {
        var width = groupWidth
        if !isFirst { width += Metrics.groupGap }
        if leadingDivider && !isFirst { width += Metrics.dividerWidth + Metrics.groupGap }
        return width
    }

    /// Keeps as many leading groups as fit. Everything fits in the full row at wide sizes; when it
    /// does not, the overflow button's slot is reserved and the trailing groups move into the popover.
    static func make(advances: [CGFloat], stripWidth: CGFloat) -> SkimStripLayoutPlan {
        let total = advances.count
        let reserved = Metrics.leadingInset + Metrics.trailingInset + Metrics.collapseControl + Metrics.trailingGap
        let room = stripWidth - reserved
        if advances.reduce(0, +) <= room {
            return SkimStripLayoutPlan(visibleCount: total, totalCount: total)
        }
        let roomWithOverflow = room - Metrics.overflowControl - Metrics.trailingControlGap
        var used: CGFloat = 0
        var visible = 0
        for advance in advances {
            guard used + advance <= roomWithOverflow else { break }
            used += advance
            visible += 1
        }
        return SkimStripLayoutPlan(visibleCount: visible, totalCount: total)
    }
}

/// Where the collapsed Skim restore tab sits: centered on the content area, its top edge flush with
/// the bottom of the titlebar.
enum SkimRestoreHandleGeometry {
    static let size = CGSize(width: 40, height: 24)
    static let minimumSideMargin: CGFloat = 8

    /// `bounds` is the window's content view; AppKit's origin is bottom-left, so flush-top is `maxY`.
    static func frame(in bounds: CGRect) -> CGRect {
        CGRect(x: max(minimumSideMargin, bounds.minX + (bounds.width - size.width) / 2),
               y: max(bounds.minY, bounds.maxY - size.height),
               width: size.width,
               height: size.height)
    }
}
