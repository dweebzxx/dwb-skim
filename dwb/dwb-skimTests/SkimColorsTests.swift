import Cocoa
import XCTest

final class SkimColorsTests: XCTestCase {

    private func components(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    func testDarkTealMatchesHex254F58() {
        let c = components(SkimColors.darkTeal)
        XCTAssertEqual(c.r, 37.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 79.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 88.0 / 255.0, accuracy: 0.001)
    }

    func testBurntOrangeMatchesHex8F4218() {
        let c = components(SkimColors.burntOrange)
        XCTAssertEqual(c.r, 143.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 66.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 24.0 / 255.0, accuracy: 0.001)
    }

    func testPeriwinkleMatchesHex4C62A8() {
        let c = components(SkimColors.periwinkle)
        XCTAssertEqual(c.r, 76.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 98.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 168.0 / 255.0, accuracy: 0.001)
    }

    func testRenameSemanticTokenMatchesDarkTealHex254F58() {
        let c = components(SkimColors.rename)
        XCTAssertEqual(c.r, 37.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 79.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 88.0 / 255.0, accuracy: 0.001)
    }

    func testDarkThemeSettingsTokensMatchEndorsedSequentialPalette() {
        let selection = components(SkimColors.darkTeal500)
        XCTAssertEqual(selection.r, 72.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(selection.g, 143.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(selection.b, 160.0 / 255.0, accuracy: 0.001)

        let accent = components(SkimColors.periwinkle300)
        XCTAssertEqual(accent.r, 154.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(accent.g, 170.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(accent.b, 216.0 / 255.0, accuracy: 0.001)
    }
}
