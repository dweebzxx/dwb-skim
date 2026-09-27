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

    // MARK: - Duration scaling & Clip Duration integration (P42)

    func testSegmentDurationsStayWithinConfiguredRandomBounds() {
        let durations: [Double] = [60, 120, 300, 600, 1_800, 3_600, 10_800, 100_000]
        for duration in durations {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: duration,
                                                              skipIntroSeconds: 0,
                                                              positionRandomValues: [0.1, 0.9, 0.3, 0.7, 0.5, 0.2, 0.4, 0.6],
                                                              durationRandomValues: [0, 1, 0.5, 0.25, 0.75, 1, 0.2, 0.8],
                                                              durationMode: .random,
                                                              randomMinimumSeconds: 5,
                                                              randomMaximumSeconds: 15)
            for segment in segments {
                XCTAssertGreaterThanOrEqual(segment.durationSeconds, 5.0 - 0.001)
                XCTAssertLessThanOrEqual(segment.durationSeconds, 15.0 + 0.001)
            }
        }
    }

    func testFixedDurationProducesExactConfiguredDurationWithoutVariation() {
        let fixedDurations: [Double] = [5, 10, 20, 30]
        for fixed in fixedDurations {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 1_200,
                                                              skipIntroSeconds: 0,
                                                              positionRandomValues: [0.1, 0.5, 0.9],
                                                              durationRandomValues: [0.0, 0.5, 1.0],
                                                              durationMode: .fixed,
                                                              fixedDurationSeconds: fixed)
            XCTAssertFalse(segments.isEmpty)
            for segment in segments {
                XCTAssertEqual(segment.durationSeconds, fixed, accuracy: 0.001)
            }
        }
    }

    func testRandomizedDurationInputsProduceVariationWithinConfiguredRange() {
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 3_600,
                                                          skipIntroSeconds: 0,
                                                          positionRandomValues: Array(repeating: 0.5, count: 16),
                                                          durationRandomValues: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0,
                                                                                  0.0, 1.0, 0.0, 1.0, 0.0, 1.0],
                                                          durationMode: .random,
                                                          randomMinimumSeconds: 5,
                                                          randomMaximumSeconds: 15)
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
                                                          durationRandomValues: Array(repeating: 1.0, count: 16),
                                                          durationMode: .fixed,
                                                          fixedDurationSeconds: 10)
        let totalSkimSeconds = segments.reduce(0) { $0 + $1.durationSeconds }
        let maxPossibleSkimSeconds = Double(ProgressiveRandomSkimPlanner.maximumSegmentCount) * 10.0
        XCTAssertLessThanOrEqual(totalSkimSeconds, maxPossibleSkimSeconds + 0.001)
        // Total skim time should be a small fraction of a 4-hour video.
        XCTAssertLessThan(totalSkimSeconds / 14_400, 0.05)
    }

    // MARK: - Safe reduction when usable duration is insufficient

    func testInsufficientUsableDurationReducesSegmentCountRatherThanProducingInvalidPlan() {
        // 30s total, skip-intro eats 27s -> only 3s usable, with 2s floor, exactly enough for one minimal segment.
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                          skipIntroSeconds: 27,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0],
                                                          durationMode: .fixed,
                                                          fixedDurationSeconds: 2.0)
        XCTAssertEqual(segments.count, 1)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 27 - 0.001)
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 30 + 0.001)
        }
    }

    func testUsableDurationTooSmallForEvenOneSegmentProducesEmptyPlanSafely() {
        // 30s total, skip-intro eats 29s -> only 1s usable, less than the 2.0s minimum floor.
        let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                          skipIntroSeconds: 29,
                                                          positionRandomValues: [0],
                                                          durationRandomValues: [0],
                                                          durationMode: .fixed,
                                                          fixedDurationSeconds: 2.0)
        XCTAssertTrue(segments.isEmpty)
    }

    func testExtremelyShortUsableRangeNeverProducesOverlappingOrOutOfRangeSegments() {
        for skipIntro in stride(from: 0.0, through: 28.0, by: 1.0) {
            let segments = ProgressiveRandomSkimPlanner.plan(mediaDurationSeconds: 30,
                                                              skipIntroSeconds: skipIntro,
                                                              positionRandomValues: Array(repeating: 0.9, count: 16),
                                                              durationRandomValues: Array(repeating: 0.9, count: 16),
                                                              durationMode: .fixed,
                                                              fixedDurationSeconds: 2.0)
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

    func testIntensityMultipliersAndDisplayTitles() {
        XCTAssertEqual(ProgressiveRandomSkimIntensity.allCases.count, 5)
        XCTAssertEqual(ProgressiveRandomSkimIntensity.light.segmentCountMultiplier, 0.7)
        XCTAssertEqual(ProgressiveRandomSkimIntensity.standard.segmentCountMultiplier, 1.0)
        XCTAssertEqual(ProgressiveRandomSkimIntensity.thorough.segmentCountMultiplier, 1.5)
        XCTAssertEqual(ProgressiveRandomSkimIntensity.ultra.segmentCountMultiplier, 2.0)
        XCTAssertEqual(ProgressiveRandomSkimIntensity.max.segmentCountMultiplier, 2.5)

        XCTAssertEqual(ProgressiveRandomSkimIntensity.light.displayTitle, "Light")
        XCTAssertEqual(ProgressiveRandomSkimIntensity.standard.displayTitle, "Standard")
        XCTAssertEqual(ProgressiveRandomSkimIntensity.thorough.displayTitle, "Thorough")
        XCTAssertEqual(ProgressiveRandomSkimIntensity.ultra.displayTitle, "Ultra")
        XCTAssertEqual(ProgressiveRandomSkimIntensity.max.displayTitle, "Max")
    }

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

    func testAllFiveIntensitiesScaleCountMonotonically() {
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
            let ultra = plan(.ultra)
            let max = plan(.max)
            XCTAssertLessThanOrEqual(light.count, standard.count,
                                     "Light should never sample more than Standard at duration \(fixture.duration)")
            XCTAssertGreaterThanOrEqual(thorough.count, standard.count,
                                        "Thorough should never sample fewer than Standard at duration \(fixture.duration)")
            XCTAssertGreaterThanOrEqual(ultra.count, thorough.count,
                                        "Ultra should never sample fewer than Thorough at duration \(fixture.duration)")
            XCTAssertGreaterThanOrEqual(max.count, ultra.count,
                                        "Max should never sample fewer than Ultra at duration \(fixture.duration)")
        }
    }

    func testHigherIntensitiesCanExceedOldSixteenSegmentCeiling() {
        let positions = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
        let durations = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)

        // 1-hour media (3,600s): base adaptive count is 12
        let plan3600Thorough = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 3_600,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.thorough.segmentCountMultiplier
        )
        let plan3600Ultra = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 3_600,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.ultra.segmentCountMultiplier
        )
        let plan3600Max = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 3_600,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier
        )
        XCTAssertEqual(plan3600Thorough.count, 18, "Thorough on 3600s video: 12 * 1.5 = 18 segments")
        XCTAssertGreaterThan(plan3600Thorough.count, 16, "Thorough can exceed the old 16 ceiling")
        XCTAssertEqual(plan3600Ultra.count, 24, "Ultra on 3600s video: 12 * 2.0 = 24 segments")
        XCTAssertGreaterThan(plan3600Ultra.count, 16, "Ultra can exceed the old 16 ceiling")
        XCTAssertEqual(plan3600Max.count, 30, "Max on 3600s video: 12 * 2.5 = 30 segments")
        XCTAssertGreaterThan(plan3600Max.count, 16, "Max can exceed the old 16 ceiling")

        // 3-hour media (10,800s): base adaptive count is 14
        let plan10800Ultra = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 10_800,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.ultra.segmentCountMultiplier
        )
        let plan10800Max = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 10_800,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier
        )
        XCTAssertEqual(plan10800Ultra.count, 28, "Ultra on 10800s video: 14 * 2.0 = 28 segments")
        XCTAssertEqual(plan10800Max.count, 35, "Max on 10800s video: 14 * 2.5 = 35 segments")
    }

    func testSegmentCountNeverExceedsCeilingOfForty() {
        XCTAssertEqual(ProgressiveRandomSkimPlanner.maximumSegmentCount, 40)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount, 40)

        let positions = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)
        let durations = Array(repeating: 0.5, count: ProgressiveRandomSkimPlanner.maximumPossibleSegmentCount)

        // 24-hour media (86,400s): base count is 18, 18 * 2.5 = 45 -> clamped to 40
        let plan24hMax = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 86_400,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: durations,
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier
        )
        XCTAssertEqual(plan24hMax.count, 40, "Max on 24h video caps at maximum ceiling 40")

        // Extreme duration: 10,000,000s
        for intensity in ProgressiveRandomSkimIntensity.allCases {
            let extremePlan = ProgressiveRandomSkimPlanner.plan(
                mediaDurationSeconds: 10_000_000,
                skipIntroSeconds: 0,
                positionRandomValues: positions,
                durationRandomValues: durations,
                segmentCountMultiplier: intensity.segmentCountMultiplier
            )
            XCTAssertLessThanOrEqual(extremePlan.count, 40)
        }
    }

    func testAllIntensitiesPreserveAllPlannerInvariants() {
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
                    segmentCountMultiplier: intensity.segmentCountMultiplier,
                    durationMode: .fixed,
                    fixedDurationSeconds: 2.0
                )
                XCTAssertLessThanOrEqual(segments.count, ProgressiveRandomSkimPlanner.maximumSegmentCount,
                                         "\(intensity) at duration \(fixture.duration)")
                for segment in segments {
                    XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, fixture.skipIntro - 0.001)
                    XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, fixture.duration + 0.001)
                    XCTAssertGreaterThanOrEqual(segment.durationSeconds,
                                                ProgressiveRandomSkimPlanner.minimumEffectiveDurationSeconds - 0.001)
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
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 10, multiplier: 2.0), 20)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 10, multiplier: 2.5), 25)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 12, multiplier: 1.5), 18)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 12, multiplier: 2.0), 24)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 12, multiplier: 2.5), 30)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 18, multiplier: 2.5), 40)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: ProgressiveRandomSkimPlanner.maximumSegmentCount, multiplier: 1.5),
                      ProgressiveRandomSkimPlanner.maximumSegmentCount)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: ProgressiveRandomSkimPlanner.maximumSegmentCount, multiplier: 2.5),
                      ProgressiveRandomSkimPlanner.maximumSegmentCount)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 1, multiplier: 0.0), 0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.scaledSegmentCount(baseCount: 1, multiplier: -1), 0)
    }

    // MARK: - P42: Random Duration Mode Tests

    func testRandomModeFiveToFifteenSecondsRemainsWithinBounds() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.1, 0.5, 0.9, 0.2, 0.8],
            durationRandomValues: [0.0, 0.25, 0.5, 0.75, 1.0],
            durationMode: .random,
            randomMinimumSeconds: 5,
            randomMaximumSeconds: 15
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.durationSeconds, 5.0 - 0.001)
            XCTAssertLessThanOrEqual(segment.durationSeconds, 15.0 + 0.001)
        }
    }

    func testRandomModeTenToThirtySecondsRemainsWithinBounds() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 1_200,
            skipIntroSeconds: 0,
            positionRandomValues: [0.2, 0.4, 0.6, 0.8, 0.5],
            durationRandomValues: [0.0, 0.3, 0.5, 0.7, 1.0],
            durationMode: .random,
            randomMinimumSeconds: 10,
            randomMaximumSeconds: 30
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.durationSeconds, 10.0 - 0.001)
            XCTAssertLessThanOrEqual(segment.durationSeconds, 30.0 + 0.001)
        }
    }

    func testRandomModeThirtyToSixtySecondsRemainsWithinBoundsOnSufficientlyLongMedia() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 7_200, // 2 hours
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 16),
            durationRandomValues: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 0.1, 0.9],
            durationMode: .random,
            randomMinimumSeconds: 30,
            randomMaximumSeconds: 60
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.durationSeconds, 30.0 - 0.001)
            XCTAssertLessThanOrEqual(segment.durationSeconds, 60.0 + 0.001)
        }
    }

    func testRandomModeValuesBelowEffectiveFloorAreClampedToTwoSeconds() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 300,
            skipIntroSeconds: 0,
            positionRandomValues: [0.0, 0.5, 1.0],
            durationRandomValues: [0.0, 0.5, 1.0],
            durationMode: .random,
            randomMinimumSeconds: 0,
            randomMaximumSeconds: 1
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertGreaterThanOrEqual(segment.durationSeconds, 2.0 - 0.001)
            // Lower and upper bound both clamp to 2.0s floor, so all durations must be 2.0s
            XCTAssertEqual(segment.durationSeconds, 2.0, accuracy: 0.001)
        }
    }

    func testRandomModeUsesDeterministicTestSeam() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 1_200,
            skipIntroSeconds: 0,
            positionRandomValues: [0.0, 0.0, 0.0],
            durationRandomValues: [0.0, 0.5, 1.0],
            durationMode: .random,
            randomMinimumSeconds: 10,
            randomMaximumSeconds: 20
        )
        XCTAssertGreaterThanOrEqual(segments.count, 3)
        // Uniform inside [10, 20]: 0.0 -> 10.0, 0.5 -> 15.0, 1.0 -> 20.0
        XCTAssertEqual(segments[0].durationSeconds, 10.0, accuracy: 0.001)
        XCTAssertEqual(segments[1].durationSeconds, 15.0, accuracy: 0.001)
        XCTAssertEqual(segments[2].durationSeconds, 20.0, accuracy: 0.001)
    }

    // MARK: - P42: Fixed Duration Mode Tests

    func testFixedModeTenSecondsProducesTenSecondTargets() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.1, 0.5, 0.9],
            durationRandomValues: [0.0, 0.5, 1.0],
            durationMode: .fixed,
            fixedDurationSeconds: 10
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertEqual(segment.durationSeconds, 10.0, accuracy: 0.001)
        }
    }

    func testFixedModeThirtySecondsProducesThirtySecondTargets() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 1_800,
            skipIntroSeconds: 0,
            positionRandomValues: [0.2, 0.7, 0.4],
            durationRandomValues: [0.1, 0.8, 0.3],
            durationMode: .fixed,
            fixedDurationSeconds: 30
        )
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertEqual(segment.durationSeconds, 30.0, accuracy: 0.001)
        }
    }

    func testFixedModeHasNoFlutterOrRandomJitter() {
        let positions = [0.2, 0.4, 0.6, 0.8]
        let planA = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: [0.0, 0.0, 0.0, 0.0],
            durationMode: .fixed,
            fixedDurationSeconds: 15
        )
        let planB = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: positions,
            durationRandomValues: [1.0, 1.0, 1.0, 1.0],
            durationMode: .fixed,
            fixedDurationSeconds: 15
        )
        // Fixed means fixed: durationRandomValues have no effect on durations
        XCTAssertEqual(planA.count, planB.count)
        for (segA, segB) in zip(planA, planB) {
            XCTAssertEqual(segA.durationSeconds, 15.0, accuracy: 0.001)
            XCTAssertEqual(segB.durationSeconds, 15.0, accuracy: 0.001)
            XCTAssertEqual(segA.startOffsetSeconds, segB.startOffsetSeconds, accuracy: 0.001)
        }
    }

    func testFixedModeBoundaryShorteningOnlyWhenRequiredByTimeline() {
        let segments = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 30,
            skipIntroSeconds: 27.5,
            positionRandomValues: [0],
            durationRandomValues: [0],
            durationMode: .fixed,
            fixedDurationSeconds: 2.0
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].durationSeconds, 2.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(segments[0].startOffsetSeconds + segments[0].durationSeconds, 30.0 + 0.001)
    }

    // MARK: - P42: Dynamic Eligibility Tests

    func testDynamicEligibilityThresholdRepresentativeValues() {
        // 5s minimum -> 30s threshold
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(minimumSnippetDuration: 5), 30.0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(
            durationMode: .random, fixedDurationSeconds: 10, randomMinimumSeconds: 5), 30.0)

        // 10s minimum -> 30s threshold
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(minimumSnippetDuration: 10), 30.0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(
            durationMode: .fixed, fixedDurationSeconds: 10, randomMinimumSeconds: 5), 30.0)

        // 30s minimum -> 60s threshold
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(minimumSnippetDuration: 30), 60.0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(
            durationMode: .random, fixedDurationSeconds: 10, randomMinimumSeconds: 30), 60.0)

        // 45s fixed -> 90s threshold
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(minimumSnippetDuration: 45), 90.0)
        XCTAssertEqual(ProgressiveRandomSkimPlanner.eligibilityThresholdSeconds(
            durationMode: .fixed, fixedDurationSeconds: 45, randomMinimumSeconds: 5), 90.0)
    }

    func testDynamicEligibilityRejectsBelowThresholdMediaTriggeringFallback() {
        // 30s minimum snippet requires >= 60s media
        let below60 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 59.9,
            skipIntroSeconds: 0,
            durationMode: .random,
            randomMinimumSeconds: 30,
            randomMaximumSeconds: 60
        )
        XCTAssertTrue(below60.isEmpty, "Media under 60s must be ineligible when snippet minimum is 30s")

        let at60 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 60.0,
            skipIntroSeconds: 0,
            durationMode: .random,
            randomMinimumSeconds: 30,
            randomMaximumSeconds: 60
        )
        XCTAssertFalse(at60.isEmpty, "Media at 60s must be eligible when snippet minimum is 30s")

        // 45s fixed requires >= 90s media
        let below90 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 89.9,
            skipIntroSeconds: 0,
            durationMode: .fixed,
            fixedDurationSeconds: 45
        )
        XCTAssertTrue(below90.isEmpty, "Media under 90s must be ineligible when fixed duration is 45s")

        let at90 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 90.0,
            skipIntroSeconds: 0,
            durationMode: .fixed,
            fixedDurationSeconds: 45
        )
        XCTAssertFalse(at90.isEmpty, "Media at 90s must be eligible when fixed duration is 45s")
    }

    // MARK: - P42: Safe Timeline Fitting Tests

    func testSafeFittingMaxIntensityWithLongSnippetsReducesSegmentCount() {
        // 300s media with Fixed 30s snippets:
        // Base count for 300s is 7. Max multiplier is 2.5 -> requested 18 segments.
        // 18 * 30s = 540s > 300s.
        // Fitting reduces count to 10 (300 / 10 = 30s).
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 300,
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 40),
            durationRandomValues: Array(repeating: 0.5, count: 40),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 30
        )
        XCTAssertEqual(plan.count, 10, "Max requested count 18 must be safely reduced to 10 for 30s snippets on 300s media")
        for segment in plan {
            XCTAssertEqual(segment.durationSeconds, 30.0, accuracy: 0.001)
        }
    }

    func testSafeFittingPreventsDurationDrivenOverlap() {
        // Dense requested count on a tight timeline
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 120,
            skipIntroSeconds: 10, // 110s usable
            positionRandomValues: Array(repeating: 1.0, count: 40), // worst-case position (end of bucket)
            durationRandomValues: Array(repeating: 1.0, count: 40),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 20
        )
        XCTAssertGreaterThan(plan.count, 1)
        for index in 1..<plan.count {
            let prev = plan[index - 1]
            let curr = plan[index]
            XCTAssertGreaterThanOrEqual(curr.startOffsetSeconds,
                                        prev.startOffsetSeconds + prev.durationSeconds - 0.001,
                                        "Segment \(index) must not overlap segment \(index - 1)")
        }
    }

    func testSafeFittingPreservesForwardProgression() {
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 15,
            positionRandomValues: [0.1, 0.9, 0.2, 0.8, 0.3, 0.7],
            durationRandomValues: [0.2, 0.8, 0.3, 0.7, 0.4, 0.6],
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.thorough.segmentCountMultiplier,
            durationMode: .random,
            randomMinimumSeconds: 15,
            randomMaximumSeconds: 25
        )
        XCTAssertGreaterThan(plan.count, 1)
        for index in 1..<plan.count {
            XCTAssertGreaterThan(plan[index].startOffsetSeconds, plan[index - 1].startOffsetSeconds)
        }
    }

    func testSafeFittingPrefersFewerSegmentsOverViolatingMinimumDuration() {
        // When snippets are long (e.g. 40s), count is reduced rather than shrinking snippets below 40s
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 200,
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 20),
            durationRandomValues: Array(repeating: 0.5, count: 20),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.standard.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 40
        )
        XCTAssertGreaterThan(plan.count, 0)
        XCTAssertLessThanOrEqual(plan.count, 5) // 200 / 40 = 5
        for segment in plan {
            XCTAssertGreaterThanOrEqual(segment.durationSeconds, 40.0 - 0.001,
                                        "Snippets must not be shrunken to preserve count")
        }
    }

    func testMediumLengthMediaRemainsValid() {
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 180,
            skipIntroSeconds: 10,
            positionRandomValues: [0.2, 0.5, 0.8],
            durationRandomValues: [0.3, 0.6, 0.9],
            durationMode: .random,
            randomMinimumSeconds: 5,
            randomMaximumSeconds: 15
        )
        XCTAssertFalse(plan.isEmpty)
        for segment in plan {
            XCTAssertGreaterThanOrEqual(segment.startOffsetSeconds, 10.0 - 0.001)
            XCTAssertLessThanOrEqual(segment.startOffsetSeconds + segment.durationSeconds, 180.0 + 0.001)
        }
    }

    func testSufficientlyLongMediaCanStillUseDenseUltraAndMaxPlans() {
        // 2-hour media (7,200s): base count is 13.
        // Ultra: 13 * 2.0 = 26. 7,200 / 26 = 276s >> 10s. No reduction needed.
        // Max: 13 * 2.5 = 33. 7,200 / 33 = 218s >> 10s. No reduction needed.
        let ultraPlan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 7_200,
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 40),
            durationRandomValues: Array(repeating: 0.5, count: 40),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.ultra.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 10
        )
        let maxPlan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 7_200,
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 40),
            durationRandomValues: Array(repeating: 0.5, count: 40),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 10
        )
        XCTAssertEqual(ultraPlan.count, 26, "Ultra produces 26 segments on 2h media with 10s snippets")
        XCTAssertEqual(maxPlan.count, 33, "Max produces 33 segments on 2h media with 10s snippets")
    }

    func testFinalSegmentCountNeverExceedsCeilingOfFortyWithConfiguredDurations() {
        // 24-hour media with Max intensity: base count 18 * 2.5 = 45 -> clamped to 40
        let plan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 86_400,
            skipIntroSeconds: 0,
            positionRandomValues: Array(repeating: 0.5, count: 40),
            durationRandomValues: Array(repeating: 0.5, count: 40),
            segmentCountMultiplier: ProgressiveRandomSkimIntensity.max.segmentCountMultiplier,
            durationMode: .fixed,
            fixedDurationSeconds: 10
        )
        XCTAssertEqual(plan.count, 40)
    }

    // MARK: - P42: Integration & State Propagation Tests

    func testIntegrationClipDurationModeReachesPlanner() {
        let fixedPlan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5, 0.5],
            durationRandomValues: [1.0, 1.0],
            durationMode: .fixed,
            fixedDurationSeconds: 10,
            randomMinimumSeconds: 5,
            randomMaximumSeconds: 25
        )
        let randomPlan = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5, 0.5],
            durationRandomValues: [1.0, 1.0],
            durationMode: .random,
            fixedDurationSeconds: 10,
            randomMinimumSeconds: 5,
            randomMaximumSeconds: 25
        )
        // In fixed mode, duration is 10s. In random mode with random value 1.0, duration is 25s.
        XCTAssertEqual(fixedPlan[0].durationSeconds, 10.0, accuracy: 0.001)
        XCTAssertEqual(randomPlan[0].durationSeconds, 25.0, accuracy: 0.001)
    }

    func testIntegrationTopStripDurationChangesAffectSubsequentPlans() {
        let suite = "com.dwb.skimTests.P42.topStrip"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let store = SkimSettingsStore(defaults: defaults, notificationCenter: NotificationCenter())

        // Initial default: fixed 10s
        let initialSnap = store.snapshot()
        let planInitial = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5],
            durationRandomValues: [0.5],
            durationMode: initialSnap.previewDurationMode == "random" ? .random : .fixed,
            fixedDurationSeconds: Double(initialSnap.fixedDurationSeconds),
            randomMinimumSeconds: Double(initialSnap.randomDurationRange.lowerBound),
            randomMaximumSeconds: Double(initialSnap.randomDurationRange.upperBound)
        )
        XCTAssertEqual(planInitial[0].durationSeconds, 10.0, accuracy: 0.001)

        // User edits top strip: changes fixed duration to 20s
        store.setFixedDurationSeconds(20)
        let updatedSnap = store.snapshot()
        let planUpdated = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5],
            durationRandomValues: [0.5],
            durationMode: updatedSnap.previewDurationMode == "random" ? .random : .fixed,
            fixedDurationSeconds: Double(updatedSnap.fixedDurationSeconds),
            randomMinimumSeconds: Double(updatedSnap.randomDurationRange.lowerBound),
            randomMaximumSeconds: Double(updatedSnap.randomDurationRange.upperBound)
        )
        XCTAssertEqual(planUpdated[0].durationSeconds, 20.0, accuracy: 0.001)
    }

    func testIntegrationExistingDurationControlsRemainMeaningfulDuringProgressiveMode() {
        // Progressive Random Skim enabled: Fixed duration controls segment length
        let plan15 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5],
            durationRandomValues: [0.5],
            durationMode: .fixed,
            fixedDurationSeconds: 15
        )
        let plan25 = ProgressiveRandomSkimPlanner.plan(
            mediaDurationSeconds: 600,
            skipIntroSeconds: 0,
            positionRandomValues: [0.5],
            durationRandomValues: [0.5],
            durationMode: .fixed,
            fixedDurationSeconds: 25
        )
        XCTAssertEqual(plan15[0].durationSeconds, 15.0, accuracy: 0.001)
        XCTAssertEqual(plan25[0].durationSeconds, 25.0, accuracy: 0.001)
    }

    func testIntegrationP41UltraAndMaxBehaviorRemainsIntact() {
        // On 1-hour media (3,600s), base count is 12:
        // Light: 8, Standard: 12, Thorough: 18, Ultra: 24, Max: 30
        let counts = ProgressiveRandomSkimIntensity.allCases.map { intensity in
            ProgressiveRandomSkimPlanner.plan(
                mediaDurationSeconds: 3_600,
                skipIntroSeconds: 0,
                positionRandomValues: Array(repeating: 0.5, count: 40),
                durationRandomValues: Array(repeating: 0.5, count: 40),
                segmentCountMultiplier: intensity.segmentCountMultiplier,
                durationMode: .fixed,
                fixedDurationSeconds: 10
            ).count
        }
        XCTAssertEqual(counts, [8, 12, 18, 24, 30])
    }
}
