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

    func testLabelKeepsEveryCharacterOfALongPrefix() {
        // The classic 8-character cut is retired: the footer cell shortens the label by measuring it against its own
        // section (`QueuePrefixLabelFitting`), and the model keeps the whole prefix.
        XCTAssertEqual(QueueMarkerChip.label(for: "12345678"), "12345678")
        XCTAssertEqual(QueueMarkerChip.label(for: "123456789"), "123456789")
        XCTAssertEqual(QueueMarkerChip.label(for: "a_very_long_review_prefix_"), "a_very_long_review_prefix_")
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

    func testTooltipAndAccessibilityNameShowTheWholePrefix() {
        let result = chips(primary: "abcdefgh_", targets: ["a.mp4"])
        XCTAssertEqual(result[0].label, "abcdefgh_")
        XCTAssertTrue(result[0].tooltip.contains("“abcdefgh_”"))
        XCTAssertTrue(result[0].accessibilityLabel.contains("abcdefgh_"))
    }

    func testBlankPrefixTooltipsPointToSettings() {
        let result = chips(primary: "", secondary: "", targets: [])
        XCTAssertEqual(result[0].tooltip, "No primary prefix set. Set one in Settings > Queue & Files.")
        XCTAssertEqual(result[1].tooltip, "No secondary prefix set. Set one in Settings > Queue & Files.")
    }

    func testAccessibilityLabelsAndValues() {
        let result = chips(targets: ["keep_a.mp4"])
        // The N / M key hints live in the accessible name and the tooltip, not on the cell.
        XCTAssertEqual(result[0].accessibilityLabel, "Apply primary prefix keep_ to selected file, shortcut N")
        XCTAssertEqual(result[1].accessibilityLabel, "Apply secondary prefix later_ to selected file, shortcut M")
        XCTAssertEqual(result[0].accessibilityValue, "applied")
        XCTAssertEqual(result[1].accessibilityValue, "not applied")
    }

    func testBlankAccessibilityLabels() {
        let result = chips(primary: "", secondary: "", targets: [])
        XCTAssertEqual(result[0].accessibilityLabel, "Primary prefix not set")
        XCTAssertEqual(result[1].accessibilityLabel, "Secondary prefix not set")
    }

    // MARK: - Applied, mixed and none (P54: the footer's dot and ring)

    func testNoneAppliedAndMixedAreDistinguishedByTheTargetsActuallyCarryingThePrefix() {
        XCTAssertEqual(chips(targets: ["a.mp4", "b.mp4"])[0].markState, .none)
        XCTAssertEqual(chips(targets: ["keep_a.mp4", "keep_b.mp4"])[0].markState, .applied)
        XCTAssertEqual(chips(targets: ["keep_a.mp4", "b.mp4"])[0].markState, .mixed)
        XCTAssertTrue(chips(targets: ["keep_a.mp4", "b.mp4"])[0].isMixed)
        XCTAssertFalse(chips(targets: ["keep_a.mp4", "b.mp4"])[0].isApplied)
    }

    func testMixedDoesNotChangeWhichChipsAreEnabled() {
        // Mixed is only a mark; the chip still acts on every target.
        let result = chips(targets: ["keep_a.mp4", "b.mp4"])
        XCTAssertEqual(result.map(\.isEnabled), [true, true])
    }

    func testPrimaryAndSecondaryMarksAreIndependent() {
        let result = chips(targets: ["keep_a.mp4", "later_b.mp4", "keep_c.mp4"])
        XCTAssertEqual(result[0].markState, .mixed)
        XCTAssertEqual(result[1].markState, .mixed)
    }

    func testOverlappingPrefixesUseTheLongerMatchForTheMixedStateToo() {
        // "a_" is also the start of "a_b_": for "a_b_clip.mp4" the longer prefix is the one present.
        let result = chips(primary: "a_", secondary: "a_b_", targets: ["a_b_clip.mp4", "a_clip.mp4"])
        XCTAssertEqual(result[0].markState, .mixed, "a_clip.mp4 carries the primary; a_b_clip.mp4 carries the secondary")
        XCTAssertEqual(result[1].markState, .mixed)
        let secondaryOnly = chips(primary: "a_", secondary: "a_b_", targets: ["a_b_clip.mp4", "a_b_other.mp4"])
        XCTAssertEqual(secondaryOnly[0].markState, .none)
        XCTAssertEqual(secondaryOnly[1].markState, .applied)
    }

    func testMarkDescribesASelectedRowCollection() {
        // Several selected rows: the mark follows exactly those names.
        let selected = ["keep_one.mp4", "keep_two.mp4", "plain.mp4"]
        XCTAssertEqual(chips(targets: selected)[0].markState, .mixed)
        XCTAssertEqual(chips(targets: Array(selected.prefix(2)))[0].markState, .applied)
    }

    func testFilteredCurrentFallbackTargetsOnlyTheCurrentItem() {
        // With nothing selected the footer targets the visible current item alone.
        XCTAssertEqual(chips(targets: ["keep_current.mp4"])[0].markState, .applied)
        // With the current item filtered out there is no target: no mark, and the cells are disabled.
        let none = QueueMarkerChip.chips(primaryPrefix: "keep_", secondaryPrefix: "later_",
                                         targetNames: [], queueHasItems: true, hasTargets: false)
        XCTAssertEqual(none.map(\.markState), [.none, .none])
        XCTAssertEqual(none.map(\.isEnabled), [false, false])
    }

    func testNoTargetsDisablesChipsEvenWithItemsAndSetPrefixes() {
        let result = QueueMarkerChip.chips(primaryPrefix: "keep_", secondaryPrefix: "later_",
                                           targetNames: [], queueHasItems: true, hasTargets: false)
        XCTAssertEqual(result.map(\.isEnabled), [false, false])
    }

    func testMixedIsAccessibleInTheValueAndTheTooltip() {
        let result = chips(targets: ["keep_a.mp4", "b.mp4"])
        XCTAssertEqual(result[0].accessibilityValue, "mixed, applied to some files")
        XCTAssertTrue(result[0].tooltip.hasSuffix("Some of the targeted files already have it."))
        XCTAssertEqual(result[1].accessibilityValue, "not applied")
    }

    func testEqualPrefixesLeaveOnlyThePrimaryInItsGridPosition() {
        let result = chips(primary: "x_", secondary: "x_", targets: ["x_a.mp4"])
        XCTAssertEqual(result.map(\.kind), [.primary])
        XCTAssertEqual(result[0].markState, .applied)
    }
}
