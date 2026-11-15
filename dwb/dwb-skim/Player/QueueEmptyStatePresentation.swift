import Foundation

/// Which empty state the queue panel shows, and its copy (design system 10.6).
enum QueueEmptyState: Equatable {
    /// The queue holds no files.
    case emptyQueue
    /// A search leaves no rows.
    case noMatches
    /// The bookmark filter alone leaves no rows.
    case noBookmarks

    /// `nil` when rows are visible.
    static func resolve(itemCount: Int,
                        visibleCount: Int,
                        query: String,
                        bookmarkFilterEnabled: Bool) -> QueueEmptyState? {
        if itemCount == 0 { return .emptyQueue }
        guard visibleCount == 0 else { return nil }
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return bookmarkFilterEnabled && !hasQuery ? .noBookmarks : .noMatches
    }

    var title: String {
        switch self {
        case .emptyQueue: return "No media in queue"
        case .noMatches: return "No matching files"
        case .noBookmarks: return "No bookmarked media"
        }
    }

    /// The helper line. Only the genuinely empty queue has one; the filtered states are a glyph, a title and one button.
    var detail: String? {
        switch self {
        case .emptyQueue: return "Add files or folders to build the queue."
        case .noMatches, .noBookmarks: return nil
        }
    }

    var actionTitle: String {
        switch self {
        case .emptyQueue: return "Add Media"
        case .noMatches: return "Clear Search"
        case .noBookmarks: return "Show All Media"
        }
    }

    /// The symbol inside the neutral circle. The empty queue shows the app icon instead.
    var glyphName: String? {
        switch self {
        case .emptyQueue: return nil
        case .noMatches: return "magnifyingglass"
        case .noBookmarks: return "bookmark"
        }
    }
}
