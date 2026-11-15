import XCTest

final class QueuePanelWidthPolicyTests: XCTestCase {

    private let accuracy: CGFloat = 0.0001

    // MARK: - Default width (no custom fraction)

    func testDefaultWidthIsThirtyOnePercentAtTheMinimumWindowWidth() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 980, customFraction: nil), 303.8, accuracy: accuracy)
    }

    func testDefaultWidthIsThirtyOnePercentAtAThousandPoints() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: nil), 310, accuracy: accuracy)
    }

    func testDefaultWidthStopsAtTheCeiling() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 2000, customFraction: nil), 360, accuracy: accuracy)
    }

    func testDefaultWidthKeepsTheFloor() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 800, customFraction: nil), 280, accuracy: accuracy)
    }

    // MARK: - Custom fraction clamping

    func testCustomFractionBelowTheMinimumClampsToTwoHundred() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.1), 200, accuracy: accuracy)
    }

    func testCustomFractionAboveTheMaximumClampsToTheMaximum() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.5), 310, accuracy: accuracy)
    }

    // MARK: - Fraction kept across a window resize

    func testQuarterFractionAtAThousandPointsIsTwoHundredFifty() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: 0.25), 250, accuracy: accuracy)
    }

    func testQuarterFractionInAWideWindowClampsToTheMaximum() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 2000, customFraction: 0.25), 360, accuracy: accuracy)
    }

    func testQuarterFractionInANarrowWindowClampsToTheMinimum() {
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 700, customFraction: 0.25), 200, accuracy: accuracy)
    }

    // MARK: - Drag end → stored fraction

    func testDragEndingAtTheMaximumClearsTheCustomWidth() {
        // W = 1000: maximum 310, so the edge at x = 690 is the default.
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 690, contentWidth: 1000))
    }

    func testDragEndingWithinHalfAPointOfTheMaximumClearsTheCustomWidth() {
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 690.4, contentWidth: 1000))
    }

    func testDragEndingPastTheMaximumClearsTheCustomWidth() {
        XCTAssertNil(QueuePanelWidthPolicy.customFraction(forEdgeX: 500, contentWidth: 1000))
    }

    func testDragPastTheMinimumStoresTheFractionForTwoHundred() {
        let fraction = QueuePanelWidthPolicy.customFraction(forEdgeX: 950, contentWidth: 1000)
        XCTAssertEqual(try XCTUnwrap(fraction), 0.2, accuracy: accuracy)
    }

    func testDragInsideTheLimitsStoresItsOwnFraction() {
        let fraction = QueuePanelWidthPolicy.customFraction(forEdgeX: 750, contentWidth: 1000)
        XCTAssertEqual(try XCTUnwrap(fraction), 0.25, accuracy: accuracy)
        XCTAssertEqual(QueuePanelWidthPolicy.width(contentWidth: 1000, customFraction: fraction), 250, accuracy: accuracy)
    }

    // MARK: - Design system metrics (P54)

    func testMinimumWidthMatchesTheDesignSystemPanelMinimum() {
        XCTAssertEqual(QueuePanelWidthPolicy.minimumWidth, DWBMetrics.queuePanelMinWidth)
        XCTAssertEqual(QueuePanelWidthPolicy.maximumSnapTolerance, 0.5)
    }

    func testTheGrabZoneIsTheEightPointSharedEdge() {
        XCTAssertEqual(QueuePanelWidthPolicy.grabZoneHalfWidth * 2, DWBMetrics.queueDividerHitWidth)
    }

    func testSkimNeverUsesThePlayerFortyFivePercentRule() {
        // The player's max(260, 45%) rule is not imported: skim stays 31% clamped to 280–360.
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 1200), 360, accuracy: accuracy)   // 45% would be 540
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 900), 280, accuracy: accuracy)    // 31% = 279 → floor
        XCTAssertEqual(QueuePanelWidthPolicy.maximumWidth(contentWidth: 980), 303.8, accuracy: accuracy)
    }

    func testInnerWidthSubtractsTheSeparator() {
        // The controller places the page at queueW - 1: a 200 pt outer panel has a 199 pt page.
        XCTAssertEqual(QueuePanelGeometry.innerWidth(forOuterPanelWidth: QueuePanelWidthPolicy.minimumWidth), 199)
        XCTAssertEqual(QueuePanelGeometry.innerWidth(forOuterPanelWidth: 360), 359)
    }
}
