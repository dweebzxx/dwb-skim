import XCTest

final class ShortcutValidationTests: XCTestCase {

    private func evaluate(_ key: ShortcutKey,
                          for id: ShortcutCommandID,
                          replacing: ShortcutKey? = nil,
                          store: ShortcutStore? = nil) -> ShortcutKeyValidation {
        let store = store ?? makeShortcutStore().store
        return ShortcutValidation.evaluate(key, for: id, replacing: replacing, store: store)
    }

    private let command = ShortcutKey(modifiers: [.command], key: "")

    // MARK: - Conflicts

    func testAKeyAnotherCommandUsesInTheSameContextConflicts() {
        XCTAssertEqual(evaluate(.bare("n"), for: .nextItem), .conflict(with: .togglePrimaryPrefix))
        XCTAssertEqual(evaluate(.bare("b"), for: .nextItem), .conflict(with: .toggleBookmark))
        XCTAssertEqual(evaluate(.bare(","), for: .nextItem), .conflict(with: .previousItem))
    }

    func testTheConflictMessageNamesTheOtherAction() {
        let validation = evaluate(.bare("n"), for: .nextItem)
        XCTAssertEqual(validation.message, "Already assigned to \u{2018}Toggle primary prefix\u{2019} in this context.")
        XCTAssertFalse(validation.allowsSave)
    }

    func testSeekForwardAndTheSegmentKeyMayShareTheRightArrow() {
        // Skim off versus Skim on: the contexts cannot be active together.
        XCTAssertEqual(evaluate(.bare(ShortcutKey.rightArrow), for: .nextSkimSegment), .valid)
        XCTAssertEqual(evaluate(.bare(ShortcutKey.rightArrow), for: .seekForward), .valid)
        // After edits too: both on one custom key.
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(ShortcutKey.rightArrow), with: .bare("l"), for: .seekForward)
        XCTAssertEqual(evaluate(.bare("l"), for: .nextSkimSegment, store: store), .valid)
        XCTAssertEqual(evaluate(.bare(ShortcutKey.rightArrow), for: .seekForward, store: store), .valid)
    }

    func testAKeyUsedWithEitherSkimStateConflictsWithTheSeekAndTheSegmentKey() {
        XCTAssertEqual(evaluate(.bare(ShortcutKey.rightArrow), for: .nextItem), .conflict(with: .seekForward))
        XCTAssertEqual(evaluate(.bare(ShortcutKey.leftArrow), for: .nextItem), .conflict(with: .seekBackward))
    }

    func testACommandNeverConflictsWithItself() {
        XCTAssertEqual(evaluate(.bare("."), for: .nextItem), .valid)
        XCTAssertEqual(evaluate(.bare(ShortcutKey.space), for: .playPause), .valid)
        XCTAssertEqual(evaluate(.bare("."), for: .nextItem, replacing: .bare(".")), .valid)
    }

    func testAKeyFreedByAnOverrideIsAvailableAndTheNewKeyIsTaken() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        XCTAssertEqual(evaluate(.bare("."), for: .toggleBookmark, store: store), .valid)
        XCTAssertEqual(evaluate(.bare("j"), for: .toggleBookmark, store: store), .conflict(with: .nextItem))
    }

    func testAKeyOfARemovedActionIsFree() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: nil, for: .togglePrimaryPrefix)
        XCTAssertEqual(evaluate(.bare("n"), for: .nextItem, store: store), .valid)
    }

    // MARK: - Fixed entries

    func testTheReservedUndoKeyNamesUndoTyping() {
        let undo = ShortcutKey(modifiers: [.command], key: "z")
        XCTAssertEqual(evaluate(undo, for: .nextItem), .conflict(with: .undoTyping))
        XCTAssertEqual(evaluate(undo, for: .volumeUp), .conflict(with: .undoTyping))
        XCTAssertEqual(evaluate(undo, for: .nextItem).message,
                       "Already assigned to \u{2018}Undo typing\u{2019} in this context.")
    }

    func testTheTextUndoEntryDoesNotConflictWithPlayerWindowCommands() {
        let typing = ShortcutCommandTable.command(.undoTyping).context(for: ShortcutKey(modifiers: [.command], key: "z"))
        for id in [ShortcutCommandID.nextItem, .previousItem, .togglePrimaryPrefix, .toggleBookmark, .seekForward] {
            let context = ShortcutCommandTable.command(id).context(for: .bare("n"))
            XCTAssertFalse(typing.overlaps(context), "\(id)")
        }
    }

    func testStandardMacCommandsAreFixedEntries() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "q"), for: .volumeUp), .conflict(with: .quit))
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "w"), for: .volumeUp), .conflict(with: .closeWindow))
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "m"), for: .volumeUp), .conflict(with: .minimizeWindow))
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: ","), for: .volumeUp), .conflict(with: .openSettings))
    }

    func testDeleteInTheQueuePanelIsAFixedEntry() {
        XCTAssertEqual(evaluate(.bare(ShortcutKey.delete), for: .nextItem), .conflict(with: .removeQueueSelection))
        XCTAssertEqual(evaluate(.bare(ShortcutKey.forwardDelete), for: .previousItem), .conflict(with: .removeQueueSelection))
    }

    func testAFixedEntryNeverConflictsWithAKeyItsContextCannotShare() {
        // The segment key needs Skim on, but the queue panel entry applies at any Skim state,
        // so Delete conflicts there too.
        XCTAssertEqual(evaluate(.bare(ShortcutKey.delete), for: .nextSkimSegment), .conflict(with: .removeQueueSelection))
    }

    // MARK: - Invalid keys

    func testAModifierAloneIsInvalid() {
        XCTAssertEqual(evaluate(command, for: .nextItem), .invalid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.shift], key: ""), for: .volumeUp), .invalid)
        XCTAssertEqual(ShortcutKeyValidation.invalid.message, "This key combination can\u{2019}t be used for this action.")
        XCTAssertFalse(ShortcutKeyValidation.invalid.allowsSave)
    }

    func testModifiedKeysUseTheKeyHandlerWhenACommandHasNoMenuItem() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.option, .command], key: "k"), for: .nextItem), .valid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.option], key: "j"), for: .toggleBookmark), .valid)
    }

    func testAnUnmodifiedKeyUsesTheKeyHandlerForAMenuCommand() {
        XCTAssertEqual(evaluate(.bare("j"), for: .volumeUp), .valid)
        XCTAssertEqual(evaluate(.bare("j"), for: .openFile), .valid)
    }

    func testShiftAloneWithAKeyIsInvalid() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.shift], key: "j"), for: .nextItem), .invalid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.shift], key: "j"), for: .playPause), .invalid)
    }

    func testAMenuKeyIsValidForACommandWithAMenuItem() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "j"), for: .newWindow, replacing: ShortcutKey(modifiers: [.command], key: "n")), .valid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.control, .option], key: "j"), for: .revealInFinder,
                                replacing: ShortcutKey(modifiers: [.shift, .command], key: "r")), .valid)
    }

    func testAMenuCommandAcceptsMoreThanOneModifiedKey() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "j"), for: .volumeUp), .valid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.option], key: "j"), for: .volumeUp), .valid)
    }

    func testPlayPauseAcceptsSpaceAndTwoModifiedKeys() {
        XCTAssertEqual(evaluate(.bare("j"), for: .playPause), .valid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.control], key: "p"), for: .playPause), .valid)
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.option], key: "p"), for: .playPause), .valid)
    }

    func testAnUnmodifiedKeyIsValidForACommandTheKeyHandlerDelivers() {
        XCTAssertEqual(evaluate(.bare("j"), for: .nextItem), .valid)
        XCTAssertEqual(evaluate(.bare("j"), for: .renameFile), .valid)
        XCTAssertEqual(evaluate(.bare(ShortcutKey.upArrow), for: .toggleBookmark), .valid)
    }

    func testAKeyOwnedByAnotherCommandConflicts() {
        XCTAssertEqual(evaluate(ShortcutKey(modifiers: [.command], key: "q"), for: .nextItem), .conflict(with: .quit))
    }

    func testEveryReservedTextEditingKeyConflictsWithItsFixedRow() {
        let rows: [(ShortcutCommandID, ShortcutKey)] = [
            (.undoTyping, ShortcutKey(modifiers: [.command], key: "z")),
            (.redoTyping, ShortcutKey(modifiers: [.shift, .command], key: "z")),
            (.cut, ShortcutKey(modifiers: [.command], key: "x")),
            (.copy, ShortcutKey(modifiers: [.command], key: "c")),
            (.paste, ShortcutKey(modifiers: [.command], key: "v")),
            (.selectAll, ShortcutKey(modifiers: [.command], key: "a")),
        ]
        for (owner, key) in rows {
            for id in [ShortcutCommandID.nextItem, .openFile, .playPause] {
                XCTAssertEqual(evaluate(key, for: id), .conflict(with: owner))
                XCTAssertEqual(evaluate(key, for: id).message,
                               ShortcutKeyValidation.conflictMessage(actionName: ShortcutCommandTable.command(owner).name))
            }
        }
    }

    func testShiftWithNonLetterIsInvalidAndShowsTheInvalidMessage() {
        let key = ShortcutKey(modifiers: [.command, .shift], key: ",")
        XCTAssertEqual(evaluate(key, for: .nextItem), .invalid)
        XCTAssertEqual(evaluate(key, for: .nextItem).message, ShortcutKeyValidation.invalidMessage)
    }

    func testAKeyNoCommandUsesIsValid() {
        XCTAssertEqual(ShortcutKeyValidation.valid.message, nil)
        XCTAssertTrue(ShortcutKeyValidation.valid.allowsSave)
    }
}
