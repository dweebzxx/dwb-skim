import AppKit
import XCTest

final class VolumeOverlayPresentationTests: XCTestCase {
    func testRegularAndOverdriveMeterLevelsCoverBoundaryValues() {
        assertPresentation(volume: 0, regularLevel: 0, overdriveLevel: 0)
        assertPresentation(volume: 75, regularLevel: 0.75, overdriveLevel: 0)
        assertPresentation(volume: 99, regularLevel: 0.99, overdriveLevel: 0)
        assertPresentation(volume: 100, regularLevel: 1, overdriveLevel: 0)
        assertPresentation(volume: 101, regularLevel: 1, overdriveLevel: 0.01)
        assertPresentation(volume: 125, regularLevel: 1, overdriveLevel: 0.25)
        assertPresentation(volume: 150, regularLevel: 1, overdriveLevel: 0.5)
        assertPresentation(volume: 175, regularLevel: 1, overdriveLevel: 0.75)
        assertPresentation(volume: 200, regularLevel: 1, overdriveLevel: 1)
    }

    func testPresentationClampsValuesWithoutBlendingOverdriveIntoRegularMeter() {
        let belowMinimum = VideoVolumeMeterPresentation(volume: -1, muted: false)
        XCTAssertEqual(belowMinimum.volume, 0)
        XCTAssertEqual(belowMinimum.regularLevel, 0)
        XCTAssertEqual(belowMinimum.overdriveLevel, 0)
        XCTAssertEqual(belowMinimum.percentageText, "0%")

        let aboveMaximum = VideoVolumeMeterPresentation(volume: 201, muted: false)
        XCTAssertEqual(aboveMaximum.volume, 200)
        XCTAssertEqual(aboveMaximum.regularLevel, 1)
        XCTAssertEqual(aboveMaximum.overdriveLevel, 1)
        XCTAssertEqual(aboveMaximum.percentageText, "200%")
    }

    func testMutePresentationPreservesExistingSpeakerSemantics() {
        let muted = VideoVolumeMeterPresentation(volume: 75, muted: true)
        XCTAssertTrue(muted.isMuted)
        XCTAssertEqual(muted.symbolName, "speaker.slash.fill")

        let silent = VideoVolumeMeterPresentation(volume: 0, muted: false)
        XCTAssertTrue(silent.isMuted)
        XCTAssertEqual(silent.symbolName, "speaker.slash.fill")
    }

    private func assertPresentation(volume: Int,
                                    regularLevel: Double,
                                    overdriveLevel: Double,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) {
        let presentation = VideoVolumeMeterPresentation(volume: volume, muted: false)
        XCTAssertEqual(presentation.volume, volume, file: file, line: line)
        XCTAssertEqual(presentation.regularLevel, regularLevel, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(presentation.overdriveLevel, overdriveLevel, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(presentation.percentageText, "\(volume)%", file: file, line: line)
    }

    func testSegmentsLightAtTheirPercentThresholds() {
        func lit(_ volume: Int, muted: Bool = false) -> (regular: Int, boost: Int) {
            let presentation = VideoVolumeMeterPresentation(volume: volume, muted: muted)
            return (presentation.litRegularSegments, presentation.litBoostSegments)
        }
        XCTAssertEqual(VideoVolumeMeterPresentation.regularSegmentCount, 7)
        XCTAssertEqual(VideoVolumeMeterPresentation.boostSegmentCount, 4)
        // SD-039: the lit count rounds up. Normal segments light at 1, 15, 29, 43, 58, 72, and 86%;
        // boost segments at 101, 126, 151, and 176%.
        XCTAssertTrue(lit(0) == (0, 0))
        XCTAssertTrue(lit(1) == (1, 0))
        XCTAssertTrue(lit(14) == (1, 0))
        XCTAssertTrue(lit(15) == (2, 0))
        XCTAssertTrue(lit(28) == (2, 0))
        XCTAssertTrue(lit(29) == (3, 0))
        XCTAssertTrue(lit(42) == (3, 0))
        XCTAssertTrue(lit(43) == (4, 0))
        XCTAssertTrue(lit(57) == (4, 0))
        XCTAssertTrue(lit(58) == (5, 0))
        XCTAssertTrue(lit(71) == (5, 0))
        XCTAssertTrue(lit(72) == (6, 0))
        XCTAssertTrue(lit(85) == (6, 0))
        XCTAssertTrue(lit(86) == (7, 0))
        XCTAssertTrue(lit(100) == (7, 0))
        XCTAssertTrue(lit(101) == (7, 1))
        XCTAssertTrue(lit(125) == (7, 1))
        XCTAssertTrue(lit(126) == (7, 2))
        XCTAssertTrue(lit(150) == (7, 2))
        XCTAssertTrue(lit(151) == (7, 3))
        XCTAssertTrue(lit(175) == (7, 3))
        XCTAssertTrue(lit(176) == (7, 4))
        XCTAssertTrue(lit(200) == (7, 4))
        XCTAssertTrue(lit(150, muted: true) == (0, 0))
        XCTAssertTrue(lit(1, muted: true) == (0, 0))
    }

    func testHeatStartsAt150AndReachesFullStrengthAt200() {
        func heat(_ volume: Int, muted: Bool = false) -> Double {
            VideoVolumeMeterPresentation(volume: volume, muted: muted).heatFraction
        }
        XCTAssertEqual(heat(100), 0, accuracy: 1e-9)
        XCTAssertEqual(heat(150), 0, accuracy: 1e-9)
        XCTAssertEqual(heat(160), 0.2, accuracy: 1e-9)
        XCTAssertEqual(heat(175), 0.5, accuracy: 1e-9)
        XCTAssertEqual(heat(200), 1, accuracy: 1e-9)
        XCTAssertEqual(heat(250), 1, accuracy: 1e-9)
        XCTAssertEqual(heat(175, muted: true), 0, accuracy: 1e-9)
    }

    func testHeatedColorBlendsTowardErrorFill() {
        func components(_ color: NSColor) -> [CGFloat] {
            let srgb = color.usingColorSpace(.sRGB)!
            return [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
        }
        let base = DWBColor.periOnDark
        XCTAssertEqual(components(VideoVolumeMeterPresentation.heatedColor(base, heatFraction: 0)), components(base))
        XCTAssertEqual(components(VideoVolumeMeterPresentation.heatedColor(base, heatFraction: 1)),
                       components(DWBColor.errorFill), accuracy: 0.002)
        // `blended(withFraction:of:)` is not a plain sRGB average, so check what must hold: every
        // channel lies between the two colors, and each step moves closer to `errorFill`.
        let start = components(base), end = components(DWBColor.errorFill)
        var previousDistance = CGFloat.greatestFiniteMagnitude
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let blended = components(VideoVolumeMeterPresentation.heatedColor(base, heatFraction: fraction))
            for channel in 0..<3 {
                XCTAssertGreaterThanOrEqual(blended[channel], min(start[channel], end[channel]) - 0.002)
                XCTAssertLessThanOrEqual(blended[channel], max(start[channel], end[channel]) + 0.002)
            }
            let distance = zip(blended, end).map { abs($0 - $1) }.reduce(0, +)
            XCTAssertLessThan(distance, previousDistance)
            previousDistance = distance
        }
    }

    func testOverlayTimingIsTransient() {
        XCTAssertGreaterThan(VolumeOverlayTiming.dismissalDelay, 0)
        XCTAssertLessThan(VolumeOverlayTiming.dismissalDelay, 3)
        XCTAssertGreaterThan(VolumeOverlayTiming.fadeDuration, 0)
        XCTAssertLessThan(VolumeOverlayTiming.fadeDuration, VolumeOverlayTiming.dismissalDelay)
    }
}

private func XCTAssertEqual(_ lhs: [CGFloat], _ rhs: [CGFloat], accuracy: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
    for (a, b) in zip(lhs, rhs) {
        XCTAssertEqual(a, b, accuracy: accuracy, file: file, line: line)
    }
}
