import CoreGraphics

/// Where the generic popover panel sits and where its arrow points (design system "Popover", 5 and 9.8).
/// The panel opens 8 pt below its anchor and overhangs the anchor by 14 pt on the trailing side, so the
/// 10 pt arrow sits 26 pt in from that edge and points at the anchor's center. When there is no room
/// below, it opens above. Frames are in screen coordinates (origin at the bottom left).
enum DWBPopoverGeometry {
    static let radius: CGFloat = 10
    static let inset: CGFloat = 14
    static let groupGap: CGFloat = 14
    /// The distance from the anchor to the panel edge.
    static let anchorOffset: CGFloat = 8
    /// How far the panel extends past the anchor on its aligned (trailing) side.
    static let overhang: CGFloat = 14
    /// The arrow is a 10 pt square turned 45 degrees; this is how far its tip stands out of the panel edge.
    static let arrowRise: CGFloat = 8
    static let screenMargin: CGFloat = 8
    /// Room around the panel for the popover shadow (0 12 32, black 50%).
    static let shadowMargin: CGFloat = 40

    struct Placement: Equatable {
        /// The panel body (without the arrow or the shadow room).
        let bodyFrame: CGRect
        /// Where the arrow's tip is, along the panel's width.
        let arrowCenterX: CGFloat
        /// `true` when the panel is below the anchor, so the arrow is on the panel's top edge.
        let arrowOnTop: Bool
    }

    static func place(anchor: CGRect, size: CGSize, visibleFrame: CGRect) -> Placement {
        var x = anchor.maxX + overhang - size.width
        let minX = visibleFrame.minX + screenMargin
        let maxX = visibleFrame.maxX - screenMargin - size.width
        x = max(minX, min(maxX, x))

        var onTop = true
        var y = anchor.minY - anchorOffset - size.height
        if y < visibleFrame.minY + screenMargin {
            onTop = false
            y = anchor.maxY + anchorOffset
        }

        let body = CGRect(origin: CGPoint(x: x, y: y), size: size)
        // The arrow points at the anchor's center, kept clear of the rounded corners.
        let clearance = radius + arrowRise
        let arrowX = max(body.minX + clearance, min(body.maxX - clearance, anchor.midX))
        return Placement(bodyFrame: body, arrowCenterX: arrowX, arrowOnTop: onTop)
    }
}
