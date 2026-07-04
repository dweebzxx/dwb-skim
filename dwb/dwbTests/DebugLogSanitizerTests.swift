import Foundation
import XCTest

final class DebugLogSanitizerTests: XCTestCase {

    // MARK: - Non-sensitive lines are preserved

    func testNonSensitiveLinesArePreserved() {
        let input = "[14:23:01.000] [queue] add: count=3 wasEmpty=true"
        XCTAssertEqual(DebugLogSanitizer().sanitize(input), input)
    }

    func testTimestampsAndLevelsArePreserved() {
        let input = "[14:23:01.000] [WARN] [rename] customPrefix: noop (empty prefix) source=videoPage"
        XCTAssertEqual(DebugLogSanitizer().sanitize(input), input)
    }

    func testMultipleSafeLinesArePreservedUnchanged() {
        let lines = [
            "[14:23:01.000] [playback] next: source=nextButton",
            "[14:23:02.000] [queue] add: count=5 wasEmpty=false",
            "[14:23:03.000] [window] keepAtTop: false",
        ]
        let input = lines.joined(separator: "\n")
        XCTAssertEqual(DebugLogSanitizer().sanitize(input), input)
    }

    // MARK: - Full path redaction

    func testFullUserPathIsRedacted() {
        let input = "[14:23:01.000] [rename] customPrefix: /Users/alice/Movies/clip.mp4 → done_clip.mp4"
        let result = DebugLogSanitizer().sanitize(input)
        XCTAssertFalse(result.contains("/Users/alice"), "User home path should be redacted")
        XCTAssertTrue(result.contains("[PATH]/clip.mp4"), "Last path component should be preserved")
    }

    func testVolumePathIsRedacted() {
        let input = "[14:23:01.000] [media] file=/Volumes/MyDrive/Media/song.mp3"
        let result = DebugLogSanitizer().sanitize(input)
        XCTAssertFalse(result.contains("/Volumes/MyDrive"), "Volume path should be redacted")
        XCTAssertTrue(result.contains("[PATH]/song.mp3"), "Filename should be preserved")
    }

    func testPrivateTmpPathIsRedacted() {
        let input = "[14:23:01.000] [err ] error: /private/tmp/test.mp4 missing"
        let result = DebugLogSanitizer().sanitize(input)
        XCTAssertFalse(result.contains("/private/tmp"), "Private tmp path should be redacted")
        XCTAssertTrue(result.contains("[PATH]/test.mp4"), "Filename should be preserved")
    }

    func testPathRedactionPreservesLogStructureAround() {
        let input = "[14:23:01.000] [rename] missing source: /Users/bob/clip.mp4"
        let result = DebugLogSanitizer().sanitize(input)
        XCTAssertTrue(result.hasPrefix("[14:23:01.000] [rename] missing source: "),
                      "Log prefix should be unchanged")
        XCTAssertTrue(result.contains("[PATH]/clip.mp4"), "Filename should be preserved")
    }

    // MARK: - Prefix redaction

    func testConfiguredPrimaryPrefixIsRedacted() {
        let input = "[14:23:01.000] [settings] customPrefixValue='x_'"
        let result = DebugLogSanitizer(prefixesToRedact: ["x_"]).sanitize(input)
        XCTAssertFalse(result.contains("x_"), "Prefix value should be redacted")
        XCTAssertTrue(result.contains("[PREFIX]"), "Placeholder should appear")
    }

    func testEmptyPrefixIsIgnored() {
        let input = "[14:23:01.000] [settings] customPrefixValue=''"
        let result = DebugLogSanitizer(prefixesToRedact: [""]).sanitize(input)
        XCTAssertEqual(result, input, "Empty prefix should not modify output")
    }

    func testBothPrefixesAreRedacted() {
        let input = "primary=done_ secondary=tag_"
        let result = DebugLogSanitizer(prefixesToRedact: ["done_", "tag_"]).sanitize(input)
        XCTAssertFalse(result.contains("done_"), "Primary prefix should be redacted")
        XCTAssertFalse(result.contains("tag_"), "Secondary prefix should be redacted")
    }

    func testLongerPrefixRedactedBeforeShorterToAvoidPartialMatch() {
        // If both "tag_" and "tag_extra_" are configured, the longer must be redacted first
        // to prevent "tag_" from partially matching inside "tag_extra_".
        let input = "file=tag_extra_clip.mp4"
        let result = DebugLogSanitizer(prefixesToRedact: ["tag_", "tag_extra_"]).sanitize(input)
        XCTAssertFalse(result.contains("tag_extra_"), "Longer prefix should be fully redacted")
        XCTAssertFalse(result.contains("tag_"), "No residual prefix fragment should remain")
    }

    // MARK: - Mixed safe and unsafe lines

    func testMixedSafeAndUnsafeLinesHandledCorrectly() {
        let lines = [
            "[14:23:01.000] [queue] add: count=3 wasEmpty=true",
            "[14:23:02.000] [rename] file=/Users/bob/Movies/clip.mp4 → done_clip.mp4",
            "[14:23:03.000] [settings] customPrefixValue='done_'",
            "[14:23:04.000] [playback] next: source=nextButton",
        ]
        let input = lines.joined(separator: "\n")
        let result = DebugLogSanitizer(prefixesToRedact: ["done_"]).sanitize(input)

        XCTAssertTrue(result.contains("[14:23:01.000] [queue] add: count=3 wasEmpty=true"),
                      "Safe line should be unchanged")
        XCTAssertFalse(result.contains("/Users/bob"), "User path should be redacted")
        XCTAssertTrue(result.contains("[PATH]/clip.mp4"), "Filename should be preserved")
        XCTAssertFalse(result.contains("'done_'"), "Prefix value in settings line should be redacted")
        XCTAssertTrue(result.contains("[14:23:04.000] [playback] next: source=nextButton"),
                      "Safe line at end should be unchanged")
    }

    func testPathAndPrefixRedactionComposeTogether() {
        let input = "[14:23:01.000] [rename] customPrefix: /Users/alice/Movies/clip.mp4 → x_clip.mp4 source=videoPage"
        let result = DebugLogSanitizer(prefixesToRedact: ["x_"]).sanitize(input)
        XCTAssertFalse(result.contains("/Users/alice"), "User path should be redacted")
        XCTAssertTrue(result.contains("[PATH]/clip.mp4"), "Original filename should be preserved")
        XCTAssertFalse(result.contains("x_clip"), "Prefix in new filename should be redacted")
        XCTAssertTrue(result.contains("source=videoPage"), "Diagnostic context should be preserved")
    }
}
