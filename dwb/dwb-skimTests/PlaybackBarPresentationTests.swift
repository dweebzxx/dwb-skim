import XCTest

final class PlaybackBarPresentationTests: XCTestCase {
    func testControlOrderMatchesAccessibilityAndVisualContract() {
        XCTAssertEqual(PlaybackBarPresentation.controlOrder,
                       ["Queue", "Skim", "Previous", "Play/Pause", "Next", "Volume", "Fullscreen"])
    }

    func testLayoutKeepsEdgeRegionsSeparateAndMiddleCentered() {
        let layout = PlaybackBarPresentation.layout(width: 980)
        XCTAssertGreaterThan(layout.edgeInset, 0)
        XCTAssertEqual(layout.centeredWidth / 2 + (980 - layout.centeredWidth) / 2, 490, accuracy: 0.001)
    }

    func testNarrowLayoutUsesReducedGapWithoutNegativeGeometry() {
        let layout = PlaybackBarPresentation.layout(width: 320)
        XCTAssertGreaterThanOrEqual(layout.gap, 2)
        XCTAssertGreaterThan(layout.centeredWidth, 0)
    }

    func testMarkerCellsSpanTheSameRailAsTheEdgeControls() {
        let layout = PlaybackBarPresentation.layout(width: 980)
        XCTAssertEqual(layout.markerCells.count, 4)
        XCTAssertEqual(layout.markerRail.minX, layout.edgeInset, accuracy: 0.001)
        XCTAssertEqual(layout.markerRail.maxX, 980 - layout.edgeInset, accuracy: 0.001)
        XCTAssertEqual(layout.markerCells.map(\.width), Array(repeating: layout.markerCells[0].width, count: 4))
        XCTAssertGreaterThan(layout.markerRail.width, layout.centeredWidth)
    }

    func testNarrowMarkerCellsRetainFourNonOverlappingValues() {
        let layout = PlaybackBarPresentation.layout(width: 320)
        XCTAssertEqual(layout.markerCells.count, 4)
        XCTAssertTrue(zip(layout.markerCells, layout.markerCells.dropFirst()).allSatisfy { $0.maxX <= $1.minX })
        let values = PlaybackBarPresentation.markers(settings: makeSnapshot()).map {
            $0.displayText(at: layout.markerCells[0].width)
        }
        XCTAssertEqual(values.count, 4)
        XCTAssertFalse(values.contains(where: { $0.isEmpty }))
    }

    func testMarkersCoverFixedAndRandomClipDurations() {
        var snapshot = makeSnapshot()
        XCTAssertEqual(PlaybackBarPresentation.markers(settings: snapshot)[0].compactText, "Clip 10s")
        snapshot = SkimSettingsSnapshot(skimEnabled: true, imageDurationSeconds: 3, gifLoopCount: 1,
                                        videoAudioNormalizationEnabled: false, previewDurationMode: "random",
                                        fixedDurationSeconds: 10, randomDurationRange: 4...12,
                                        startPositionMode: "beginning", skipIntroSeconds: 0, queueOrderMode: .sequential,
                                        loopQueueEnabled: false)
        XCTAssertEqual(PlaybackBarPresentation.markers(settings: snapshot)[0].compactText, "Clip Random 4–12s")
    }

    func testMarkersCoverStartIntroAndEachQueueOrder() {
        for mode in QueueOrderMode.allCases {
            let markers = PlaybackBarPresentation.markers(settings: makeSnapshot(queue: mode, start: "random", intro: 15))
            XCTAssertEqual(markers[1].compactText, "Start Random")
            XCTAssertEqual(markers[2].compactText, "Intro 15s")
            XCTAssertTrue(markers[3].fullText.contains(mode == .sequential ? "Sequential" : mode == .shuffle ? "Shuffle" : "Weighted"))
        }
    }

    func testSkimDisabledMutesOnlyDependentMarkers() {
        let markers = PlaybackBarPresentation.markers(settings: makeSnapshot(skimEnabled: false))
        XCTAssertFalse(markers[0].isActive)
        XCTAssertFalse(markers[1].isActive)
        XCTAssertTrue(markers[2].isActive)
        XCTAssertTrue(markers[3].isActive)
        XCTAssertTrue(markers[0].accessibilityValue.contains("inactive while Skim is off"))
    }

    func testStripVisibilityDefaultsVisibleAndRestoresWithoutChangingState() {
        var visibility = SkimControlsVisibilityState()
        XCTAssertTrue(visibility.isVisible)
        visibility.hide()
        XCTAssertFalse(visibility.isVisible)
        visibility.restore()
        XCTAssertTrue(visibility.isVisible)
    }

    func testPlaybackChromeVisibleFadingAndHiddenTransitionsAreExplicit() {
        var state = PlaybackChromeVisibilityState(autoHideEnabled: true)
        XCTAssertEqual(state.phase, .visible)
        XCTAssertTrue(state.isInteractive)
        state.requestHide(reduceMotion: false)
        XCTAssertEqual(state.phase, .fading)
        state.completeHide()
        XCTAssertEqual(state.phase, .hidden)
        XCTAssertFalse(state.isInteractive)
        state.reveal()
        XCTAssertEqual(state.phase, .visible)
    }

    func testReducedMotionHidesAndRevealsWithoutIntermediateFade() {
        var state = PlaybackChromeVisibilityState(autoHideEnabled: true)
        state.requestHide(reduceMotion: true)
        XCTAssertEqual(state.phase, .hidden)
        state.reveal()
        XCTAssertEqual(state.phase, .visible)
    }

    func testDisablingAutoHideKeepsAllPlaybackChromeVisible() {
        var state = PlaybackChromeVisibilityState(autoHideEnabled: true)
        state.requestHide(reduceMotion: true)
        state.setAutoHideEnabled(false)
        XCTAssertEqual(state.phase, .visible)
        state.requestHide(reduceMotion: false)
        XCTAssertEqual(state.phase, .visible)
    }

    func testSkimRestoreArrowAndTransportShareTheHiddenState() {
        var state = PlaybackChromeVisibilityState(autoHideEnabled: true)
        XCTAssertTrue(state.isInteractive)
        XCTAssertTrue(state.showsSkimRestoreButton(skimControlsExpanded: false, isFullscreen: false))
        XCTAssertFalse(state.showsSkimRestoreButton(skimControlsExpanded: true, isFullscreen: false))

        state.requestHide(reduceMotion: true)
        XCTAssertFalse(state.isInteractive)
        XCTAssertFalse(state.showsSkimRestoreButton(skimControlsExpanded: false, isFullscreen: false))

        state.reveal()
        XCTAssertTrue(state.isInteractive)
        XCTAssertTrue(state.showsSkimRestoreButton(skimControlsExpanded: false, isFullscreen: false))
    }

    private func makeSnapshot(skimEnabled: Bool = true, queue: QueueOrderMode = .sequential,
                              start: String = "beginning", intro: Int = 0) -> SkimSettingsSnapshot {
        SkimSettingsSnapshot(skimEnabled: skimEnabled, imageDurationSeconds: 3, gifLoopCount: 1,
                             videoAudioNormalizationEnabled: false,
                             previewDurationMode: "fixed", fixedDurationSeconds: 10,
                             randomDurationRange: 4...12, startPositionMode: start,
                             skipIntroSeconds: intro, queueOrderMode: queue, loopQueueEnabled: false)
    }
}
