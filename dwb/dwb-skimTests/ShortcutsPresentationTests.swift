import XCTest

final class ShortcutsPresentationTests: XCTestCase {

    private func groups(_ store: ShortcutStore? = nil) -> [ShortcutGroup] {
        ShortcutsPresentation.groups(store: store ?? makeShortcutStore().store)
    }

    private func rows(_ store: ShortcutStore? = nil) -> [ShortcutRow] { groups(store).flatMap(\.rows) }

    private func titles(_ query: String, store: ShortcutStore? = nil) -> [String] {
        let all = groups(store)
        return ShortcutsPresentation.filtered(all, query: query).flatMap(\.rows).map(\.title)
    }

    // MARK: - Page text

    func testPageTextMatchesTheApprovedWording() {
        XCTAssertEqual(ShortcutsPresentation.pageDescription, "Find and customize keyboard shortcuts for this app.")
        XCTAssertEqual(ShortcutsPresentation.scopeText, "Changes apply only to dwb skim.")
        XCTAssertEqual(ShortcutsPresentation.searchLabel, "Search shortcuts")
        XCTAssertEqual(ShortcutsPresentation.restoreDefaultsTitle, "Restore Defaults\u{2026}")
        XCTAssertEqual(ShortcutsPresentation.restoreConfirmTitle, "Restore default shortcuts for dwb skim?")
        XCTAssertEqual(ShortcutsPresentation.restoreConfirmAction, "Restore Defaults")
        XCTAssertEqual(ShortcutsPresentation.noMatchesText, "No matching shortcuts.")
    }

    // MARK: - Grouping

    func testGroupsAreTheTasksInOrder() {
        XCTAssertEqual(groups().map(\.title),
                       ["Playback", "Skim", "Navigation", "File actions", "Bookmarks", "Window", "Queue", "Text editing"])
        XCTAssertEqual(groups().map(\.title), ShortcutsPresentation.groupTitles)
    }

    func testEveryCommandIsOneRowInOneGroup() {
        XCTAssertEqual(rows().count, ShortcutCommandTable.all.count)
        XCTAssertEqual(Set(rows().map(\.commandID)), Set(ShortcutCommandID.allCases))
        for group in groups() {
            for row in group.rows { XCTAssertEqual(row.groupTitle, group.title) }
        }
    }

    func testSkimGroupHoldsToggleSkimAndTheSegmentKey() {
        let group = groups().first { $0.title == "Skim" }
        XCTAssertEqual(group?.rows.map(\.title), ["Toggle Skim", "Next Progressive Random Skim segment"])
        let toggle = group?.rows.first
        XCTAssertEqual(toggle?.caps, ["Double-tap Option"])
        XCTAssertEqual(toggle?.isEditable, false)
        XCTAssertEqual(toggle?.keys, [])
    }

    func testPlayOrPauseIsOneRowWithSpaceOnly() {
        let row = rows().first { $0.title == "Play or pause" }
        XCTAssertEqual(row?.caps, ["Space"])
        XCTAssertEqual(rows().filter { $0.title == "Play or pause" }.count, 1)
    }

    func testTextEditingRowsAreLastInTheApprovedOrder() {
        XCTAssertEqual(groups().last?.rows.map(\.title),
                       ["Undo typing", "Redo typing", "Cut", "Copy", "Paste", "Select all"])
        let text = groups().last?.rows ?? []
        XCTAssertEqual(text.map(\.caps), [["⌘Z"], ["⇧⌘Z"], ["⌘X"], ["⌘C"], ["⌘V"], ["⌘A"]])
        XCTAssertEqual(text.prefix(2).map(\.contextText),
                       ["While a text field is being edited.", "While a text field is being edited."])
        XCTAssertEqual(text.dropFirst(2).map(\.contextText),
                       Array(repeating: "Acts on the text field being edited. The key is reserved in every window.", count: 4))
        XCTAssertEqual(groups().first { $0.title == "File actions" }?.rows.contains { $0.title == "Undo prefix change" }, true)
    }

    func testSettingsSidebarNavigationRowIsInNavigationGroup() {
        let row = groups().first { $0.title == "Navigation" }?.rows.first { $0.title == "Move between Settings pages" }
        XCTAssertEqual(row?.caps, ["↑", "↓"])
        XCTAssertEqual(row?.contextText, "Settings window, with the sidebar focused.")
        XCTAssertEqual(row?.isEditable, false)
    }

    func testSeekAndSegmentStaySeparateRowsOnTheSameKey() {
        let seek = rows().first { $0.title == "Seek forward 10 seconds" }
        let segment = rows().first { $0.title == "Next Progressive Random Skim segment" }
        XCTAssertEqual(seek?.caps, ["\u{2192}"])
        XCTAssertEqual(segment?.caps, ["\u{2192}"])
    }

    func testSeekRowsMatchTheKeyboardShortcutTable() {
        let seek = rows().filter { $0.title.hasPrefix("Seek") }.map { ($0.title, $0.caps.first ?? "") }
        XCTAssertEqual(seek.count, SkimKeyboardShortcut.tenSecondSeekSettingsRows.count)
        for (title, key) in SkimKeyboardShortcut.tenSecondSeekSettingsRows {
            XCTAssertTrue(seek.contains { $0.0 == title && $0.1 == key }, title)
        }
    }

    func testKeysUseSymbolsInTheStandardModifierOrder() {
        let byTitle = Dictionary(uniqueKeysWithValues: rows().map { ($0.title, $0.caps) })
        XCTAssertEqual(byTitle["Reveal in Finder"], ["\u{21E7}\u{2318}R"])
        XCTAssertEqual(byTitle["Clear queue"], ["\u{21E7}\u{2318}\u{232B}"])
        XCTAssertEqual(byTitle["Volume up"], ["\u{2318}\u{2191}"])
        XCTAssertEqual(byTitle["Undo prefix change"], ["\u{2318}Z"])
        XCTAssertEqual(byTitle["Remove selected queue items"], ["\u{232B}", "\u{2326}"])
    }

    func testEveryConditionalActionCarriesItsContextInTheRow() {
        let byTitle = Dictionary(uniqueKeysWithValues: rows().map { ($0.title, $0) })
        XCTAssertTrue(byTitle["Seek forward 10 seconds"]?.contextText?.contains("Skim is off") == true)
        XCTAssertTrue(byTitle["Next Progressive Random Skim segment"]?.contextText?.contains("Skim is on") == true)
        XCTAssertTrue(byTitle["Next Progressive Random Skim segment"]?.contextText?.contains("Progressive Random Skim") == true)
        XCTAssertTrue(byTitle["Next item"]?.contextText?.contains("text field") == true)
        XCTAssertTrue(byTitle["Undo typing"]?.contextText?.contains("text field") == true)
        XCTAssertTrue(byTitle["Remove selected queue items"]?.contextText?.contains("Queue panel") == true)
        XCTAssertNil(byTitle["Volume up"]?.contextText)
    }

    func testRenameFileKeepsTheAlwaysRenamesTheCurrentItemRule() {
        let rename = rows().first { $0.title == "Rename file" }
        XCTAssertTrue(rename?.contextText?.contains("current item") == true)
    }

    // MARK: - Unassigned and overrides

    func testAnActionWithNoKeyIsUnassigned() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: nil, for: .nextItem)
        let row = rows(store).first { $0.title == "Next item" }
        XCTAssertEqual(row?.isUnassigned, true)
        XCTAssertEqual(row?.caps, [])
        XCTAssertEqual(row?.spoken, "Unassigned")
        XCTAssertEqual(titles("unassigned", store: store), ["Next item"])
    }

    func testRowsFollowTheKeysInUse() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("."), with: .bare("j"), for: .nextItem)
        let row = rows(store).first { $0.title == "Next item" }
        XCTAssertEqual(row?.caps, ["J"])
        XCTAssertEqual(row?.isUnassigned, false)
    }

    func testNoRowIsUnassignedByDefault() {
        XCTAssertEqual(rows().filter(\.isUnassigned).count, 0)
    }

    // MARK: - Search

    func testBlankQueryKeepsEveryGroup() {
        let all = groups()
        XCTAssertEqual(ShortcutsPresentation.filtered(all, query: ""), all)
        XCTAssertEqual(ShortcutsPresentation.filtered(all, query: "  "), all)
    }

    func testSearchByActionName() {
        XCTAssertEqual(Set(titles("vol")), ["Volume up", "Volume down"])
        XCTAssertEqual(titles("undo"), ["Undo prefix change", "Undo typing"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(titles("UNDO"), titles("undo"))
    }

    func testSearchBySymbolAndBySpokenFormFindTheSameRows() {
        let symbol = titles("\u{2318}")
        let word = titles("command")
        XCTAssertEqual(Set(symbol), Set(word))
        XCTAssertFalse(symbol.contains("Play or pause"))
        XCTAssertTrue(symbol.contains("Volume up"))
        XCTAssertTrue(symbol.contains("Quit dwb skim"))
        XCTAssertFalse(symbol.contains("Next item"))
    }

    func testSearchByAKeyCapAndAKeyWord() {
        XCTAssertEqual(titles("\u{2318}z"), ["Undo prefix change", "Undo typing", "Redo typing"])
        XCTAssertEqual(titles("command-shift-r"), ["Reveal in Finder", "Redo typing"])
        XCTAssertEqual(titles("command shift r"), ["Reveal in Finder", "Redo typing"])
        XCTAssertTrue(titles("right arrow").contains("Seek forward 10 seconds"))
        XCTAssertTrue(titles("comma").contains("Previous item"))
    }

    func testSearchByGroupName() {
        XCTAssertEqual(titles("bookmarks"), ["Toggle bookmark"])
        XCTAssertTrue(titles("file actions").contains("Rename file"))
    }

    func testSearchByContextText() {
        let result = titles("text field")
        XCTAssertTrue(result.contains("Next item"))
        XCTAssertTrue(result.contains("Undo typing"))
        XCTAssertFalse(result.contains("Volume up"))
        XCTAssertTrue(titles("queue panel").contains("Remove selected queue items"))
    }

    func testSearchForPrefixAndSkim() {
        XCTAssertEqual(Set(titles("prefix")), ["Toggle primary prefix", "Toggle secondary prefix", "Undo prefix change"])
        let skim = ShortcutsPresentation.filtered(groups(), query: "skim")
        XCTAssertEqual(skim.first?.title, "Playback") // the seek rows say "Skim is off"
        XCTAssertTrue(skim.contains { $0.title == "Skim" })
        XCTAssertTrue(skim.flatMap(\.rows).map(\.title).contains("Toggle Skim"))
    }

    func testSearchDropsGroupsWithNoRows() {
        let result = ShortcutsPresentation.filtered(groups(), query: "bookmarks")
        XCTAssertEqual(result.map(\.title), ["Bookmarks"])
    }

    func testSearchWithNoMatchReturnsNothing() {
        XCTAssertTrue(ShortcutsPresentation.filtered(groups(), query: "zzz").isEmpty)
    }

    // MARK: - Keyboard map

    func testMapLayoutHasTheQwertyRowsSpaceAndArrows() {
        XCTAssertEqual(ShortcutsPresentation.mapLetterRows.map(\.count), [13, 9, 9])
        XCTAssertEqual(ShortcutsPresentation.mapArrowKeys.count, 4)
        XCTAssertTrue(ShortcutsPresentation.mapKeySet.contains("Space"))
    }

    func testMarkerKeysTakeTheMarkerTonesAndOthersTheAccent() {
        let tones = ShortcutsPresentation.mapTones(in: groups())
        XCTAssertEqual(tones["N"], .markerPrimary)
        XCTAssertEqual(tones["M"], .markerSecondary)
        XCTAssertEqual(tones["Q"], .accent)
        XCTAssertEqual(tones["Space"], .accent)
        XCTAssertEqual(tones["\u{2192}"], .accent)
        XCTAssertNil(tones["Z"])
    }

    func testRowsLightTheirOwnUnmodifiedKeysOnTheMap() {
        let byTitle = Dictionary(uniqueKeysWithValues: rows().map { ($0.title, $0.mapKeys) })
        XCTAssertEqual(byTitle["Toggle primary prefix"], ["N"])
        XCTAssertEqual(byTitle["Play or pause"], ["Space"])
        XCTAssertEqual(byTitle["Seek forward 10 seconds"], ["\u{2192}"])
        XCTAssertEqual(byTitle["Previous item"], [","])
        // Chords have no single key on the map.
        XCTAssertEqual(byTitle["Undo prefix change"], [])
        XCTAssertEqual(byTitle["Toggle Skim"], [])
    }

    func testTheMapFollowsAMovedKey() {
        let (store, _, _) = makeShortcutStore()
        store.replaceKey(.bare("n"), with: .bare("k"), for: .togglePrimaryPrefix)
        let tones = ShortcutsPresentation.mapTones(in: groups(store))
        XCTAssertEqual(tones["K"], .markerPrimary)
        XCTAssertNil(tones["N"])
    }

    func testMapNames() {
        XCTAssertEqual(ShortcutsPresentation.mapName(forKey: ShortcutKey.space), "Space")
        XCTAssertEqual(ShortcutsPresentation.mapName(forKey: ShortcutKey.upArrow), "\u{2191}")
        XCTAssertEqual(ShortcutsPresentation.mapName(forKey: "j"), "J")
    }

    // MARK: - Accessibility text

    func testRowAccessibilityLabelKeepsTheKeyWords() {
        let undo = rows().first { $0.title == "Undo prefix change" }
        XCTAssertEqual(undo?.accessibilityLabel, "Undo prefix change, Command-Z")
        let play = rows().first { $0.title == "Play or pause" }
        XCTAssertEqual(play?.accessibilityLabel, "Play or pause, Space")
    }
}
