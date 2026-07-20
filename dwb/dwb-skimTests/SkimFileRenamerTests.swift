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

    func testRenameDoesNotGenerateRenamePrefix() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("Original.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.rename(sourceURL: original,
                                                 toCompleteFilename: "Better.mov")

        XCTAssertEqual(renamed.lastPathComponent, "Better.mov")
        XCTAssertFalse(renamed.lastPathComponent.hasPrefix("rename_"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.appendingPathComponent("rename_Better.mov").path))
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

    // MARK: - keep_/delete_ immediate prefix rename (P08.2)

    func testApplyKeepPrefixImmediatelyRenamesFile() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("clip.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.applyReviewPrefix(.keep, to: original)

        XCTAssertEqual(renamed.lastPathComponent, "keep_clip.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testApplyDeletePrefixImmediatelyRenamesFile() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("clip.mov")
        try writeEmptyFile(original)

        let renamed = try SkimFileRenamer.applyReviewPrefix(.delete, to: original)

        XCTAssertEqual(renamed.lastPathComponent, "delete_clip.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testSwitchingDeleteToKeepDoesNotStackPrefixes() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let deleteNamed = tmp.appendingPathComponent("delete_clip.mov")
        try writeEmptyFile(deleteNamed)

        let renamed = try SkimFileRenamer.applyReviewPrefix(.keep, to: deleteNamed)

        XCTAssertEqual(renamed.lastPathComponent, "keep_clip.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteNamed.path))
    }

    func testSwitchingKeepToDeleteDoesNotStackPrefixes() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let keepNamed = tmp.appendingPathComponent("keep_clip.mov")
        try writeEmptyFile(keepNamed)

        let renamed = try SkimFileRenamer.applyReviewPrefix(.delete, to: keepNamed)

        XCTAssertEqual(renamed.lastPathComponent, "delete_clip.mov")
        XCTAssertFalse(FileManager.default.fileExists(atPath: keepNamed.path))
    }

    func testReapplyingSamePrefixIsHarmlessNoOp() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let keepNamed = tmp.appendingPathComponent("keep_clip.mov")
        try writeEmptyFile(keepNamed)

        let result = try SkimFileRenamer.applyReviewPrefix(.keep, to: keepNamed)

        XCTAssertEqual(result, keepNamed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepNamed.path))
    }

    func testApplyKeepPrefixStripsLegacyRenamePrefix() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let legacyNamed = tmp.appendingPathComponent("rename_clip.mov")
        try writeEmptyFile(legacyNamed)

        let renamed = try SkimFileRenamer.applyReviewPrefix(.keep, to: legacyNamed)

        XCTAssertEqual(renamed.lastPathComponent, "keep_clip.mov")
        XCTAssertFalse(renamed.lastPathComponent.contains("rename_"))
    }

    func testApplyReviewPrefixRejectsTargetCollisionWithoutOverwrite() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let original = tmp.appendingPathComponent("clip.mov")
        let existingTarget = tmp.appendingPathComponent("keep_clip.mov")
        try Data("original".utf8).write(to: original)
        try Data("existing".utf8).write(to: existingTarget)

        XCTAssertThrowsError(try SkimFileRenamer.applyReviewPrefix(.keep, to: original)) { error in
            XCTAssertEqual(error as? SkimFileRenameError, .targetExists("keep_clip.mov"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try String(contentsOf: existingTarget), "existing")
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
