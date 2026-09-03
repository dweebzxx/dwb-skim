import AppKit
import XCTest

final class SkimKeyboardShortcutTests: XCTestCase {

    // MARK: - P36 target mappings

    func testCommaMapsToPreviousVideo() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: ","), .previousVideo)
    }

    func testPeriodMapsToNextVideo() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "."), .nextVideo)
    }

    func testNMapsToPrimaryPrefixRename() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "n"), .primaryPrefixRename)
    }

    func testMMapsToSecondaryPrefixRename() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "m"), .secondaryPrefixRename)
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

    // MARK: - Unaffected bindings preserved

    func testUnaffectedBindingsPreserved() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "k"), .reviewKeep)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "d"), .reviewDelete)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "r"), .renameSheet)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "z"), .reviewUndo)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "q"), .toggleQueuePanel)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: " "), .togglePlayPause)
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: "f"), .toggleFullScreen)
    }

    func testUnknownKeyIsUnbound() {
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "x"))
        XCTAssertNil(SkimKeyboardShortcut(unmodifiedKey: "1"))
    }
}
