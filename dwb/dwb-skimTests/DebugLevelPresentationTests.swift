import XCTest

final class DebugLevelPresentationTests: XCTestCase {

    private let levels: [DebugLevel] = [.info, .warning, .error]

    func testEveryLevelHasAWordAndAGlyph() {
        XCTAssertEqual(levels.map(\.word), ["INFO", "WARN", "ERR"])
        for level in levels {
            XCTAssertFalse(level.word.isEmpty)
            XCTAssertFalse(level.glyphName.isEmpty)
        }
    }

    func testLevelsAreNeverToldApartByColorAlone() {
        XCTAssertEqual(Set(levels.map(\.word)).count, 3)
        XCTAssertEqual(Set(levels.map(\.glyphName)).count, 3)
    }

    func testLevelsKeepTheirOrder() {
        XCTAssertLessThan(DebugLevel.info, .warning)
        XCTAssertLessThan(DebugLevel.warning, .error)
    }
}
