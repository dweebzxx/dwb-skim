import XCTest

final class PlaybackBarPresentationTests: XCTestCase {
    func testControlOrderMatchesAccessibilityAndVisualContract() {
        XCTAssertEqual(PlaybackBarPresentation.controlOrder,
                       ["Queue",
                        "Skim", "Start From Top", "Previous", "Play/Pause", "Next", "Advance Segment", "Volume",
                        "dwb+ on", "Bookmark", "Settings", "Fullscreen"])
    }

    func testLayoutCountsSixButtonsOnePlayButtonAndSixGaps() {
        // 980 pt: the gap is capped at 8, so the group is 6 * 30 + 36 + 6 * 8 = 264, centered.
        let layout = PlaybackBarPresentation.layout(width: 980)
        XCTAssertEqual(PlaybackBarPresentation.centerButtonCount, 6)
        XCTAssertEqual(layout.gap, 8, accuracy: 0.001)
        XCTAssertEqual(layout.centeredWidth, 264, accuracy: 0.001)
        XCTAssertEqual((980 - layout.centeredWidth) / 2, 358, accuracy: 0.001)

        let wide = PlaybackBarPresentation.layout(width: 2560)
        XCTAssertEqual(wide.gap, 8, accuracy: 0.001)
        XCTAssertEqual(wide.centeredWidth, 264, accuracy: 0.001)
        XCTAssertEqual((2560 - wide.centeredWidth) / 2 + wide.centeredWidth / 2, 1280, accuracy: 0.001)
    }

    func testLayoutGapIsClampedToTwoThroughEightPoints() {
        // (width - 216) / 6 is 5 at 246 pt, below 2 at 200 pt, and above 8 at 300 pt.
        XCTAssertEqual(PlaybackBarPresentation.layout(width: 246).gap, 5, accuracy: 0.001)
        XCTAssertEqual(PlaybackBarPresentation.layout(width: 246).centeredWidth, 246, accuracy: 0.001)
        XCTAssertEqual(PlaybackBarPresentation.layout(width: 200).gap, 2, accuracy: 0.001)
        XCTAssertEqual(PlaybackBarPresentation.layout(width: 200).centeredWidth, 228, accuracy: 0.001)
        XCTAssertEqual(PlaybackBarPresentation.layout(width: 300).gap, 8, accuracy: 0.001)
    }

    func testEveryRailItemFitsAtTheMinimumWidthWithTheLabelShown() {
        // The geometry `BottomRailView.layout()` builds at 980 pt, with a label wider than the real one.
        let width: CGFloat = 980
        let layout = PlaybackBarPresentation.layout(width: width)
        let button: CGFloat = 30, play: CGFloat = 36, gap = layout.gap
        let centerStart = (width - layout.centeredWidth) / 2
        let centerEndX = centerStart + play + button * 6 + gap * 7
        let fullscreenX = width - layout.edgeInset - button
        let settingsX = fullscreenX - gap - button
        let bookmarkX = settingsX - gap - button
        let labelWidth: CGFloat = 60
        let labelX = bookmarkX - gap - labelWidth
        let visibility = PlaybackBarPresentation.rightGroupVisibility(labelWanted: true, labelX: labelX,
                                                                      bookmarkX: bookmarkX, centerEndX: centerEndX)
        XCTAssertEqual(visibility, RailRightGroupVisibility(showsBackgroundAudioLabel: true, showsBookmark: true))
        XCTAssertGreaterThan(labelX, centerEndX)
        XCTAssertLessThan(layout.edgeInset + button, centerStart)
    }

    func testBackgroundAudioLabelShowsOnlyWhileTheTrackPlays() {
        let url = URL(fileURLWithPath: "/tmp/track.mp3")
        XCTAssertTrue(PlaybackBarPresentation.showsBackgroundAudioLabel(for: .playing(url)))
        XCTAssertFalse(PlaybackBarPresentation.showsBackgroundAudioLabel(for: .paused(url)))
        XCTAssertFalse(PlaybackBarPresentation.showsBackgroundAudioLabel(for: .inactive))
        XCTAssertFalse(PlaybackBarPresentation.showsBackgroundAudioLabel(for: .unavailable("No track")))
    }

    func testNarrowRailHidesTheLabelBeforeBookmark() {
        func visibility(labelX: CGFloat, bookmarkX: CGFloat, wanted: Bool = true) -> RailRightGroupVisibility {
            PlaybackBarPresentation.rightGroupVisibility(labelWanted: wanted, labelX: labelX,
                                                         bookmarkX: bookmarkX, centerEndX: 500)
        }
        XCTAssertEqual(visibility(labelX: 520, bookmarkX: 600),
                       RailRightGroupVisibility(showsBackgroundAudioLabel: true, showsBookmark: true))
        // The label would overlap the center group; Bookmark still fits.
        XCTAssertEqual(visibility(labelX: 460, bookmarkX: 510),
                       RailRightGroupVisibility(showsBackgroundAudioLabel: false, showsBookmark: true))
        // Bookmark would overlap too: both hide.
        XCTAssertEqual(visibility(labelX: 440, bookmarkX: 490),
                       RailRightGroupVisibility(showsBackgroundAudioLabel: false, showsBookmark: false))
        // A label that is not wanted never shows.
        XCTAssertEqual(visibility(labelX: 520, bookmarkX: 600, wanted: false),
                       RailRightGroupVisibility(showsBackgroundAudioLabel: false, showsBookmark: true))
    }

    func testStartFromTopTargetsTheFirstItemOrNothing() {
        XCTAssertEqual(StartFromTop.targetDisplayIndex(displayOrderCount: 1), 0)
        XCTAssertEqual(StartFromTop.targetDisplayIndex(displayOrderCount: 40), 0)
        XCTAssertNil(StartFromTop.targetDisplayIndex(displayOrderCount: 0))
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

    func testDurationTimerIsCenteredDirectlyAbovePlayPause() {
        let layout = PlaybackBarPresentation.layout(width: 980)
        XCTAssertEqual(layout.durationTimerFrame.midX, 490, accuracy: 0.001)
        XCTAssertEqual(layout.durationTimerFrame.minY, 42, accuracy: 0.001)
    }

    func testSkimOffVideoShowsElapsedAndRemainingDuration() {
        let presentation = PlaybackBarPresentation.duration(
            elapsedMilliseconds: 83_000,
            durationMilliseconds: 308_000,
            isSkimEnabled: false,
            isImageMode: false
        )
        XCTAssertEqual(presentation?.text, "01:23  -03:45")
        XCTAssertEqual(presentation?.accessibilityValue, "Elapsed 01:23, remaining 03:45")
    }

    func testDurationTimerClampsAtMediaBoundaries() {
        XCTAssertEqual(
            PlaybackBarPresentation.duration(elapsedMilliseconds: -1,
                                             durationMilliseconds: 60_000,
                                             isSkimEnabled: false,
                                             isImageMode: false)?.text,
            "00:00  -01:00"
        )
        XCTAssertEqual(
            PlaybackBarPresentation.duration(elapsedMilliseconds: 75_000,
                                             durationMilliseconds: 60_000,
                                             isSkimEnabled: false,
                                             isImageMode: false)?.text,
            "01:00  -00:00"
        )
    }

    func testDurationTimerIsHiddenWhenSkimOwnsPlayback() {
        XCTAssertNil(PlaybackBarPresentation.duration(elapsedMilliseconds: 10_000,
                                                       durationMilliseconds: 60_000,
                                                       isSkimEnabled: true,
                                                       isImageMode: false))
    }

    func testDurationTimerIsHiddenForImagesAndUnknownMedia() {
        XCTAssertNil(PlaybackBarPresentation.duration(elapsedMilliseconds: 10_000,
                                                       durationMilliseconds: 60_000,
                                                       isSkimEnabled: false,
                                                       isImageMode: true))
        XCTAssertNil(PlaybackBarPresentation.duration(elapsedMilliseconds: 0,
                                                       durationMilliseconds: 0,
                                                       isSkimEnabled: false,
                                                       isImageMode: false))
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
                                        startPositionMode: "beginning", skipIntroSeconds: 0,
                                        progressiveRandomSkimEnabled: false, progressiveRandomSkimIntensity: .standard,
                                        queueOrderMode: .sequential,
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
                             skipIntroSeconds: intro, progressiveRandomSkimEnabled: false,
                             progressiveRandomSkimIntensity: .standard,
                             queueOrderMode: queue, loopQueueEnabled: false)
    }
}
