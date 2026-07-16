import Cocoa

/// Display-only review status derived from a filename prefix.
///
/// This type does not own queue state and does not imply any filesystem action.
enum SkimReviewStatus: Equatable {
    case keep
    case delete
    case rename
    case unmarked

    var prefixToken: String? {
        switch self {
        case .keep: return "keep_"
        case .delete: return "delete_"
        case .rename: return "rename_"
        case .unmarked: return nil
        }
    }

    var color: NSColor? {
        switch self {
        case .keep: return SkimColors.darkTeal
        case .delete: return SkimColors.burntOrange
        case .rename: return SkimColors.periwinkle
        case .unmarked: return nil
        }
    }

    var accessibilityLabel: String? {
        switch self {
        case .keep: return "keep"
        case .delete: return "delete"
        case .rename: return "rename"
        case .unmarked: return nil
        }
    }
}

struct SkimReviewStatusDescriptor {
    let status: SkimReviewStatus
    let prefixToken: String?
    let visibleFilename: String
    let statusColor: NSColor?
    let statusLabel: String?

    static func describe(displayName: String) -> SkimReviewStatusDescriptor {
        let status = statusForDisplayName(displayName)
        let prefixToken = status.prefixToken
        let visibleFilename: String
        if let prefixToken, displayName.hasPrefix(prefixToken) {
            visibleFilename = String(displayName.dropFirst(prefixToken.count))
        } else {
            visibleFilename = displayName
        }
        return SkimReviewStatusDescriptor(status: status,
                                          prefixToken: prefixToken,
                                          visibleFilename: visibleFilename,
                                          statusColor: status.color,
                                          statusLabel: status.accessibilityLabel)
    }

    static func describe(url: URL) -> SkimReviewStatusDescriptor {
        describe(displayName: url.lastPathComponent)
    }

    private static func statusForDisplayName(_ displayName: String) -> SkimReviewStatus {
        if displayName.hasPrefix("keep_") { return .keep }
        if displayName.hasPrefix("delete_") { return .delete }
        if displayName.hasPrefix("rename_") { return .rename }
        return .unmarked
    }
}
