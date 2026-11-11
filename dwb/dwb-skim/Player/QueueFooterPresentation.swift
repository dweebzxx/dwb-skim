import Foundation

/// Pure footer logic for the queue panel: where the marker group sits, and the total label.
/// It owns no views, so the decisions can be unit tested from plain numbers.
enum QueueFooterPresentation {

    /// The corner radius of the marker group's outline and of every highlight drawn inside it: the applied
    /// chip fill and its edge, the chip hover fill, and Undo's hover fill.
    static let markerGroupCornerRadius: CGFloat = DWBMetrics.radiusPill

    /// How the Remove button and the marker group share the top of the footer.
    enum MarkerGroupPlan: Equatable {
        /// 1. Remove and the full marker group on one row.
        case sharedRow
        /// 2. Remove and the marker group with glyph-only Undo on one row.
        case sharedRowCompactUndo
        /// 3. The marker group wraps to its own row below Remove. Undo is glyph-only
        ///    when the full group does not fit that row.
        case ownRow(compactUndo: Bool)

        var isUndoCompact: Bool {
            switch self {
            case .sharedRow: return false
            case .sharedRowCompactUndo: return true
            case .ownRow(let compactUndo): return compactUndo
            }
        }

        var wrapsMarkerGroup: Bool {
            if case .ownRow = self { return true }
            return false
        }
    }

    /// Picks the marker group's placement, in this order: full group beside Remove; glyph-only
    /// Undo beside Remove; the group on its own row. Nothing is ever collapsed into a menu.
    ///
    /// - Parameters:
    ///   - availableWidth: The row width inside the footer's side padding.
    ///   - removeWidth: The Remove button's width.
    ///   - fullGroupWidth: The marker group's width with "Undo" spelled out.
    ///   - compactGroupWidth: The marker group's width with glyph-only Undo.
    ///   - itemGap: The gap between items in a row.
    static func markerGroupPlan(availableWidth: CGFloat,
                                removeWidth: CGFloat,
                                fullGroupWidth: CGFloat,
                                compactGroupWidth: CGFloat,
                                itemGap: CGFloat) -> MarkerGroupPlan {
        if removeWidth + itemGap + fullGroupWidth <= availableWidth { return .sharedRow }
        if removeWidth + itemGap + compactGroupWidth <= availableWidth { return .sharedRowCompactUndo }
        return .ownRow(compactUndo: fullGroupWidth > availableWidth)
    }

    /// "Total: 00:12:34 | 3 items" ("1 item", "0 items"), or "Total: 00:12:34 | 2/3 shown" while a
    /// search or filter is active.
    static func totalText(duration: String,
                          itemCount: Int,
                          visibleCount: Int,
                          isFiltered: Bool) -> String {
        if isFiltered { return "Total: \(duration) | \(visibleCount)/\(itemCount) shown" }
        return "Total: \(duration) | \(itemCount) \(itemCount == 1 ? "item" : "items")"
    }
}
