import XCTest

final class VideoAudioNormalizationPolicyTests: XCTestCase {
    func testNormalizationAppliesOnlyToVideoMedia() {
        XCTAssertTrue(VideoAudioNormalizationPolicy.applies(to: .video))
        XCTAssertFalse(VideoAudioNormalizationPolicy.applies(to: .image))
        XCTAssertFalse(VideoAudioNormalizationPolicy.applies(to: .gif))
    }

    func testDesiredGainRejectsSilenceAndBoundsQuietOrLoudMedia() {
        XCTAssertNil(VideoAudioNormalizationPolicy.desiredPreampDB(forMomentaryLoudness: .nan))
        XCTAssertNil(VideoAudioNormalizationPolicy.desiredPreampDB(forMomentaryLoudness: .infinity))
        XCTAssertNil(VideoAudioNormalizationPolicy.desiredPreampDB(forMomentaryLoudness: -70))
        XCTAssertEqual(VideoAudioNormalizationPolicy.desiredPreampDB(forMomentaryLoudness: -40), 12)
        XCTAssertEqual(VideoAudioNormalizationPolicy.desiredPreampDB(forMomentaryLoudness: -8), -10)
    }

    func testNormalizerStateSmoothsGainAndResetPreservesNoExternalState() throws {
        var state = VideoAudioNormalizerState()
        let first = try XCTUnwrap(state.ingest(momentaryLoudnessLUFS: -28))
        XCTAssertEqual(first, 1.8, accuracy: 0.0001)
        XCTAssertEqual(state.preampDB, 1.8, accuracy: 0.0001)
        state.reset()
        XCTAssertEqual(state.preampDB, 0)
    }

    func testEvaluationBoostsQuietInputAndMovesTowardTarget() throws {
        var state = VideoAudioNormalizerState()
        let decision = state.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let applied = try appliedGain(from: decision)
        XCTAssertGreaterThan(applied, 0)
        XCTAssertLessThan(abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - (-28 + applied)),
                          abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - -28))
    }

    func testEvaluationAttenuatesLoudInputAndMovesTowardTarget() throws {
        var state = VideoAudioNormalizerState()
        let decision = state.evaluate(momentaryLoudnessLUFS: -8, isEnabled: true)
        let applied = try appliedGain(from: decision)
        XCTAssertLessThan(applied, 0)
        XCTAssertLessThan(abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - (-8 + applied)),
                          abs(VideoAudioNormalizationPolicy.targetLoudnessLUFS - -8))
    }

    func testEvaluationLeavesTargetLevelUnchangedAndHonorsExactGainLimits() throws {
        var target = VideoAudioNormalizerState()
        XCTAssertEqual(try appliedGain(from: target.evaluate(momentaryLoudnessLUFS: -18, isEnabled: true)),
                       0,
                       accuracy: 0.000_001)

        var quiet = VideoAudioNormalizerState()
        let quietDecision = quiet.evaluate(momentaryLoudnessLUFS: -40, isEnabled: true)
        XCTAssertEqual(try desiredGain(from: quietDecision), VideoAudioNormalizationPolicy.maximumPreampDB)
        XCTAssertLessThanOrEqual(try appliedGain(from: quietDecision), VideoAudioNormalizationPolicy.maximumPreampDB)

        var loud = VideoAudioNormalizerState()
        let loudDecision = loud.evaluate(momentaryLoudnessLUFS: -6, isEnabled: true)
        XCTAssertEqual(try desiredGain(from: loudDecision), VideoAudioNormalizationPolicy.minimumPreampDB)
        XCTAssertGreaterThanOrEqual(try appliedGain(from: loudDecision), VideoAudioNormalizationPolicy.minimumPreampDB)
    }

    func testEvaluationBypassesDisabledAndInvalidMeasurementsWithoutChangingGain() throws {
        var state = VideoAudioNormalizerState()
        _ = state.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let priorGain = state.preampDB

        XCTAssertEqual(state.evaluate(momentaryLoudnessLUFS: -8, isEnabled: false), .bypassed)
        XCTAssertEqual(state.preampDB, priorGain)
        XCTAssertEqual(state.evaluate(momentaryLoudnessLUFS: .nan, isEnabled: true), .ignoredMeasurement)
        XCTAssertEqual(state.preampDB, priorGain)
        XCTAssertEqual(state.evaluate(momentaryLoudnessLUFS: -70, isEnabled: true), .ignoredMeasurement)
        XCTAssertEqual(state.preampDB, priorGain)
    }

    func testRepeatedEvaluationIsDeterministic() {
        var first = VideoAudioNormalizerState()
        var second = VideoAudioNormalizerState()
        let measurements = [-28.0, -8.0, -18.0, -40.0]
        let firstDecisions = measurements.map { first.evaluate(momentaryLoudnessLUFS: $0, isEnabled: true) }
        let secondDecisions = measurements.map { second.evaluate(momentaryLoudnessLUFS: $0, isEnabled: true) }
        XCTAssertEqual(firstDecisions, secondDecisions)
        XCTAssertEqual(first.preampDB, second.preampDB, accuracy: 0.000_001)
    }

    func testNormalizationDecisionIsIndependentOfVideoVolumeAndMutePolicy() throws {
        var normalizedAtAudibleVolume = VideoAudioNormalizerState()
        var normalizedWhileMuted = VideoAudioNormalizerState()
        let audibleDecision = normalizedAtAudibleVolume.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)
        let mutedDecision = normalizedWhileMuted.evaluate(momentaryLoudnessLUFS: -28, isEnabled: true)

        XCTAssertEqual(audibleDecision, mutedDecision)
        XCTAssertEqual(try appliedGain(from: audibleDecision), 1.8, accuracy: 0.000_001)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88,
                                                        muted: false,
                                                        mixMode: .videoAndUploaded,
                                                        backgroundAudioIsActive: true), 88)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88,
                                                        muted: true,
                                                        mixMode: .videoAndUploaded,
                                                        backgroundAudioIsActive: true), 0)
    }

    private func desiredGain(from decision: VideoAudioNormalizationDecision,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> Double {
        guard case .apply(let desired, _) = decision else {
            XCTFail("Expected an applied normalization decision, got \(decision)", file: file, line: line)
            throw NSError(domain: "VideoAudioNormalizationPolicyTests", code: 1)
        }
        return desired
    }

    private func appliedGain(from decision: VideoAudioNormalizationDecision,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> Double {
        guard case .apply(_, let applied) = decision else {
            XCTFail("Expected an applied normalization decision, got \(decision)", file: file, line: line)
            throw NSError(domain: "VideoAudioNormalizationPolicyTests", code: 1)
        }
        return applied
    }
}
