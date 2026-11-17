import Foundation

/// One randomized preview segment within a Progressive Random Skim plan.
struct ProgressiveRandomSkimSegment: Equatable {
    let startOffsetSeconds: Double
    let durationSeconds: Double
}

/// Coverage (Part 4): scales the Part 2 adaptive planner's preview *count* only —
/// duration stays governed entirely by `targetSegmentDuration`. `standard` is the unscaled Part 2
/// behavior and is the persisted default, so existing users see zero change until they opt in.
enum ProgressiveRandomSkimIntensity: String, CaseIterable, Equatable {
    case light
    case standard
    case thorough
    case ultra
    case max

    /// Applied to the adaptive segment count before the safe timeline fitting loop; never
    /// read by the planner from settings — callers resolve this and pass the raw `Double` in.
    var segmentCountMultiplier: Double {
        switch self {
        case .light: return 0.7
        case .standard: return 1.0
        case .thorough: return 1.5
        case .ultra: return 2.0
        case .max: return 2.5
        }
    }

    var displayTitle: String {
        switch self {
        case .light: return "Light"
        case .standard: return "Standard"
        case .thorough: return "Thorough"
        case .ultra: return "Ultra"
        case .max: return "Max"
        }
    }
}

/// Pure, testable planner for Progressive Random Skim.
///
/// No VLCKit, UserDefaults, or timer dependency — callers apply the resulting segments against the
/// real player and drive advancement through the existing `SkimPreviewSessionScheduler` /
/// `SkimPlaybackStartIntentCoordinator` machinery, one segment at a time.
///
/// ## Adaptive planning & Clip Duration integration (P42)
///
/// Snippet durations follow the authoritative Clip Duration configuration:
/// - **Fixed Duration mode**: each segment targets `max(2.0, configuredFixedDurationSeconds)` with
///   zero intentional flutter or variation.
/// - **Random Duration mode**: each segment uniformly selects its target duration within
///   `[max(2.0, randomMinimumSeconds), max(lowerBound, randomMaximumSeconds)]`.
/// - **Dynamic Eligibility**: media is eligible only if `mediaDurationSeconds >= max(30.0, minimumSnippetDuration * 2.0)`.
///   Videos below the threshold receive an empty plan, gracefully falling back to standard skim preview.
/// - **Safe Timeline Fitting**: if the requested segment count (scaled by intensity) is too dense for
///   the configured minimum snippet duration (`usableDuration / count < minimumSnippetDuration`),
///   the count is reduced until snippets safely fit without overlap or artificial shrinkage, down to 1 (or empty).
enum ProgressiveRandomSkimPlanner {
    /// Absolute floor on any single preview's duration, regardless of video length or settings.
    static let minimumEffectiveDurationSeconds: Double = 2.0

    /// Baseline media duration for eligibility when snippets are at or below 15s.
    static let baselineEligibilityThresholdSeconds: Double = 30.0

    /// Backward-compatibility alias for the baseline 30-second eligibility floor.
    static let eligibilityThresholdSeconds: Double = baselineEligibilityThresholdSeconds

    /// Smallest and largest number of previews a plan may contain.
    static let minimumSegmentCount = 2
    static let maximumSegmentCount = 40

    /// Per-doubling growth in segment count: `countGrowthScale * ln(2) ≈ 1.4` extra previews each
    /// time usable duration doubles.
    static let countGrowthScale: Double = 2.0

    /// Upper bound on `adaptiveSegmentCount(forUsableDurationSeconds:)`, useful for callers sizing a
    /// fixed pool of random values up front.
    static let maximumPossibleSegmentCount = maximumSegmentCount

    /// Effective minimum snippet duration given the active duration mode and parameters.
    /// Clamped to at least `minimumEffectiveDurationSeconds` (2.0s).
    static func effectiveMinimumSnippetDuration(durationMode: SkimPreviewDurationMode,
                                                fixedDurationSeconds: Double,
                                                randomMinimumSeconds: Double) -> Double {
        switch durationMode {
        case .fixed:
            return max(minimumEffectiveDurationSeconds, fixedDurationSeconds)
        case .random:
            return max(minimumEffectiveDurationSeconds, randomMinimumSeconds)
        }
    }

    /// Dynamic eligibility threshold for Progressive Random Skim: `max(30.0, minimumSnippetDuration * 2.0)`.
    static func eligibilityThresholdSeconds(minimumSnippetDuration: Double) -> Double {
        max(baselineEligibilityThresholdSeconds, minimumSnippetDuration * 2.0)
    }

    /// Dynamic eligibility threshold for Progressive Random Skim given the active duration mode and settings.
    static func eligibilityThresholdSeconds(durationMode: SkimPreviewDurationMode,
                                            fixedDurationSeconds: Double,
                                            randomMinimumSeconds: Double) -> Double {
        let minimumSnippet = effectiveMinimumSnippetDuration(durationMode: durationMode,
                                                             fixedDurationSeconds: fixedDurationSeconds,
                                                             randomMinimumSeconds: randomMinimumSeconds)
        return eligibilityThresholdSeconds(minimumSnippetDuration: minimumSnippet)
    }

    /// Adaptive duration-to-segment-count rule. Count increases with usable duration with diminishing
    /// returns, and is capped at `maximumSegmentCount`.
    static func adaptiveSegmentCount(forUsableDurationSeconds usableDuration: Double) -> Int {
        guard usableDuration.isFinite, usableDuration > 0 else { return 0 }
        let ratio = usableDuration / baselineEligibilityThresholdSeconds
        let raw = Double(minimumSegmentCount) + countGrowthScale * log(ratio)
        let clamped = min(Double(maximumSegmentCount), max(Double(minimumSegmentCount), raw))
        return Int(clamped.rounded())
    }

    /// - Parameters:
    ///   - mediaDurationSeconds: Total media duration. Videos under the dynamic eligibility threshold
    ///     receive an empty plan and fall back to normal skim.
    ///   - skipIntroSeconds: Earliest allowed position for the first preview segment. Clamped to
    ///     `0...mediaDurationSeconds`. `usableDuration = mediaDurationSeconds - skipIntroSeconds`.
    ///   - positionRandomValues: One value in `0..<1` per planned segment, choosing where within its
    ///     bucket the segment starts. Missing entries are treated as `0`. Tests inject deterministic sequences.
    ///   - durationRandomValues: One value in `0..<1` per planned segment, choosing the segment's
    ///     duration within `[lowerBound, upperBound]` in Random mode. Ignored in Fixed mode.
    ///   - segmentCountMultiplier: Coverage-intensity scale applied to the adaptive segment count.
    ///   - durationMode: Fixed or Random duration mode from authoritative Clip Duration settings.
    ///   - fixedDurationSeconds: Configured fixed duration in seconds.
    ///   - randomMinimumSeconds: Configured random minimum duration in seconds.
    ///   - randomMaximumSeconds: Configured random maximum duration in seconds.
    /// - Returns: An ordered list of segments, each strictly starting after the previous segment
    ///   ends, none extending past `mediaDurationSeconds`, and none starting before `skipIntroSeconds`.
    static func plan(mediaDurationSeconds: Double,
                     skipIntroSeconds: Double,
                     positionRandomValues: [Double] = [],
                     durationRandomValues: [Double] = [],
                     segmentCountMultiplier: Double = 1.0,
                     durationMode: SkimPreviewDurationMode = .fixed,
                     fixedDurationSeconds: Double = Double(SettingsDefaultsRegistry.Defaults.clipDurationSeconds),
                     randomMinimumSeconds: Double = Double(SettingsDefaultsRegistry.Defaults.randomPreviewMinimumSeconds),
                     randomMaximumSeconds: Double = Double(SettingsDefaultsRegistry.Defaults.randomPreviewMaximumSeconds)) -> [ProgressiveRandomSkimSegment] {
        let fixedTarget = max(minimumEffectiveDurationSeconds, fixedDurationSeconds)
        let randomLower = max(minimumEffectiveDurationSeconds, randomMinimumSeconds)
        let randomUpper = max(randomLower, randomMaximumSeconds)

        let minimumSnippetDuration: Double
        switch durationMode {
        case .fixed:
            minimumSnippetDuration = fixedTarget
        case .random:
            minimumSnippetDuration = randomLower
        }

        let threshold = eligibilityThresholdSeconds(minimumSnippetDuration: minimumSnippetDuration)
        guard mediaDurationSeconds.isFinite, mediaDurationSeconds >= threshold else {
            return []
        }

        let usableStart = max(0, min(skipIntroSeconds, mediaDurationSeconds))
        let usableEnd = mediaDurationSeconds
        let usableDuration = usableEnd - usableStart
        guard usableDuration > 0 else { return [] }

        let baseCount = adaptiveSegmentCount(forUsableDurationSeconds: usableDuration)
        var count = scaledSegmentCount(baseCount: baseCount, multiplier: segmentCountMultiplier)
        while count > 1 && usableDuration / Double(count) < minimumSnippetDuration {
            count -= 1
        }
        guard count >= 1, usableDuration >= minimumSnippetDuration else { return [] }

        var segments: [ProgressiveRandomSkimSegment] = []
        var cursor = usableStart
        for index in 0..<count {
            let remainingBuckets = count - index
            let remainingSpan = usableEnd - cursor
            guard remainingSpan >= minimumSnippetDuration else { break }
            let bucketSpan = remainingSpan / Double(remainingBuckets)

            let target: Double
            switch durationMode {
            case .fixed:
                target = fixedTarget
            case .random:
                let durationRandom = clampedUnit(durationRandomValues[safe: index] ?? 0)
                target = randomLower + (randomUpper - randomLower) * durationRandom
            }

            let duration = min(target, bucketSpan)
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
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
