import XCTest

final class DebugLogRetentionBufferTests: XCTestCase {
    func testRetainsEntriesThroughCapacity() {
        var buffer = DebugLogRetentionBuffer<Int>(capacity: 5_000)

        for entry in 1...5_000 { buffer.append(entry) }

        XCTAssertEqual(buffer.count, 5_000)
        XCTAssertEqual(buffer.entries.first, 1)
        XCTAssertEqual(buffer.entries.last, 5_000)
    }

    func testAddingFiveThousandAndFirstEvictsOldestAndRetainsNewest() {
        var buffer = DebugLogRetentionBuffer<Int>(capacity: 5_000)
        for entry in 1...5_001 { buffer.append(entry) }

        XCTAssertEqual(buffer.count, 5_000)
        XCTAssertEqual(buffer.entries.first, 2)
        XCTAssertEqual(buffer.entries.last, 5_001)
    }

    func testClearEmptiesBufferAndPreservesSubsequentOrdering() {
        var buffer = DebugLogRetentionBuffer<Int>(capacity: 5_000)
        buffer.append(1)
        buffer.removeAll()
        buffer.append(2)

        XCTAssertEqual(buffer.entries, [2])
    }
}
