import XCTest

final class SettingsKeyboardFocusTests: XCTestCase {
    func testSidebarMovesToNextAndPreviousPage() {
        XCTAssertEqual(SettingsSidebarNavigation.adjacentIndex(from: 2, direction: 1, count: 6), 3)
        XCTAssertEqual(SettingsSidebarNavigation.adjacentIndex(from: 2, direction: -1, count: 6), 1)
    }

    func testSidebarStopsAtTheFirstAndLastPage() {
        XCTAssertNil(SettingsSidebarNavigation.adjacentIndex(from: 0, direction: -1, count: 6))
        XCTAssertNil(SettingsSidebarNavigation.adjacentIndex(from: 5, direction: 1, count: 6))
    }

    func testFocusedQueueFooterTakesSpaceAndReturnButNotALetter() {
        XCTAssertTrue(ShortcutFocusRouting.focusedControlTakesKey(.footerSection, keyCode: 49))
        XCTAssertTrue(ShortcutFocusRouting.focusedControlTakesKey(.footerSection, keyCode: 36))
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(.footerSection, keyCode: 45))
    }

    func testFocusedQueueDividerTakesArrowsAndHomeButNotALetter() {
        for code in [UInt16](arrayLiteral: 123, 124, 115) {
            XCTAssertTrue(ShortcutFocusRouting.focusedControlTakesKey(.queueDivider, keyCode: code))
        }
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(.queueDivider, keyCode: 45))
    }

    func testOtherFocusedButtonTakesSpaceButNotALetter() {
        XCTAssertTrue(ShortcutFocusRouting.focusedControlTakesKey(.button, keyCode: 49))
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(.button, keyCode: 45))
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(.other, keyCode: 49))
    }

    func testModifiedKeysStillReachTheShortcutRoute() {
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(
            .footerSection, keyCode: 49, modifiers: [.command]))
        XCTAssertFalse(ShortcutFocusRouting.focusedControlTakesKey(
            .queueDivider, keyCode: 123, modifiers: [.option]))
    }
}
