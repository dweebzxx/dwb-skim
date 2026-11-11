import AppKit

/// dwb skim's design-system theme. Every view reads colors from here or from `DWBColor`.
let theme = DWBTheme.skim

extension DWBColor {
    /// Canvas at 88%: badges and the strip restore handle (opaque under Increase Contrast).
    static let backingBadge = canvas.withAlphaComponent(0.88)
}

extension DWBTheme {
    /// Accent fill at 45%: the preview range and visited-segment bars.
    var accentRange: NSColor { accentFill.withAlphaComponent(0.45) }
}

extension DWBTheme {
    /// The marker fill stops (`marker-primary-fill`, `marker-secondary-fill`): the 18% chip tint
    /// and the applied chip's edge. Skim's `N` is Periwinkle and `M` is Burnt Orange.
    var markerPrimaryFill: NSColor { DWBColor.periFillDark }
    var markerSecondaryFill: NSColor { DWBColor.orangeFillDark }
}
