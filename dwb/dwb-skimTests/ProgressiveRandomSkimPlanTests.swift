import XCTest

final class ProgressiveRandomSkimPlanTests: XCTestCase {

    // MARK: - Eligibility

    func testUnderThirtySecondsIsIneligible() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 29.999,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: [],
                                                          durationRandomValues: [])
        XCTAssertTrue(segments.isEmpty)
    }

    func testExactlyThirtySecondsIsEligible() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: [0, 0],
                                                          durationRandomValues: [0, 0])
        XCTAssertFalse(segments.isEmpty)
    }

    func testThirtyPlusSecondsIsEligible() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 31,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: [0, 0],
                                                          durationRandomValues: [0, 0])
        XCTAssertFalse(segments.isEmpty)
    }

    func testZeroAndNegativeDurationsAreIneligible() {
        XCTAssertTrue(ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 0,
                                                         skipIntroSeconds: 0,
                                                         positionRandomValues: [],
                                                         durationRandomValues: []).isEmpty)
        XCTAssertTrue(ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: -5,
                                                         skipIntroSeconds: 0,
                                                         positionRandomValues: [],
                                                         durationRandomValues: []).isEmpty)
    }

    // MARK: - Multiple, forward-moving, non-overlapping segments

    func testEligibleVideoWithAmpleDurationProducesMultipleSegments() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                          skipIntroSeconds: 5,
                                                          positionRandomValues: [0.2, 0.5, 0.8, 0.1, 0.9],
                                                          durationRandomValues: [0.3, 0.6, 0.1, 0.9, 0.4])
        XCTAssertGreaterThan(segments.count, 1)
    }

    func testSegmentsAlwaysMoveForwardAndNeverOverlap() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 300,
                                                          skipIntroSeconds: 5,
                                                          positionRandomValues: [1, 1, 1, 1, 1, 1],
                                                          durationRandomValues: [1, 1, 1, 1, 1, 1])
        XCTAssertGreaterThan(segments.count, 1)
        for index in 1..<segments.count {
            let previous = segments[index - 1]
            let current = segments[index]
            XCTAssertGreaterThan(current.startOffsetSeconds, previous.startOffsetSeconds)
            XCTAssertGreaterThanOrEqual(current.startOffsetSeconds,
                                        previous.startOffsetSeconds + previous.durationSeconds)
        }
    }

    func testSegmentsAreDistributedAcrossTheUsableTimelineNotClustered() {
        let duration = 600.0
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: Array(repeating: 0.5, count: 10),
                                                          durationRandomValues: Array(repeating: 0.0, count: 10))
        XCTAssertGreaterThan(segments.count, 2)
        // Segments should collectively span a meaningful majority of the usable timeline rather
        // than clustering near one end of it.
        let firstStart = segments.first!.startOffsetSeconds
        let lastEnd = segments.last!.startOffsetSeconds + segments.last!.durationSeconds
        XCTAssertGreaterThanOrEqual(lastEnd - firstStart, duration * 0.5)
        // No single gap between consecutive segments should swallow most of the timeline.
        for index in 1..<segments.count {
            let gap = segments[index].startOffsetSeconds
                - (segments[index - 1].startOffsetSeconds + segments[index - 1].durationSeconds)
            XCTAssertLessThan(gap, duration * 0.5)
        }
    }

    func testEarlyMiddleAndLateRegionsAllReceiveSamplingOpportunities() {
        let duration = 1_800.0
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: Array(repeating: 0.5, count: 16),
                                                          durationRandomValues: Array(repeating: 0.5, count: 16))
        XCTAssertFalse(segments.isEmpty)
        let earlyBound = duration / 3
        let lateBound = duration * 2 / 3
        XCTAssertTrue(segments.contains { $0.startOffsetSeconds < earlyBound })
        XCTAssertTrue(segments.contains { $0.startOffsetSeconds >= earlyBound && $0.startOffsetSeconds < lateBound })
        XCTAssertTrue(segments.contains { $0.startOffsetSeconds >= lateBound })
    }

    // MARK: - Skip Intro

    func testFirstSegmentNeverStartsBeforeSkipIntro() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 120,
                                                          skipIntroSeconds: 20,
                                                          positionRandomValues: [0, 0, 0],
                                                          durationRandomValues: [0, 0, 0])
        XCTAssertFalse(segments.isEmpty)
        XCTAssertGreaterThanOrEqual(segments[0].startOffsetSeconds, 20 - 0.001)
    }

    func testNegativeSkipIntroIsTreatedAsZero() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 60,
                                                          skipIntroSeconds: -5,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0])
        XCTAssertFalse(segments.isEmpty)
        XCTAssertGreaterThanOrEqual(segments[0].startOffsetSeconds, 0)
    }

    func testLargeSkipIntroReducesUsableSamplingSpace() {
        // 600s media, 500s skip intro -> only 100s usable, well under the full-duration target.
        let fullyUsable = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                             skipIntroSeconds: 0,
                                                             positionRandomValues: Array(repeating: 0.5, count: 16),
                                                             durationRandomValues: Array(repeating: 0.5, count: 16))
        let heavySkipIntro = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                                skipIntroSeconds: 500,
                                                                positionRandomValues: Array(repeating: 0.5, count: 16),
                                                                durationRandomValues: Array(repeating: 0.5, count: 16))
        XCTAssertFalse(heavySkipIntro.isEmpty)
        XCTAssertLessThan(heavySkipIntro.count, fullyUsable.count)
        for segment in heavySkipIntro {
            XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 500 - 0.001)
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 600 + 0.001)
        }
    }

    func testSkipIntroEqualToDurationProducesEmptyPlan() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 120,
                                                          skipIntroSeconds: 120,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0])
        XCTAssertTrue(segments.isEmpty)
    }

    func testSkipIntroGreaterThanDurationProducesEmptyPlanSafely() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 120,
                                                          skipIntroSeconds: 500,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0])
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - No segment exceeds the playable range

    func testNoSegmentExtendsPastMediaDuration() {
        let duration = 245.0
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                          skipIntroSeconds: 3,
                                                          positionRandomValues: [1, 1, 1, 1, 1, 1],
                                                          durationRandomValues: [1, 1, 1, 1, 1, 1])
        for segment in segments {
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, duration + 0.001)
        }
    }

    // MARK: - Adaptive count scaling

    func testAdaptiveSegmentCountIncreasesWithUsableDuration() {
        let durations: [Double] = [30, 45, 60, 120, 300, 600, 1_800, 3_600, 10_800]
        var previousCount = 0
        for duration in durations {
            let count = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: duration)
            XCTAssertGreaterThanOrEqual(count, previousCount, "count should never decrease as duration grows")
            previousCount = count
        }
    }

    func testAdaptiveSegmentCountGrowthHasDiminishingReturns() {
        // Doubling from a small base should add strictly more new segments than doubling again from
        // an already-large base — i.e. growth slows down, it doesn't stay linear.
        let c30 = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: 60)
        let c60 = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: 120)
        let c1800 = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: 1_800)
        let c3600 = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: 3_600)
        let earlyGrowth = c60 - c30
        let lateGrowth = c3600 - c1800
        XCTAssertGreaterThanOrEqual(earlyGrowth, lateGrowth)
    }

    func testAdaptiveSegmentCountNeverExceedsMaximum() {
        let durations: [Double] = [3_600, 10_800, 86_400, 1_000_000]
        for duration in durations {
            let count = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: duration)
            XCTAssertLessThanOrEqual(count, ProgressiveRandomSkimPlanner.maximumSegmentCount)
        }
    }

    func testVeryShortEligibleVideosReceiveOnlyAFewSegments() {
        let count = ProgressiveRandomSkimPlanner.adaptiveSegmentCount(forUsableDurationSeconds: 30)
        XCTAssertEqual(count, ProgressiveRandomSkimPlanner.minimumSegmentCount)
    }

    func testMediumVideosReceiveNoticeablyMoreSegmentsThanShortOnes() {
        let short = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 45,
                                                       skipIntroSeconds: 0,
                                                       positionRandomValues: Array(repeating: 0.5, count: 16),
                                                       durationRandomValues: Array(repeating: 0.5, count: 16))
        let medium = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 300,
                                                        skipIntroSeconds: 0,
                                                        positionRandomValues: Array(repeating: 0.5, count: 16),
                                                        durationRandomValues: Array(repeating: 0.5, count: 16))
        let long = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 3_600,
                                                      skipIntroSeconds: 0,
                                                      positionRandomValues: Array(repeating: 0.5, count: 16),
                                                      durationRandomValues: Array(repeating: 0.5, count: 16))
        XCTAssertLessThan(short.count, medium.count)
        XCTAssertLessThan(medium.count, long.count)
    }

    // MARK: - Adaptive duration scaling

    func testSegmentDurationsStayWithinGlobalBoundsAcrossManyDurations() {
        let durations: [Double] = [30, 60, 120, 300, 600, 1_800, 3_600, 10_800, 100_000]
        for duration in durations {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                              skipIntroSeconds: 0,
                                                              positionRandomValues: [0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.4, 0.6],
                                                              durationRandomValues: [0, 1, 0.5, 0.25, 0.75, 1, 0.2, 0.8])
            for segment in segments {
                XCTAssertGreaterThanOrEqual(segment.durationSeconds,
                                            ProgressiveRandomSkimPlanner.minimumSegmentDurationSeconds - 0.001)
                XCTAssertLessThanOrEqual(segment.durationSeconds,
                                         ProgressiveRandomSkimPlanner.maximumSegmentDurationSeconds + 0.001)
            }
        }
    }

    func testTargetSegmentDurationIncreasesWithUsableDurationButStaysBounded() {
        let short = ProgressiveRandomSkimPlanner.targetSegmentDuration(forUsableDurationSeconds: 30)
        let medium = ProgressiveRandomSkimPlanner.targetSegmentDuration(forUsableDurationSeconds: 600)
        let long = ProgressiveRandomSkimPlanner.targetSegmentDuration(forUsableDurationSeconds: 100_000)
        XCTAssertLessThan(short, medium)
        XCTAssertLessThanOrEqual(medium, long)
        XCTAssertLessThanOrEqual(long, ProgressiveRandomSkimPlanner.maximumSegmentDurationSeconds)
        XCTAssertGreaterThanOrEqual(short, ProgressiveRandomSkimPlanner.minimumSegmentDurationSeconds)
    }

    func testRandomizedDurationInputsProduceVariationWithinASinglePlan() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 3_600,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: Array(repeating: 0.5, count: 16),
                                                          durationRandomValues: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0,
                                                                                  0.0, 1.0, 0.0, 1.0, 0.0, 1.0])
        let distinctDurations = Set(segments.map { ($0.durationSeconds * 100).rounded() })
        XCTAssertGreaterThan(distinctDurations.count, 1)
    }

    func testDeterministicRandomInputsProduceDeterministicDurations() {
        let positions = Array(repeating: 0.5, count: 8)
        let durations = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
        let first = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 900,
                                                       skipIntroSeconds: 10,
                                                       positionRandomValues: positions,
                                                       durationRandomValues: durations)
        let second = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 900,
                                                        skipIntroSeconds: 10,
                                                        positionRandomValues: positions,
                                                        durationRandomValues: durations)
        XCTAssertEqual(first, second)
    }

    // MARK: - Very long videos

    func testVeryLongVideosAcrossASpanOfDurationsProduceValidGrowingPlans() {
        let durations: [Double] = [30, 50, 120, 300, 600, 1_800, 3_600, 14_400]
        var previousCount = 0
        var previousCoverage = 0.0
        for duration in durations {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                              skipIntroSeconds: 0,
                                                              positionRandomValues: Array(repeating: 0.5, count: 16),
                                                              durationRandomValues: Array(repeating: 0.5, count: 16))
            XCTAssertFalse(segments.isEmpty, "duration \(duration) should be eligible")
            XCTAssertGreaterThanOrEqual(segments.count, previousCount)
            let coverage = (segments.last!.startOffsetSeconds + segments.last!.durationSeconds)
                - segments.first!.startOffsetSeconds
            XCTAssertGreaterThanOrEqual(coverage, previousCoverage)
            for segment in segments {
                XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 0)
                XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, duration + 0.001)
            }
            previousCount = segments.count
            previousCoverage = coverage
        }
    }

    func testTotalSkimTimeStaysBoundedRelativeToVideoDurationForVeryLongVideos() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 14_400, // 4 hours
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: Array(repeating: 0.5, count: 16),
                                                          durationRandomValues: Array(repeating: 1.0, count: 16))
        let totalSkimSeconds = segments.reduce(0) { $0 + $1.durationSeconds }
        let maxPossibleSkimSeconds = Double(ProgressiveRandomSkimPlanner.maximumSegmentCount)
            * ProgressiveRandomSkimPlanner.maximumSegmentDurationSeconds
        XCTAssertLessThanOrEqual(totalSkimSeconds, maxPossibleSkimSeconds + 0.001)
        // Total skim time should be a small fraction of a 4-hour video.
        XCTAssertLessThan(totalSkimSeconds / 14_400, 0.05)
    }

    // MARK: - Safe reduction when usable duration is insufficient

    func testInsufficientUsableDurationReducesSegmentCountRatherThanProducingInvalidPlan() {
        // 30s total, skip-intro eats 27s -> only 3s usable, far too little for the adaptive count but
        // exactly enough for one minimal segment.
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                          skipIntroSeconds: 27,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0])
        XCTAssertLessThanOrEqual(segments.count, 1)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 27 - 0.001)
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 30 + 0.001)
        }
    }

    func testUsableDurationTooSmallForEvenOneSegmentProducesEmptyPlanSafely() {
        // 30s total, skip-intro eats 29s -> only 1s usable, less than the 2.5s minimum segment.
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                          skipIntroSeconds: 29,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0])
        XCTAssertTrue(segments.isEmpty)
    }

    func testExtremelyShortUsableRangeNeverProducesOverlappingOrOutOfRangeSegments() {
        for skipIntro in stride(from: 0.0, through: 29.0, by: 1.0) {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                              skipIntroSeconds: skipIntro,
                                                              positionRandomValues: Array(repeating: 0.9, count: 16),
                                                              durationRandomValues: Array(repeating: 0.9, count: 16))
            for segment in segments {
                XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, skipIntro - 0.001)
                XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 30 + 0.001)
            }
            for index in 1..<max(segments.count, 1) where segments.count > 1 {
                XCTAssertGreaterThanOrEqual(segments[index].startOffsetSeconds,
                                            segments[index - 1].startOffsetSeconds + segments[index - 1].durationSeconds)
            }
        }
    }

    func testMissingRandomValuesDefaultToZeroRatherThanCrashing() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 300,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: [],
                                                          durationRandomValues: [])
        XCTAssertFalse(segments.isEmpty)
    }

    func testOutOfRangeRandomValuesAreClamped() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 300,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: [-5, 5, -1, 2],
                                                          durationRandomValues: [-5, 5, -1, 2])
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 0)
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 300 + 0.001)
        }
    }

    func testDifferentRandomInputsCanProduceDifferentValidPlans() {
        let planA = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                       skipIntroSeconds: 0,
                                                       positionRandomValues: Array(repeating: 0.1, count: 10),
                                                       durationRandomValues: Array(repeating: 0.1, count: 10))
        let planB = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                       skipIntroSeconds: 0,
                                                       positionRandomValues: Array(repeating: 0.9, count: 10),
                                                       durationRandomValues: Array(repeating: 0.9, count: 10))
        XCTAssertNotEqual(planA, planB)
        for plan in [planA, planB] {
            for segment in plan {
                XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 0)
                XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 600 + 0.001)
            }
        }
    }

    // MARK: - Part 4: coverage intensity

    private static let intensityFixtures: [(duration: Double, skipIntro: Double)] = [
        (30, 0), (45, 0), (60, 5), (120, 10), (300, 0), (600, 5), (1_800, 0), (3_600, 60), (10_800, 0),
    ]

    func testStandardIntensityMultiplierIsByteIdenticalToUnscaledPlan() {
        for fixture in Self.intensityFixtures {
            let positions = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
            let durations = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
            let unscaled = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: fixture.duration,
                                                              skipIntroSeconds: fixture.skipIntro,
                                                              positionRandomValues: positions,
                                                              durationRandomValues: durations)
            let standard = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: fixture.duration,
                                                              skipIntroSeconds: fixture.skipIntro,
                                                              positionRandomValues: positions,
                                                              durationRandomValues: durations,
                                                              segmentCountMultiplier: ProgressiveRandomSkimIntensity.standard.segmentCountMultiplier)
            XCTAssertEqual(unscaled, standard, "duration \(fixture.duration) skipIntro \(fixture.skipIntro)")
        }
    }

    func testLightAndThoroughScaleCountRelativeToStandard() {
        for fixture in Self.intensityFixtures {
            let positions = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
            let durations = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
            func plan(_ intensity: ProgressiveRandomSkimIntensity) -> [ProgressiveRandomSkimSegment] {
                ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: fixture.duration,
                                                  skipIntroSeconds: fixture.skipIntro,
                                                  positionRandomValues: positions,
                                                  durationRandomValues: durations,
                                                  segmentCountMultiplier: intensity.segmentCountMultiplier)
            }
            let light = plan(.light)
            let standard = plan(.standard)
            let thorough = plan(.thorough)
            XCTAssertLessThanOrEqual(light.count, standard.count,
                                     "Light should never sample more than Standard at duration \(fixture.duration)")
            XCTAssertGreaterThanOrEqual(thorough.count, standard.count,
                                        "Thorough should never sample fewer than Standard at duration \(fixture.duration)")
        }
    }

    func testLightAndThoroughPreserveAllPlannerInvariants() {
        let edgeCases: [(duration: Double, skipIntro: Double)] = [
            (30, 0), (30, 27), (31, 0), (14_400, 0), (14_400, 14_000), (100_000, 90_000),
        ]
        for fixture in edgeCases {
            for intensity in ProgressiveRandomSkimIntensity.allCases {
                let segments = ProgressiveRandomSkimPlanner.plan(
                    mediaDurationSeconds: fixture.duration,
                    skipIntroSeconds: fixture.skipIntro,
                    positionRandomValues: Array(repeating: 0.7, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount),
                    durationRandomValues: Array(repeating: 0.7, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount),
                    segmentCountMultiplier: intensity.segmentCountMultiplier
                )
                XCTAssertLessThanOrEqual(segments.count, ProgressiveRandomSkimPlanner.maximumSegmentCount,
                                         "\(intensity) at duration \(fixture.duration)")
                for segment in segments {
                    XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, fixture.skipIntro - 0.001)
                    XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, fixture.duration + 0.001)
                    XCTAssertGreaterThanOrEqual(segment.durationSeconds,
                                                ProgressiveRandomSkimPlanner.minimumSegmentDurationSeconds - 0.001)
                    XCTAssertLessThanOrEqual(segment.durationSeconds,
                                             ProgressiveRandomSkimPlanner.maximumSegmentDurationSeconds + 0.001)
                }
                for index in 1..<max(segments.count, 1) where segments.count > 1 {
                    XCTAssertGreaterThanOrEqual(segments[index].startOffsetSeconds,
                                                segments[index - 1].startOffsetSeconds + segments[index - 1].durationSeconds)
                }
            }
        }
    }

    func testInvalidMultiplierSafelyReducesToEmptyPlanRatherThanCrashing() {
        for multiplier in [0.0, -1.0, Double.nan, Double.infinity] {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 600,
                                                              skipIntroSeconds: 0,
                                                              positionRandomValues: [0.5],
                                                              durationRandomValues: [0.5],
                                                              segmentCountMultiplier: multiplier)
            if multiplier <= 0 || multiplier.isNaN {
                XCTAssertTrue(segments.isEmpty, "multiplier \(multiplier) should safely produce an empty plan")
            }
        }
    }

    func testScaledSegmentCountClampsToValidRange() {
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 10, multiplier: 1.0), 10)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 10, multiplier: 0.7), 7)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 10, multiplier: 1.5), 15)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: ProgressiveRandomSkimPlanner.maximumSegmentCount, multiplier: 1.5),
                      ProgressiveRandomSkimPlanner.maximumSegmentCount)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 1, multiplier: 0.0), 0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 1, multiplier: -1), 0)
    }
}
