import AppKit
import XCTest

final class DWBThemeTests: XCTestCase {

    // MARK: - Helpers

    private func rgb(_ color: NSColor, file: StaticString = #filePath, line: UInt = #line) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        guard let srgb = color.usingColorSpace(.sRGB) else {
            XCTFail("Color has no sRGB representation", file: file, line: line)
            return (0, 0, 0)
        }
        return (srgb.redComponent, srgb.greenComponent, srgb.blueComponent)
    }

    private func assertSameColor(_ actual: NSColor, _ expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        let a = rgb(actual, file: file, line: line), e = rgb(expected, file: file, line: line)
        XCTAssertEqual(a.r, e.r, accuracy: 0.0005, file: file, line: line)
        XCTAssertEqual(a.g, e.g, accuracy: 0.0005, file: file, line: line)
        XCTAssertEqual(a.b, e.b, accuracy: 0.0005, file: file, line: line)
    }

    /// WCAG 2.x relative luminance of an opaque sRGB color.
    private func luminance(_ color: NSColor) -> Double {
        func linear(_ channel: CGFloat) -> Double {
            let c = Double(channel)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let c = rgb(color)
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    // MARK: - Theme

    func testSkimThemeUsesTealLeadPeriwinklePrimaryAndOrangeSecondary() {
        assertSameColor(theme.accentText, DWBColor.tealOnDark)
        assertSameColor(theme.accentFill, DWBColor.tealFillDark)
        assertSameColor(theme.markerPrimary, DWBColor.periOnDark)
        assertSameColor(theme.markerSecondary, DWBColor.orangeOnDark)
    }

    func testSkimThemeAddsBackingBadgeAndAccentRange() {
        XCTAssertEqual(DWBColor.backingBadge.alphaComponent, 0.88, accuracy: 0.0001)
        assertSameColor(DWBColor.backingBadge, DWBColor.canvas)
        XCTAssertEqual(theme.accentRange.alphaComponent, 0.45, accuracy: 0.0001)
        assertSameColor(theme.accentRange, DWBColor.tealFillDark)
    }

    // MARK: - Contrast

    func testOnDarkTextStopsReachFourPointFiveAgainstEveryDarkSurface() {
        let textStops: [(String, NSColor)] = [
            ("tealOnDark", DWBColor.tealOnDark),
            ("periOnDark", DWBColor.periOnDark),
            ("orangeOnDark", DWBColor.orangeOnDark),
            ("successText", DWBColor.successText),
            ("cautionText", DWBColor.cautionText),
            ("errorText", DWBColor.errorText),
            ("textPrimary", DWBColor.textPrimary),
            ("textSecondary", DWBColor.textSecondary),
            ("textTertiary", DWBColor.textTertiary),
        ]
        let surfaces: [(String, NSColor)] = [
            ("canvas", DWBColor.canvas),
            ("surface", DWBColor.surface),
            ("surfaceElevated", DWBColor.surfaceElevated),
        ]
        for (textName, text) in textStops {
            for (surfaceName, surface) in surfaces {
                XCTAssertGreaterThanOrEqual(contrast(text, surface), 4.5, "\(textName) on \(surfaceName)")
            }
        }
    }

    func testFillStopsReachThreeAgainstSurface() {
        let fillStops: [(String, NSColor)] = [
            ("tealFillDark", DWBColor.tealFillDark),
            ("periFillDark", DWBColor.periFillDark),
            ("orangeFillDark", DWBColor.orangeFillDark),
            ("successFill", DWBColor.successFill),
            ("cautionFill", DWBColor.cautionFill),
            ("errorFill", DWBColor.errorFill),
        ]
        for (name, fill) in fillStops {
            XCTAssertGreaterThanOrEqual(contrast(fill, DWBColor.surface), 3.0, "\(name) on surface")
        }
    }

    func testTextOnFillIsReadableOnEveryAccentFill() {
        for fill in [DWBColor.tealFillDark, DWBColor.periFillDark, DWBColor.orangeFillDark, DWBColor.errorFill] {
            XCTAssertGreaterThanOrEqual(contrast(DWBColor.textOnFill, fill), 3.0)
        }
    }
}
