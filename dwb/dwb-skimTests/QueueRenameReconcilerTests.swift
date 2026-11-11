import Foundation
import XCTest

final class QueueRenameReconcilerTests: XCTestCase {
    private let originalURLs = ["a.mp4", "b.mp4", "c.mp4", "d.mp4"].map {
        URL(fileURLWithPath: "/queue/\($0)")
    }

    func testCustomRenamePreservesCompleteSequentialIdentitySequenceAndIndex() {
        assertRenamePreserves(order: [0, 1, 2, 3], renamedSetIndex: 1)
    }

    func testShuffleRenamePreservesCompleteIdentitySequence() {
        assertRenamePreserves(order: [2, 0, 3, 1], renamedSetIndex: 3)
    }

    func testWeightedWaitedRenamePreservesCompleteIdentitySequenceUntilRegeneration() {
        assertRenamePreserves(order: [3, 1, 0, 2], renamedSetIndex: 0)
    }

    func testPlayingItemRenamePreservesAssignmentOwnership() {
        var registry = SkimMediaAssignmentRegistry()
        _ = registry.installPlayer()
        let assignment = registry.assign()
        let items = makeItems()
        let renamed = QueueRenameReconciler.replacingURL(
            in: items,
            at: 2,
            with: URL(fileURLWithPath: "/queue/renamed-c.mp4"),
            fileIdentity: "file-c"
        )!

        XCTAssertEqual(registry.current, assignment)
        XCTAssertTrue(registry.isCurrent(assignment))
        XCTAssertEqual(renamed[2].id, items[2].id)
    }

    func testSelectionRemainsAttachedToRenamedItem() {
        let items = makeItems()
        let renamed = QueueRenameReconciler.replacingURL(
            in: items,
            at: 1,
            with: URL(fileURLWithPath: "/queue/keep_b.mp4"),
            fileIdentity: "file-b"
        )!
        let result = QueueRenameReconciler.reconcile(
            currentItems: renamed,
            displayOrder: [2, 1, 0, 3],
            currentDisplayIndex: 0,
            selectedItemIDs: ["B"],
            snapshot: renamed.map { .init(url: $0.url, fileIdentity: $0.fileIdentity) },
            makeID: { _ in XCTFail("No new identity expected"); return "unexpected" }
        )

        XCTAssertEqual(result.selectedItemIDs, ["B"])
        XCTAssertEqual(result.displayItemIDs, ["C", "B", "A", "D"])
    }

    func testSelfGeneratedWatcherSnapshotNeitherDuplicatesNorReorders() {
        var items = makeItems()
        items[1].url = URL(fileURLWithPath: "/queue/delete_b.mp4")
        let before = [2, 0, 3, 1]
        let result = QueueRenameReconciler.reconcile(
            currentItems: items,
            displayOrder: before,
            currentDisplayIndex: 2,
            selectedItemIDs: ["B"],
            snapshot: items.map { .init(url: $0.url, fileIdentity: $0.fileIdentity) },
            makeID: { _ in XCTFail("Watcher must reconcile to existing identity"); return "unexpected" }
        )

        XCTAssertFalse(result.membershipChanged)
        XCTAssertTrue(result.renamedItemIDs.isEmpty)
        XCTAssertEqual(result.items.count, items.count)
        XCTAssertEqual(result.displayOrder, before)
        XCTAssertEqual(result.displayItemIDs, ["C", "A", "D", "B"])
        XCTAssertEqual(result.currentDisplayIndex, 2)
    }

    func testExternalRenameMatchesStableFileIdentityAndPreservesLineup() {
        let items = makeItems()
        var snapshot = items.map { SkimQueueSnapshotItem(url: $0.url, fileIdentity: $0.fileIdentity) }
        snapshot[2] = .init(url: URL(fileURLWithPath: "/queue/externally-renamed-c.mp4"),
                            fileIdentity: "file-c")
        let result = QueueRenameReconciler.reconcile(
            currentItems: items,
            displayOrder: [3, 2, 0, 1],
            currentDisplayIndex: 1,
            selectedItemIDs: ["C"],
            snapshot: snapshot,
            makeID: { _ in XCTFail("External rename must reuse identity"); return "unexpected" }
        )

        XCTAssertFalse(result.membershipChanged)
        XCTAssertEqual(result.renamedItemIDs, ["C"])
        XCTAssertEqual(result.displayItemIDs, ["D", "C", "A", "B"])
        XCTAssertEqual(result.currentDisplayIndex, 1)
        XCTAssertEqual(result.selectedItemIDs, ["C"])
    }

    func testFilesystemIdentitySurvivesSameDirectoryRename() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwb-skim-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.mp4")
        let renamed = directory.appendingPathComponent("renamed.mp4")
        XCTAssertTrue(FileManager.default.createFile(atPath: original.path, contents: Data([0x00])))
        let before = SkimFileIdentityResolver.identity(for: original)
        try FileManager.default.moveItem(at: original, to: renamed)
        let after = SkimFileIdentityResolver.identity(for: renamed)

        XCTAssertNotNil(before)
        XCTAssertEqual(after, before)
    }

    func testFailedRenameLeavesModelUnchanged() {
        let items = makeItems()
        XCTAssertNil(QueueRenameReconciler.replacingURL(
            in: items,
            at: 99,
            with: URL(fileURLWithPath: "/queue/nope.mp4"),
            fileIdentity: nil
        ))
        XCTAssertEqual(items.map(\.url), originalURLs)
        XCTAssertEqual(items.map(\.id), ["A", "B", "C", "D"])
    }

    func testReviewPrefixVisibleNameAndStylingStillFollowUpdatedURL() {
        let primary = SkimReviewStatusDescriptor.describe(
            displayName: "select_b.mp4",
            primaryPrefix: "select_",
            secondaryPrefix: "later_"
        )
        let secondary = SkimReviewStatusDescriptor.describe(
            displayName: "later_b.mp4",
            primaryPrefix: "select_",
            secondaryPrefix: "later_"
        )
        XCTAssertEqual(primary.status, .primary)
        XCTAssertEqual(secondary.status, .secondary)
        XCTAssertEqual(primary.visibleFilename, "b.mp4")
        XCTAssertEqual(secondary.visibleFilename, "b.mp4")
    }

    private func assertRenamePreserves(order: [Int], renamedSetIndex: Int,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let items = makeItems()
        let beforeIDs = order.map { items[$0].id }
        let displayIndex = order.firstIndex(of: renamedSetIndex)!
        let renamed = QueueRenameReconciler.replacingURL(
            in: items,
            at: renamedSetIndex,
            with: URL(fileURLWithPath: "/queue/renamed-\(renamedSetIndex).mp4"),
            fileIdentity: items[renamedSetIndex].fileIdentity
        )!
        let afterIDs = order.map { renamed[$0].id }
        XCTAssertEqual(afterIDs, beforeIDs, file: file, line: line)
        XCTAssertEqual(order.firstIndex(of: renamedSetIndex), displayIndex, file: file, line: line)
        XCTAssertEqual(renamed[renamedSetIndex].id, items[renamedSetIndex].id, file: file, line: line)
    }

    private func makeItems() -> [SkimQueueItemRecord] {
        zip(["A", "B", "C", "D"], originalURLs).map { id, url in
            SkimQueueItemRecord(id: id,
                                url: url,
                                fileIdentity: "file-\(id.lowercased())")
        }
    }
}
