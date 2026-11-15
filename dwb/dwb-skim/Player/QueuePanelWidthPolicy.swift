import CoreGraphics

/// Width rules for the windowed queue panel (`queueW`: the 1 pt separator plus the panel).
///
/// The default width is the maximum: 31% of the window content width, kept between 280 and
/// 360 pt. Dragging the shared edge can only narrow the panel, down to 200 pt. A custom width
/// is held as a fraction of the content width, so the panel keeps its proportion when the
/// window is resized. Pure: no AppKit types.
enum QueuePanelWidthPolicy {
    static let minimumWidth: CGFloat = 200
    static let defaultFraction: CGFloat = 0.31
    static let defaultFloor: CGFloat = 280
    static let defaultCeiling: CGFloat = 360
    /// A drag that ends this close to the maximum clears the custom width.
    static let maximumSnapTolerance: CGFloat = 0.5
    /// The grab zone reaches this far to each side of the shared edge.
    static let grabZoneHalfWidth: CGFloat = 4

    /// The default, and widest, panel width for a window content width.
    static func maximumWidth(contentWidth: CGFloat) -> CGFloat {
        min(defaultCeiling, max(defaultFloor, contentWidth * defaultFraction))
    }

    static func clampedWidth(_ width: CGFloat, contentWidth: CGFloat) -> CGFloat {
        min(maximumWidth(contentWidth: contentWidth), max(minimumWidth, width))
    }

    /// The panel width for a content width, with an optional custom fraction.
    static func width(contentWidth: CGFloat, customFraction: CGFloat?) -> CGFloat {
        guard let customFraction else { return maximumWidth(contentWidth: contentWidth) }
        return clampedWidth(contentWidth * customFraction, contentWidth: contentWidth)
    }

    /// The fraction to store when the shared edge is dragged to `edgeX` (content view
    /// coordinates), or nil when the clamped width is at the maximum.
    static func customFraction(forEdgeX edgeX: CGFloat, contentWidth: CGFloat) -> CGFloat? {
        guard contentWidth > 0 else { return nil }
        let width = clampedWidth(contentWidth - edgeX, contentWidth: contentWidth)
        if width >= maximumWidth(contentWidth: contentWidth) - maximumSnapTolerance { return nil }
        return width / contentWidth
    }
}
