import Foundation

/// Locates the queue search match to highlight in a filename (design system 9.7).
///
/// The match options are the ones the queue filter uses, so every row the filter keeps
/// has a match to show.
enum QueueSearchHighlight {
    static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The first match of `query` in `name`, or `nil` when the query is blank or absent.
    static func matchRange(in name: String, query: String) -> NSRange? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let range = name.range(of: trimmed, options: matchOptions) else { return nil }
        return NSRange(range, in: name)
    }
}
