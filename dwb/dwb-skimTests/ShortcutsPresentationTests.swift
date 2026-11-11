import XCTest

final class ShortcutsPresentationTests: XCTestCase {

    private var allRows: [ShortcutRow] { ShortcutsPresentation.groups.flatMap(\.rows) }

    // MARK: - Grouping

    func testGroupsAreTheFiveTasksInOrder() {
        XCTAssertEqual(ShortcutsPresentation.groups.map(\.title),
                       ["Playback", "Navigation", "File markers", "Queue & window", "dwb skim only"])
        XCTAssertEqual(ShortcutsPresentation.groups.map(\.title), ShortcutsPresentation.groupTitles)
    }

    func testFileMarkersGroupHoldsTheMarkerAndBookmarkKeys() {
        let group = ShortcutsPresentation.groups.first { $0.title == "File markers" }
        XCTAssertEqual(group?.rows.map(\.title), [
            "Primary prefix (add / remove / replace)",
            "Secondary prefix (add / remove / replace)",
            "Rename current file\u{2026}",
            "Undo last prefix change",
            "Bookmark",
        ])
        XCTAssertEqual(group?.rows.map(\.spoken), ["N", "M", "R", "Command-Z", "B"])
        XCTAssertEqual(group?.rows.first?.tone, .markerPrimary)
        XCTAssertEqual(group?.rows.dropFirst().first?.tone, .markerSecondary)
    }

    func testSkimOnlyGroupHoldsTheSkimAndSegmentKeys() {
        let group = ShortcutsPresentation.groups.first { $0.title == "dwb skim only" }
        XCTAssertEqual(group?.rows.map(\.title), ["Toggle Skim", "Next Progressive Random Skim segment"])
    }

    func testEveryRowThePageHadIsStillThereExactlyOnce() {
        let expected = [
            "Rename current file\u{2026}", "Undo last prefix change", "Bookmark",
            "Primary prefix (add / remove / replace)", "Secondary prefix (add / remove / replace)",
            "Previous item", "Next item", "Toggle queue panel",
            "Play/Pause", "Fullscreen", "Toggle Skim",
            "Seek backward 10 seconds", "Seek forward 10 seconds",
            "Next Progressive Random Skim segment",
            "Settings\u{2026}", "Quit dwb skim", "Open\u{2026}", "Reveal in Finder", "Clear Queue",
            "New Window", "Play / Pause", "Volume Up", "Volume Down", "Fit", "Fill", "Stretch",
            "Minimize", "Close", "Four Window Grid",
        ]
        XCTAssertEqual(allRows.count, expected.count)
        XCTAssertEqual(allRows.map(\.title).sorted(), expected.sorted())
    }

    func testSeekRowsMatchTheKeyboardShortcutTable() {
        let seek = allRows.filter { $0.title.hasPrefix("Seek") }.map { ($0.title, $0.spoken) }
        XCTAssertEqual(seek.count, SkimKeyboardShortcut.tenSecondSeekSettingsRows.count)
        for (title, key) in SkimKeyboardShortcut.tenSecondSeekSettingsRows {
            XCTAssertTrue(seek.contains { $0.0 == title && $0.1 == key }, title)
        }
    }

    // MARK: - Search

    func testBlankQueryKeepsEveryGroup() {
        XCTAssertEqual(ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: ""),
                       ShortcutsPresentation.groups)
        XCTAssertEqual(ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "  "),
                       ShortcutsPresentation.groups)
    }

    func testSearchByActionNameLeavesTheUndoRow() {
        let result = ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "undo")
        XCTAssertEqual(result.map(\.title), ["File markers"])
        XCTAssertEqual(result.first?.rows.map(\.title), ["Undo last prefix change"])
        XCTAssertEqual(result.first?.rows.first?.caps, ["\u{2318}Z"])
    }

    func testSearchIsCaseInsensitive() {
        let result = ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "UNDO")
        XCTAssertEqual(result.flatMap(\.rows).map(\.title), ["Undo last prefix change"])
    }

    func testSearchByKeyCapFindsTheRow() {
        let result = ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "\u{2318}z")
        XCTAssertEqual(result.flatMap(\.rows).map(\.title), ["Undo last prefix change"])
    }

    func testSearchByKeyWordFindsTheRow() {
        let result = ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "command-shift-r")
        XCTAssertEqual(result.flatMap(\.rows).map(\.title), ["Reveal in Finder"])
    }

    func testSearchDropsGroupsWithNoRows() {
        let result = ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "skim segment")
        XCTAssertEqual(result.map(\.title), ["dwb skim only"])
    }

    func testSearchWithNoMatchReturnsNothing() {
        XCTAssertTrue(ShortcutsPresentation.filtered(ShortcutsPresentation.groups, query: "zzzz").isEmpty)
    }

    // MARK: - Caps

    func testChordsAreDrawnWithModifierGlyphs() {
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Command-Z"), "\u{2318}Z")
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Command-Shift-R"), "\u{2318}\u{21E7}R")
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Command-Shift-Delete"), "\u{2318}\u{21E7}\u{232B}")
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Command-,"), "\u{2318},")
    }

    func testSingleKeysAndGesturesPassThrough() {
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Space"), "Space")
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "N"), "N")
        XCTAssertEqual(ShortcutsPresentation.capText(forSpoken: "Double-tap Option"), "Double-tap Option")
    }

    // MARK: - Keyboard map

    func testMapLayoutHasTheQwertyRowsSpaceAndArrows() {
        XCTAssertEqual(ShortcutsPresentation.mapLetterRows.map(\.count), [13, 9, 9])
        XCTAssertEqual(ShortcutsPresentation.mapArrowKeys.count, 4)
        XCTAssertTrue(ShortcutsPresentation.mapKeySet.contains("Space"))
    }

    func testMarkerKeysTakeTheMarkerTonesAndOthersTheAccent() {
        let tones = ShortcutsPresentation.mapTones()
        XCTAssertEqual(tones["N"], .markerPrimary)
        XCTAssertEqual(tones["M"], .markerSecondary)
        XCTAssertEqual(tones["Q"], .accent)
        XCTAssertEqual(tones["Space"], .accent)
        XCTAssertNil(tones["Z"])
    }

    func testRowsLightTheirOwnKeysOnTheMap() {
        let primary = allRows.first { $0.title == "Primary prefix (add / remove / replace)" }
        XCTAssertEqual(primary?.mapKeys, ["N"])
        // Chords have no single key on the map.
        let undo = allRows.first { $0.title == "Undo last prefix change" }
        XCTAssertEqual(undo?.mapKeys, [])
    }

    func testRowAccessibilityLabelKeepsTheKeyWords() {
        let undo = allRows.first { $0.title == "Undo last prefix change" }
        XCTAssertEqual(undo?.accessibilityLabel, "Undo last prefix change, Command-Z")
    }
}
