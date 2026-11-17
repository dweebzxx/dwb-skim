import XCTest

final class DWBPopoverGeometryTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 300, height: 200)

    func testOpensBelowTheAnchorEightPointsAwayAndOverhangsItByFourteen() {
        let anchor = CGRect(x: 800, y: 600, width: 24, height: 24)
        let placement = DWBPopoverGeometry.place(anchor: anchor, size: size, visibleFrame: visible)
        XCTAssertTrue(placement.arrowOnTop)
        XCTAssertEqual(placement.bodyFrame.maxY, anchor.minY - 8, accuracy: 0.001)
        XCTAssertEqual(placement.bodyFrame.maxX, anchor.maxX + 14, accuracy: 0.001)
        XCTAssertEqual(placement.bodyFrame.size, size)
    }

    func testTheArrowPointsAtTheAnchorCenterTwentySixPointsInFromTheTrailingEdge() {
        let anchor = CGRect(x: 800, y: 600, width: 24, height: 24)
        let placement = DWBPopoverGeometry.place(anchor: anchor, size: size, visibleFrame: visible)
        XCTAssertEqual(placement.arrowCenterX, anchor.midX, accuracy: 0.001)
        XCTAssertEqual(placement.bodyFrame.maxX - placement.arrowCenterX, 26, accuracy: 0.001)
    }

    func testOpensAboveWhenThereIsNoRoomBelow() {
        let anchor = CGRect(x: 800, y: 60, width: 24, height: 24)
        let placement = DWBPopoverGeometry.place(anchor: anchor, size: size, visibleFrame: visible)
        XCTAssertFalse(placement.arrowOnTop)
        XCTAssertEqual(placement.bodyFrame.minY, anchor.maxY + 8, accuracy: 0.001)
    }

    func testStaysOnTheScreenAndKeepsTheArrowInsideThePanel() {
        let anchor = CGRect(x: 1416, y: 600, width: 24, height: 24)
        let placement = DWBPopoverGeometry.place(anchor: anchor, size: size, visibleFrame: visible)
        XCTAssertEqual(placement.bodyFrame.maxX, 1440 - 8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(placement.bodyFrame.maxX - placement.arrowCenterX,
                                    DWBPopoverGeometry.radius + DWBPopoverGeometry.arrowRise)
        // Pushed in from the screen edge, the arrow stops short of the corner instead of leaving the panel.
        XCTAssertLessThanOrEqual(placement.arrowCenterX, placement.bodyFrame.maxX - 18)
    }

    func testPanelMetricsAreTheDesignSystemValues() {
        XCTAssertEqual(DWBPopoverGeometry.radius, 10)
        XCTAssertEqual(DWBPopoverGeometry.inset, 14)
        XCTAssertEqual(DWBPopoverGeometry.groupGap, 14)
        XCTAssertEqual(DWBPopoverGeometry.anchorOffset, 8)
    }
}
