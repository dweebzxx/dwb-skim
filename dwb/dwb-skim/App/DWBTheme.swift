// dwb suite design system — AppKit reference (generated from tokens). sRGB, points.
import AppKit

enum DWBColor {
    static let canvas = NSColor(srgbRed: 0.118, green: 0.125, blue: 0.133, alpha: 1) // #1E2022
    static let surface = NSColor(srgbRed: 0.149, green: 0.161, blue: 0.173, alpha: 1) // #26292C
    static let surfaceElevated = NSColor(srgbRed: 0.188, green: 0.204, blue: 0.220, alpha: 1) // #303438
    static let surfaceSunken = NSColor(srgbRed: 0.098, green: 0.106, blue: 0.114, alpha: 1) // #191B1D
    static let gridLine = NSColor(srgbRed: 0.227, green: 0.247, blue: 0.267, alpha: 1) // #3A3F44
    static let border = NSColor(srgbRed: 0.306, green: 0.329, blue: 0.357, alpha: 1) // #4E545B
    static let borderStrong = NSColor(srgbRed: 0.502, green: 0.529, blue: 0.561, alpha: 1) // #80878F
    static let textPrimary = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 1) // #F2EEE9
    static let textSecondary = NSColor(srgbRed: 0.749, green: 0.769, blue: 0.788, alpha: 1) // #BFC4C9
    static let textTertiary = NSColor(srgbRed: 0.635, green: 0.659, blue: 0.682, alpha: 1) // #A2A8AE
    static let textDisabled = NSColor(srgbRed: 0.545, green: 0.569, blue: 0.596, alpha: 1) // #8B9198
    static let textOnFill = NSColor(srgbRed: 0.118, green: 0.125, blue: 0.133, alpha: 1) // #1E2022
    static let overlayHover = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.06) // #F2EEE9 @ 0.06
    static let overlaySelected = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.1) // #F2EEE9 @ 0.1
    static let overlayPressed = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.14) // #F2EEE9 @ 0.14
    static let backingChrome = NSColor(srgbRed: 0.118, green: 0.125, blue: 0.133, alpha: 0.88) // #1E2022 @ 0.88
    static let backingHUD = NSColor(srgbRed: 0.118, green: 0.125, blue: 0.133, alpha: 0.92) // #1E2022 @ 0.92
    static let backingTitle = NSColor(srgbRed: 0.118, green: 0.125, blue: 0.133, alpha: 0.8) // #1E2022 @ 0.8
    static let hairline = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.1) // #F2EEE9 @ 0.1
    static let track = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.18) // #F2EEE9 @ 0.18
    static let tick = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.55) // #F2EEE9 @ 0.55
    static let paneIdleBorder = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.12) // #F2EEE9 @ 0.12
    static let paneSelectedBorder = NSColor(srgbRed: 0.949, green: 0.933, blue: 0.914, alpha: 0.4) // #F2EEE9 @ 0.4
    static let successText = NSColor(srgbRed: 0.502, green: 0.769, blue: 0.596, alpha: 1) // #80C498
    static let successFill = NSColor(srgbRed: 0.314, green: 0.596, blue: 0.439, alpha: 1) // #509870
    static let cautionText = NSColor(srgbRed: 0.878, green: 0.753, blue: 0.376, alpha: 1) // #E0C060
    static let cautionFill = NSColor(srgbRed: 0.753, green: 0.565, blue: 0.188, alpha: 1) // #C09030
    static let errorText = NSColor(srgbRed: 0.878, green: 0.596, blue: 0.533, alpha: 1) // #E09888
    static let errorFill = NSColor(srgbRed: 0.784, green: 0.408, blue: 0.345, alpha: 1) // #C86858
    static let tealOnDark = NSColor(srgbRed: 0.588, green: 0.784, blue: 0.816, alpha: 1) // #96C8D0
    static let tealFillDark = NSColor(srgbRed: 0.282, green: 0.561, blue: 0.627, alpha: 1) // #488FA0
    static let periOnDark = NSColor(srgbRed: 0.565, green: 0.627, blue: 0.863, alpha: 1) // #90A0DC
    static let periFillDark = NSColor(srgbRed: 0.439, green: 0.502, blue: 0.776, alpha: 1) // #7080C6
    static let orangeOnDark = NSColor(srgbRed: 0.910, green: 0.541, blue: 0.282, alpha: 1) // #E88A48
    static let orangeFillDark = NSColor(srgbRed: 0.800, green: 0.416, blue: 0.188, alpha: 1) // #CC6A30
}

struct DWBTheme {
    let accentText: NSColor, accentFill: NSColor, markerPrimary: NSColor, markerSecondary: NSColor
    var accentSolid: NSColor { accentText }
    var accentTint: NSColor { accentFill.withAlphaComponent(0.18) }
    var accentTintStrong: NSColor { accentFill.withAlphaComponent(0.28) }
    func focusRing(increaseContrast: Bool) -> NSColor { increaseContrast ? accentText : accentFill }
    static let player = DWBTheme(accentText: DWBColor.periOnDark, accentFill: DWBColor.periFillDark, markerPrimary: DWBColor.orangeOnDark, markerSecondary: DWBColor.tealOnDark)
    static let skim = DWBTheme(accentText: DWBColor.tealOnDark, accentFill: DWBColor.tealFillDark, markerPrimary: DWBColor.periOnDark, markerSecondary: DWBColor.orangeOnDark)
    static let grid = DWBTheme(accentText: DWBColor.orangeOnDark, accentFill: DWBColor.orangeFillDark, markerPrimary: DWBColor.tealOnDark, markerSecondary: DWBColor.periOnDark)
}

enum DWBMetrics {
    static let railHeight: CGFloat = 68, railButton: CGFloat = 30, railButtonPrimary: CGFloat = 36
    // Optical rail icon scale (D16) — replaces flat railIcon 15.
    static let railIconUtility: CGFloat = 11, railIconVolume: CGFloat = 12, railIconSkip: CGFloat = 13, railIconPrimary: CGFloat = 17
    static let scrubberTrack: CGFloat = 2, scrubberRange: CGFloat = 4, knob: CGFloat = 6, knobEmphasized: CGFloat = 8
    // queueRowHeight 56 / queueRowInset 4 are the CLASSIC look (inactive alternative) and no longer drive the queue list.
    // The active queue metrics are the "Queue panel (active look)" block at the end of `DWBMetrics`.
    static let queueRowHeight: CGFloat = 56, queueRowInset: CGFloat = 4, queueHeaderHeight: CGFloat = 52
    static let settingsSize = NSSize(width: 820, height: 550), settingsMinSize = NSSize(width: 760, height: 500)
    static let sidebarWidth: CGFloat = 188, sidebarRow: CGFloat = 32, labelColumn: CGFloat = 156, contentMax: CGFloat = 620
    static let insets = NSEdgeInsets(top: 54, left: 30, bottom: 28, right: 26), columnGap: CGFloat = 14, rowGap: CGFloat = 13, sectionGap: CGFloat = 26
    static let radiusTag: CGFloat = 3, radiusKey: CGFloat = 4, radiusBanner: CGFloat = 5, radiusControl: CGFloat = 6, radiusRow: CGFloat = 8, radiusCard: CGFloat = 10, radiusPill: CGFloat = 12
    static let focusWidth: CGFloat = 2, focusWidthIC: CGFloat = 3, locatorWidth: CGFloat = 3
    static let disabledAlpha: CGFloat = 0.32
    // Gap-analysis additions (2026-10-03)
    static let pipPanelSize = NSSize(width: 300, height: 480), pipPanelWidthRange: ClosedRange<CGFloat> = 280...320, pipPanelMinHeight: CGFloat = 320, pipTitlebar: CGFloat = 22
    static let queueRowDense: CGFloat = 32, dropLine: CGFloat = 2, dropRing: CGFloat = 8, playNextTag: CGFloat = 16
    static let renameSheetWidth: CGFloat = 400, batchSheetWidth: CGFloat = 420, sheetFieldHeight: CGFloat = 24
    static let statusHUDMinHeight: CGFloat = 44, hudBottomOffset: CGFloat = 132
    static let paneChip: CGFloat = 22, paneChipGap: CGFloat = 4, paneSpinner: CGFloat = 28
    static let skimStripHeight: CGFloat = 54, skimWindowMinWidth: CGFloat = 980, skimRestoreHandle = NSSize(width: 30, height: 20)
    static let prefixSwatch: CGFloat = 8, aboutIcon: CGFloat = 96, aboutTitle: CGFloat = 26
    // Queue panel (active look, 2026-11-11) — tokens-and-specs §10. Colors come from DWBColor / DWBTheme; no new color tokens.
    // The panel width rule (31% of the window, 280–360, minimum 200) lives in `QueuePanelWidthPolicy`; the player-only
    // 45% / 260 rule and the handoff's `queuePanelMaxWidth` helper are intentionally not ported.
    // Panel (§10.1): surface, 1pt border leading edge, list padding 0 / 6 / 12. Compact below queueCompactBelow.
    static let queuePanelMinWidth: CGFloat = 200, queueCompactBelow: CGFloat = 390
    static let queueListSidePadding: CGFloat = 6, queueListBottomPadding: CGFloat = 12
    static let queueDividerHitWidth: CGFloat = 8 /* 4 each side */, queueDividerLine: CGFloat = 2, queueDividerLineAlpha: CGFloat = 0.7, queueDividerKeyStep: CGFloat = 10
    // Header (§10.2): 52 tall, no title, 1pt gridLine bottom.
    static let queueHeaderInset: CGFloat = 12, queueHeaderInsetCompact: CGFloat = 7, queueHeaderGap: CGFloat = 4
    static let queueSearchHeight: CGFloat = 28, queueSearchRadius: CGFloat = 6, queueHeaderButton: CGFloat = 28, queueHeaderButtonCompactWidth: CGFloat = 24, queueHeaderButtonRadius: CGFloat = 5
    static let queueSortLabelMaxWidth: CGFloat = 120
    // Rows (§10.4): flat row and the playing card (48 card + 4 gap = queuePlayingRowHeight).
    static let queueFlatRowHeight: CGFloat = 44, queueFlatRowRadius: CGFloat = 6, queueRowTrailingMargin: CGFloat = 4, queueRowTextInset: CGFloat = 5, queueRowTextInsetFailed: CGFloat = 27, queueRowTextTrailing: CGFloat = 10
    static let queueRowSeparator: CGFloat = 0.5, queueRowSeparatorInsetLeading: CGFloat = 5, queueRowSeparatorInsetTrailing: CGFloat = 7
    static let queuePlayingRowHeight: CGFloat = 52, queuePlayingCardHeight: CGFloat = 48, queuePlayingCardGap: CGFloat = 4, queuePlayingCardRadius: CGFloat = 7
    static let queuePlayingBar: CGFloat = 3, queuePlayingGlyph: CGFloat = 13, queuePlayingGlyphLeading: CGFloat = 14, queuePlayingTextInset: CGFloat = 37, queuePlayingEdge: CGFloat = 0.5
    static let queueRowNameLine: CGFloat = 18, queueRowNameGap: CGFloat = 6, queueRowDragAlpha: CGFloat = 0.4
    /// Middle truncation (§10.4): characters kept after the ellipsis = min(9, kept count / 2).
    static let queueNameTailMax = 9
    // Footer (§10.5): 78 tall, canvas, 1pt gridLine top. Row 1 = 39 incl. its 1pt rule; row 2 = 38.
    static let queueFooterHeight: CGFloat = 78, queueActionRowHeight: CGFloat = 39, queueStatusRowHeight: CGFloat = 38
    static let queueCellDivider = NSSize(width: 0.5, height: 18), queueCellDividerTop: CGFloat = 10, queueCellIcon: CGFloat = 15
    static let queueMarkerStateMark: CGFloat = 4, queueMarkerStateInset: CGFloat = 7, queueFooterDisabledAlpha: CGFloat = 0.4
    /// Footer cell hover / pressed: DWBColor.textPrimary at these alphas (from the study; not yet color tokens).
    static let queueCellHoverAlpha: CGFloat = 0.035, queueCellPressedAlpha: CGFloat = 0.075
    /// Status row columns: Rescan · total · Clear queue (compact hides the button labels).
    static let queueStatusColumns: (leading: CGFloat, trailing: CGFloat) = (100, 110), queueStatusColumnsCompact: (leading: CGFloat, trailing: CGFloat) = (34, 34)
    /// The total shortens until it fits the cell width minus this (§10.5).
    static let queueTotalFitInset: CGFloat = 16
    // Empty states (§10.6).
    // Empty queue: faded app icon, then 10 · title · 6 · detail (max 320) · 10 · outlined pill 26 r12.
    static let queueEmptyIcon: CGFloat = 96, queueEmptyIconAlpha: CGFloat = 0.32, queueEmptyIconSaturation: CGFloat = 0.6
    static let queueEmptyIconToTitle: CGFloat = 10, queueEmptyTitleToDetail: CGFloat = 6, queueEmptyDetailToButton: CGFloat = 10, queueEmptyDetailMaxWidth: CGFloat = 320, queueEmptyPill: CGFloat = 26
    // No search results / no bookmarks: glyph circle column.
    static let queueEmptyCircle: CGFloat = 44, queueEmptyGlyph: CGFloat = 18, queueEmptyGap: CGFloat = 13, queueEmptyPadding: CGFloat = 15, queueEmptyButtonRadius: CGFloat = 5
    // Sort menu (§10.7).
    static let queueSortMenuWidth: CGFloat = 190, queueSortMenuOffset: CGFloat = 4
}

enum DWBRailIcon {
    /// Optical point size for a rail symbol (D16).
    static func size(for symbol: String, primary: Bool = false) -> CGFloat {
        if primary { return DWBMetrics.railIconPrimary }
        if symbol.hasPrefix("speaker") || symbol == "ellipsis" { return DWBMetrics.railIconVolume }
        if ["gobackward", "goforward", "backward.end", "forward.end", "backward.frame", "forward.frame"].contains(where: symbol.hasPrefix) { return DWBMetrics.railIconSkip }
        return DWBMetrics.railIconUtility
    }
}

enum DWBMotion {
    static let hover: TimeInterval = 0.12, fade: TimeInterval = 0.18, rail: TimeInterval = 0.25
    static let volumeHold: TimeInterval = 1.25, scaleHUDHold: TimeInterval = 1.25, windowLimitHold: TimeInterval = 2.5, audioPulse: TimeInterval = 1.6, syncHold: TimeInterval = 1.8, failureHold: TimeInterval = 3.0, locatorHold: TimeInterval = 2.0
    static func duration(_ d: TimeInterval, reduceMotion: Bool) -> TimeInterval { reduceMotion ? 0 : d }
}
