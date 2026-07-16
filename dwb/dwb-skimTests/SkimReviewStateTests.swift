import Cocoa
import XCTest

final class SkimReviewStateTests: XCTestCase {

    private func components(_ color: NSColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let color else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func assertColor(_ actual: NSColor?, matches expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualComponents = components(actual),
              let expectedComponents = components(expected) else {
            XCTFail("Expected both colors to expose RGB components", file: file, line: line)
            return
        }
        XCTAssertEqual(actualComponents.r, expectedComponents.r, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.g, expectedComponents.g, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.b, expectedComponents.b, accuracy: 0.001, file: file, line: line)
    }

    // MARK: - Keep

    func testSetKeepProducesKeepStateWithoutTouchingAFile() {
        let store = SkimReviewStateStore()
        let url = URL(fileURLWithPath: "/tmp/DSCF1234.MP4")

        store.setKeep(for: url)

        XCTAssertEqual(store.intent(for: url), .keep)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testKeepDisplayShowsKeepPrefixAndDarkTealColor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "DSCF1234.MP4", explicitIntent: .keep)

        XCTAssertEqual(descriptor.status, .keep)
        XCTAssertEqual(descriptor.prefixToken, "keep_")
        assertColor(descriptor.statusColor, matches: SkimColors.darkTeal)
    }

    // MARK: - Delete

    func testSetDeleteProducesDeleteStateWithoutTouchingAFile() {
        let store = SkimReviewStateStore()
        let url = URL(fileURLWithPath: "/tmp/clip_0002.mov")

        store.setDelete(for: url)

        XCTAssertEqual(store.intent(for: url), .delete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteDisplayShowsDeletePrefixAndBurntOrangeColor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "clip_0002.mov", explicitIntent: .delete)

        XCTAssertEqual(descriptor.status, .delete)
        XCTAssertEqual(descriptor.prefixToken, "delete_")
        assertColor(descriptor.statusColor, matches: SkimColors.burntOrange)
    }

    // MARK: - Rename

    func testReviewStateStoreDoesNotCreateRenamePendingState() {
        let store = SkimReviewStateStore()
        let url = URL(fileURLWithPath: "/tmp/old_name.mov")

        XCTAssertEqual(store.intent(for: url), .unmarked)
    }

    func testMigrateIntentPreservesKeepStateAfterFilesystemRename() {
        let store = SkimReviewStateStore()
        let oldURL = URL(fileURLWithPath: "/tmp/old_name.mov")
        let newURL = URL(fileURLWithPath: "/tmp/New Name.mov")

        store.setKeep(for: oldURL)
        store.migrateIntent(from: oldURL, to: newURL)

        XCTAssertEqual(store.intent(for: oldURL), .unmarked)
        XCTAssertEqual(store.intent(for: newURL), .keep)
    }

    // MARK: - P07/P08 display precedence

    func testUnmarkedItemFallsBackToLegacyPrefixDisplay() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "keep_legacy.mov", explicitIntent: .unmarked)

        XCTAssertEqual(descriptor.status, .keep)
        XCTAssertEqual(descriptor.prefixToken, "keep_")
        XCTAssertEqual(descriptor.visibleFilename, "legacy.mov")
    }

    func testExplicitIntentOverridesLegacyPrefixDisplay() {
        // A literal `rename_` filename would normally read as legacy "rename"
        // status, but an explicit P08 "keep" intent must win.
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "rename_legacy.mov", explicitIntent: .keep)

        XCTAssertEqual(descriptor.status, .keep)
        XCTAssertEqual(descriptor.prefixToken, "keep_")
    }

    // MARK: - Undo

    func testUndoRevertsMostRecentChange() {
        let store = SkimReviewStateStore()
        let url = URL(fileURLWithPath: "/tmp/clip.mov")

        store.setKeep(for: url)
        store.setDelete(for: url)
        XCTAssertEqual(store.intent(for: url), .delete)

        store.undoLastChange()
        XCTAssertEqual(store.intent(for: url), .keep)

        store.undoLastChange()
        XCTAssertEqual(store.intent(for: url), .unmarked)
    }

    func testUndoWithNoHistoryIsHarmless() {
        let store = SkimReviewStateStore()
        store.undoLastChange()
        store.undoLastChange()
        // No crash, no state to observe — this test simply documents that
        // calling undo with an empty history is a safe no-op.
    }
}
