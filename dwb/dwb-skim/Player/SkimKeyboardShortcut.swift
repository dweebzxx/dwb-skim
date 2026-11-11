import AppKit

/// Pure mapping from an unmodified key press to the player-window action it
/// invokes. Extracted so the shortcut table can be unit-tested without driving
/// AppKit event plumbing; `PlayerWindowController.handleSkimShortcut` is the
/// only production caller and owns modifier rejection and text-entry guards.
///
/// P46 mapping (unmodified keys):
///
/// | Key | Action                        |
/// | --- | ----------------------------- |
/// | `,` | Previous Video                |
/// | `.` | Next Video                     |
/// | `n` | Primary Prefix Rename         |
/// | `m` | Secondary Prefix Rename       |
/// | `r` | Rename sheet                  |
/// | `b` | Toggle bookmark               |
/// | `q` | Toggle queue panel            |
/// | ` ` | Play / Pause                  |
/// | `f` | Toggle fullscreen             |
/// | `←` | Seek backward 10 seconds when Skim is off |
/// | `→` | Seek forward 10 seconds when Skim is off; advance Progressive Random Skim when it owns the key |
///
/// P36 removed the pre-P36 bindings `[` (Previous Video), `]` (Next Video), and
/// `m` (Mute). P46 removed `k` (keep_), `d` (delete_), and `z` (undo); marker
/// rename undo is Command-Z in the Edit menu. Those keys are intentionally
/// absent from this table so they no longer trigger any action.
enum SkimKeyboardShortcut: Equatable, CaseIterable {
    case renameSheet
    case toggleBookmark
    case previousVideo
    case nextVideo
    case primaryPrefixRename
    case secondaryPrefixRename
    case toggleQueuePanel
    case togglePlayPause
    case toggleFullScreen
    case seekBackwardTenSeconds
    case seekForwardTenSeconds

    static let tenSecondSeekInterval = 10

    /// Arrow key equivalents as they appear in `charactersIgnoringModifiers`.
    static let leftArrowKey = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    static let rightArrowKey = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    /// Fixed-shortcut rows consumed by the existing Settings → Shortcuts page.
    static let tenSecondSeekSettingsRows = [
        ("Seek backward 10 seconds", "←"),
        ("Seek forward 10 seconds", "→"),
    ]

    var isArrowKey: Bool {
        switch self {
        case .seekBackwardTenSeconds, .seekForwardTenSeconds:
            return true
        default:
            return false
        }
    }

    /// AppKit repeat events are actionable only for normal-playback arrows.
    /// Skim retains P36's original single-key-down routing.
    func handlesKeyRepeat(isSkimEnabled: Bool) -> Bool {
        isArrowKey && !isSkimEnabled
    }

    /// Resolves the one authoritative player-window arrow-key context into one
    /// action. The caller supplies its existing Skim and Progressive Random
    /// Skim state; this table does not own or infer either state.
    func arrowDispatch(isSkimEnabled: Bool,
                       isProgressiveRandomSkimSessionActive: Bool,
                       canManuallyAdvanceProgressiveRandomSkimSegment: Bool) -> SkimArrowKeyDispatch? {
        switch self {
        case .seekBackwardTenSeconds:
            return isSkimEnabled ? .passThrough : .seek(seconds: -Self.tenSecondSeekInterval)
        case .seekForwardTenSeconds:
            guard !isSkimEnabled else {
                if canManuallyAdvanceProgressiveRandomSkimSegment {
                    return .advanceProgressiveRandomSkimSegment
                }
                return isProgressiveRandomSkimSessionActive ? .consume : .passThrough
            }
            return .seek(seconds: Self.tenSecondSeekInterval)
        default:
            return nil
        }
    }

    /// Maps an already-lowercased, modifier-free key to its action, or `nil`
    /// when the key is not bound.
    init?(unmodifiedKey key: String) {
        switch key {
        case "r": self = .renameSheet
        case "b": self = .toggleBookmark
        case ",": self = .previousVideo
        case ".": self = .nextVideo
        case "n": self = .primaryPrefixRename
        case "m": self = .secondaryPrefixRename
        case "q": self = .toggleQueuePanel
        case " ": self = .togglePlayPause
        case "f": self = .toggleFullScreen
        case Self.leftArrowKey: self = .seekBackwardTenSeconds
        case Self.rightArrowKey: self = .seekForwardTenSeconds
        default: return nil
        }
    }
}

enum SkimArrowKeyDispatch: Equatable {
    case seek(seconds: Int)
    case advanceProgressiveRandomSkimSegment
    case consume
    case passThrough
}
