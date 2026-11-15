import AppKit

// Measured text fitting for the active queue (design system section 10.4 and 10.5). Every rule takes a
// `measure` closure, so the decisions are the same ones the views make with real native font
// measurement and can be tested the same way.

/// The fonts the queue measures and draws with, so a fit decision and the drawing never disagree.
enum QueueFonts {
    static func name(isCurrent: Bool) -> NSFont { .systemFont(ofSize: 12.5, weight: isCurrent ? .semibold : .medium) }
    static let namePrefix = NSFont.systemFont(ofSize: 12.5, weight: .bold)
    static let metadata = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
    /// Marker cell label: 11 medium, tabular digits.
    static let marker = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    static let utility = NSFont.systemFont(ofSize: 10.5, weight: .regular)
    static let total = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)

    /// The width of `string` set in `font`, rounded up to whole points.
    static func width(of string: String, font: NSFont) -> CGFloat {
        ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }
}

/// Middle truncation of filenames (section 10.4): drop one character at a time, keeping
/// min(9, kept count / 2) characters after the ellipsis, until the name fits.
enum QueueNameFitting {

    enum Fit: Equatable {
        /// The whole name fits.
        case full
        /// `head` characters, an ellipsis, then `tail` characters.
        case middle(head: Int, tail: Int)
        /// Nothing but the ellipsis fits.
        case ellipsisOnly
    }

    /// Characters kept after the ellipsis when `keptCount` characters are kept in all.
    static func tailLength(keptCount: Int) -> Int {
        min(DWBMetrics.queueNameTailMax, keptCount / 2)
    }

    /// - Parameters:
    ///   - characterCount: the name's length in characters.
    ///   - maxWidth: the width available to the name after its accessories are reserved.
    ///   - measure: the width of the name shown with the given fit.
    static func fit(characterCount: Int, maxWidth: CGFloat, measure: (Fit) -> CGFloat) -> Fit {
        if measure(.full) <= maxWidth { return .full }
        var kept = characterCount - 1
        while kept > 0 {
            let tail = tailLength(keptCount: kept)
            let candidate = Fit.middle(head: kept - tail, tail: tail)
            if measure(candidate) <= maxWidth { return candidate }
            kept -= 1
        }
        return .ellipsisOnly
    }

    /// The attributed name shown for a fit. The name itself is never changed; only what is drawn.
    static func apply(_ fit: Fit, to name: NSAttributedString) -> NSAttributedString {
        let string = name.string
        let count = string.count
        switch fit {
        case .full:
            return name
        case .ellipsisOnly:
            return NSAttributedString(string: "…", attributes: name.length > 0 ? name.attributes(at: 0, effectiveRange: nil) : [:])
        case .middle(let head, let tail):
            guard head >= 0, tail >= 0, head + tail < count else { return name }
            let headEnd = string.index(string.startIndex, offsetBy: head)
            let tailStart = string.index(string.endIndex, offsetBy: -tail)
            let result = NSMutableAttributedString(attributedString: name)
            let range = NSRange(headEnd..<tailStart, in: string)
            // The ellipsis takes the attributes of the character before it, so a long prefix keeps its color.
            let attributesIndex = max(0, min(name.length - 1, range.location > 0 ? range.location - 1 : 0))
            let attributes = name.length > 0 ? name.attributes(at: attributesIndex, effectiveRange: nil) : [:]
            result.replaceCharacters(in: range, with: NSAttributedString(string: "…", attributes: attributes))
            return result
        }
    }

    /// Fits an attributed name by measuring each candidate in its real fonts.
    static func fitted(_ name: NSAttributedString, maxWidth: CGFloat) -> NSAttributedString {
        let fit = fit(characterCount: name.string.count, maxWidth: maxWidth) { candidate in
            ceil(apply(candidate, to: name).size().width)
        }
        return apply(fit, to: name)
    }
}

/// Shortens a configured prefix shown in a footer marker cell. The full prefix always stays in the
/// tooltip and the accessibility label.
enum QueuePrefixLabelFitting {

    /// The whole text when it fits; otherwise the longest leading part plus an ellipsis that fits.
    /// Falls back to the ellipsis alone when not even one character fits.
    static func fit(_ text: String, maxWidth: CGFloat, measure: (String) -> CGFloat) -> String {
        if measure(text) <= maxWidth { return text }
        var kept = text.count - 1
        while kept > 0 {
            let candidate = String(text.prefix(kept)) + "…"
            if measure(candidate) <= maxWidth { return candidate }
            kept -= 1
        }
        return "…"
    }

    static func fit(_ text: String, maxWidth: CGFloat, font: NSFont = QueueFonts.marker) -> String {
        fit(text, maxWidth: maxWidth) { QueueFonts.width(of: $0, font: font) }
    }
}

/// Row metadata copy (section 10.4).
enum QueueRowTextPresentation {
    static let failedMetaFull = "Playback failed · Double-click to retry"
    static let failedMetaShort = "Playback failed"

    /// "5:58 · 58.5 MB".
    static func metadata(duration: String, fileSize: String) -> String {
        "\(duration) · \(fileSize)"
    }

    /// The failed-row message that fits `maxWidth`: the full sentence, then its first clause.
    /// The full sentence is always in the tooltip and the accessibility help.
    static func failedMeta(maxWidth: CGFloat, measure: (String) -> CGFloat) -> String {
        measure(failedMetaFull) <= maxWidth ? failedMetaFull : failedMetaShort
    }
}

/// The attributes of a row's filename (sections 5 "File markers", 9.7 and 10.4).
enum QueueNameStyle {

    /// The row's filename, with its configured marker prefix in bold marker color at 100% (primary and secondary use
    /// the same classifier as the renamer, so overlapping prefixes agree) and the first case- and accent-insensitive
    /// search match in bold on an `accentTintStrong` ground with a 1 pt `accentText` underline. The playing row's
    /// name is semibold; every other name is medium. The text itself is never changed.
    static func attributed(for name: String,
                           isCurrent: Bool,
                           searchQuery: String,
                           primaryPrefix: String,
                           secondaryPrefix: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: name, attributes: [
            .font: QueueFonts.name(isCurrent: isCurrent),
            .foregroundColor: DWBColor.textPrimary,
        ])

        let marker = SkimReviewStatusDescriptor.describe(displayName: name,
                                                         primaryPrefix: primaryPrefix,
                                                         secondaryPrefix: secondaryPrefix)
        if let token = marker.prefixToken, let color = marker.statusColor {
            result.addAttributes([
                .font: QueueFonts.namePrefix,
                .foregroundColor: color,
            ], range: NSRange(location: 0, length: (token as NSString).length))
        }

        if let match = QueueSearchHighlight.matchRange(in: name, query: searchQuery) {
            result.addAttributes([
                .font: QueueFonts.namePrefix,
                .backgroundColor: theme.accentTintStrong,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: theme.accentText,
            ], range: match)
        }
        return result
    }
}
