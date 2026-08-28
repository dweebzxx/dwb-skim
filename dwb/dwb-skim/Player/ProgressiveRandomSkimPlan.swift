import Foundation

/// One randomized preview segment within a Progressive Random Skim plan.
struct ProgressiveRandomSkimSegment: Equatable {
    let startOffsetSeconds: Double
    let durationSeconds: Double
}

/// Coverage intensity (Part 4): scales the Part 2 adaptive planner's preview *count* only —
/// duration stays governed entirely by `targetSegmentDuration`. `standard` is the unscaled Part 2
/// behavior and is the persisted default, so existing users see zero change until they opt in.
enum ProgressiveRandomSkimIntensity: String, CaseIterable, Equatable {
    case light
    case standard
    case thorough

    /// Applied to the Part 2 adaptive segment count before the existing safe-reduction loop; never
    /// read by the planner from settings — callers resolve this and pass the raw `Double` in.
    var segmentCountMultiplier: Double {
        switch self {
        case .light: return 0.7
        case .standard: return 1.0
        case .thorough: return 1.5
        }
    }
}

/// Pure, testable planner for Progressive Random Skim.
///
/// No VLCKit, UserDefaults, or timer dependency — callers apply the resulting segments against the
/// real player and drive advancement through the existing `SkimPreviewSessionScheduler` /
/// `SkimPlaybackStartIntentCoordinator` machinery, one segment at a time.
///
/// ## Adaptive planning (Part 2)
///
/// The planner optimizes for *useful exposure per second spent skimming*, not for the largest
/// possible number of previews. A longer video has more content worth sampling, so it earns more
/// previews and more timeline coverage — but each additional minute of video should buy a
/// progressively smaller increase in total skim time. Both preview count and preview duration are
/// therefore driven by natural-log growth curves of the usable duration (`mediaDurationSeconds -
/// skipIntroSeconds`): cheap to reason about, monotonic, and self-limiting without hard-coded
/// duration tiers.
///
/// - **Count** (`adaptiveSegmentCount`): `minimumSegmentCount + countGrowthScale *
///   ln(usableDuration / eligibilityThresholdSeconds)`, clamped to
///   `minimumSegmentCount...maximumSegmentCount`. Doubling the usable duration adds a constant
///   number of previews (`countGrowthScale * ln(2) ≈ 1.4`), not a constant *factor* — so a 1-hour
///   video gets noticeably more previews than a 5-minute one, but a 3-hour video only gets a little
///   more than a 1-hour one.
/// - **Duration** (`targetSegmentDuration`): `durationBaseSeconds + durationGrowthScale *
///   ln(max(usableDuration / eligibilityThresholdSeconds, 1))`, clamped to
///   `minimumSegmentDurationSeconds...maximumSegmentDurationSeconds`. Previews stay short glimpses
///   even for very long videos; they never grow proportionally with the video.
/// - **Coverage / spacing**: the usable timeline is divided into `count` ordered, consecutive
///   buckets (unchanged from Part 1). Each segment's duration and position are randomized within its
///   own bucket, so every bucket — early, middle, late — gets a sampling opportunity, positions stay
///   randomized and strictly forward-moving, and segments never overlap. As duration grows, bucket
///   spans grow, which naturally increases the *distance* between previews rather than clustering
///   them near the start.
/// - **Graceful degradation**: if the usable timeline can't safely hold the target count/duration
///   combination (e.g. a large Skip Intro), segment count is reduced first, then duration is
///   narrowed per-bucket, before ever violating timeline bounds or producing overlaps. The planner
///   always returns a valid plan, down to an empty one.
enum ProgressiveRandomSkimPlanner {
    /// Videos shorter than this are never eligible for Progressive Random Skim.
    static let eligibilityThresholdSeconds: Double = 30

    /// Absolute floor/ceiling on any single preview's duration, regardless of video length. Chosen
    /// so a preview always reads as a "glimpse": long enough to orient the viewer (2.5s), never long
    /// enough to itself become something worth watching in full (10s).
    static let minimumSegmentDurationSeconds: Double = 2.5
    static let maximumSegmentDurationSeconds: Double = 10

    /// Baseline target duration at the eligibility threshold, and the per-doubling growth added on
    /// top of it. `durationGrowthScale * ln(2) ≈ 0.83s` added per doubling of usable duration — a
    /// slow, sub-linear climb toward `maximumSegmentDurationSeconds`.
    static let durationBaseSeconds: Double = 3
    static let durationGrowthScale: Double = 1.2
    /// Random per-segment variation applied around the target duration (±30%), so segments within
    /// the same plan aren't all identical lengths.
    static let durationVariationFraction: Double = 0.3

    /// Smallest and largest number of previews a plan may contain. The minimum matches "a video
    /// barely over 30 seconds should only receive a few useful glimpses"; the maximum keeps very
    /// long videos from producing an unbounded number of previews — at the ceiling, total skim time
    /// is still capped at `maximumSegmentCount * maximumSegmentDurationSeconds` = 160s regardless of
    /// how long the source video is.
    static let minimumSegmentCount = 2
    static let maximumSegmentCount = 16
    /// Per-doubling growth in segment count: `countGrowthScale * ln(2) ≈ 1.4` extra previews each
    /// time usable duration doubles.
    static let countGrowthScale: Double = 2.0

    /// Upper bound on `adaptiveSegmentCount(forUsableDurationSeconds:)`, useful for callers sizing a
    /// fixed pool of random values up front.
    static let maximumPossibleSegmentCount = maximumSegmentCount

    /// Adaptive duration-to-segment-count rule (see type documentation for the rationale). Count
    /// increases with usable duration with diminishing returns, and is capped at
    /// `maximumSegmentCount`.
    static func adaptiveSegmentCount(forUsableDurationSeconds usableDuration: Double) -> Int {
        guard usableDuration.isFinite, usableDuration > 0 else { return 0 }
        let ratio = usableDuration / eligibilityThresholdSeconds
        let raw = Double(minimumSegmentCount) + countGrowthScale * log(ratio)
        let clamped = min(Double(maximumSegmentCount), max(Double(minimumSegmentCount), raw))
        return Int(clamped.rounded())
    }

    /// Adaptive target preview duration for a given usable duration (see type documentation). Actual
    /// per-segment durations are randomized around this target and further narrowed to fit their
    /// bucket, but never leave `minimumSegmentDurationSeconds...maximumSegmentDurationSeconds`.
    static func targetSegmentDuration(forUsableDurationSeconds usableDuration: Double) -> Double {
        guard usableDuration.isFinite, usableDuration > 0 else { return minimumSegmentDurationSeconds }
        let ratio = usableDuration / eligibilityThresholdSeconds
        let raw = durationBaseSeconds + durationGrowthScale * log(max(ratio, 1))
        return min(maximumSegmentDurationSeconds, max(minimumSegmentDurationSeconds, raw))
    }

    /// - Parameters:
    ///   - mediaDurationSeconds: Total media duration. Videos under `eligibilityThresholdSeconds`
    ///     seconds are ineligible and receive an empty plan.
    ///   - skipIntroSeconds: Earliest allowed position for the first preview segment. Clamped to
    ///     `0...mediaDurationSeconds`. `usableDuration = mediaDurationSeconds - skipIntroSeconds`
    ///     drives every adaptive calculation below.
    ///   - positionRandomValues: One value in `0..<1` per planned segment, choosing where within its
    ///     bucket the segment starts. Missing entries are treated as `0`. Tests inject deterministic
    ///     sequences instead of `Double.random`.
    ///   - durationRandomValues: One value in `0..<1` per planned segment, choosing the segment's
    ///     duration within the adaptive target's variation range (narrowed further if its bucket is
    ///     too small to hold that range).
    ///   - segmentCountMultiplier: Coverage-intensity scale (Part 4) applied to the adaptive segment
    ///     count only, before the existing safe-reduction loop below. `1.0` (the default, matching
    ///     `ProgressiveRandomSkimIntensity.standard`) reproduces the unscaled Part 2 count exactly.
    ///     The planner stays pure: callers resolve the user-facing intensity to this raw multiplier
    ///     themselves rather than this function reading settings.
    /// - Returns: An ordered list of segments, each strictly starting after the previous segment
    ///   ends, none extending past `mediaDurationSeconds`, and none starting before `skipIntroSeconds`.
    ///   When the usable timeline cannot safely hold the adaptive segment count, the count is reduced
    ///   (down to zero) rather than producing overlapping or out-of-range segments.
    static func plan(mediaDurationSeconds: Double,
                     skipIntroSeconds: Double,
                     positionRandomValues: [Double],
                     durationRandomValues: [Double],
                     segmentCountMultiplier: Double = 1.0) -> [ProgressiveRandomSkimSegment] {
        guard mediaDurationSeconds.isFinite, mediaDurationSeconds >= eligibilityThresholdSeconds else {
            return []
        }
        let usableStart = max(0, min(skipIntroSeconds, mediaDurationSeconds))
        let usableEnd = mediaDurationSeconds
        let usableDuration = usableEnd - usableStart
        guard usableDuration > 0 else { return [] }

        let baseCount = adaptiveSegmentCount(forUsableDurationSeconds: usableDuration)
        var count = scaledSegmentCount(baseCount: baseCount, multiplier: segmentCountMultiplier)
        while count > 1 && usableDuration / Double(count) < minimumSegmentDurationSeconds {
            count -= 1
        }
        guard count >= 1, usableDuration >= minimumSegmentDurationSeconds else { return [] }

        let target = targetSegmentDuration(forUsableDurationSeconds: usableDuration)
        let targetLow = max(minimumSegmentDurationSeconds, target * (1 - durationVariationFraction))
        let targetHigh = min(maximumSegmentDurationSeconds, target * (1 + durationVariationFraction))

        var segments: [ProgressiveRandomSkimSegment] = []
        var cursor = usableStart
        for index in 0..<count {
            let remainingBuckets = count - index
            let remainingSpan = usableEnd - cursor
            guard remainingSpan >= minimumSegmentDurationSeconds else { break }
            let bucketSpan = remainingSpan / Double(remainingBuckets)
            let maxDuration = min(targetHigh, bucketSpan)
            let minDuration = min(targetLow, maxDuration)
            let durationRandom = clampedUnit(durationRandomValues[safe: index] ?? 0)
            let duration = minDuration + (maxDuration - minDuration) * durationRandom
            guard duration > 0 else { break }
            let slack = max(0, bucketSpan - duration)
            let positionRandom = clampedUnit(positionRandomValues[safe: index] ?? 0)
            let start = cursor + slack * positionRandom
            segments.append(ProgressiveRandomSkimSegment(startOffsetSeconds: start, durationSeconds: duration))
            cursor = start + duration
        }
        return segments
    }

    /// Applies a coverage-intensity multiplier to the Part 2 adaptive count, clamped back to
    /// `0...maximumSegmentCount` so Thorough can't blow past the design's total-skim-time cap and a
    /// near-zero Light result degrades to an empty plan (handled by `plan`'s own `count >= 1` guard)
    /// instead of a negative count.
    static func scaledSegmentCount(baseCount: Int, multiplier: Double) -> Int {
        guard multiplier.isFinite, multiplier > 0 else { return 0 }
        let scaled = Double(baseCount) * multiplier
        guard scaled.isFinite else { return maximumSegmentCount }
        return min(maximumSegmentCount, max(0, Int(scaled.rounded())))
    }

    private static func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
