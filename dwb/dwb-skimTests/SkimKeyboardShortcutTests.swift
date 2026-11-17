import AppKit
import XCTest

final class SkimKeyboardShortcutTests: XCTestCase {

    // MARK: - P36 target mappings

    func testCommaMapsToPreviousVideo() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: ","), .previousVideo)
    }

    func testPeriodMapsToNextVideo() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "."), .nextVideo)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "p"), .startQueueFromTop)
        XCTAssertEqual(SkimKeyboardShortcut.startQueueFromTop.commandID, .startQueueFromTop)
    }

    func testNMapsToPrimaryPrefixRename() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "n"), .primaryPrefixRename)
    }

    func testMMapsToSecondaryPrefixRename() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "m"), .secondaryPrefixRename)
    }

    func testAssignedKeysReadFromTheSameTableAsTheKeyLookup() {
        for assignment in SkimKeyboardShortcut.keyAssignments {
            // Two actions can share a key when they apply in different Skim states, so the
            // lookup returns every action that holds the key.
            XCTAssertTrue(SkimKeyboardShortcut.shortcuts(for: .bare(assignment.key)).contains(assignment.shortcut), assignment.key)
            XCTAssertTrue(SkimKeyboardShortcut.assignedKeys(for: assignment.shortcut).contains(assignment.key))
        }
        XCTAssertEqual(SkimKeyboardShortcut.assignedKeys(for: .primaryPrefixRename), ["n"])
        XCTAssertEqual(SkimKeyboardShortcut.assignedKeys(for: .secondaryPrefixRename), ["m"])
    }

    func testKeyCapTextForSettings() {
        XCTAssertEqual(SkimKeyboardShortcut.keyCapText("n"), "N")
        XCTAssertEqual(SkimKeyboardShortcut.keyCapText(" "), "Space")
        XCTAssertEqual(SkimKeyboardShortcut.keyCapText(SkimKeyboardShortcut.leftArrowKey), "\u{2190}")
        XCTAssertEqual(SkimKeyboardShortcut.keyCapText(SkimKeyboardShortcut.rightArrowKey), "\u{2192}")
    }

    func testRightArrowMapsToForwardTenSecondSeekShortcut() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: SkimKeyboardShortcut.rightArrowKey),
                       .seekForwardTenSeconds)
    }

    func testLeftArrowMapsToBackwardTenSecondSeekShortcut() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: SkimKeyboardShortcut.leftArrowKey),
                       .seekBackwardTenSeconds)
    }

    func testSkimOffRightArrowDispatchesForwardTenSecondSeek() {
        XCTAssertEqual(SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
            isSkimEnabled: false,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        ), .seek(seconds: 10))
    }

    func testSkimOffLeftArrowDispatchesBackwardTenSecondSeek() {
        XCTAssertEqual(SkimKeyboardShortcut.seekBackwardTenSeconds.arrowDispatch(
            isSkimEnabled: false,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        ), .seek(seconds: -10))
    }

    func testRepeatedArrowKeyDownIsHandledOnlyWhenSkimIsOff() {
        XCTAssertTrue(SkimKeyboardShortcut.seekForwardTenSeconds.handlesKeyRepeat(isSkimEnabled: false))
        XCTAssertTrue(SkimKeyboardShortcut.seekBackwardTenSeconds.handlesKeyRepeat(isSkimEnabled: false))
        XCTAssertFalse(SkimKeyboardShortcut.seekForwardTenSeconds.handlesKeyRepeat(isSkimEnabled: true))
        XCTAssertFalse(SkimKeyboardShortcut.seekBackwardTenSeconds.handlesKeyRepeat(isSkimEnabled: true))
        XCTAssertFalse(SkimKeyboardShortcut.nextVideo.handlesKeyRepeat(isSkimEnabled: false))

        let forward = SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
            isSkimEnabled: false,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        )
        let backward = SkimKeyboardShortcut.seekBackwardTenSeconds.arrowDispatch(
            isSkimEnabled: false,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        )
        XCTAssertEqual(forward, .seek(seconds: 10))
        XCTAssertEqual(backward, .seek(seconds: -10))
    }

    func testSkimActiveArrowsDoNotDispatchTenSecondSeeks() {
        XCTAssertEqual(SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
            isSkimEnabled: true,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        ), .passThrough)
        XCTAssertEqual(SkimKeyboardShortcut.seekBackwardTenSeconds.arrowDispatch(
            isSkimEnabled: true,
            isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        ), .passThrough)
    }

    func testProgressiveRandomSkimRightArrowRetainsNextSegmentDispatch() {
        XCTAssertEqual(SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
            isSkimEnabled: true,
            isProgressiveRandomSkimSessionActive: true,
            canManuallyAdvanceProgressiveRandomSkimSegment: true
        ), .advanceProgressiveRandomSkimSegment)
    }

    func testProgressiveRandomSkimFinalSegmentRightArrowRemainsConsumed() {
        XCTAssertEqual(SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
            isSkimEnabled: true,
            isProgressiveRandomSkimSessionActive: true,
            canManuallyAdvanceProgressiveRandomSkimSegment: false
        ), .consume)
    }

    func testTenSecondSeekSettingsRowsContainBothArrowKeysExactlyOnce() {
        XCTAssertEqual(SkimKeyboardShortcut.tenSecondSeekSettingsRows.map(\.0),
                       ["Seek backward 10 seconds", "Seek forward 10 seconds"])
        XCTAssertEqual(SkimKeyboardShortcut.tenSecondSeekSettingsRows.map(\.1), ["←", "→"])
    }

    // MARK: - Superseded bindings are removed, not retained as aliases

    func testMDoesNotMapToMute() {
        // `m` now routes to Secondary Prefix Rename; there is no `.mute` case.
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "m"), .secondaryPrefixRename)
    }

    func testOpenBracketIsNoLongerBound() {
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "["))
    }

    func testCloseBracketIsNoLongerBound() {
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "]"))
    }

    func testKeepDeleteAndPlainUndoKeysAreNoLongerBound() {
        // SD-023: N and M are the only marker keys; undo is Command-Z in the Edit menu.
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "k"))
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "d"))
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "z"))
    }

    // MARK: - P46 bookmark

    func testBMapsToToggleBookmark() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "b"), .toggleBookmark)
    }

    func testBookmarkKeyIgnoresKeyRepeat() {
        XCTAssertFalse(SkimKeyboardShortcut.toggleBookmark.handlesKeyRepeat(isSkimEnabled: false))
        XCTAssertFalse(SkimKeyboardShortcut.toggleBookmark.handlesKeyRepeat(isSkimEnabled: true))
    }

    // MARK: - Unaffected bindings preserved

    func testUnaffectedBindingsPreserved() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "r"), .renameSheet)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "q"), .toggleQueuePanel)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: " "), .togglePlayPause)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "f"), .toggleFullScreen)
    }

    func testUnknownKeyIsUnbound() {
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "x"))
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "1"))
    }

    // MARK: - Keys come from the command table

    private let arrowRight = SkimKeyboardShortcut.rightArrowKey
    private let arrowLeft = SkimKeyboardShortcut.leftArrowKey

    private func resolve(_ key: String,
                         skim: Bool = false,
                         session: Bool = false,
                         canAdvance: Bool = false,
                         store: ShortcutStore) -> SkimKeyboardShortcut.Resolution? {
        SkimKeyboardShortcut.resolve(unmodifiedKey: key,
                                     isSkimEnabled: skim,
                                     isProgressiveRandomSkimSessionActive: session,
                                     canManuallyAdvanceProgressiveRandomSkimSegment: canAdvance,
                                     store: store)
    }

    func testEveryDefaultKeyRunsTheSameActionAsBefore() {
        let (store, _, _) = makeShortcutStore()
        let expected: [(String, SkimKeyboardShortcut)] = [
            (",", .previousVideo), (".", .nextVideo), ("p", .startQueueFromTop),
            ("n", .primaryPrefixRename), ("m", .secondaryPrefixRename),
            ("r", .renameSheet), ("b", .toggleBookmark), ("q", .toggleQueuePanel), (" ", .togglePlayPause),
            ("f", .toggleFullScreen),
        ]
        for (key, shortcut) in expected {
            XCTAssertEqual(resolve(key, store: store)?.shortcut, shortcut, key)
            XCTAssertEqual(resolve(key, skim: true, store: store)?.shortcut, shortcut, key)
            XCTAssertNil(resolve(key, store: store)?.arrow)
        }
        XCTAssertEqual(resolve(arrowLeft, store: store), .init(shortcut: .seekBackwardTenSeconds, arrow: .seek(seconds: -10)))
        XCTAssertEqual(resolve(arrowRight, store: store), .init(shortcut: .seekForwardTenSeconds, arrow: .seek(seconds: 10)))
    }

    func testDefaultRightArrowWithSkimOnFollowsTheProgressiveRandomSkimStates() {
        let (store, _, _) = makeShortcutStore()
        XCTAssertEqual(resolve(arrowRight, skim: true, session: true, canAdvance: true, store: store),
                       .init(shortcut: .nextProgressiveRandomSkimSegment, arrow: .advanceProgressiveRandomSkimSegment))
        XCTAssertEqual(resolve(arrowRight, skim: true, session: true, canAdvance: false, store: store)?.arrow, .consume)
        XCTAssertEqual(resolve(arrowRight, skim: true, session: false, canAdvance: false, store: store)?.arrow, .passThrough)
    }

    func testDefaultLeftArrowWithSkimOnRunsNothing() {
        let (store, _, _) = makeShortcutStore()
        XCTAssertNil(resolve(arrowLeft, skim: true, store: store))
    }

    func testUnboundKeysRunNothing() {
        let (store, _, _) = makeShortcutStore()
        for key in ["x", "1", "[", "]", "k", "d", "z"] {
            XCTAssertNil(resolve(key, store: store), key)
        }
    }

    func testAnOverrideMovesTheActionAndFreesTheOldKey() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        XCTAssertEqual(resolve("j", store: store)?.shortcut, .nextVideo)
        XCTAssertEqual(resolve("j", skim: true, store: store)?.shortcut, .nextVideo)
        XCTAssertNil(resolve(".", store: store))
        XCTAssertEqual(resolve(",", store: store)?.shortcut, .previousVideo)
    }

    func testMovingSeekForwardKeepsTheSegmentKeyOnTheRightArrow() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(arrowRight), with: .bare("l"), for: .seekForward)

        // Skim off: L seeks, and the old arrow no longer does.
        XCTAssertEqual(resolve("l", store: store), .init(shortcut: .seekForwardTenSeconds, arrow: .seek(seconds: 10)))
        XCTAssertNil(resolve(arrowRight, store: store))
        // Skim on with Progressive Random Skim: the right arrow still advances the segment; L does nothing.
        XCTAssertEqual(resolve(arrowRight, skim: true, session: true, canAdvance: true, store: store)?.arrow,
                       .advanceProgressiveRandomSkimSegment)
        XCTAssertNil(resolve("l", skim: true, session: true, canAdvance: true, store: store))
    }

    func testMovingTheSegmentKeyLeavesTheSeekOnTheRightArrow() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(arrowRight), with: .bare("j"), for: .nextSkimSegment)
        XCTAssertEqual(resolve("j", skim: true, session: true, canAdvance: true, store: store)?.arrow,
                       .advanceProgressiveRandomSkimSegment)
        XCTAssertNil(resolve("j", store: store))
        XCTAssertEqual(resolve(arrowRight, store: store)?.arrow, .seek(seconds: 10))
        XCTAssertNil(resolve(arrowRight, skim: true, session: true, canAdvance: true, store: store))
    }

    func testOneCustomKeyCanSeekWithSkimOffAndAdvanceWithSkimOn() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(arrowRight), with: .bare("l"), for: .seekForward)
        store.replaceKey(.bare(arrowRight), with: .bare("l"), for: .nextSkimSegment)
        XCTAssertEqual(resolve("l", store: store)?.arrow, .seek(seconds: 10))
        XCTAssertEqual(resolve("l", skim: true, session: true, canAdvance: true, store: store)?.arrow,
                       .advanceProgressiveRandomSkimSegment)
    }

    func testAnActionWithTwoKeysAnswersToBoth() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(nil, with: .bare("h"), for: .togglePrimaryPrefix)
        XCTAssertEqual(resolve("n", store: store)?.shortcut, .primaryPrefixRename)
        XCTAssertEqual(resolve("h", store: store)?.shortcut, .primaryPrefixRename)
        XCTAssertEqual(SkimKeyboardShortcut.shortcuts(for: .bare("h"), store: store), [.primaryPrefixRename])
    }

    func testModifiedNextItemKeyRunsOnlyFromTheKeyHandlerRoute() {
        let (store, _, _) = makeShortcutStore()
        let key = ShortcutKey(modifiers: [.option, .command], key: "k")
        store.replaceKey(nil, with: key, for: .nextItem)
        let matches = SkimKeyboardShortcut.shortcuts(for: key, store: store)
        XCTAssertEqual(matches, [.nextVideo])
        XCTAssertEqual(SkimKeyboardShortcut.resolve(key: key, isSkimEnabled: false,
                                                  isProgressiveRandomSkimSessionActive: false,
                                                  canManuallyAdvanceProgressiveRandomSkimSegment: false,
                                                  store: store)?.shortcut, .nextVideo)
    }

    func testModifiedPlayPauseKeysStayOnTheMenuRoute() {
        let (store, _, _) = makeShortcutStore()
        let first = ShortcutKey(modifiers: [.control], key: "p")
        let second = ShortcutKey(modifiers: [.option], key: "p")
        store.replaceKey(nil, with: first, for: .playPause)
        store.replaceKey(nil, with: second, for: .playPause)
        XCTAssertEqual(store.activeKeys(for: .playPause).filter(\.usesMenu), [first, second])
        XCTAssertEqual(ShortcutCommandTable.command(.playPause).route(for: first), .menu)
        XCTAssertEqual(ShortcutCommandTable.command(.playPause).route(for: second), .menu)
        XCTAssertTrue(SkimKeyboardShortcut.shortcuts(for: first, store: store).isEmpty)
        XCTAssertTrue(SkimKeyboardShortcut.shortcuts(for: second, store: store).isEmpty)
    }

    func testAnUnassignedActionRunsNothing() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: nil, for: .togglePrimaryPrefix)
        XCTAssertNil(resolve("n", store: store))
    }

    func testKeyRepeatFollowsTheActionNotTheKey() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare(arrowRight), with: .bare("l"), for: .seekForward)
        let seek = resolve("l", store: store)?.shortcut
        XCTAssertEqual(seek?.handlesKeyRepeat(isSkimEnabled: false), true)
        XCTAssertEqual(seek?.handlesKeyRepeat(isSkimEnabled: true), false)
        let segment = resolve(arrowRight, skim: true, session: true, canAdvance: true, store: store)?.shortcut
        XCTAssertEqual(segment?.handlesKeyRepeat(isSkimEnabled: true), false)
    }

    func testTheSegmentActionAppliesOnlyWithSkimOn() {
        XCTAssertTrue(SkimKeyboardShortcut.nextProgressiveRandomSkimSegment.isActive(isSkimEnabled: true))
        XCTAssertFalse(SkimKeyboardShortcut.nextProgressiveRandomSkimSegment.isActive(isSkimEnabled: false))
        XCTAssertTrue(SkimKeyboardShortcut.seekForwardTenSeconds.isActive(isSkimEnabled: false))
        XCTAssertFalse(SkimKeyboardShortcut.seekForwardTenSeconds.isActive(isSkimEnabled: true))
        XCTAssertTrue(SkimKeyboardShortcut.nextVideo.isActive(isSkimEnabled: true))
        XCTAssertTrue(SkimKeyboardShortcut.nextVideo.isActive(isSkimEnabled: false))
    }

    func testTheSegmentActionDispatchMatchesTheDefaultRightArrow() {
        for session in [false, true] {
            for canAdvance in [false, true] {
                XCTAssertEqual(
                    SkimKeyboardShortcut.nextProgressiveRandomSkimSegment.arrowDispatch(
                        isSkimEnabled: true, isProgressiveRandomSkimSessionActive: session,
                        canManuallyAdvanceProgressiveRandomSkimSegment: canAdvance),
                    SkimKeyboardShortcut.seekForwardTenSeconds.arrowDispatch(
                        isSkimEnabled: true, isProgressiveRandomSkimSessionActive: session,
                        canManuallyAdvanceProgressiveRandomSkimSegment: canAdvance))
            }
        }
        XCTAssertEqual(SkimKeyboardShortcut.nextProgressiveRandomSkimSegment.arrowDispatch(
            isSkimEnabled: false, isProgressiveRandomSkimSessionActive: false,
            canManuallyAdvanceProgressiveRandomSkimSegment: false), .passThrough)
    }

    func testTheSeekRowsAreReadFromTheTable() {
        XCTAssertEqual(SkimKeyboardShortcut.tenSecondSeekSettingsRows.map(\.0),
                       [ShortcutCommandTable.command(.seekBackward).name, ShortcutCommandTable.command(.seekForward).name])
    }
}
