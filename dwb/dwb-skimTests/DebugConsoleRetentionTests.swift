import XCTest

final class DebugConsoleRetentionTests: XCTestCase {

    private var clock = 0

    private func entry(_ message: String,
                       level: DebugLevel = .info,
                       category: String = "playback") -> DebugLogEntry {
        clock += 1
        return DebugLogEntry(date: Date(timeIntervalSince1970: TimeInterval(clock)),
                             level: level, category: category, message: message)
    }

    private func messages(_ entries: [DebugLogEntry]) -> [String] { entries.map(\.message) }

    // MARK: - Console off

    func testOffKeeps400InfoLinesAndThe401stPushesOutTheOldest() {
        var retention = DebugConsoleRetention()
        for n in 1...400 { retention.store(entry("i\(n)"), isConsoleEnabled: false) }
        XCTAssertEqual(retention.pendingContextEntries.count, 400)
        XCTAssertEqual(retention.pendingContextEntries.first?.message, "i1")

        retention.store(entry("i401"), isConsoleEnabled: false)
        XCTAssertEqual(retention.pendingContextEntries.count, 400)
        XCTAssertEqual(retention.pendingContextEntries.first?.message, "i2")
        XCTAssertEqual(retention.pendingContextEntries.last?.message, "i401")
        XCTAssertTrue(retention.entries.isEmpty, "Info lines stay out of the main buffer while off")
    }

    func testOffInfoLineReportsMainBufferUnchanged() {
        var retention = DebugConsoleRetention()
        XCTAssertFalse(retention.store(entry("quiet"), isConsoleEnabled: false))
        XCTAssertTrue(retention.store(entry("loud", level: .warning), isConsoleEnabled: false))
    }

    func testWarningFlushesAll400ContextLinesThenItselfInTimeOrder() {
        var retention = DebugConsoleRetention()
        for n in 1...450 { retention.store(entry("i\(n)"), isConsoleEnabled: false) }
        retention.store(entry("warn", level: .warning), isConsoleEnabled: false)

        let expected = (51...450).map { "i\($0)" } + ["warn"]
        XCTAssertEqual(messages(retention.entries), expected)
        XCTAssertTrue(retention.pendingContextEntries.isEmpty)
    }

    func testErrorFlushesContextThenItself() {
        var retention = DebugConsoleRetention()
        for n in 1...400 { retention.store(entry("i\(n)"), isConsoleEnabled: false) }
        retention.store(entry("boom", level: .error), isConsoleEnabled: false)

        XCTAssertEqual(messages(retention.entries), (1...400).map { "i\($0)" } + ["boom"])
        XCTAssertTrue(retention.pendingContextEntries.isEmpty)
    }

    func testNoLineIsStoredTwiceAcrossTwoWarnings() {
        var retention = DebugConsoleRetention()
        retention.store(entry("a"), isConsoleEnabled: false)
        retention.store(entry("w1", level: .warning), isConsoleEnabled: false)
        retention.store(entry("b"), isConsoleEnabled: false)
        retention.store(entry("c"), isConsoleEnabled: false)
        retention.store(entry("w2", level: .warning), isConsoleEnabled: false)

        XCTAssertEqual(messages(retention.entries), ["a", "w1", "b", "c", "w2"])
    }

    func testOnlyTheNewestContextBeforeASecondWarningIsKept() {
        var retention = DebugConsoleRetention()
        for n in 1...5 { retention.store(entry("old\(n)"), isConsoleEnabled: false) }
        retention.store(entry("w1", level: .warning), isConsoleEnabled: false)
        for n in 1...500 { retention.store(entry("new\(n)"), isConsoleEnabled: false) }
        retention.store(entry("w2", level: .warning), isConsoleEnabled: false)

        let all = messages(retention.entries)
        XCTAssertEqual(all.prefix(6), ["old1", "old2", "old3", "old4", "old5", "w1"])
        XCTAssertEqual(all.count, 6 + 400 + 1)
        XCTAssertEqual(all.last, "w2")
        XCTAssertEqual(all[6], "new101")
    }

    // MARK: - queue-geometry

    func testQueueGeometryInfoIsNeverKeptAsContext() {
        var retention = DebugConsoleRetention()
        retention.store(entry("keep"), isConsoleEnabled: false)
        for n in 1...50 {
            retention.store(entry("geo\(n)", category: "queue-geometry"), isConsoleEnabled: false)
        }
        retention.store(entry("w", level: .warning), isConsoleEnabled: false)

        XCTAssertEqual(messages(retention.entries), ["keep", "w"])
    }

    func testQueueGeometryInfoDoesNotPushOutRealContext() {
        var retention = DebugConsoleRetention()
        for n in 1...400 { retention.store(entry("i\(n)"), isConsoleEnabled: false) }
        for n in 1...1_000 {
            retention.store(entry("geo\(n)", category: "queue-geometry"), isConsoleEnabled: false)
        }
        XCTAssertEqual(retention.pendingContextEntries.count, 400)
        XCTAssertEqual(retention.pendingContextEntries.first?.message, "i1")
    }

    func testQueueGeometryWarningIsKeptLikeAnyWarning() {
        var retention = DebugConsoleRetention()
        retention.store(entry("before"), isConsoleEnabled: false)
        retention.store(entry("geo warn", level: .warning, category: "queue-geometry"),
                        isConsoleEnabled: false)
        retention.store(entry("geo err", level: .error, category: "queue-geometry"),
                        isConsoleEnabled: false)

        XCTAssertEqual(messages(retention.entries), ["before", "geo warn", "geo err"])
    }

    func testQueueGeometryInfoIsKeptWhileOn() {
        var retention = DebugConsoleRetention()
        retention.store(entry("geo", category: "queue-geometry"), isConsoleEnabled: true)
        XCTAssertEqual(messages(retention.entries), ["geo"])
    }

    // MARK: - Turning on, off, and clearing

    func testTurningOnMovesContextIntoMainBufferInOrder() {
        var retention = DebugConsoleRetention()
        for n in 1...3 { retention.store(entry("i\(n)"), isConsoleEnabled: false) }
        retention.flushContext()

        XCTAssertEqual(messages(retention.entries), ["i1", "i2", "i3"])
        XCTAssertTrue(retention.pendingContextEntries.isEmpty)
    }

    func testTurningOnTwiceDoesNotDuplicateLines() {
        var retention = DebugConsoleRetention()
        retention.store(entry("i1"), isConsoleEnabled: false)
        retention.flushContext()
        retention.flushContext()
        XCTAssertEqual(messages(retention.entries), ["i1"])
    }

    func testTurningOffClearsNothing() {
        var retention = DebugConsoleRetention()
        retention.store(entry("on1"), isConsoleEnabled: true)
        retention.store(entry("on2"), isConsoleEnabled: true)
        // Turning the console off changes how new lines are stored; it has no clearing call.
        retention.store(entry("off-info"), isConsoleEnabled: false)

        XCTAssertEqual(messages(retention.entries), ["on1", "on2"])
        XCTAssertEqual(messages(retention.pendingContextEntries), ["off-info"])
    }

    func testClearEmptiesBothMainBufferAndContext() {
        var retention = DebugConsoleRetention()
        retention.store(entry("main"), isConsoleEnabled: true)
        retention.store(entry("ctx"), isConsoleEnabled: false)
        retention.removeAll()

        XCTAssertTrue(retention.entries.isEmpty)
        XCTAssertTrue(retention.pendingContextEntries.isEmpty)

        retention.store(entry("w", level: .warning), isConsoleEnabled: false)
        XCTAssertEqual(messages(retention.entries), ["w"], "Cleared context must not come back")
    }

    // MARK: - Console on

    func testOnInfoLinesGoStraightToMainBuffer() {
        var retention = DebugConsoleRetention()
        XCTAssertTrue(retention.store(entry("i1"), isConsoleEnabled: true))
        XCTAssertEqual(messages(retention.entries), ["i1"])
        XCTAssertTrue(retention.pendingContextEntries.isEmpty)
    }

    func testOnMainBufferStillCapsAt5000() {
        var retention = DebugConsoleRetention()
        for n in 1...5_001 { retention.store(entry("l\(n)"), isConsoleEnabled: true) }

        XCTAssertEqual(retention.entries.count, 5_000)
        XCTAssertEqual(retention.entries.first?.message, "l2")
        XCTAssertEqual(retention.entries.last?.message, "l5001")
    }

    func testCategoriesComeFromStoredLinesSorted() {
        var retention = DebugConsoleRetention()
        retention.store(entry("a", category: "playback"), isConsoleEnabled: false)
        retention.store(entry("b", category: "media"), isConsoleEnabled: false)
        XCTAssertTrue(retention.categories.isEmpty, "Context-only lines are not stored yet")

        retention.flushContext()
        retention.store(entry("c", category: "console"), isConsoleEnabled: true)
        XCTAssertEqual(retention.categories, ["console", "media", "playback"])
    }
}
