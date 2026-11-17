import XCTest

final class ShortcutStoreTests: XCTestCase {

    private let key = ShortcutStore.defaultsKey

    func testTheDefaultsKeyIsShortcutOverrides() {
        XCTAssertEqual(ShortcutStore.defaultsKey, "shortcutOverrides")
    }

    func testWithoutOverridesEveryCommandUsesItsDefaults() {
        let (store, defaults, _) = makeShortcutStore()
        for command in ShortcutCommandTable.all {
            XCTAssertEqual(store.activeKeys(for: command.id), command.defaultKeys, "\(command.id)")
        }
        XCTAssertFalse(store.hasOverrides)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testAnOverrideRoundTripsThroughUserDefaults() {
        let (store, defaults, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        XCTAssertEqual(store.activeKeys(for: .nextItem), [.bare("j")])

        let reopened = ShortcutStore(defaults: defaults)
        XCTAssertEqual(reopened.activeKeys(for: .nextItem), [.bare("j")])
        XCTAssertEqual(reopened.activeKeys(for: .previousItem), [.bare(",")])
    }

    func testStoredFormatIsADictionaryFromIdentifierToKeyTexts() {
        let (store, defaults, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        store.replaceKey(nil, with: ShortcutKey(modifiers: [.command], key: ShortcutKey.space), for: .playPause)
        store.replaceKey(ShortcutKey(modifiers: [.command], key: ShortcutKey.space),
                         with: ShortcutKey(modifiers: [.command, .shift], key: "p"), for: .playPause)
        let stored = defaults.dictionary(forKey: key) as? [String: [String]]
        XCTAssertEqual(stored, ["nextItem": ["j"], "playPause": ["space", "shift+command+p"]])
    }

    func testUnknownIdentifiersAreIgnored() {
        let (store, defaults, _) = makeShortcutStore()
        defaults.set(["noSuchCommand": ["x"], "nextItem": ["j"], "previousItem": "not a list"], forKey: key)
        store.reload()
        XCTAssertEqual(store.activeKeys(for: .nextItem), [.bare("j")])
        XCTAssertEqual(store.activeKeys(for: .previousItem), [.bare(",")])
    }

    func testAFixedCommandCannotBeOverridden() {
        let (store, defaults, _) = makeShortcutStore()
        defaults.set(["quit": ["j"], "undoPrefixChange": []], forKey: key)
        store.reload()
        XCTAssertEqual(store.activeKeys(for: .quit), ShortcutCommandTable.command(.quit).defaultKeys)
        XCTAssertEqual(store.activeKeys(for: .undoPrefixChange), ShortcutCommandTable.command(.undoPrefixChange).defaultKeys)
        store.setKeys([.bare("j")], for: .quit)
        XCTAssertEqual(store.activeKeys(for: .quit), ShortcutCommandTable.command(.quit).defaultKeys)
    }

    func testAnEntryWhoseKeysAreAllUnreadableFallsBackToTheDefaults() {
        let (store, defaults, _) = makeShortcutStore()
        defaults.set(["nextItem": ["banana", ""]], forKey: key)
        store.reload()
        XCTAssertEqual(store.activeKeys(for: .nextItem), [.bare(".")])
    }

    func testRemoveClearsOnlyThatKeyAndKeepsTheOthers() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(nil, with: ShortcutKey(modifiers: [.control], key: "p"), for: .playPause)
        store.replaceKey(.bare(ShortcutKey.space), with: nil, for: .playPause)
        XCTAssertEqual(store.activeKeys(for: .playPause),
                       [ShortcutKey(modifiers: [.control], key: "p")])
    }

    func testStoredReturnIsIgnoredWhileOtherKeysStayAndDiskIsUntouched() {
        let (store, defaults, _) = makeShortcutStore()
        let saved = ["nextItem": ["return", "option+command+k", "."]]
        defaults.set(saved, forKey: key)
        store.reload()
        XCTAssertEqual(store.activeKeys(for: .nextItem),
                       [ShortcutKey(modifiers: [.option, .command], key: "k"), .bare(".")])
        XCTAssertEqual(defaults.dictionary(forKey: key) as? [String: [String]], saved)
    }

    func testAnOverrideKeepsMultipleModifiedAndUnmodifiedKeys() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(nil, with: ShortcutKey(modifiers: [.control], key: "p"), for: .playPause)
        store.replaceKey(nil, with: ShortcutKey(modifiers: [.option], key: "p"), for: .playPause)
        XCTAssertEqual(store.activeKeys(for: .playPause),
                       [.bare(ShortcutKey.space), ShortcutKey(modifiers: [.control], key: "p"),
                        ShortcutKey(modifiers: [.option], key: "p")])
        XCTAssertEqual(store.menuKeys(for: .playPause),
                       [ShortcutKey(modifiers: [.control], key: "p"),
                        ShortcutKey(modifiers: [.option], key: "p")])
        XCTAssertEqual(store.menuKeys(for: .nextItem), [])
    }

    func testRemovingEveryKeyLeavesTheActionUnassignedAndSurvivesARelaunch() {
        let (store, defaults, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: nil, for: .togglePrimaryPrefix)
        XCTAssertEqual(store.activeKeys(for: .togglePrimaryPrefix), [])
        XCTAssertEqual(ShortcutStore(defaults: defaults).activeKeys(for: .togglePrimaryPrefix), [])
        XCTAssertEqual((defaults.dictionary(forKey: key) as? [String: [String]])?["togglePrimaryPrefix"], [])
    }

    func testAddingASecondKeyKeepsTheFirst() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: .bare("k"), for: .togglePrimaryPrefix)
        store.replaceKey(nil, with: .bare("h"), for: .togglePrimaryPrefix)
        XCTAssertEqual(store.activeKeys(for: .togglePrimaryPrefix), [.bare("k"), .bare("h")])
    }

    func testAddingAKeyToAnUnassignedActionGivesItThatKey() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: nil, for: .togglePrimaryPrefix)
        store.replaceKey(nil, with: .bare("k"), for: .togglePrimaryPrefix)
        XCTAssertEqual(store.activeKeys(for: .togglePrimaryPrefix), [.bare("k")])
    }

    func testSavingTheSameKeyTwiceKeepsOneCopy() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(nil, with: .bare("n"), for: .togglePrimaryPrefix)
        XCTAssertEqual(store.activeKeys(for: .togglePrimaryPrefix), [.bare("n")])
        XCTAssertFalse(store.hasOverrides)
    }

    func testKeysEqualToTheDefaultsRemoveTheOverride() {
        let (store, defaults, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        XCTAssertTrue(store.hasOverrides)
        store.replaceKey(.bare("j"), with: .bare("."), for: .nextItem)
        XCTAssertFalse(store.hasOverrides)
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testRestoreDefaultsClearsEveryOverrideAndNothingElse() {
        let (store, defaults, _) = makeShortcutStore()
        defaults.set(true, forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled)
        defaults.set("kept", forKey: "somethingElse")
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        store.replaceKey(.bare("b"), with: .bare("v"), for: .toggleBookmark)

        store.restoreDefaults()

        XCTAssertFalse(store.hasOverrides)
        XCTAssertEqual(store.activeKeys(for: .nextItem), [.bare(".")])
        XCTAssertEqual(store.activeKeys(for: .toggleBookmark), [.bare("b")])
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled), true)
        XCTAssertEqual(defaults.string(forKey: "somethingElse"), "kept")
    }

    func testRestoreAllSettingsClearsTheOverridesWithTheOtherPreferences() {
        let (store, defaults, _) = makeShortcutStore()
        defaults.set(true, forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled)
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)

        SettingsDefaultsRegistry.restoreAllSettings(defaults: defaults, reduceMotionDefault: false)
        store.reload()

        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.loopQueueEnabled), false)
        XCTAssertNil(defaults.object(forKey: key))
        XCTAssertEqual(store.activeKeys(for: .nextItem), [.bare(".")])
    }

    func testEveryChangePostsTheShortcutsChangedNotification() {
        let (store, _, _) = makeShortcutStore()
        var count = 0
        let observer = NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: store, queue: nil) { _ in
            count += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        store.replaceKey(.bare("j"), with: nil, for: .nextItem)
        store.restoreDefaults()
        store.reload()
        XCTAssertEqual(count, 4)
    }

    func testTheKeyHintNamesTheFirstActiveKeyOrNothing() {
        let (store, _, _) = makeShortcutStore()
        XCTAssertEqual(ShortcutHints.help("Next item", for: .nextItem, store: store), "Next item (.)")
        XCTAssertEqual(ShortcutHints.help("Play or Pause", for: .playPause, store: store), "Play or Pause (Space)")
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        XCTAssertEqual(ShortcutHints.help("Next item", for: .nextItem, store: store), "Next item (J)")
        store.replaceKey(.bare("j"), with: nil, for: .nextItem)
        XCTAssertEqual(ShortcutHints.help("Next item", for: .nextItem, store: store), "Next item")
        XCTAssertNil(ShortcutHints.keyText(for: .nextItem, store: store))
    }
}
