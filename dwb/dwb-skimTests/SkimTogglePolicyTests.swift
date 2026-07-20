import XCTest

final class SkimTogglePolicyTests: XCTestCase {
    func testTopBarOrderAndAccessibilityIdentifiers() {
        XCTAssertEqual(SkimTopBarControl.leadingOrder,
                       [.previousItem, .skimToggle, .queuePanel])
        XCTAssertEqual(SkimControlAccessibility.previousIdentifier, "previousItemButton")
        XCTAssertEqual(SkimControlAccessibility.toggleIdentifier, "skimToggleButton")
        XCTAssertEqual(SkimControlAccessibility.queueIdentifier, "queuePanelButton")
    }

    func testClipDurationAndStartPositionFollowAuthoritativeEnabledState() {
        let on = SkimControlPresentation(isEnabled: true)
        XCTAssertTrue(on.clipDurationControlsEnabled)
        XCTAssertTrue(on.startPositionControlsEnabled)
        XCTAssertEqual(on.toggleAccessibilityValue, "On")

        let off = SkimControlPresentation(isEnabled: false)
        XCTAssertFalse(off.clipDurationControlsEnabled)
        XCTAssertFalse(off.startPositionControlsEnabled)
        XCTAssertEqual(off.toggleAccessibilityValue, "Off")
        XCTAssertTrue(off.toggleHelp.contains("Double-tap Option"))
    }

    func testButtonAndShortcutUseSameToggleTransition() {
        let buttonResult = SkimToggleTransition.toggled(true)
        let shortcutResult = SkimToggleTransition.toggled(true)
        XCTAssertEqual(buttonResult, shortcutResult)
        XCTAssertFalse(buttonResult)
    }

    func testDisabledSkimCancelsDeadlineAndStaleCallbackCannotAdvance() {
        var scheduler = SkimPreviewSessionScheduler()
        scheduler.begin(sessionID: 7, queueItemID: "A", plannedDurationSeconds: 5,
                        createdUptime: 0, metadataRetryWindow: 2)
        _ = scheduler.registerReadiness(sessionID: 7, queueItemID: "A",
                                        source: .playing, now: 0)
        XCTAssertTrue(scheduler.cancel(reason: "skim-disabled"))
        XCTAssertEqual(scheduler.claimDeadline(sessionID: 7, queueItemID: "A",
                                               expectedDeadlineUptime: 5, now: 5),
                       .rejected("not-scheduled"))
    }

    func testDeadlineRequiresEnabledStateAndCurrentAssignmentToken() {
        var registry = SkimMediaAssignmentRegistry()
        _ = registry.installPlayer()
        let first = registry.assign()
        XCTAssertTrue(SkimDeadlineGuard(isSkimEnabled: true,
                                        scheduledAssignment: first,
                                        currentAssignment: first).mayAdvance)
        XCTAssertFalse(SkimDeadlineGuard(isSkimEnabled: false,
                                         scheduledAssignment: first,
                                         currentAssignment: first).mayAdvance)
        let second = registry.assign()
        XCTAssertFalse(SkimDeadlineGuard(isSkimEnabled: true,
                                         scheduledAssignment: first,
                                         currentAssignment: second).mayAdvance)
    }

    func testAssignmentsBypassSkimWhileOffAndResumeUsingSkimAfterEnable() {
        XCTAssertEqual(SkimAssignmentBehavior.nextAssignment(isSkimEnabled: false), .fullPlayback)
        XCTAssertEqual(SkimAssignmentBehavior.nextAssignment(isSkimEnabled: true), .skimPreview)
    }
}
