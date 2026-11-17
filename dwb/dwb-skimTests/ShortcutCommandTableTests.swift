import XCTest

final class ShortcutCommandTableTests: XCTestCase {

    private func describe(_ context: ShortcutContext?) -> String {
        guard let context else { return "-" }
        return "\(context.window)/\(context.typing)/\(context.skim)"
    }

    /// The golden list: every skim command as the keyboard inventory found it, with its
    /// default keys and the contexts they fire in. A change to any default key or context
    /// must change this list on purpose.
    private let inventory = [
        "playPause|Play or pause|Playback|space|editable|player/notEditing/any|any/any/any",
        "seekBackward|Seek backward 10 seconds|Playback|left|editable|player/notEditing/off|-",
        "seekForward|Seek forward 10 seconds|Playback|right|editable|player/notEditing/off|-",
        "volumeUp|Volume up|Playback|command+up|editable|player/notEditing/any|any/any/any",
        "volumeDown|Volume down|Playback|command+down|editable|player/notEditing/any|any/any/any",
        "toggleSkim|Toggle Skim|Skim||fixed|-|-",
        "nextSkimSegment|Next Progressive Random Skim segment|Skim|right|editable|player/notEditing/on|-",
        "previousItem|Previous item|Navigation|,|editable|player/notEditing/any|-",
        "nextItem|Next item|Navigation|.|editable|player/notEditing/any|-",
        "moveBetweenSettingsPages|Move between Settings pages|Navigation|up down|fixed|settings/notEditing/any|-",
        "openFile|Open\u{2026}|File actions|command+o|editable|player/notEditing/any|any/any/any",
        "renameFile|Rename file|File actions|r|editable|player/notEditing/any|any/any/any",
        "togglePrimaryPrefix|Toggle primary prefix|File actions|n|editable|player/notEditing/any|-",
        "toggleSecondaryPrefix|Toggle secondary prefix|File actions|m|editable|player/notEditing/any|-",
        "undoPrefixChange|Undo prefix change|File actions|command+z|fixed|-|player/notEditing/any",
        "revealInFinder|Reveal in Finder|File actions|shift+command+r|editable|player/notEditing/any|any/any/any",
        "toggleBookmark|Toggle bookmark|Bookmarks|b|editable|player/notEditing/any|-",
        "toggleQueuePanel|Toggle queue panel|Window|q|editable|player/notEditing/any|-",
        "toggleFullScreen|Toggle full screen|Window|f|editable|player/notEditing/any|-",
        "newWindow|New window|Window|command+n|editable|player/notEditing/any|any/any/any",
        "fourWindowGrid|Four window grid|Window|command+4|editable|player/notEditing/any|any/any/any",
        "fitVideo|Fit video|Window|command+1|editable|player/notEditing/any|any/any/any",
        "fillVideo|Fill video|Window|command+2|editable|player/notEditing/any|any/any/any",
        "stretchVideo|Stretch video|Window|command+3|editable|player/notEditing/any|any/any/any",
        "openSettings|Open settings|Window|command+,|fixed|-|any/any/any",
        "closeWindow|Close window|Window|command+w|fixed|-|any/any/any",
        "minimizeWindow|Minimize window|Window|command+m|fixed|-|any/any/any",
        "quit|Quit dwb skim|Window|command+q|fixed|-|any/any/any",
        "clearQueue|Clear queue|Queue|shift+command+delete|editable|player/notEditing/any|any/any/any",
        "removeQueueSelection|Remove selected queue items|Queue|delete forwarddelete|fixed|queuePanel/notEditing/any|-",
        "undoTyping|Undo typing|Text editing|command+z|fixed|-|any/editing/any",
        "redoTyping|Redo typing|Text editing|shift+command+z|fixed|-|any/editing/any",
        "cut|Cut|Text editing|command+x|fixed|-|any/any/any",
        "copy|Copy|Text editing|command+c|fixed|-|any/any/any",
        "paste|Paste|Text editing|command+v|fixed|-|any/any/any",
        "selectAll|Select all|Text editing|command+a|fixed|-|any/any/any",
    ]

    func testDefaultTableEqualsTheInventory() {
        let actual = ShortcutCommandTable.all.map { command in
            [command.id.rawValue,
             command.name,
             command.group.rawValue,
             command.defaultKeys.map(\.storageText).joined(separator: " "),
             command.isEditable ? "editable" : "fixed",
             describe(command.keyHandlerContext),
             describe(command.menuContext)].joined(separator: "|")
        }
        XCTAssertEqual(actual, inventory)
    }

    func testEveryIdentifierHasExactlyOneCommand() {
        let ids = ShortcutCommandTable.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(ids), Set(ShortcutCommandID.allCases))
    }

    func testGroupsAreInPageOrderAndEveryCommandIsInOne() {
        XCTAssertEqual(ShortcutCommandTable.groups.map(\.group.rawValue),
                       ["Playback", "Skim", "Navigation", "File actions", "Bookmarks", "Window", "Queue", "Text editing"])
        XCTAssertEqual(ShortcutCommandTable.groups.flatMap(\.commands).count, ShortcutCommandTable.all.count)
    }

    func testTheRequiredActionNamesAreUsed() {
        let names = Set(ShortcutCommandTable.all.map(\.name))
        for required in ["Play or pause", "Volume up", "Volume down", "Previous item", "Next item",
                         "Toggle primary prefix", "Toggle secondary prefix", "Rename file",
                         "Undo prefix change", "Toggle bookmark"] {
            XCTAssertTrue(names.contains(required), required)
        }
    }

    func testNoDefaultKeyIsUsedByTwoCommandsThatCanBeActiveTogether() {
        for first in ShortcutCommandTable.all {
            for second in ShortcutCommandTable.all where first.id.rawValue < second.id.rawValue {
                for key in first.defaultKeys where second.defaultKeys.contains(key) {
                    XCTAssertFalse(first.context(for: key).overlaps(second.context(for: key)),
                                   "\(first.id) and \(second.id) share \(key.storageText)")
                }
            }
        }
    }

    func testTheSharedDefaultKeysAreTheSeekAndSegmentArrowAndTheTwoUndos() {
        var shared = Set<String>()
        for first in ShortcutCommandTable.all {
            for second in ShortcutCommandTable.all where first.id.rawValue < second.id.rawValue {
                for key in first.defaultKeys where second.defaultKeys.contains(key) {
                    shared.insert("\(first.id.rawValue)+\(second.id.rawValue)")
                }
            }
        }
        XCTAssertEqual(shared, ["nextSkimSegment+seekForward", "undoPrefixChange+undoTyping"])
    }

    func testEditableCommandsAreExactlyTheOnesWithAKeyExceptTheFixedEntries() {
        let fixed = Set(ShortcutCommandTable.all.filter { !$0.isEditable }.map(\.id))
        XCTAssertEqual(fixed, [.toggleSkim, .undoPrefixChange, .undoTyping, .redoTyping,
                               .cut, .copy, .paste, .selectAll, .moveBetweenSettingsPages,
                               .openSettings, .closeWindow, .minimizeWindow, .quit, .removeQueueSelection])
        for command in ShortcutCommandTable.all where command.isEditable {
            XCTAssertFalse(command.defaultKeys.isEmpty, "\(command.id)")
        }
    }

    func testTheGestureRowHasNoKeyAndNoContextOfItsOwn() {
        let skim = ShortcutCommandTable.command(.toggleSkim)
        XCTAssertEqual(skim.gestureText, "Double-tap Option")
        XCTAssertTrue(skim.defaultKeys.isEmpty)
        XCTAssertFalse(skim.isEditable)
    }

    func testEveryDefaultKeyIsDeliverableByItsCommand() {
        for command in ShortcutCommandTable.all where command.isEditable {
            for key in command.defaultKeys {
                let others = command.defaultKeys.filter { $0 != key }
                XCTAssertTrue(ShortcutValidation.canDeliver(key, to: command, otherKeys: others),
                              "\(command.id) \(key.storageText)")
            }
        }
    }

    func testEverySkimShortcutIsAnEditableCommandThatTakesUnmodifiedKeys() {
        for shortcut in SkimKeyboardShortcut.allCases {
            let command = ShortcutCommandTable.command(shortcut.commandID)
            XCTAssertTrue(command.isEditable, "\(shortcut)")
            XCTAssertNotNil(command.keyHandlerContext, "\(shortcut)")
        }
        XCTAssertEqual(Set(SkimKeyboardShortcut.allCases.map(\.commandID)).count, SkimKeyboardShortcut.allCases.count)
    }

    func testContextOverlapRules() {
        let skimOff = ShortcutContext(window: .player, typing: .notEditing, skim: .off)
        let skimOn = ShortcutContext(window: .player, typing: .notEditing, skim: .on)
        XCTAssertFalse(skimOff.overlaps(skimOn))
        XCTAssertTrue(skimOff.overlaps(.playerKey))
        XCTAssertTrue(ShortcutContext.anywhere.overlaps(skimOn))
        let editing = ShortcutContext(window: .any, typing: .editing, skim: .any)
        XCTAssertFalse(editing.overlaps(.playerKey))
        XCTAssertTrue(editing.overlaps(.anywhere))
        let queue = ShortcutContext(window: .queuePanel, typing: .notEditing, skim: .any)
        XCTAssertTrue(queue.overlaps(.playerKey))
        XCTAssertTrue(ShortcutContext.playerKey.overlaps(queue))
        XCTAssertFalse(ShortcutContext.settingsSidebar.overlaps(.playerKey))
    }

    func testPlayPauseDefaultsToSpaceOnly() {
        XCTAssertEqual(ShortcutCommandTable.command(.playPause).defaultKeys, [.bare(ShortcutKey.space)])
    }

    func testEveryModifiedKeyOfAMenuCommandUsesTheMenuRoute() {
        let command = ShortcutCommandTable.command(.playPause)
        for mask in 1...15 where mask != ShortcutModifiers.shift.rawValue {
            let modifiers = ShortcutModifiers(rawValue: mask)
            let key = ShortcutKey(modifiers: modifiers, key: "p")
            XCTAssertEqual(command.route(for: key), .menu)
            XCTAssertEqual(command.context(for: key), .anywhere)
        }
    }

    func testModifiedKeyWithoutAMenuUsesTheKeyHandlerRoute() {
        let command = ShortcutCommandTable.command(.nextItem)
        let key = ShortcutKey(modifiers: [.option, .command], key: "k")
        XCTAssertEqual(command.route(for: key), .keyHandler)
        XCTAssertEqual(command.context(for: key), .playerKey)
    }

    func testUnmodifiedMenuCommandUsesPlayerKeyHandler() {
        let (store, _, _) = makeShortcutStore()
        let key = ShortcutKey.bare("j")
        store.replaceKey(nil, with: key, for: .openFile)
        XCTAssertEqual(ShortcutCommandTable.command(.openFile).route(for: key), .keyHandler)
        XCTAssertEqual(ShortcutCommandTable.keyHandlerMenuCommand(for: key, store: store), .openFile)
        XCTAssertNil(ShortcutCommandTable.keyHandlerMenuCommand(
            for: ShortcutKey(modifiers: [.command], key: "o"), store: store))
    }

    func testContextTextNamesNoKey() {
        // Context text is not rewritten when a key changes, so it must not name one.
        for command in ShortcutCommandTable.all {
            guard let text = command.contextText else { continue }
            for symbol in ["\u{2318}", "\u{2303}", "\u{2325}", "\u{21E7}", "Space", "\u{2190}", "\u{2192}"] {
                XCTAssertFalse(text.contains(symbol), "\(command.id): \(text)")
            }
        }
    }
}
