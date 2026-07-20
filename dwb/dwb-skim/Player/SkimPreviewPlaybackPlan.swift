import Foundation

/// Start-position modes a skim preview plan can be computed for.
///
/// This type intentionally does not read from `SettingsWindowController` or
/// `SettingsDefaultsRegistry` — callers supply concrete values so the planner
/// stays pure and testable.
enum SkimPreviewStartMode: String, Equatable {
    case beginning
    case random
}

enum SkimPreviewDurationMode: String, Equatable {
    case fixed
    case random
}

/// Pure calculation of where a skim preview should start and whether/when it
/// should auto-advance, given duration, start position, and skip-intro inputs.
///
/// No VLCKit, UserDefaults, or timer dependency — callers apply the resulting
/// offsets/durations against the real player and schedule advancement themselves.
struct SkimPreviewPlaybackPlan {
    /// Seconds into the media playback should begin, clamped to a safe range.
    let startOffsetSeconds: Double
    /// The clip duration to actually use, if playback should auto-advance
    /// rather than play to the end of the file. `nil` means full-file behavior.
    let effectiveClipDurationSeconds: Double?

    /// Whether the plan calls for auto-advancing away from the item before
    /// natural end-of-file completion.
    var shouldAutoAdvance: Bool { effectiveClipDurationSeconds != nil }

    static func resolvedClipDurationSeconds(mode: SkimPreviewDurationMode,
                                            fixedDurationSeconds: Double?,
                                            randomMinimumSeconds: Double,
                                            randomMaximumSeconds: Double,
                                            randomValue: Double = Double.random(in: 0..<1)) -> Double? {
        switch mode {
        case .fixed:
            return (fixedDurationSeconds ?? 0) > 0 ? fixedDurationSeconds : nil
        case .random:
            let minimum = max(1, randomMinimumSeconds)
            let maximum = max(minimum, randomMaximumSeconds)
            guard maximum > minimum else { return minimum }
            return minimum + (maximum - minimum) * clampedUnit(randomValue)
        }
    }

    /// - Parameters:
    ///   - mode: Beginning or random start position.
    ///   - skipIntroSeconds: Seconds to skip from the start of the media before
    ///     playback begins. Zero/negative means no skip. Ignored (treated as 0)
    ///     when `mediaDurationSeconds` is unknown, since an intro offset cannot
    ///     be safely validated against an unknown-length file.
    ///   - clipDurationSeconds: Configured clip duration. `nil`, zero, or
    ///     negative means "entire file" — full-file behavior is preserved and
    ///     `effectiveClipDurationSeconds` will be `nil`.
    ///   - mediaDurationSeconds: Known media duration, if any. `nil` for
    ///     unknown-duration or still-image media that has no intrinsic length.
    ///   - randomValue: A caller-supplied value in `0..<1` used to place the
    ///     random start position. Tests inject a deterministic value instead of
    ///     relying on `Double.random`.
    static func plan(mode: SkimPreviewStartMode,
                     skipIntroSeconds: Double,
                     clipDurationSeconds: Double?,
                     mediaDurationSeconds: Double?,
                     randomValue: Double = Double.random(in: 0..<1)) -> SkimPreviewPlaybackPlan {
        plan(mode: mode,
             durationMode: .fixed,
             skipIntroSeconds: skipIntroSeconds,
             fixedClipDurationSeconds: clipDurationSeconds,
             randomMinimumSeconds: 5,
             randomMaximumSeconds: 30,
             mediaDurationSeconds: mediaDurationSeconds,
             startRandomValue: randomValue,
             durationRandomValue: randomValue)
    }

    static func plan(mode: SkimPreviewStartMode,
                     durationMode: SkimPreviewDurationMode,
                     skipIntroSeconds: Double,
                     fixedClipDurationSeconds: Double?,
                     randomMinimumSeconds: Double,
                     randomMaximumSeconds: Double,
                     mediaDurationSeconds: Double?,
                     startRandomValue: Double = Double.random(in: 0..<1),
                     durationRandomValue: Double = Double.random(in: 0..<1)) -> SkimPreviewPlaybackPlan {
        let skipIntro = max(0, skipIntroSeconds)
        let effectiveClipDuration = resolvedClipDurationSeconds(mode: durationMode,
                                                                fixedDurationSeconds: fixedClipDurationSeconds,
                                                                randomMinimumSeconds: randomMinimumSeconds,
                                                                randomMaximumSeconds: randomMaximumSeconds,
                                                                randomValue: durationRandomValue)

        guard let duration = mediaDurationSeconds, duration > 0 else {
            // Unknown or zero duration: skip intro cannot be validated against
            // the file's length, so the safest start is the beginning regardless
            // of requested mode. Auto-advance is still honored if a clip
            // duration was configured, since that doesn't depend on knowing
            // the file's total length.
            return SkimPreviewPlaybackPlan(startOffsetSeconds: 0,
                                            effectiveClipDurationSeconds: effectiveClipDuration)
        }

        switch mode {
        case .beginning:
            let start = min(skipIntro, maxSafeStart(duration: duration))
            return SkimPreviewPlaybackPlan(startOffsetSeconds: start,
                                            effectiveClipDurationSeconds: effectiveClipDuration)

        case .random:
            let lowerBound = min(skipIntro, maxSafeStart(duration: duration))
            // The window that must remain playable after the chosen start: the
            // configured clip duration if known, otherwise a minimal epsilon so
            // the start isn't pinned exactly to the end of the file.
            let requiredTail = min(effectiveClipDuration ?? minimumPlayableTail, duration)
            let upperBound = max(lowerBound, duration - requiredTail)
            let start = lowerBound + (upperBound - lowerBound) * clampedUnit(startRandomValue)
            return SkimPreviewPlaybackPlan(startOffsetSeconds: start,
                                            effectiveClipDurationSeconds: effectiveClipDuration)
        }
    }

    /// Never start later than this far before end-of-file, so a start offset
    /// never lands exactly at (or past) the end of a short file.
    private static let minimumPlayableTail: Double = 0.25

    private static func maxSafeStart(duration: Double) -> Double {
        max(0, duration - minimumPlayableTail)
    }

    private static func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
