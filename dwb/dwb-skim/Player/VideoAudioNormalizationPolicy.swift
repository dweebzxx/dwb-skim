import Foundation

struct VideoAudioNormalizationPolicy {
    static let targetLoudnessLUFS = -18.0
    static let silenceFloorLUFS = -55.0
    static let minimumPreampDB = -12.0
    static let maximumPreampDB = 12.0
    static let smoothingFactor = 0.18

    static func applies(to kind: MediaFileSupport.MediaKind) -> Bool {
        kind == .video
    }

    static func desiredPreampDB(forMomentaryLoudness loudness: Double) -> Double? {
        guard loudness.isFinite,
              loudness < 0,
              loudness >= silenceFloorLUFS else { return nil }
        return min(maximumPreampDB,
                   max(minimumPreampDB, targetLoudnessLUFS - loudness))
    }

    static func smoothedPreampDB(current: Double, desired: Double) -> Double {
        let boundedCurrent = min(maximumPreampDB, max(minimumPreampDB, current))
        let boundedDesired = min(maximumPreampDB, max(minimumPreampDB, desired))
        return boundedCurrent + (boundedDesired - boundedCurrent) * smoothingFactor
    }
}

/// The deterministic result of handling one loudness measurement. The VLCKit
/// owner uses this to decide whether to write a preamp value to its equalizer.
enum VideoAudioNormalizationDecision: Equatable {
    case bypassed
    case ignoredMeasurement
    case apply(desiredPreampDB: Double, appliedPreampDB: Double)
}

struct VideoAudioNormalizerState: Equatable {
    private(set) var preampDB = 0.0

    mutating func reset() {
        preampDB = 0
    }

    mutating func ingest(momentaryLoudnessLUFS: Double) -> Double? {
        guard let desired = VideoAudioNormalizationPolicy.desiredPreampDB(
            forMomentaryLoudness: momentaryLoudnessLUFS
        ) else { return nil }
        preampDB = VideoAudioNormalizationPolicy.smoothedPreampDB(current: preampDB,
                                                                  desired: desired)
        return preampDB
    }

    /// Evaluates the same decision that the VLCKit owner applies to the
    /// equalizer, without requiring a player, audio device, or decoded media.
    mutating func evaluate(momentaryLoudnessLUFS: Double,
                           isEnabled: Bool) -> VideoAudioNormalizationDecision {
        guard isEnabled else { return .bypassed }
        guard let desired = VideoAudioNormalizationPolicy.desiredPreampDB(
            forMomentaryLoudness: momentaryLoudnessLUFS
        ) else {
            return .ignoredMeasurement
        }
        preampDB = VideoAudioNormalizationPolicy.smoothedPreampDB(current: preampDB,
                                                                  desired: desired)
        return .apply(desiredPreampDB: desired, appliedPreampDB: preampDB)
    }
}
