import Cocoa

/// Display-only marker status derived from a filename and the two configured
/// marker prefixes (primary on `N`, secondary on `M`).
///
/// This type does not own queue state and does not imply any filesystem action.
enum SkimReviewStatus: Equatable {
    case primary
    case secondary
    case unmarked

    var color: NSColor? {
        switch self {
        case .primary: return theme.markerPrimary
        case .secondary: return theme.markerSecondary
        case .unmarked: return nil
        }
    }
}

struct SkimReviewStatusDescriptor {
    let status: SkimReviewStatus
    let prefixToken: String?
    let visibleFilename: String
    let statusColor: NSColor?

    /// A filename that starts with the primary prefix is the primary marker,
    /// and one that starts with the secondary prefix is the secondary marker.
    /// A blank prefix recognizes nothing. When both prefixes match, the longer
    /// one is the prefix actually present, as in
    /// `SkimFileRenamer.customPrefixToggleTargetFilename`.
    static func describe(displayName: String,
                         primaryPrefix: String,
                         secondaryPrefix: String) -> SkimReviewStatusDescriptor {
        let hasPrimary = !primaryPrefix.isEmpty && displayName.hasPrefix(primaryPrefix)
        let hasSecondary = !secondaryPrefix.isEmpty && displayName.hasPrefix(secondaryPrefix)

        let status: SkimReviewStatus
        let prefixToken: String?
        if hasPrimary && (!hasSecondary || primaryPrefix.count >= secondaryPrefix.count) {
            status = .primary
            prefixToken = primaryPrefix
        } else if hasSecondary {
            status = .secondary
            prefixToken = secondaryPrefix
        } else {
            status = .unmarked
            prefixToken = nil
        }

        let visibleFilename = prefixToken.map { String(displayName.dropFirst($0.count)) } ?? displayName
        return SkimReviewStatusDescriptor(status: status,
                                          prefixToken: prefixToken,
                                          visibleFilename: visibleFilename,
                                          statusColor: status.color)
    }

    static func describe(url: URL,
                         primaryPrefix: String,
                         secondaryPrefix: String) -> SkimReviewStatusDescriptor {
        describe(displayName: url.lastPathComponent,
                 primaryPrefix: primaryPrefix,
                 secondaryPrefix: secondaryPrefix)
    }
}
