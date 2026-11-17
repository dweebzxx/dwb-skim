import AppKit

/// Pure mapping from an unmodified key press to the player-window action it
/// invokes. Extracted so the shortcut table can be unit-tested without driving
/// AppKit event plumbing; `PlayerWindowController.handleSkimShortcut` is the
/// only production caller and owns modifier rejection and text-entry guards.
///
/// The keys are not written here. Each case names a command in `ShortcutCommandTable`, and
/// `ShortcutStore` supplies the keys now in use (the defaults, or the user's overrides).
/// What stays here is the context logic: which commands apply with Skim off or on, the
/// Progressive Random Skim segment states, and key-repeat handling.
///
/// Default keys (unmodified):
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
/// | `→` | Seek forward 10 seconds when Skim is off |
/// | `→` | Advance Progressive Random Skim when Skim is on and it owns the key |
///
/// P36 removed the pre-P36 bindings `[` (Previous Video), `]` (Next Video), and
/// `m` (Mute). P46 removed `k` (keep_), `d` (delete_), and `z` (undo); marker
/// rename undo is Command-Z in the Edit menu. Those keys are intentionally
/// absent from the default table so they no longer trigger any action.
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
    case nextProgressiveRandomSkimSegment

    static let tenSecondSeekInterval = 10

    /// Arrow key equivalents as they appear in `charactersIgnoringModifiers`.
    static let leftArrowKey = ShortcutKey.leftArrow
    static let rightArrowKey = ShortcutKey.rightArrow

    /// The command in `ShortcutCommandTable` that holds this action's keys.
    var commandID: ShortcutCommandID {
        switch self {
        case .renameSheet: return .renameFile
        case .toggleBookmark: return .toggleBookmark
        case .previousVideo: return .previousItem
        case .nextVideo: return .nextItem
        case .primaryPrefixRename: return .togglePrimaryPrefix
        case .secondaryPrefixRename: return .toggleSecondaryPrefix
        case .toggleQueuePanel: return .toggleQueuePanel
        case .togglePlayPause: return .playPause
        case .toggleFullScreen: return .toggleFullScreen
        case .seekBackwardTenSeconds: return .seekBackward
        case .seekForwardTenSeconds: return .seekForward
        case .nextProgressiveRandomSkimSegment: return .nextSkimSegment
        }
    }

    /// The Seek rows as the Settings page names and keys them by default, read from the table.
    static var tenSecondSeekSettingsRows: [(String, String)] {
        [ShortcutCommandID.seekBackward, .seekForward].map { id in
            let command = ShortcutCommandTable.command(id)
            return (command.name, command.defaultKeys.first?.capText ?? "")
        }
    }

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

    /// Whether this action applies in the current Skim state. The seeks apply with Skim off;
    /// the Progressive Random Skim segment key applies with Skim on; the rest always apply.
    func isActive(isSkimEnabled: Bool) -> Bool {
        switch self {
        case .seekBackwardTenSeconds, .seekForwardTenSeconds: return !isSkimEnabled
        case .nextProgressiveRandomSkimSegment: return isSkimEnabled
        default: return true
        }
    }

    /// Resolves the one authoritative player-window arrow-key context into one
    /// action. The caller supplies its existing Skim and Progressive Random
    /// Skim state; this table does not own or infer either state.
    ///
    /// For the default `→` key this answers for both of its actions: the seek with Skim off and
    /// the segment advance with Skim on. A user's own keys route through `resolve`, which
    /// asks each action only about the state it applies in.
    func arrowDispatch(isSkimEnabled: Bool,
                       isProgressiveRandomSkimSessionActive: Bool,
                       canManuallyAdvanceProgressiveRandomSkimSegment: Bool) -> SkimArrowKeyDispatch? {
        switch self {
        case .seekBackwardTenSeconds:
            return isSkimEnabled ? .passThrough : .seek(seconds: -Self.tenSecondSeekInterval)
        case .seekForwardTenSeconds:
            guard !isSkimEnabled else {
                return Self.segmentAdvanceDispatch(
                    isProgressiveRandomSkimSessionActive: isProgressiveRandomSkimSessionActive,
                    canManuallyAdvance: canManuallyAdvanceProgressiveRandomSkimSegment
                )
            }
            return .seek(seconds: Self.tenSecondSeekInterval)
        case .nextProgressiveRandomSkimSegment:
            guard isSkimEnabled else { return .passThrough }
            return Self.segmentAdvanceDispatch(
                isProgressiveRandomSkimSessionActive: isProgressiveRandomSkimSessionActive,
                canManuallyAdvance: canManuallyAdvanceProgressiveRandomSkimSegment
            )
        default:
            return nil
        }
    }

    private static func segmentAdvanceDispatch(isProgressiveRandomSkimSessionActive: Bool,
                                               canManuallyAdvance: Bool) -> SkimArrowKeyDispatch {
        if canManuallyAdvance {
            return .advanceProgressiveRandomSkimSegment
        }
        return isProgressiveRandomSkimSessionActive ? .consume : .passThrough
    }

    // MARK: - Keys

    /// The actions whose active keys include `key`, in table order.
    static func shortcuts(for key: ShortcutKey, store: ShortcutStore = .shared) -> [SkimKeyboardShortcut] {
        allCases.filter {
            ShortcutCommandTable.command($0.commandID).route(for: key) == .keyHandler
                && store.activeKeys(for: $0.commandID).contains(key)
        }
    }

    /// Every unmodified key in use and the action it invokes, in table order: the one key list
    /// the key handler, the Settings text, and the tests read. Several actions can share a key
    /// when they apply in different Skim states.
    static var keyAssignments: [(key: String, shortcut: SkimKeyboardShortcut)] {
        allCases.flatMap { shortcut in
            ShortcutStore.shared.activeKeys(for: shortcut.commandID)
                .filter(\.usesKeyHandler)
                .map { (key: $0.key, shortcut: shortcut) }
        }
    }

    /// The unmodified keys currently assigned to `shortcut`, in assignment order, as the key
    /// handler matches them (lowercase, modifier-free). Empty when the action has no such key.
    static func assignedKeys(for shortcut: SkimKeyboardShortcut) -> [String] {
        ShortcutStore.shared.activeKeys(for: shortcut.commandID).filter(\.usesKeyHandler).map(\.key)
    }

    /// A key as it reads in Settings text: letters in capitals ("N"), the space bar as "Space",
    /// and the arrow keys as arrows.
    static func keyCapText(_ key: String) -> String {
        ShortcutKey.keyCapText(key)
    }

    /// Maps an already-lowercased, modifier-free key to its action, or `nil` when the key is
    /// not bound. When two actions share the key, the first in table order answers; the
    /// key handler uses `resolve`, which also applies the Skim state.
    init?(unmodifiedKey key: String) {
        guard let match = Self.shortcuts(for: .bare(key)).first else { return nil }
        self = match
    }

    // MARK: - Dispatch

    /// What a key press does now.
    struct Resolution: Equatable {
        let shortcut: SkimKeyboardShortcut
        /// The arrow-key outcome for the seeks and the segment key; `nil` for every other action.
        let arrow: SkimArrowKeyDispatch?
    }

    /// The action an unmodified key runs in the current Skim state, or `nil` when it runs none.
    /// Two actions may share a key (`→` seeks with Skim off and advances a segment with Skim
    /// on); only the one that applies to the state answers.
    static func resolve(unmodifiedKey key: String,
                        isSkimEnabled: Bool,
                        isProgressiveRandomSkimSessionActive: Bool,
                        canManuallyAdvanceProgressiveRandomSkimSegment: Bool,
                        store: ShortcutStore = .shared) -> Resolution? {
        resolve(key: .bare(key), isSkimEnabled: isSkimEnabled,
                isProgressiveRandomSkimSessionActive: isProgressiveRandomSkimSessionActive,
                canManuallyAdvanceProgressiveRandomSkimSegment: canManuallyAdvanceProgressiveRandomSkimSegment,
                store: store)
    }

    static func resolve(key: ShortcutKey,
                        isSkimEnabled: Bool,
                        isProgressiveRandomSkimSessionActive: Bool,
                        canManuallyAdvanceProgressiveRandomSkimSegment: Bool,
                        store: ShortcutStore = .shared) -> Resolution? {
        for shortcut in shortcuts(for: key, store: store) where shortcut.isActive(isSkimEnabled: isSkimEnabled) {
            let arrow = shortcut.arrowDispatch(
                isSkimEnabled: isSkimEnabled,
                isProgressiveRandomSkimSessionActive: isProgressiveRandomSkimSessionActive,
                canManuallyAdvanceProgressiveRandomSkimSegment: canManuallyAdvanceProgressiveRandomSkimSegment
            )
            return Resolution(shortcut: shortcut, arrow: arrow)
        }
        return nil
    }
}

enum SkimArrowKeyDispatch: Equatable {
    case seek(seconds: Int)
    case advanceProgressiveRandomSkimSegment
    case consume
    case passThrough
}
