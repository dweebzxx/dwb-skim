import Foundation
import XCTest

final class SkimFileRenamerTests: XCTestCase {

    func testValidRenameMovesActualFileToCompleteFilename() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        let target = tmp.appendingPathComponent("Better Clip Name.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original,
                                                 toCompleteFilename: "Better Clip Name.mov")

        XCTAssertEqual(renamed.standardizedFileURL, target.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testEmptyOrWhitespaceTargetIsRejectedAndFileRemainsUnchanged() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        XCTAssertThrowsError(try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "   ")) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .invalidName)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testTargetContainingSlashIsRejectedAndFileRemainsUnchanged() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        XCTAssertThrowsError(try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "nested/Better.mov")) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .invalidName)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("nested").path))
    }

    func testExistingTargetCollisionIsRejectedWithoutOverwrite() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        let existing = tmp.appendingPathComponent("Better.mov")
        try Data("original".utf8).write(to: original)
        try Data("existing".utf8).write(to: existing)

        XCTAssertThrowsError(try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better.mov")) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .targetExists("Better.mov"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: existing), "existing")
    }

    // MARK: - Extension preservation (P08.2)

    func testRenameWithBareStemAppendsOriginalExtension() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name")

        XCTAssertEqual(renamed.lastPathComponent, "Better Clip Name.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    func testRenameWithMatchingExtensionSucceeds() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name.mov")

        XCTAssertEqual(renamed.lastPathComponent, "Better Clip Name.mov")
    }

    func testRenameWithDifferentCaseExtensionPreservesOriginalSpelling() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name.MOV")

        XCTAssertEqual(renamed.lastPathComponent, "Better Clip Name.mov")
    }

    func testRenameWithDifferentExtensionIsRejectedAsExtensionChange() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        XCTAssertThrowsError(try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name.mp4")) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .extensionChange)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testRenameAddingExtensionToExtensionlessOriginalIsRejected() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original")
        try writeEmptyFile(original)

        XCTAssertThrowsError(try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name.mov")) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .extensionChange)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testRenameExtensionlessOriginalWithBareStemSucceeds() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original, toCompleteFilename: "Better Clip Name")

        XCTAssertEqual(renamed.lastPathComponent, "Better Clip Name")
    }

    func testQueueURLUpdateByURLReplacesRegardlessOfDisplayOrder() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let c = URL(fileURLWithPath: "/tmp/c.mov")
        let renamed = URL(fileURLWithPath: "/tmp/keep_b.mov")

        let updated = SkimQueueURLUpdate.replacingURL(in: [a, b, c], matching: b, with: renamed)

        XCTAssertEqual(updated, [a, renamed, c])
    }

    func testQueueURLUpdateByURLReturnsNilWhenURLNotPresent() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let missing = URL(fileURLWithPath: "/tmp/missing.mov")
        let renamed = URL(fileURLWithPath: "/tmp/keep_missing.mov")

        let updated = SkimQueueURLUpdate.replacingURL(in: [a, b], matching: missing, with: renamed)

        XCTAssertNil(updated)
    }

    func testQueueURLUpdateChangesOnlySelectedDisplayItemURL() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let c = URL(fileURLWithPath: "/tmp/c.mov")
        let renamed = URL(fileURLWithPath: "/tmp/Better Clip Name.mov")

        let updated = SkimQueueURLUpdate.replacingURL(in: [a, b, c],
                                                      displayOrder: [2, 0, 1],
                                                      displayIndex: 2,
                                                      matching: b,
                                                      with: renamed)

        XCTAssertEqual(updated, [a, renamed, c])
    }

    func testQueueURLUpdateRejectsStaleDisplaySelection() {
        let a = URL(fileURLWithPath: "/tmp/a.mov")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        let c = URL(fileURLWithPath: "/tmp/c.mov")
        let renamed = URL(fileURLWithPath: "/tmp/Better Clip Name.mov")

        let updated = SkimQueueURLUpdate.replacingURL(in: [a, b, c],
                                                      displayOrder: [2, 0, 1],
                                                      displayIndex: 2,
                                                      matching: a,
                                                      with: renamed)

        XCTAssertNil(updated)
    }

    func testQueueDisplayModelShowsNewFilenameAfterSuccessfulRename() throws {
        struct DisplayItem {
            let url: URL
            let displayName: String
        }

        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)
        let renamed = try SkimFileRenamer.rename(sourceURL: original,
                                                 toCompleteFilename: "Better Clip Name.mov")

        let item = DisplayItem(url: renamed, displayName: renamed.lastPathComponent)

        XCTAssertEqual(item.displayName, "Better Clip Name.mov")
        XCTAssertEqual(item.url.lastPathComponent, "Better Clip Name.mov")
    }

    // MARK: - P36 custom-prefix toggle / replace transitions

    private let p = "select_"
    private let s = "later_"

    private func toggle(_ filename: String, _ action: CustomPrefixAction) -> String? {
        SkimFileRenamer.customPrefixToggleTargetFilename(for: filename,
                                                         primaryPrefix: p,
                                                         secondaryPrefix: s,
                                                         action: action)
    }

    func testNoPrefixToPrimaryAddsPrimary() {
        XCTAssertEqual(toggle("clip.mov", .primary), "select_clip.mov")
    }

    func testNoPrefixToSecondaryAddsSecondary() {
        XCTAssertEqual(toggle("clip.mov", .secondary), "later_clip.mov")
    }

    func testPrimaryInvokedAgainRemovesPrimary() {
        XCTAssertEqual(toggle("select_clip.mov", .primary), "clip.mov")
    }

    func testSecondaryInvokedAgainRemovesSecondary() {
        XCTAssertEqual(toggle("later_clip.mov", .secondary), "clip.mov")
    }

    func testPrimaryPresentSecondaryActionReplacesPrimaryWithSecondary() {
        XCTAssertEqual(toggle("select_clip.mov", .secondary), "later_clip.mov")
    }

    func testSecondaryPresentPrimaryActionReplacesSecondaryWithPrimary() {
        XCTAssertEqual(toggle("later_clip.mov", .primary), "select_clip.mov")
    }

    func testTogglingNeverStacksPrefixes() {
        // Repeatedly applying primary then secondary never yields "select_later_" or "later_select_".
        var name = "clip.mov"
        name = toggle(name, .primary) ?? name       // select_clip.mov
        name = toggle(name, .secondary) ?? name      // later_clip.mov
        name = toggle(name, .primary) ?? name        // select_clip.mov
        XCTAssertEqual(name, "select_clip.mov")
        XCTAssertFalse(name.contains("select_later_"))
        XCTAssertFalse(name.contains("later_select_"))
    }

    func testRemainderAndExtensionPreservedIncludingMultiDotNames() {
        XCTAssertEqual(toggle("My.Clip.v2.final.mp4", .primary), "select_My.Clip.v2.final.mp4")
        XCTAssertEqual(toggle("select_My.Clip.v2.final.mp4", .primary), "My.Clip.v2.final.mp4")
        XCTAssertEqual(toggle("archive.tar.gz", .secondary), "later_archive.tar.gz")
    }

    func testExtensionlessFilenamePreserved() {
        XCTAssertEqual(toggle("README", .primary), "select_README")
        XCTAssertEqual(toggle("select_README", .primary), "README")
    }

    func testUnrelatedLeadingTextResemblingAPrefixIsNotStripped() {
        // "selected_" is not the configured "select_" prefix; only exact configured
        // prefixes are recognized, so primary is simply prepended.
        XCTAssertEqual(toggle("selection_clip.mov", .primary), "select_selection_clip.mov")
    }

    func testEmptyRequestedPrefixIsNoOp() {
        XCTAssertNil(SkimFileRenamer.customPrefixToggleTargetFilename(
            for: "clip.mov", primaryPrefix: "", secondaryPrefix: s, action: .primary))
    }

    func testReplaceIsASingleResultingFilename() {
        // Switching from one prefix to the other is expressed as one target name
        // (one rename operation for the caller), not two.
        let result = toggle("select_holiday.mov", .secondary)
        XCTAssertEqual(result, "later_holiday.mov")
    }

    func testOverlappingConfiguredPrefixesUseLongestMatch() {
        // primary "a_" is a leading substring of secondary "a_b_".
        let out = SkimFileRenamer.customPrefixToggleTargetFilename(
            for: "a_b_clip.mov", primaryPrefix: "a_", secondaryPrefix: "a_b_", action: .primary)
        XCTAssertEqual(out, "a_clip.mov") // recognized as secondary present → replace with primary
    }

    // MARK: - Prefix normalization (trailing underscore)

    func testNormalizedCustomPrefixAppendsTrailingUnderscore() {
        XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix("select"), "select_")
    }

    func testNormalizedCustomPrefixKeepsExistingTrailingUnderscore() {
        XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix("select_"), "select_")
    }

    func testNormalizedCustomPrefixTrimsWhitespace() {
        XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix("  later  "), "later_")
    }

    func testNormalizedCustomPrefixEmptyStaysEmpty() {
        XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix(""), "")
        XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix("   "), "")
    }

    func testNormalizedCustomPrefixCollapsesTrailingUnderscores() {
        let cases = [
            ("keep", "keep_"), ("keep_", "keep_"),
            ("keep__", "keep_"), ("keep___", "keep_"),
            ("  keep__  ", "keep_"), ("a_b__", "a_b_"),
            ("_", "_"), ("__", "_"), ("", ""), ("   ", "")
        ]
        for (input, expected) in cases {
            XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix(input), expected, input)
        }
    }

    func testNormalizedCustomPrefixIsIdempotent() {
        for input in ["keep", "keep_", "keep__", "keep___", "  keep__  ",
                      "a_b__", "_", "__", "", "   "] {
            let normalized = SkimFileRenamer.normalizedCustomPrefix(input)
            XCTAssertEqual(SkimFileRenamer.normalizedCustomPrefix(normalized), normalized, input)
        }
    }

    func testDoubleUnderscorePrefixToggleAndReplaceMatchSingleUnderscore() {
        let secondary = SkimFileRenamer.normalizedCustomPrefix("delete_")
        for filename in ["clip.mp4", "keep_clip.mp4", "delete_clip.mp4"] {
            for action in [CustomPrefixAction.primary, .secondary] {
                let fromDouble = SkimFileRenamer.customPrefixToggleTargetFilename(
                    for: filename,
                    primaryPrefix: SkimFileRenamer.normalizedCustomPrefix("keep__"),
                    secondaryPrefix: secondary, action: action)
                let fromSingle = SkimFileRenamer.customPrefixToggleTargetFilename(
                    for: filename,
                    primaryPrefix: SkimFileRenamer.normalizedCustomPrefix("keep_"),
                    secondaryPrefix: secondary, action: action)
                XCTAssertEqual(fromDouble, fromSingle, "\(filename), \(action)")
            }
        }
    }

    func testNormalizedPrefixThenToggleProducesPrefixUnderscoreFilename() {
        let primary = SkimFileRenamer.normalizedCustomPrefix("select")
        XCTAssertEqual(
            SkimFileRenamer.customPrefixToggleTargetFilename(
                for: "clip.mov", primaryPrefix: primary, secondaryPrefix: "", action: .primary),
            "select_clip.mov")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwb-skim-renameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeEmptyFile(_ url: URL) throws {
        try Data().write(to: url)
    }
}
