import Cocoa

/// Centralized skim accent/status color tokens. See docs/skim-m1-plan.md for the
/// palette rationale and the M1 review-status mapping (keep/delete/rename/other).
enum SkimColors {
    /// Dark Teal (#254F58): primary skim accent and custom tagged filename text.
    static let darkTeal = NSColor(calibratedRed: 37.0 / 255.0,
                                  green: 79.0 / 255.0,
                                  blue: 88.0 / 255.0,
                                  alpha: 1.0)

    /// Burnt Orange (#8F4218): "delete" / destructive review status.
    static let burntOrange = NSColor(calibratedRed: 143.0 / 255.0,
                                     green: 66.0 / 255.0,
                                     blue: 24.0 / 255.0,
                                     alpha: 1.0)

    /// Periwinkle (#4C62A8): categorical review accent.
    static let periwinkle = NSColor(calibratedRed: 76.0 / 255.0,
                                    green: 98.0 / 255.0,
                                    blue: 168.0 / 255.0,
                                    alpha: 1.0)

    /// Semantic token for Rename and configured custom-rename presentation.
    static let rename = darkTeal
}
