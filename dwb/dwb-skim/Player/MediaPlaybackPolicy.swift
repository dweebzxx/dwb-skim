import Foundation

enum MediaPlaybackLimit: Equatable {
    case videoPreview(seconds: Double?)
    case imageSeconds(Double)
    case gifLoops(Int)
}

enum MediaPlaybackPolicy {
    static func limit(for kind: MediaFileSupport.MediaKind,
                      videoPreviewSeconds: Double?,
                      imageDurationSeconds: Double,
                      gifLoopCount: Int) -> MediaPlaybackLimit {
        switch kind {
        case .video:
            let duration = videoPreviewSeconds.flatMap { value in
                value.isFinite && value > 0 ? value : nil
            }
            return .videoPreview(seconds: duration)
        case .image:
            return .imageSeconds(SettingsDefaultsRegistry.validatedImageDurationSeconds(imageDurationSeconds))
        case .gif:
            return .gifLoops(SettingsDefaultsRegistry.validatedGIFLoopCount(gifLoopCount))
        }
    }
}

struct GIFLoopCompletionTracker: Equatable {
    private(set) var targetLoops: Int
    private(set) var completedLoops = 0
    private(set) var didSignalCompletion = false

    init(targetLoops: Int) {
        self.targetLoops = SettingsDefaultsRegistry.validatedGIFLoopCount(targetLoops)
    }

    mutating func updateTargetLoops(_ value: Int) -> Bool {
        targetLoops = SettingsDefaultsRegistry.validatedGIFLoopCount(value)
        return signalIfComplete()
    }

    mutating func recordFrameTransition(from previousIndex: Int,
                                        to nextIndex: Int,
                                        frameCount: Int) -> Bool {
        guard frameCount > 0,
              previousIndex == frameCount - 1,
              nextIndex == 0 else { return false }
        completedLoops += 1
        return signalIfComplete()
    }

    private mutating func signalIfComplete() -> Bool {
        guard !didSignalCompletion, completedLoops >= targetLoops else { return false }
        didSignalCompletion = true
        return true
    }
}
