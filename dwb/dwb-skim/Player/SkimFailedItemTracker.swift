import Foundation

/// Session-scoped record of which queue items have failed to become playable (P32, Part 3).
///
/// Identity is the window's own `queueItemIDs` UUID for a playback-set slot — the same stable
/// identity `QueueOrderPlanner`/`lastPlayedOrdinalByID` already use — never the media URL, so a
/// rename in place doesn't lose or duplicate a failure mark and doesn't need to migrate anything.
///
/// Deliberately holds nothing but a set: this is state/selection logic only. The caller
/// (`PlayerWindowController`) owns *detecting* a failure (VLC error state, exhausted playback-start
/// handshake) and owns *advancing* the queue (`advanceToNextItem`); this type only remembers which
/// items to route automatic selection around for the remainder of the current playback session.
///
/// Session-scoped by construction: a `PlayerWindowController` resets its instance whenever the
/// queue is replaced wholesale (`openAndPlay`) or cleared (`removeAllQueueItems`), never on a
/// per-item basis — a failure here is not written back to settings or the filesystem, so it can
/// never make a file permanently unplayable. Explicit user reselection of a failed item (queue-panel
/// pick, Next, Previous) clears that one item's mark, which is the only way a marked item plays
/// automatically again.
struct SkimFailedItemTracker: Equatable {
    private(set) var failedItemIDs: Set<String> = []

    /// Marks `id` failed for the remainder of the session. Returns `true` the first time `id` is
    /// marked, `false` if it was already marked (repeat failures of the same item are not tracked
    /// as distinct events — the item was already being suppressed from automatic retry).
    @discardableResult
    mutating func markFailed(_ id: String) -> Bool {
        failedItemIDs.insert(id).inserted
    }

    func isFailed(_ id: String) -> Bool {
        failedItemIDs.contains(id)
    }

    /// Explicit user retry: clears one item's failure mark so automatic selection can choose it
    /// again. Never affects any other item's mark.
    mutating func clearFailed(_ id: String) {
        failedItemIDs.remove(id)
    }

    /// New playback session (queue replaced/cleared): every mark is forgotten. A failed item is
    /// never permanently blacklisted — this is the ordinary path back to eligibility, alongside
    /// explicit per-item retry via `clearFailed`.
    mutating func reset() {
        failedItemIDs.removeAll()
    }

    /// True when every id in `ids` is marked failed — the condition under which automatic queue
    /// advancement must stop rather than keep walking (or wrapping, under Loop Queue) forever.
    /// `ids` empty is not "all failed": there is nothing to have failed.
    func allFailed(among ids: [String]) -> Bool {
        !ids.isEmpty && ids.allSatisfy(isFailed)
    }
}
