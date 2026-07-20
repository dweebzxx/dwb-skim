import XCTest

final class SettingsPresentationTests: XCTestCase {
    func testSettingsCategoriesAreStableAndRestorable() {
        XCTAssertEqual(SettingsPresentation.paneIdentifiers.count, 8)
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("skimPlus"), "skimPlus")
        XCTAssertEqual(SettingsPresentation.validatedPaneIdentifier("removed"), "playback")
    }

    func testSettingsUsesOneSharedAlignmentAndResponsiveLayoutModel() {
        XCTAssertEqual(SettingsPresentation.labelColumnWidth, 150)
        XCTAssertEqual(SettingsPresentation.columnSpacing, 12)
        XCTAssertEqual(SettingsPresentation.rowSpacing, 12)
        XCTAssertGreaterThanOrEqual(SettingsPresentation.minimumWindowSize.width, 760)
        XCTAssertGreaterThanOrEqual(SettingsPresentation.minimumWindowSize.height, 480)
        XCTAssertGreaterThan(SettingsPresentation.maximumContentWidth, SettingsPresentation.labelColumnWidth)
    }

    func testEveryExistingSettingIsRepresentedOnceInTheInventory() {
        let labels = SettingsPresentation.representedSettingLabels
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.contains("Clip duration"))
        XCTAssertTrue(labels.contains("Queue order"))
        XCTAssertTrue(labels.contains("Background audio volume"))
        XCTAssertTrue(labels.contains("Restore All Settings to Default"))
    }
}
