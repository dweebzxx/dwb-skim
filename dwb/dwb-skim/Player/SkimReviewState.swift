import Foundation

/// Explicit, user-set review intent for a queue item.
///
/// This is in-memory/session-only state (see `SkimReviewStateStore`). Keep and
/// delete remain prefix-based *display* concepts (`keep_` / `delete_`). Rename
/// is an immediate file operation handled outside this state store, not a
/// pending review intent and not a `rename_` prefix.
enum SkimReviewIntent: Equatable {
    case unmarked
    case keep
    case delete
}

/// In-memory, per-window store of explicit review intents, keyed by a queue
/// item's standardized file path.
///
/// Never persisted (no UserDefaults, no disk, no sidecar files) and never
/// performs a filesystem operation.
final class SkimReviewStateStore {

    private struct Change {
        let key: String
        let previous: SkimReviewIntent
    }

    private var intents: [String: SkimReviewIntent] = [:]
    private var history: [Change] = []

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    func intent(for url: URL) -> SkimReviewIntent {
        intents[Self.key(for: url)] ?? .unmarked
    }

    func setKeep(for url: URL) {
        setIntent(.keep, for: url)
    }

    func setDelete(for url: URL) {
        setIntent(.delete, for: url)
    }

    /// Clears the in-memory review state for a single item.
    func clear(for url: URL) {
        setIntent(.unmarked, for: url)
    }

    /// Moves any keep/delete review state to a renamed URL, preserving the
    /// user's mark after a successful same-directory filesystem rename.
    func migrateIntent(from oldURL: URL, to newURL: URL) {
        let oldKey = Self.key(for: oldURL)
        let newKey = Self.key(for: newURL)
        guard oldKey != newKey else { return }
        let existing = intents.removeValue(forKey: oldKey)
        if let existing {
            intents[newKey] = existing
        } else {
            intents.removeValue(forKey: newKey)
        }
    }

    /// Reverts the most recent in-memory review-state change across all items, if any.
    func undoLastChange() {
        guard let change = history.popLast() else { return }
        if case .unmarked = change.previous {
            intents.removeValue(forKey: change.key)
        } else {
            intents[change.key] = change.previous
        }
    }

    private func setIntent(_ intent: SkimReviewIntent, for url: URL) {
        let key = Self.key(for: url)
        let previous = intents[key] ?? .unmarked
        guard previous != intent else { return }
        history.append(Change(key: key, previous: previous))
        if case .unmarked = intent {
            intents.removeValue(forKey: key)
        } else {
            intents[key] = intent
        }
    }
}

extension SkimReviewStatusDescriptor {
    /// Builds a descriptor for a queue row, giving an explicit P08 in-memory
    /// intent priority over the P07 legacy filename-prefix compatibility
    /// display. When `explicitIntent` is `.unmarked`, this falls back to the
    /// P07 prefix-derived display so existing `keep_`/`delete_`/`rename_`
    /// filenames keep reading as before.
    static func describe(displayName: String, explicitIntent: SkimReviewIntent) -> SkimReviewStatusDescriptor {
        switch explicitIntent {
        case .unmarked:
            return describe(displayName: displayName)
        case .keep:
            return SkimReviewStatusDescriptor(status: .keep,
                                              prefixToken: SkimReviewStatus.keep.prefixToken,
                                              visibleFilename: displayName,
                                              statusColor: SkimReviewStatus.keep.color,
                                              statusLabel: SkimReviewStatus.keep.accessibilityLabel)
        case .delete:
            return SkimReviewStatusDescriptor(status: .delete,
                                              prefixToken: SkimReviewStatus.delete.prefixToken,
                                              visibleFilename: displayName,
                                              statusColor: SkimReviewStatus.delete.color,
                                              statusLabel: SkimReviewStatus.delete.accessibilityLabel)
        }
    }
}
