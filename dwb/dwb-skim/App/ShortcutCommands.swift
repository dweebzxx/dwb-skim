import Foundation

// The one table of skim's keyboard commands: identifier, action name, group, context,
// default keys, and whether the user can change them. The Shortcuts page, the main menu,
// and the player window's key handler all read their keys from here (default keys plus the
// overrides `ShortcutStore` holds). The defaults below come from the live definitions:
// `AppDelegate.buildMainMenu()` for the menu keys, the player window's key handler for the
// unmodified keys, the queue table for Delete, and the Option double-tap coordinator.

/// A stable identifier. The raw value is what `shortcutOverrides` stores, so do not rename one.
enum ShortcutCommandID: String, CaseIterable {
    case playPause, seekBackward, seekForward, volumeUp, volumeDown
    case toggleSkim, nextSkimSegment
    case previousItem, nextItem, startQueueFromTop
    case openFile, renameFile, togglePrimaryPrefix, toggleSecondaryPrefix, undoPrefixChange, undoTyping, redoTyping, cut, copy, paste, selectAll, revealInFinder
    case moveBetweenSettingsPages
    case toggleBookmark
    case toggleQueuePanel, toggleFullScreen, newWindow, fourWindowGrid, fitVideo, fillVideo, stretchVideo
    case openSettings, closeWindow, minimizeWindow, quit
    case clearQueue, removeQueueSelection
}

/// Where and when a key fires. Two contexts that can be active at the same time overlap.
struct ShortcutContext: Equatable {
    enum Window: Equatable { case any, player, queuePanel, settings }
    enum Typing: Equatable { case any, notEditing, editing }
    enum SkimState: Equatable { case any, off, on }

    var window: Window = .any
    var typing: Typing = .any
    var skim: SkimState = .any

    func overlaps(_ other: ShortcutContext) -> Bool {
        // The queue panel sits inside the player window, so those two overlap.
        let nested = (window == .player && other.window == .queuePanel)
            || (window == .queuePanel && other.window == .player)
        let windows = window == .any || other.window == .any || window == other.window || nested
        let typings = typing == .any || other.typing == .any || typing == other.typing
        let skims = skim == .any || other.skim == .any || skim == other.skim
        return windows && typings && skims
    }

    /// A key handled by the player window's key handler: player window, no text being edited.
    static let playerKey = ShortcutContext(window: .player, typing: .notEditing, skim: .any)
    static let settingsSidebar = ShortcutContext(window: .settings, typing: .notEditing, skim: .any)
    static let anywhere = ShortcutContext()
}

struct ShortcutCommand: Equatable {
    enum Group: String, CaseIterable {
        case playback = "Playback"
        case skim = "Skim"
        case navigation = "Navigation"
        case fileActions = "File actions"
        case bookmarks = "Bookmarks"
        case window = "Window"
        case queue = "Queue"
        case textEditing = "Text editing"
    }

    enum Tone: Equatable { case accent, markerPrimary, markerSecondary }

    let id: ShortcutCommandID
    let name: String
    let group: Group
    let defaultKeys: [ShortcutKey]
    /// The context of a key with no modifier (the player window's key handler). `nil` when the
    /// command takes no unmodified key.
    let keyHandlerContext: ShortcutContext?
    /// The context of a key with ⌘, ⌃, or ⌥ (a menu item). `nil` when the command has no menu item.
    let menuContext: ShortcutContext?
    let isEditable: Bool
    /// Shown in the row next to the action. It never names a key, so it needs no refresh.
    let contextText: String?
    /// Reference rows that are a gesture, not a key (double-tap Option).
    let gestureText: String?
    let tone: Tone

    enum Route: Equatable { case menu, keyHandler, invalid }

    func route(for key: ShortcutKey) -> Route {
        guard key.isRecordable else { return .invalid }
        if key.modifiers.hasMenuModifier && menuContext != nil { return .menu }
        return keyHandlerContext == nil ? .invalid : .keyHandler
    }

    /// The context of the route this key uses.
    func context(for key: ShortcutKey) -> ShortcutContext {
        if route(for: key) == .menu, let menuContext { return menuContext }
        if route(for: key) == .keyHandler, let keyHandlerContext { return keyHandlerContext }
        return keyHandlerContext ?? menuContext ?? .anywhere
    }
}

enum ShortcutCommandTable {

    private static let typingNote = "Does nothing while a text field is being edited."

    private static func cmd(_ id: ShortcutCommandID, _ name: String, _ group: ShortcutCommand.Group,
                            keys: [ShortcutKey] = [],
                            keyHandler: ShortcutContext? = nil,
                            menu: ShortcutContext? = nil,
                            editable: Bool = true,
                            note: String? = nil,
                            gesture: String? = nil,
                            tone: ShortcutCommand.Tone = .accent) -> ShortcutCommand {
        ShortcutCommand(id: id, name: name, group: group, defaultKeys: keys,
                        keyHandlerContext: keyHandler, menuContext: menu, isEditable: editable,
                        contextText: note, gestureText: gesture, tone: tone)
    }

    private static func menuKey(_ key: String, _ modifiers: ShortcutModifiers = [.command]) -> ShortcutKey {
        ShortcutKey(modifiers: modifiers, key: key)
    }

    private static let player = ShortcutContext.playerKey
    private static let skimOff = ShortcutContext(window: .player, typing: .notEditing, skim: .off)
    private static let skimOn = ShortcutContext(window: .player, typing: .notEditing, skim: .on)

    /// Every command, in page order within each group.
    static let all: [ShortcutCommand] = [
        // Playback
        cmd(.playPause, "Play or pause", .playback,
            keys: [.bare(ShortcutKey.space)],
            keyHandler: player, menu: .anywhere, note: "Unmodified keys do nothing while a text field is being edited."),
        cmd(.seekBackward, "Seek backward 10 seconds", .playback,
            keys: [.bare(ShortcutKey.leftArrow)], keyHandler: skimOff,
            note: "Only when Skim is off. \(typingNote)"),
        cmd(.seekForward, "Seek forward 10 seconds", .playback,
            keys: [.bare(ShortcutKey.rightArrow)], keyHandler: skimOff,
            note: "Only when Skim is off. \(typingNote)"),
        cmd(.volumeUp, "Volume up", .playback, keys: [menuKey(ShortcutKey.upArrow)], keyHandler: player, menu: .anywhere),
        cmd(.volumeDown, "Volume down", .playback, keys: [menuKey(ShortcutKey.downArrow)], keyHandler: player, menu: .anywhere),

        // Skim
        cmd(.toggleSkim, "Toggle Skim", .skim, editable: false,
            note: "Player window only. Does nothing while a text field is being edited.",
            gesture: "Double-tap Option"),
        cmd(.nextSkimSegment, "Next Progressive Random Skim segment", .skim,
            keys: [.bare(ShortcutKey.rightArrow)], keyHandler: skimOn,
            note: "Only when Skim is on and Progressive Random Skim is active. \(typingNote)"),

        // Navigation
        cmd(.previousItem, "Previous item", .navigation,
            keys: [.bare(",")], keyHandler: player, note: typingNote),
        cmd(.nextItem, "Next item", .navigation,
            keys: [.bare(".")], keyHandler: player, note: typingNote),
        cmd(.startQueueFromTop, "Start queue from top", .navigation,
            keys: [.bare("p")], keyHandler: player,
            note: "Restarts the queue from the top. \(typingNote)"),
        cmd(.moveBetweenSettingsPages, "Move between Settings pages", .navigation,
            keys: [.bare(ShortcutKey.upArrow), .bare(ShortcutKey.downArrow)],
            keyHandler: .settingsSidebar, editable: false,
            note: "Settings window, with the sidebar focused."),

        // File actions
        cmd(.openFile, "Open\u{2026}", .fileActions, keys: [menuKey("o")], keyHandler: player, menu: .anywhere),
        cmd(.renameFile, "Rename file", .fileActions,
            keys: [.bare("r")], keyHandler: player, menu: .anywhere,
            note: "Always renames the current item. Unmodified keys do nothing while a text field is being edited."),
        cmd(.togglePrimaryPrefix, "Toggle primary prefix", .fileActions,
            keys: [.bare("n")], keyHandler: player, note: typingNote, tone: .markerPrimary),
        cmd(.toggleSecondaryPrefix, "Toggle secondary prefix", .fileActions,
            keys: [.bare("m")], keyHandler: player, note: typingNote, tone: .markerSecondary),
        cmd(.undoPrefixChange, "Undo prefix change", .fileActions,
            keys: [menuKey("z")], menu: ShortcutContext(window: .player, typing: .notEditing, skim: .any),
            editable: false, note: "Player window. Does not apply while a text field is being edited."),
        cmd(.revealInFinder, "Reveal in Finder", .fileActions,
            keys: [menuKey("r", [.shift, .command])], keyHandler: player, menu: .anywhere),

        // Bookmarks
        cmd(.toggleBookmark, "Toggle bookmark", .bookmarks,
            keys: [.bare("b")], keyHandler: player, note: typingNote),

        // Window
        cmd(.toggleQueuePanel, "Toggle queue panel", .window,
            keys: [.bare("q")], keyHandler: player, note: typingNote),
        cmd(.toggleFullScreen, "Toggle full screen", .window,
            keys: [.bare("f")], keyHandler: player, note: typingNote),
        cmd(.newWindow, "New window", .window, keys: [menuKey("n")], keyHandler: player, menu: .anywhere),
        cmd(.fourWindowGrid, "Four window grid", .window, keys: [menuKey("4")], keyHandler: player, menu: .anywhere),
        cmd(.fitVideo, "Fit video", .window, keys: [menuKey("1")], keyHandler: player, menu: .anywhere),
        cmd(.fillVideo, "Fill video", .window, keys: [menuKey("2")], keyHandler: player, menu: .anywhere),
        cmd(.stretchVideo, "Stretch video", .window, keys: [menuKey("3")], keyHandler: player, menu: .anywhere),
        cmd(.openSettings, "Open settings", .window, keys: [menuKey(",")], menu: .anywhere, editable: false),
        cmd(.closeWindow, "Close window", .window, keys: [menuKey("w")], menu: .anywhere, editable: false),
        cmd(.minimizeWindow, "Minimize window", .window, keys: [menuKey("m")], menu: .anywhere, editable: false),
        cmd(.quit, "Quit dwb skim", .window, keys: [menuKey("q")], menu: .anywhere, editable: false),

        // Queue
        cmd(.clearQueue, "Clear queue", .queue,
            keys: [menuKey(ShortcutKey.delete, [.shift, .command])], keyHandler: player, menu: .anywhere),
        cmd(.removeQueueSelection, "Remove selected queue items", .queue,
            keys: [.bare(ShortcutKey.delete), .bare(ShortcutKey.forwardDelete)],
            keyHandler: ShortcutContext(window: .queuePanel, typing: .notEditing, skim: .any),
            editable: false, note: "Queue panel, with rows selected."),

        // Text editing
        cmd(.undoTyping, "Undo typing", .textEditing,
            keys: [menuKey("z")], menu: ShortcutContext(window: .any, typing: .editing, skim: .any),
            editable: false, note: "While a text field is being edited."),
        cmd(.redoTyping, "Redo typing", .textEditing,
            keys: [menuKey("z", [.shift, .command])], menu: ShortcutContext(window: .any, typing: .editing, skim: .any),
            editable: false, note: "While a text field is being edited."),
        cmd(.cut, "Cut", .textEditing, keys: [menuKey("x")], menu: .anywhere,
            editable: false, note: "Acts on the text field being edited. The key is reserved in every window."),
        cmd(.copy, "Copy", .textEditing, keys: [menuKey("c")], menu: .anywhere,
            editable: false, note: "Acts on the text field being edited. The key is reserved in every window."),
        cmd(.paste, "Paste", .textEditing, keys: [menuKey("v")], menu: .anywhere,
            editable: false, note: "Acts on the text field being edited. The key is reserved in every window."),
        cmd(.selectAll, "Select all", .textEditing, keys: [menuKey("a")], menu: .anywhere,
            editable: false, note: "Acts on the text field being edited. The key is reserved in every window."),
    ]

    static func command(_ id: ShortcutCommandID) -> ShortcutCommand {
        all.first { $0.id == id }!
    }

    /// A menu-backed command using an unmodified player key. The caller invokes the same
    /// target and action as its menu item; the first match keeps dispatch to one command.
    static func keyHandlerMenuCommand(for key: ShortcutKey, store: ShortcutStore) -> ShortcutCommandID? {
        all.first {
            $0.isEditable && $0.menuContext != nil && $0.route(for: key) == .keyHandler
                && store.activeKeys(for: $0.id).contains(key)
        }?.id
    }

    /// The groups in page order, each with its commands in table order. Empty groups are dropped.
    static var groups: [(group: ShortcutCommand.Group, commands: [ShortcutCommand])] {
        ShortcutCommand.Group.allCases.compactMap { group in
            let commands = all.filter { $0.group == group }
            return commands.isEmpty ? nil : (group, commands)
        }
    }
}
