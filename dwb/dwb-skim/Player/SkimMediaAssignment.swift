import Foundation

/// Identifies one logical player-media assignment for a single window.
///
/// This exists because VLCKit's wrapper objects are not a usable identity. When
/// `VLCMediaPlayer.media` is assigned, VLCKit calls `libvlc_media_player_set_media_async`
/// and later handles the resulting `MediaPlayerMediaChanged` event by allocating a *new*
/// `VLCMedia` wrapper (`+[VLCMedia mediaWithLibVLCMediaDescriptor:]`) around the same
/// underlying `libvlc_media_t` and overwriting its own `media` ivar with it. The wrapper the
/// caller assigned and the wrapper the getter later returns are therefore different objects
/// that describe the same assignment, so `ObjectIdentifier` comparisons of them always fail.
///
/// The generations below are minted by the window that owns the player, never derived from a
/// wrapper, so they stay stable for the life of an assignment.
struct SkimMediaAssignmentToken: Equatable, CustomStringConvertible {
    /// Increments each time the window installs a different `VLCMediaPlayer`.
    let playerGeneration: Int
    /// Increments for every logical media assignment made to any player in this window.
    let assignmentGeneration: Int

    var description: String { "p\(playerGeneration)/m\(assignmentGeneration)" }
}

/// Window-owned record of which media assignment the current player carries.
///
/// Per-window by construction: each `PlayerWindowController` holds its own registry, so no
/// generation is shared between windows.
struct SkimMediaAssignmentRegistry {
    private(set) var playerGeneration = 0
    private(set) var assignmentGeneration = 0
    private(set) var current: SkimMediaAssignmentToken?

    /// Records that a genuinely new `VLCMediaPlayer` now backs this window. Any assignment made
    /// to the replaced player stops being current, so its in-flight callbacks are rejected.
    @discardableResult
    mutating func installPlayer() -> Int {
        playerGeneration += 1
        current = nil
        return playerGeneration
    }

    /// Mints the token for one media assignment. Called once per logical assignment, immediately
    /// around the `player.media = ...` write, and never recomputed from a wrapper afterwards.
    @discardableResult
    mutating func assign() -> SkimMediaAssignmentToken {
        assignmentGeneration += 1
        let token = SkimMediaAssignmentToken(playerGeneration: playerGeneration,
                                             assignmentGeneration: assignmentGeneration)
        current = token
        return token
    }

    /// Drops the current assignment without retiring the player, e.g. when the window stops
    /// carrying video. Generations never rewind, so a later assignment cannot reuse a token.
    mutating func clear() {
        current = nil
    }

    /// True when `token` is the assignment this window's current player is carrying.
    func isCurrent(_ token: SkimMediaAssignmentToken) -> Bool {
        current == token
    }
}
