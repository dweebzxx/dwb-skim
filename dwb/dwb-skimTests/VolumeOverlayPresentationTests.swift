import XCTest

final class VolumeOverlayPresentationTests: XCTestCase {
    func testRegularAndOverdriveMeterLevelsCoverBoundaryValues() {
        assertPresentation(volume: 0, regularLevel: 0, overdriveLevel: 0)
        assertPresentation(volume: 75, regularLevel: 0.75, overdriveLevel: 0)
        assertPresentation(volume: 99, regularLevel: 0.99, overdriveLevel: 0)
        assertPresentation(volume: 100, regularLevel: 1, overdriveLevel: 0)
        assertPresentation(volume: 101, regularLevel: 1, overdriveLevel: 0.02)
        assertPresentation(volume: 125, regularLevel: 1, overdriveLevel: 0.5)
        assertPresentation(volume: 150, regularLevel: 1, overdriveLevel: 1)
    }

    func testPresentationClampsValuesWithoutBlendingOverdriveIntoRegularMeter() {
        let belowMinimum = VideoVolumeMeterPresentation(volume: -1, muted: false)
        XCTAssertEqual(belowMinimum.volume, 0)
        XCTAssertEqual(belowMinimum.regularLevel, 0)
        XCTAssertEqual(belowMinimum.overdriveLevel, 0)
        XCTAssertEqual(belowMinimum.percentageText, "0%")

        let aboveMaximum = VideoVolumeMeterPresentation(volume: 200, muted: false)
        XCTAssertEqual(aboveMaximum.volume, 150)
        XCTAssertEqual(aboveMaximum.regularLevel, 1)
        XCTAssertEqual(aboveMaximum.overdriveLevel, 1)
        XCTAssertEqual(aboveMaximum.percentageText, "150%")
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

    func testOverlayTimingIsTransient() {
        XCTAssertGreaterThan(VolumeOverlayTiming.dismissalDelay, 0)
        XCTAssertLessThan(VolumeOverlayTiming.dismissalDelay, 3)
        XCTAssertGreaterThan(VolumeOverlayTiming.fadeDuration, 0)
        XCTAssertLessThan(VolumeOverlayTiming.fadeDuration, VolumeOverlayTiming.dismissalDelay)
    }
}
