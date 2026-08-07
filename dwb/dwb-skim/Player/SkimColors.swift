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

    /// Dark-theme selection fill from the endorsed Dark Teal 500 token (#488FA0).
    static let darkTeal500 = NSColor(calibratedRed: 72.0 / 255.0,
                                     green: 143.0 / 255.0,
                                     blue: 160.0 / 255.0,
                                     alpha: 1.0)

    /// High-contrast dark-theme accent text from Periwinkle 300 (#9AAAD8).
    static let periwinkle300 = NSColor(calibratedRed: 154.0 / 255.0,
                                       green: 170.0 / 255.0,
                                       blue: 216.0 / 255.0,
                                       alpha: 1.0)

    /// Quiet selected text from Periwinkle 100 (#EEEFF8).
    static let periwinkle100 = NSColor(calibratedRed: 238.0 / 255.0,
                                       green: 239.0 / 255.0,
                                       blue: 248.0 / 255.0,
                                       alpha: 1.0)

    /// Dark-theme destructive emphasis from Burnt Orange 300 (#D4906A).
    static let burntOrange300 = NSColor(calibratedRed: 212.0 / 255.0,
                                        green: 144.0 / 255.0,
                                        blue: 106.0 / 255.0,
                                        alpha: 1.0)

    /// Semantic token for Rename and configured custom-rename presentation.
    static let rename = darkTeal
}
