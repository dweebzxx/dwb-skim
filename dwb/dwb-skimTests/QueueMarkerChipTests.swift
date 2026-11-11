import XCTest

final class QueueMarkerChipTests: XCTestCase {

    private func chips(primary: String = "keep_",
                       secondary: String = "later_",
                       targets: [String]) -> [QueueMarkerChip] {
        QueueMarkerChip.chips(primaryPrefix: primary, secondaryPrefix: secondary, targetNames: targets)
    }

    func testChipsAreThePrimaryNThenTheSecondaryM() {
        let result = chips(targets: ["a.mp4"])
        XCTAssertEqual(result.map(\.kind), [.primary, .secondary])
        XCTAssertEqual(result.map(\.keyTag), ["N", "M"])
        XCTAssertEqual(result.map(\.label), ["keep_", "later_"])
        XCTAssertEqual(result.map(\.isEnabled), [true, true])
    }

    // MARK: - Applied state

    func testChipIsAppliedWhenEveryTargetedFileStartsWithItsPrefix() {
        let result = chips(targets: ["keep_a.mp4", "keep_b.mp4", "keep_c.mp4"])
        XCTAssertTrue(result[0].isApplied)
        XCTAssertFalse(result[1].isApplied)
    }

    func testChipIsNotAppliedWhenAnyTargetLacksThePrefix() {
        let result = chips(targets: ["keep_a.mp4", "b.mp4"])
        XCTAssertFalse(result[0].isApplied)
        XCTAssertFalse(result[1].isApplied)
    }

    func testSecondaryChipAppliesToItsOwnPrefix() {
        let result = chips(targets: ["later_a.mp4"])
        XCTAssertFalse(result[0].isApplied)
        XCTAssertTrue(result[1].isApplied)
    }

    func testNoTargetsMeansNoChipIsApplied() {
        let result = chips(targets: [])
        XCTAssertFalse(result[0].isApplied)
        XCTAssertFalse(result[1].isApplied)
    }

    func testPrefixIsMatchedAtTheStartOfTheName() {
        let result = chips(targets: ["my_keep_a.mp4"])
        XCTAssertFalse(result[0].isApplied)
    }

    func testOverlappingPrefixesResolveToTheLongerMatchLikeTheRenamer() {
        // "a_" is also the start of "a_b_": the longer prefix is the one present.
        let result = chips(primary: "a_", secondary: "a_b_", targets: ["a_b_clip.mp4"])
        XCTAssertFalse(result[0].isApplied)
        XCTAssertTrue(result[1].isApplied)
    }

    // MARK: - Blank prefix

    func testBlankPrefixShowsADashAndIsDisabled() {
        let result = chips(primary: "", secondary: "later_", targets: ["a.mp4"])
        XCTAssertEqual(result[0].label, "—")
        XCTAssertTrue(result[0].isBlank)
        XCTAssertFalse(result[0].isEnabled)
        XCTAssertFalse(result[0].isApplied)
        XCTAssertTrue(result[1].isEnabled)
    }

    func testWhitespaceOnlyPrefixIsBlank() {
        let result = chips(primary: "   ", secondary: "", targets: ["a.mp4"])
        XCTAssertTrue(result[0].isBlank)
        XCTAssertTrue(result[1].isBlank)
        XCTAssertEqual(result.map(\.label), ["—", "—"])
    }

    func testBlankPrefixIsNeverApplied() {
        let result = chips(primary: "", secondary: "", targets: ["a.mp4", "b.mp4"])
        XCTAssertEqual(result.map(\.isApplied), [false, false])
    }

    // MARK: - Label

    func testLabelIsTheTrimmedPrefix() {
        XCTAssertEqual(QueueMarkerChip.label(for: "  keep_ "), "keep_")
    }

    func testLabelKeepsUpToEightCharacters() {
        XCTAssertEqual(QueueMarkerChip.label(for: "12345678"), "12345678")
    }

    func testLongerLabelIsCutToEightCharactersWithAnEllipsis() {
        XCTAssertEqual(QueueMarkerChip.label(for: "123456789"), "12345678…")
    }

    // MARK: - Duplicate

    func testSecondaryChipIsOmittedWhenItRepeatsThePrimary() {
        let result = chips(primary: "keep_", secondary: "keep_", targets: ["a.mp4"])
        XCTAssertEqual(result.map(\.kind), [.primary])
    }

    // MARK: - Label (R5)

    func testEmptyAndWhitespaceOnlyLabelsAreADash() {
        XCTAssertEqual(QueueMarkerChip.label(for: ""), "—")
        XCTAssertEqual(QueueMarkerChip.label(for: "   "), "—")
        XCTAssertEqual(QueueMarkerChip.label(for: " \n\t "), "—")
    }

    func testShortPrefixIsShownAsIs() {
        XCTAssertEqual(QueueMarkerChip.label(for: "keep_"), "keep_")
    }

    func testExactlyEightCharactersHasNoEllipsis() {
        XCTAssertEqual(QueueMarkerChip.label(for: "abcdefg_"), "abcdefg_")
        XCTAssertFalse(QueueMarkerChip.label(for: "abcdefg_").contains("…"))
    }

    func testNineCharactersShowTheFirstEightAndAnEllipsis() {
        XCTAssertEqual(QueueMarkerChip.label(for: "abcdefgh_"), "abcdefgh…")
    }

    func testLabelTrimsLeadingAndTrailingWhitespaceAndNewlines() {
        XCTAssertEqual(QueueMarkerChip.label(for: "\n  keep_ \t\n"), "keep_")
    }

    // MARK: - Enabled (R6)

    func testBlankPrefixDisablesItsChipEvenWithItemsInTheQueue() {
        let result = QueueMarkerChip.chips(primaryPrefix: "", secondaryPrefix: "later_",
                                           targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(result.map(\.isEnabled), [false, true])
    }

    func testEmptyQueueDisablesBothChips() {
        let result = QueueMarkerChip.chips(primaryPrefix: "keep_", secondaryPrefix: "later_",
                                           targetNames: [], queueHasItems: false)
        XCTAssertEqual(result.map(\.isEnabled), [false, false])
    }

    func testSetPrefixesWithItemsInTheQueueAreEnabled() {
        let result = chips(targets: ["a.mp4"])
        XCTAssertEqual(result.map(\.isEnabled), [true, true])
    }

    // MARK: - Secondary chip visibility (R6)

    func testSecondaryChipIsShownWhenItDiffersFromThePrimary() {
        XCTAssertEqual(chips(primary: "keep_", secondary: "later_", targets: []).map(\.kind), [.primary, .secondary])
    }

    func testBlankSecondaryChipIsShownDisabledWithADash() {
        let result = QueueMarkerChip.chips(primaryPrefix: "keep_", secondaryPrefix: "",
                                           targetNames: ["a.mp4"], queueHasItems: true)
        XCTAssertEqual(result.map(\.kind), [.primary, .secondary])
        XCTAssertEqual(result[1].label, "—")
        XCTAssertFalse(result[1].isEnabled)
    }

    func testBlankPrimaryAndBlankSecondaryAreBothShown() {
        // Two blank prefixes are not "equal and non-empty", so neither chip is hidden.
        XCTAssertEqual(chips(primary: "", secondary: "", targets: []).map(\.kind), [.primary, .secondary])
    }

    // MARK: - Copy (R11)

    func testSetPrefixTooltipsNameThePrefixAndTheKey() {
        let result = chips(targets: ["a.mp4"])
        XCTAssertEqual(result[0].tooltip,
                       "Primary prefix “keep_”: add it to the selected file, press again to remove it, "
                       + "or replace the secondary prefix. Shortcut: N")
        XCTAssertEqual(result[1].tooltip,
                       "Secondary prefix “later_”: add it to the selected file, press again to remove it, "
                       + "or replace the primary prefix. Shortcut: M")
    }

    func testTooltipShowsTheWholePrefixNotTheCutLabel() {
        let result = chips(primary: "abcdefgh_", targets: ["a.mp4"])
        XCTAssertEqual(result[0].label, "abcdefgh…")
        XCTAssertTrue(result[0].tooltip.contains("“abcdefgh_”"))
    }

    func testBlankPrefixTooltipsPointToSettings() {
        let result = chips(primary: "", secondary: "", targets: [])
        XCTAssertEqual(result[0].tooltip, "No primary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(result[1].tooltip, "No secondary prefix set. Set one in Settings > Queue & Files.")
    }

    func testAccessibilityLabelsAndValues() {
        let result = chips(targets: ["keep_a.mp4"])
        XCTAssertEqual(result[0].accessibilityLabel, "Apply primary prefix keep_ to selected file")
        XCTAssertEqual(result[1].accessibilityLabel, "Apply secondary prefix later_ to selected file")
        XCTAssertEqual(result[0].accessibilityValue, "applied")
        XCTAssertEqual(result[1].accessibilityValue, "not applied")
    }

    func testBlankAccessibilityLabels() {
        let result = chips(primary: "", secondary: "", targets: [])
        XCTAssertEqual(result[0].accessibilityLabel, "Primary prefix not set")
        XCTAssertEqual(result[1].accessibilityLabel, "Secondary prefix not set")
    }
}
