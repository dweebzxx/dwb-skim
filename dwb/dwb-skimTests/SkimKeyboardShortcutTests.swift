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

    func testRightArrowMapsToAdvanceProgressiveRandomSkimSegment() {
        XCTAssertEqual(SkimKeyboardShortcut(unmodifiedKey: SkimKeyboardShortcut.rightArrowKey),
                       .advanceProgressiveRandomSkimSegment)
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
