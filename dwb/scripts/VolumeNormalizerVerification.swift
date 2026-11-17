import Darwin
import Foundation

// The production policy's media-kind gate is not part of this fixture-free
// command. This minimal declaration lets swiftc compile that source directly.
enum MediaFileSupport {
    enum MediaKind {
        case video
        case image
        case gif
    }
}

@main
struct VolumeNormalizerVerification {
    private static let tolerance = 0.000_001

    static func main() {
        var allPassed = true

        allPassed = reportEvaluation(name: "quiet",
                                     inputLUFS: -28,
                                     expected: "boost") { state in
            let decision = state.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
            guard case .apply(let desired, let applied) = decision else { return (decision, false) }
            let movedTowardTarget = abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - (-28 + applied))
                < abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - -28)
            return (decision, desired > 0 && applied > 0 && movedTowardTarget)
        } && allPassed

        allPassed = reportEvaluation(name: "target",
                                     inputLUFS: -18,
                                     expected: "neutral") { state in
            let decision = state.evaluate(momentaryLoudnessLUFS: -18, isEnabled: true)
            guard case .apply(let desired, let applied) = decision else { return (decision, false) }
            return (decision, abs(desired) <= tolerance && abs(applied) <= tolerance)
        } && allPassed

        allPassed = reportEvaluation(name: "loud",
                                     inputLUFS: -8,
                                     expected: "attenuate") { state in
            let decision = state.evaluate(momentaryLoudnessLUFS: -8, isEnabled: true)
            guard case .apply(let desired, let applied) = decision else { return (decision, false) }
            let movedTowardTarget = abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - (-8 + applied))
                < abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - -8)
            return (decision, desired < 0 && applied < 0 && movedTowardTarget)
        } && allPassed

        allPassed = reportEvaluation(name: "upper-clamp",
                                     inputLUFS: -40,
                                     expected: "boost / +12.000 dB limit") { state in
            let decision = state.evaluate(momentaryLoudnessLUFS: -40, isEnabled: true)
            guard case .apply(let desired, let applied) = decision else { return (decision, false) }
            return (decision, approximatelyEqual(desired, VideoAudioNormalizationPolicy.maximumPreampDB)
                    && applied <= VideoAudioNormalizationPolicy.maximumPreampDB)
        } && allPassed

        allPassed = reportEvaluation(name: "lower-clamp",
                                     inputLUFS: -6,
                                     expected: "attenuate / -12.000 dB limit") { state in
            let decision = state.evaluate(momentaryLoudnessLUFS: -6, isEnabled: true)
            guard case .apply(let desired, let applied) = decision else { return (decision, false) }
            return (decision, approximatelyEqual(desired, VideoAudioNormalizationPolicy.minimumPreampDB)
                    && applied >= VideoAudioNormalizationPolicy.minimumPreampDB)
        } && allPassed

        var bypassState = VideoAudioNormalizerState()
        _ = bypassState.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let gainBeforeBypass = bypassState.preampDB
        let bypassDecision = bypassState.evaluate(momentaryLoudnessLUFS: -8, isEnabled: false)
        let bypassPassed = bypassDecision == .bypassed
            && approximatelyEqual(gainBeforeBypass, bypassState.preampDB)
        report(name: "disabled", inputLUFS: -8, expected: "bypass", decision: bypassDecision, passed: bypassPassed)
        allPassed = bypassPassed && allPassed

        var invalidState = VideoAudioNormalizerState()
        _ = invalidState.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let gainBeforeInvalid = invalidState.preampDB
        let invalidDecision = invalidState.evaluate(momentaryLoudnessLUFS: .nan, isEnabled: true)
        let invalidPassed = invalidDecision == .ignoredMeasurement
            && approximatelyEqual(gainBeforeInvalid, invalidState.preampDB)
        report(name: "invalid", inputLUFS: .nan, expected: "ignore", decision: invalidDecision, passed: invalidPassed)
        allPassed = invalidPassed && allPassed

        var first = VideoAudioNormalizerState()
        var second = VideoAudioNormalizerState()
        let firstDecision = first.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let secondDecision = second.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let deterministicPassed = firstDecision == secondDecision && approximatelyEqual(first.preampDB, second.preampDB)
        report(name: "repeat", inputLUFS: -28, expected: "same decision", decision: firstDecision, passed: deterministicPassed)
        allPassed = deterministicPassed && allPassed

        let finalResult = allPassed ? "PASS" : "FAIL"
        print("volume-normalizer verification: \(finalResult)")
        if !allPassed { exit(1) }
    }

    private static func reportEvaluation(
        name: String,
        inputLUFS: Double,
        expected: String,
        evaluate: (inout VideoAudioNormalizerState) -> (VideoAudioNormalizationDecision, Bool)
    ) -> Bool {
        var state = VideoAudioNormalizerState()
        let (decision, passed) = evaluate(&state)
        report(name: name, inputLUFS: inputLUFS, expected: expected, decision: decision, passed: passed)
        return passed
    }

    private static func report(name: String,
                               inputLUFS: Double,
                               expected: String,
                               decision: VideoAudioNormalizationDecision,
                               passed: Bool) {
        let result = passed ? "PASS" : "FAIL"
        print("\(name): input=\(format(inputLUFS)) LUFS expected=\(expected) actual=\(format(decision)) \(result)")
    }

    private static func format(_ decision: VideoAudioNormalizationDecision) -> String {
        switch decision {
        case .bypassed:
            return "bypassed"
        case .ignoredMeasurement:
            return "ignored"
        case .apply(let desired, let applied):
            return "desired=\(format(desired)) dB applied=\(format(applied)) dB"
        }
    }

    private static func format(_ value: Double) -> String {
        value.isFinite ? String(format: "%+.3f", value) : "NaN"
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
