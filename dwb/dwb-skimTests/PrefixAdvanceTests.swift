import Foundation
import XCTest

/// P52: the transition kind of a custom-prefix press and the advance-after-prefix decision.
final class PrefixAdvanceTests: XCTestCase {

    private let primary = "keep_"
    private let secondary = "fav_"

    private func transition(_ filename: String,
                            primary: String? = nil,
                            secondary: String? = nil,
                            action: CustomPrefixAction) -> CustomPrefixTransition? {
        SkimFileRenamer.customPrefixTransition(for: filename,
                                               primaryPrefix: primary ?? self.primary,
                                               secondaryPrefix: secondary ?? self.secondary,
                                               action: action)
    }

    // MARK: - Transition kind (the six cells of the table)

    func testNeitherPrefixPresentAddsPrimaryOrSecondary() {
        XCTAssertEqual(transition("clip.mov", action: .primary), .added)
        XCTAssertEqual(transition("clip.mov", action: .secondary), .added)
    }

    func testPrimaryPresentRemovesPrimaryAndReplacesWithSecondary() {
        XCTAssertEqual(transition("keep_clip.mov", action: .primary), .removed)
        XCTAssertEqual(transition("keep_clip.mov", action: .secondary), .replaced)
    }

    func testSecondaryPresentReplacesWithPrimaryAndRemovesSecondary() {
        XCTAssertEqual(transition("fav_clip.mov", action: .primary), .replaced)
        XCTAssertEqual(transition("fav_clip.mov", action: .secondary), .removed)
    }

    // MARK: - Transition kind (edges)

    func testEmptyRequestedPrefixHasNoTransition() {
        XCTAssertNil(transition("clip.mov", primary: "", action: .primary))
        XCTAssertNil(transition("clip.mov", secondary: "", action: .secondary))
    }

    func testEmptyOtherPrefixIsNeverTreatedAsPresent() {
        XCTAssertEqual(transition("clip.mov", secondary: "", action: .primary), .added)
        XCTAssertEqual(transition("keep_clip.mov", secondary: "", action: .primary), .removed)
    }

    func testUnrelatedLeadingTextIsNotAPrefix() {
        XCTAssertEqual(transition("xkeep_clip.mov", action: .primary), .added)
    }

    func testLongerMatchWinsWhenOnePrefixBeginsWithTheOther() {
        // "a_" is a leading substring of "a_b_". On "a_b_clip.mov" the longer one is present.
        XCTAssertEqual(transition("a_b_clip.mov", primary: "a_", secondary: "a_b_", action: .primary), .replaced)
        XCTAssertEqual(transition("a_b_clip.mov", primary: "a_", secondary: "a_b_", action: .secondary), .removed)
        // On "a_clip.mov" only the shorter one is present.
        XCTAssertEqual(transition("a_clip.mov", primary: "a_", secondary: "a_b_", action: .primary), .removed)
        XCTAssertEqual(transition("a_clip.mov", primary: "a_", secondary: "a_b_", action: .secondary), .replaced)
    }

    func testTransitionAgreesWithToggleTargetForEveryCase() {
        let names = ["clip.mov", "keep_clip.mov", "fav_clip.mov", "a_clip.mov", "a_b_clip.mov", "keep_fav_clip.mov"]
        let prefixPairs: [(String, String)] = [("keep_", "fav_"), ("a_", "a_b_"), ("a_b_", "a_"), ("", "fav_"), ("keep_", ""), ("", "")]
        for name in names {
            for (p, s) in prefixPairs {
                for action in [CustomPrefixAction.primary, .secondary] {
                    let target = SkimFileRenamer.customPrefixToggleTargetFilename(
                        for: name, primaryPrefix: p, secondaryPrefix: s, action: action)
                    let kind = SkimFileRenamer.customPrefixTransition(
                        for: name, primaryPrefix: p, secondaryPrefix: s, action: action)
                    XCTAssertEqual(target == nil, kind == nil,
                                   "Disagreement for \(name) p=\(p) s=\(s) \(action)")
                }
            }
        }
    }

    func testTransitionMatchesTheRenameThatActuallyHappens() {
        // added: name grows by the prefix; removed: name shrinks; replaced: swapped in place.
        let add = SkimFileRenamer.customPrefixToggleTargetFilename(
            for: "clip.mov", primaryPrefix: primary, secondaryPrefix: secondary, action: .primary)
        XCTAssertEqual(add, "keep_clip.mov")
        let remove = SkimFileRenamer.customPrefixToggleTargetFilename(
            for: "keep_clip.mov", primaryPrefix: primary, secondaryPrefix: secondary, action: .primary)
        XCTAssertEqual(remove, "clip.mov")
        let replace = SkimFileRenamer.customPrefixToggleTargetFilename(
            for: "keep_clip.mov", primaryPrefix: primary, secondaryPrefix: secondary, action: .secondary)
        XCTAssertEqual(replace, "fav_clip.mov")
    }

    // MARK: - Advance decision

    private func decide(settingEnabled: Bool = true,
                        origin: PrefixPressOrigin = .key,
                        targets: [Int] = [2],
                        current: Int = 2,
                        transition: CustomPrefixTransition? = .added,
                        hasNext: Bool = true) -> PrefixAdvanceDecision {
        PrefixAdvancePolicy.decision(settingEnabled: settingEnabled,
                                     origin: origin,
                                     targetDisplayIndices: targets,
                                     currentDisplayIndex: current,
                                     transition: transition,
                                     hasNextItem: hasNext)
    }

    func testSettingOffNeverAdvancesAndReportsOff() {
        for transition in [CustomPrefixTransition.added, .replaced, .removed] {
            XCTAssertEqual(decide(settingEnabled: false, transition: transition), .settingOff)
        }
        XCTAssertEqual(decide(settingEnabled: false, origin: .footerChip), .settingOff)
        XCTAssertEqual(decide(settingEnabled: false, targets: [0, 1]), .settingOff)
    }

    func testKeyOnTheCurrentItemAdvancesForAddedAndReplaced() {
        XCTAssertEqual(decide(transition: .added), .advance)
        XCTAssertEqual(decide(transition: .replaced), .advance)
    }

    func testRemovalDoesNotAdvance() {
        XCTAssertEqual(decide(transition: .removed), .skip(.removed))
    }

    func testFooterChipNeverAdvances() {
        for transition in [CustomPrefixTransition.added, .replaced, .removed] {
            XCTAssertEqual(decide(origin: .footerChip, transition: transition), .skip(.queueTarget))
        }
    }

    func testKeyOnAnotherRowDoesNotAdvance() {
        XCTAssertEqual(decide(targets: [3], current: 2), .skip(.queueTarget))
    }

    func testKeyOnSeveralRowsDoesNotAdvanceEvenWhenCurrentIsIncluded() {
        XCTAssertEqual(decide(targets: [1, 2], current: 2), .skip(.queueTarget))
        XCTAssertEqual(decide(targets: [2, 2], current: 2), .skip(.queueTarget))
    }

    func testNoTargetsDoNotAdvance() {
        XCTAssertEqual(decide(targets: []), .skip(.queueTarget))
    }

    func testNoNextItemDoesNotAdvance() {
        XCTAssertEqual(decide(transition: .added, hasNext: false), .skip(.noNextItem))
        XCTAssertEqual(decide(transition: .replaced, hasNext: false), .skip(.noNextItem))
    }

    func testRemovalOnLastItemReportsRemovalNotMissingNextItem() {
        XCTAssertEqual(decide(transition: .removed, hasNext: false), .skip(.removed))
    }

    func testPressThatChangesNothingNeverAdvances() {
        XCTAssertNotEqual(decide(transition: nil), .advance)
    }

    func testEveryCombinationAdvancesOnlyForTheOneAllowedCase() {
        let transitions: [CustomPrefixTransition?] = [.added, .replaced, .removed, nil]
        let origins: [PrefixPressOrigin] = [.key, .footerChip]
        let targetSets: [[Int]] = [[], [2], [3], [1, 2]]
        var advances = 0
        for transition in transitions {
            for origin in origins {
                for targets in targetSets {
                    for hasNext in [true, false] {
                        let result = decide(origin: origin, targets: targets, current: 2,
                                            transition: transition, hasNext: hasNext)
                        if result == .advance {
                            advances += 1
                            XCTAssertEqual(origin, .key)
                            XCTAssertEqual(targets, [2])
                            XCTAssertTrue(transition == .added || transition == .replaced)
                            XCTAssertTrue(hasNext)
                        }
                    }
                }
            }
        }
        // key origin x target [2] x (added|replaced) x next present
        XCTAssertEqual(advances, 2)
    }

    // MARK: - Setting

    func testAdvanceAfterPrefixIsRegisteredAndOffByDefault() {
        let values = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)
        XCTAssertEqual(SettingsDefaultsRegistry.Keys.advanceAfterPrefix, "advanceAfterPrefix")
        XCTAssertEqual(values[SettingsDefaultsRegistry.Keys.advanceAfterPrefix] as? Bool, false)
    }

    func testRegisteredDefaultReadsAsOffAndRestoreValuesTurnItOff() {
        let suite = "com.dwb.skimTests.PrefixAdvance.defaults"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        XCTAssertFalse(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.advanceAfterPrefix))

        defaults.set(true, forKey: SettingsDefaultsRegistry.Keys.advanceAfterPrefix)
        XCTAssertTrue(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.advanceAfterPrefix))

        // Restore Default Settings writes every registered default back.
        SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)
            .forEach { defaults.set($0.value, forKey: $0.key) }
        XCTAssertFalse(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.advanceAfterPrefix))
    }
}
