import XCTest

final class MediaPlaybackPolicyTests: XCTestCase {
    func testMediaKindsSelectIndependentPlaybackLimits() {
        XCTAssertEqual(MediaPlaybackPolicy.limit(for: .video,
                                                 videoPreviewSeconds: 10,
                                                 imageDurationSeconds: 3,
                                                 gifLoopCount: 2),
                       .videoPreview(seconds: 10))
        XCTAssertEqual(MediaPlaybackPolicy.limit(for: .image,
                                                 videoPreviewSeconds: 10,
                                                 imageDurationSeconds: 4.25,
                                                 gifLoopCount: 2),
                       .imageSeconds(4.25))
        XCTAssertEqual(MediaPlaybackPolicy.limit(for: .gif,
                                                 videoPreviewSeconds: 10,
                                                 imageDurationSeconds: 4.25,
                                                 gifLoopCount: 2),
                       .gifLoops(2))
    }

    func testGIFTrackerCountsOnlyCompleteAnimationWrapsAndSignalsOnce() {
        var tracker = GIFLoopCompletionTracker(targetLoops: 2)
        XCTAssertFalse(tracker.recordFrameTransition(from: 0, to: 1, frameCount: 3))
        XCTAssertFalse(tracker.recordFrameTransition(from: 1, to: 2, frameCount: 3))
        XCTAssertFalse(tracker.recordFrameTransition(from: 2, to: 0, frameCount: 3))
        XCTAssertEqual(tracker.completedLoops, 1)
        XCTAssertFalse(tracker.recordFrameTransition(from: 0, to: 1, frameCount: 3))
        XCTAssertFalse(tracker.recordFrameTransition(from: 1, to: 2, frameCount: 3))
        XCTAssertTrue(tracker.recordFrameTransition(from: 2, to: 0, frameCount: 3))
        XCTAssertEqual(tracker.completedLoops, 2)
        XCTAssertFalse(tracker.recordFrameTransition(from: 2, to: 0, frameCount: 3))
    }

    func testLoweringGIFTargetSignalsCompletionAtMostOnce() {
        var tracker = GIFLoopCompletionTracker(targetLoops: 4)
        XCTAssertFalse(tracker.recordFrameTransition(from: 1, to: 0, frameCount: 2))
        XCTAssertFalse(tracker.recordFrameTransition(from: 1, to: 0, frameCount: 2))
        XCTAssertTrue(tracker.updateTargetLoops(2))
        XCTAssertFalse(tracker.updateTargetLoops(1))
    }
}
