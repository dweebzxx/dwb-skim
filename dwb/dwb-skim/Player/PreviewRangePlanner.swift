import Foundation

struct ActivePreviewRange: Equatable {
    let startSeconds: Double
    let endSeconds: Double
    let totalDurationSeconds: Double

    var durationSeconds: Double { max(0, endSeconds - startSeconds) }

    var normalizedStart: Double {
        totalDurationSeconds > 0 ? startSeconds / totalDurationSeconds : 0
    }

    var normalizedEnd: Double {
        totalDurationSeconds > 0 ? endSeconds / totalDurationSeconds : 0
    }
}

enum PreviewRangePlanner {
    private static let minimumPlayableTail = 0.25

    static func range(startSeconds: Double,
                      previewDurationSeconds: Double?,
                      totalDurationSeconds: Double) -> ActivePreviewRange? {
        guard totalDurationSeconds.isFinite, totalDurationSeconds > 0 else { return nil }
        let latestStart = max(0, totalDurationSeconds - min(minimumPlayableTail, totalDurationSeconds))
        let start = min(latestStart, max(0, startSeconds.isFinite ? startSeconds : 0))
        let end: Double
        if let previewDurationSeconds,
           previewDurationSeconds.isFinite,
           previewDurationSeconds > 0 {
            end = min(totalDurationSeconds, start + previewDurationSeconds)
        } else {
            end = totalDurationSeconds
        }
        return ActivePreviewRange(startSeconds: start,
                                  endSeconds: max(start, end),
                                  totalDurationSeconds: totalDurationSeconds)
    }

    static func relocated(normalizedStart: Double,
                          preservingDurationSeconds: Double?,
                          totalDurationSeconds: Double) -> ActivePreviewRange? {
        let normalized = normalizedStart.isFinite ? min(1, max(0, normalizedStart)) : 0
        return range(startSeconds: normalized * totalDurationSeconds,
                     previewDurationSeconds: preservingDurationSeconds,
                     totalDurationSeconds: totalDurationSeconds)
    }
}
