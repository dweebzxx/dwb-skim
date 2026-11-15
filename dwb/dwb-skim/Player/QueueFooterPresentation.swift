import Foundation

/// Pure footer logic for the active queue look (design system section 10.5): the status row's total.
/// It owns no views, so the decisions can be unit tested from plain numbers and real font measurement.
///
/// The total is always the whole queue's duration, as the window reports it (`totalDurationText`):
/// "HH:MM:SS", "HH:MM:SS +" when some durations are still unknown, or "--:--" when none are known.
/// Filtering changes only the item count, never the duration, and shortening never drops the "+".
enum QueueTotalPresentation {

    /// A parsed duration text.
    struct Duration: Equatable {
        /// Known whole seconds; nil for the all-unknown "--:--" (and anything unrecognized).
        let seconds: Int?
        /// Some items' durations are still unknown ("+").
        let isPartial: Bool
    }

    static func parse(_ text: String) -> Duration {
        var body = text.trimmingCharacters(in: .whitespaces)
        var partial = false
        if body.hasSuffix("+") {
            partial = true
            body = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]),
              h >= 0, (0..<60).contains(m), (0..<60).contains(s) else {
            return Duration(seconds: nil, isPartial: partial)
        }
        return Duration(seconds: h * 3600 + m * 60 + s, isPartial: partial)
    }

    /// "280 items", "1 item", or while a search or filter is active "12 of 280 items".
    static func countText(itemCount: Int, visibleCount: Int, isFiltered: Bool) -> String {
        let unit = itemCount == 1 ? "item" : "items"
        if isFiltered { return "\(visibleCount) of \(itemCount) \(unit)" }
        return "\(itemCount) \(unit)"
    }

    /// The candidates in the order they are tried: duration with count, duration alone, then hours and
    /// minutes, then (last resort) hours alone. An all-unknown total stays "--:--" in every candidate, and
    /// a partial total keeps its "+".
    static func candidates(durationText: String, countText: String) -> [String] {
        let full = durationText.trimmingCharacters(in: .whitespaces)
        var result = ["\(full) · \(countText)", full]
        let parsed = parse(durationText)
        if let seconds = parsed.seconds {
            let plus = parsed.isPartial ? " +" : ""
            result.append("\(seconds / 3600)h \(seconds % 3600 / 60)m\(plus)")
            result.append("\(seconds / 3600)h\(plus)")
        }
        return result
    }

    /// The first candidate that fits `availableWidth`. When none does, the shortest, so the total still
    /// reads as a duration; it is never an unknown value shown as zero.
    static func fit(durationText: String,
                    countText: String,
                    availableWidth: CGFloat,
                    measure: (String) -> CGFloat) -> String {
        let all = candidates(durationText: durationText, countText: countText)
        return all.first { measure($0) <= availableWidth } ?? all[all.count - 1]
    }

    /// The full total for the tooltip and the accessibility value: "Total: 111:32:18 · 280 items".
    static func fullText(durationText: String, countText: String) -> String {
        "Total: \(durationText.trimmingCharacters(in: .whitespaces)) · \(countText)"
    }
}
