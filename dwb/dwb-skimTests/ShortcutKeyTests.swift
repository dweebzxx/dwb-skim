import AppKit
import XCTest

final class ShortcutKeyTests: XCTestCase {

    // MARK: - Notation

    func testModifierSymbolsFollowTheStandardOrder() {
        let all: ShortcutModifiers = [.command, .shift, .option, .control]
        XCTAssertEqual(all.symbols, "\u{2303}\u{2325}\u{21E7}\u{2318}")
        XCTAssertEqual(ShortcutKey(modifiers: [.command, .shift], key: "r").capText, "\u{21E7}\u{2318}R")
        XCTAssertEqual(ShortcutKey(modifiers: [.command, .option], key: "j").capText, "\u{2325}\u{2318}J")
    }

    func testSpecialKeysUseTheirGlyphs() {
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: ShortcutKey.space).capText, "\u{2318}Space")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.space).capText, "Space")
        XCTAssertEqual(ShortcutKey(modifiers: [.command, .shift], key: ShortcutKey.delete).capText, "\u{21E7}\u{2318}\u{232B}")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.rightArrow).capText, "\u{2192}")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.leftArrow).capText, "\u{2190}")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: ShortcutKey.upArrow).capText, "\u{2318}\u{2191}")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: ShortcutKey.downArrow).capText, "\u{2318}\u{2193}")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.returnKey).capText, "\u{21A9}")
        XCTAssertEqual(ShortcutKey.bare(",").capText, ",")
        XCTAssertEqual(ShortcutKey.bare("n").capText, "N")
    }

    func testSpokenFormUsesWordsInTheSameOrder() {
        XCTAssertEqual(ShortcutKey(modifiers: [.command, .shift], key: "r").spokenText, "Shift-Command-R")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: ShortcutKey.space).spokenText, "Command-Space")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.rightArrow).spokenText, "Right Arrow")
        XCTAssertEqual(ShortcutKey.bare(",").spokenText, "Comma")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: "").spokenText, "Command")
    }

    func testSearchTextHoldsTheSymbolAndTheWords() {
        let text = ShortcutKey(modifiers: [.command], key: "z").searchText
        XCTAssertTrue(text.contains("\u{2318}"))
        XCTAssertTrue(text.lowercased().contains("command"))
    }

    // MARK: - Storage

    func testStorageTextExamples() {
        XCTAssertEqual(ShortcutKey.bare("n").storageText, "n")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.space).storageText, "space")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: ShortcutKey.space).storageText, "command+space")
        XCTAssertEqual(ShortcutKey(modifiers: [.command, .shift], key: "r").storageText, "shift+command+r")
        XCTAssertEqual(ShortcutKey(modifiers: [.command], key: "+").storageText, "command++")
        XCTAssertEqual(ShortcutKey.bare(ShortcutKey.rightArrow).storageText, "right")
    }

    func testStorageRoundTripsEveryKindOfKey() {
        let keys: [ShortcutKey] = [
            .bare("n"), .bare(","), .bare("."), .bare("+"), .bare("["),
            .bare(ShortcutKey.space), .bare(ShortcutKey.leftArrow), .bare(ShortcutKey.delete),
            .bare(ShortcutKey.forwardDelete), .bare(ShortcutKey.returnKey),
            ShortcutKey(modifiers: [.command], key: ShortcutKey.space),
            ShortcutKey(modifiers: [.command, .shift], key: "r"),
            ShortcutKey(modifiers: [.control, .option, .shift, .command], key: ShortcutKey.upArrow),
            ShortcutKey(modifiers: [.command], key: "+"),
            ShortcutKey(modifiers: [.option], key: "5"),
        ]
        for key in keys {
            XCTAssertEqual(ShortcutKey(storageText: key.storageText), key, key.storageText)
        }
    }

    func testStorageReadsModifiersInAnyOrderAndAnyCase() {
        XCTAssertEqual(ShortcutKey(storageText: "command+shift+R"),
                       ShortcutKey(modifiers: [.command, .shift], key: "r"))
        XCTAssertEqual(ShortcutKey(storageText: "Space"), .bare(ShortcutKey.space))
    }

    func testUnreadableStorageTextIsRejected() {
        for text in ["", "shift+", "banana", "command+", "ab", "command+shift", "+x+y"] {
            XCTAssertNil(ShortcutKey(storageText: text), text)
        }
    }

    // MARK: - Recording

    func testRecordingUsesKeyCodesForSpaceAndTheArrows() {
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 49, characters: " ", modifiers: []), .bare(ShortcutKey.space))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 123, characters: nil, modifiers: []), .bare(ShortcutKey.leftArrow))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 124, characters: "", modifiers: []), .bare(ShortcutKey.rightArrow))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 125, characters: "", modifiers: [.command]),
                       ShortcutKey(modifiers: [.command], key: ShortcutKey.downArrow))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 126, characters: "", modifiers: [.command]),
                       ShortcutKey(modifiers: [.command], key: ShortcutKey.upArrow))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 51, characters: "\u{7F}", modifiers: [.command, .shift]),
                       ShortcutKey(modifiers: [.command, .shift], key: ShortcutKey.delete))
    }

    func testRecordingUsesTheCharacterForLettersAndPunctuation() {
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 45, characters: "N", modifiers: []), .bare("n"))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 43, characters: ",", modifiers: []), .bare(","))
        XCTAssertEqual(ShortcutKey.recorded(keyCode: 15, characters: "r", modifiers: [.command, .shift]),
                       ShortcutKey(modifiers: [.command, .shift], key: "r"))
    }

    func testAKeyWithNoCharacterIsNotRecorded() {
        XCTAssertNil(ShortcutKey.recorded(keyCode: 9999, characters: nil, modifiers: []))
        XCTAssertNil(ShortcutKey.recorded(keyCode: 9999, characters: "", modifiers: []))
        XCTAssertNil(ShortcutKey.recorded(keyCode: 9999, characters: "ab", modifiers: []))
    }

    func testSuiteRecordableBaseKeys() {
        for key in ["a", "7", ",", "©", ShortcutKey.space, ShortcutKey.leftArrow,
                    ShortcutKey.rightArrow, ShortcutKey.upArrow, ShortcutKey.downArrow,
                    ShortcutKey.delete, ShortcutKey.forwardDelete] {
            XCTAssertTrue(ShortcutKey.bare(key).isRecordable, key)
        }
    }

    func testSuiteRejectsNonRecordableSpecialKeys() {
        for key in [ShortcutKey.returnKey, ShortcutKey.enter, ShortcutKey.tab,
                    ShortcutKey.escape, ShortcutKey.home, ShortcutKey.end,
                    ShortcutKey.pageUp, ShortcutKey.pageDown, ""] {
            XCTAssertFalse(ShortcutKey.bare(key).isRecordable, key)
            XCTAssertFalse(ShortcutKey(modifiers: [.command], key: key).isRecordable, key)
        }
        let functionCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                       103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for code in [UInt16](arrayLiteral: 36, 76, 48, 53, 115, 119, 116, 121) + functionCodes {
            XCTAssertNil(ShortcutKey.recorded(keyCode: code, characters: nil, modifiers: []), "\(code)")
        }
    }

    func testSuiteModifierRule() {
        for mask in 0...15 {
            let modifiers = ShortcutModifiers(rawValue: mask)
            XCTAssertEqual(ShortcutKey(modifiers: modifiers, key: "k").isRecordable,
                           mask != ShortcutModifiers.shift.rawValue, "\(mask)")
        }
        for key in ["7", ",", "©"] {
            XCTAssertFalse(ShortcutKey(modifiers: [.shift, .command], key: key).isRecordable, key)
        }
        XCTAssertTrue(ShortcutKey(modifiers: [.shift, .command], key: ShortcutKey.delete).isRecordable)
        XCTAssertTrue(ShortcutKey(modifiers: [.shift, .option], key: ShortcutKey.leftArrow).isRecordable)
    }

    // MARK: - Routes

    func testAKeyReachesTheKeyHandlerOnlyWithNoModifier() {
        XCTAssertTrue(ShortcutKey.bare("n").usesKeyHandler)
        XCTAssertFalse(ShortcutKey.bare("n").usesMenu)
        XCTAssertFalse(ShortcutKey(modifiers: [.command], key: "n").usesKeyHandler)
    }

    func testAKeyReachesTheMenuWithCommandControlOrOption() {
        XCTAssertTrue(ShortcutKey(modifiers: [.command], key: "n").usesMenu)
        XCTAssertTrue(ShortcutKey(modifiers: [.control], key: "n").usesMenu)
        XCTAssertTrue(ShortcutKey(modifiers: [.option], key: "n").usesMenu)
        XCTAssertTrue(ShortcutKey(modifiers: [.shift, .command], key: "n").usesMenu)
    }

    func testShiftAloneReachesNeitherRoute() {
        let key = ShortcutKey(modifiers: [.shift], key: "n")
        XCTAssertFalse(key.usesKeyHandler)
        XCTAssertFalse(key.usesMenu)
    }

    func testAModifierAloneReachesNeitherRoute() {
        let key = ShortcutKey(modifiers: [.command], key: "")
        XCTAssertTrue(key.isModifierOnly)
        XCTAssertFalse(key.usesKeyHandler)
        XCTAssertFalse(key.usesMenu)
    }

    // MARK: - Event flags

    func testEventFlagsKeepOnlyTheFourModifiers() {
        XCTAssertEqual(ShortcutModifiers(eventFlags: [.capsLock, .function, .numericPad]), [])
        XCTAssertEqual(ShortcutModifiers(eventFlags: [.command, .shift, .numericPad]), [.command, .shift])
        XCTAssertEqual(ShortcutModifiers([.control, .option, .shift, .command]).eventFlags,
                       [.control, .option, .shift, .command])
    }
}
