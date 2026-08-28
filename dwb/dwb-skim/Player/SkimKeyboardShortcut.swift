import AppKit

/// Pure mapping from an unmodified key press to the player-window action it
/// invokes. Extracted so the shortcut table can be unit-tested without driving
/// AppKit event plumbing; `PlayerWindowController.handleSkimShortcut` is the
/// only production caller and owns modifier rejection and text-entry guards.
///
/// P36 mapping (unmodified keys):
///
/// | Key | Action                        |
/// | --- | ----------------------------- |
/// | `,` | Previous Video                |
/// | `.` | Next Video                     |
/// | `n` | Primary Prefix Rename         |
/// | `m` | Secondary Prefix Rename       |
/// | `k` | Review keep_                  |
/// | `d` | Review delete_                |
/// | `r` | Rename sheet                  |
/// | `z` | Review undo                   |
/// | `q` | Toggle queue panel            |
/// | ` ` | Play / Pause                  |
/// | `f` | Toggle fullscreen             |
/// | `→` | Advance Progressive Random Skim segment |
///
/// P36 removed the pre-P36 bindings `[` (Previous Video), `]` (Next Video), and
/// `m` (Mute). Those keys are intentionally absent from this table so they no
/// longer trigger any action.
enum SkimKeyboardShortcut: Equatable, CaseIterable {
    case reviewKeep
    case reviewDelete
    case renameSheet
    case reviewUndo
    case previousVideo
    case nextVideo
    case primaryPrefixRename
    case secondaryPrefixRename
    case toggleQueuePanel
    case togglePlayPause
    case toggleFullScreen
    case advanceProgressiveRandomSkimSegment

    /// The key equivalent for the Advance Progressive Random Skim Segment
    /// action (Right Arrow), as it appears in `charactersIgnoringModifiers`.
    static let rightArrowKey = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    /// Maps an already-lowercased, modifier-free key to its action, or `nil`
    /// when the key is not bound.
    init?(unmodifiedKey key: String) {
        switch key {
        case "k": self = .reviewKeep
        case "d": self = .reviewDelete
        case "r": self = .renameSheet
        case "z": self = .reviewUndo
        case ",": self = .previousVideo
        case ".": self = .nextVideo
        case "n": self = .primaryPrefixRename
        case "m": self = .secondaryPrefixRename
        case "q": self = .toggleQueuePanel
        case " ": self = .togglePlayPause
        case "f": self = .toggleFullScreen
        case Self.rightArrowKey: self = .advanceProgressiveRandomSkimSegment
        default: return nil
        }
    }
}
