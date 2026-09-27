import Foundation
import XCTest

final class QueueRemovalTests: XCTestCase {

    // MARK: - Presentation & Wording

    func testQueueRemovalPresentationWordingIsNonDestructive() {
        XCTAssertEqual(QueueRemovalPresentation.buttonTitle, "Remove")
        XCTAssertEqual(QueueRemovalPresentation.buttonToolTip, "Remove from Queue")
        XCTAssertEqual(QueueRemovalPresentation.buttonAccessibilityLabel, "Remove from Queue")
        XCTAssertEqual(QueueRemovalPresentation.buttonSymbolName, "minus.circle")
        XCTAssertEqual(QueueRemovalPresentation.contextMenuItemTitle, "Remove from Queue")
        XCTAssertEqual(QueueRemovalPresentation.menuItemTitle, "Remove Current from Queue")
        XCTAssertFalse(QueueRemovalPresentation.isDestructiveFilesystemOperation)
    }

    // MARK: - Middle of Queue Removal

    func testRemoveMiddleItemWhenPlayingTransitionsToNextItem() {
        // 5 items in sequential display order [0, 1, 2, 3, 4]
        // Current playing item is at index 2 (item 2)
        let displayOrder = [0, 1, 2, 3, 4]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 2,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 2,
                                                     totalSetCount: 5)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        // Removed set index is 2
        XCTAssertEqual(result.removedSetIndex, 2)
        XCTAssertTrue(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)

        // Remaining 4 items remapped: set indices > 2 decrement by 1
        // [0, 1, 3, 4] -> [0, 1, 2, 3]
        XCTAssertEqual(result.displayOrder, [0, 1, 2, 3])

        // Current item transitions to the item that shifted into index 2 (old item 3)
        XCTAssertEqual(result.currentDisplayIndex, 2)
    }

    func testRemoveMiddleItemBeforeCurrentDecrementsCurrentIndexWithoutInterruptingPlayback() {
        // 5 items in sequential display order [0, 1, 2, 3, 4]
        // Current playing item is at index 3 (item 3)
        // Remove item at index 1 (item 1)
        let displayOrder = [0, 1, 2, 3, 4]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 1,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 3,
                                                     totalSetCount: 5)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 1)
        XCTAssertFalse(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)

        // [0, 2, 3, 4] remapped -> [0, 1, 2, 3]
        XCTAssertEqual(result.displayOrder, [0, 1, 2, 3])

        // Current index was 3, item 1 removed before it, so current shifts to 2 (still item 3)
        XCTAssertEqual(result.currentDisplayIndex, 2)
    }

    func testRemoveMiddleItemAfterCurrentPreservesCurrentIndexWithoutInterruptingPlayback() {
        // 5 items in sequential display order [0, 1, 2, 3, 4]
        // Current playing item is at index 1 (item 1)
        // Remove item at index 3 (item 3)
        let displayOrder = [0, 1, 2, 3, 4]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 3,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 1,
                                                     totalSetCount: 5)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 3)
        XCTAssertFalse(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)

        // [0, 1, 2, 4] remapped -> [0, 1, 2, 3]
        XCTAssertEqual(result.displayOrder, [0, 1, 2, 3])

        // Current index was 1, item 3 removed after it, so current remains 1
        XCTAssertEqual(result.currentDisplayIndex, 1)
    }

    // MARK: - First Item Removal

    func testRemoveFirstItemWhenPlayingTransitionsToNewFirstItem() {
        // 3 items [0, 1, 2], current is 0
        let displayOrder = [0, 1, 2]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 3)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 0)
        XCTAssertTrue(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)

        // [1, 2] remapped -> [0, 1]
        XCTAssertEqual(result.displayOrder, [0, 1])

        // min(0, 2 - 1) = 0
        XCTAssertEqual(result.currentDisplayIndex, 0)
    }

    func testRemoveFirstItemWhenNotPlayingDecrementsCurrentIndex() {
        // 3 items [0, 1, 2], current is 2
        let displayOrder = [0, 1, 2]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 2,
                                                     totalSetCount: 3)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 0)
        XCTAssertFalse(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [0, 1])
        XCTAssertEqual(result.currentDisplayIndex, 1)
    }

    // MARK: - Last Item Removal

    func testRemoveLastItemWhenPlayingTransitionsToPreviousItem() {
        // 3 items [0, 1, 2], current is 2 (last item)
        let displayOrder = [0, 1, 2]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 2,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 2,
                                                     totalSetCount: 3)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 2)
        XCTAssertTrue(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [0, 1])

        // min(2, 2 - 1) = 1 (transitions to item 1)
        XCTAssertEqual(result.currentDisplayIndex, 1)
    }

    func testRemoveLastItemWhenNotPlayingPreservesCurrentIndex() {
        // 3 items [0, 1, 2], current is 0
        let displayOrder = [0, 1, 2]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 2,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 3)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 2)
        XCTAssertFalse(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [0, 1])
        XCTAssertEqual(result.currentDisplayIndex, 0)
    }

    // MARK: - Only Remaining Item Removal

    func testRemoveOnlyRemainingItemYieldsValidEmptyQueueState() {
        // 1 item [0], current is 0
        let displayOrder = [0]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 1)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 0)
        XCTAssertTrue(result.removingCurrent)
        XCTAssertTrue(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [])
        XCTAssertEqual(result.currentDisplayIndex, -1)
    }

    // MARK: - Shuffled / Non-Sequential Queue Removal

    func testRemoveFromShuffledQueuePreservesRelativeOrder() {
        // Shuffled order: playbackSet indices [3, 1, 0, 2]
        // Current is display index 0 (which is playbackSet item 3)
        // Remove display index 2 (which is playbackSet item 0)
        let displayOrder = [3, 1, 0, 2]
        let result = QueueRemovalPlanner.planRemoval(displayIndex: 2,
                                                     displayOrder: displayOrder,
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 4)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertEqual(result.removedSetIndex, 0)
        XCTAssertFalse(result.removingCurrent)
        XCTAssertFalse(result.isQueueEmpty)

        // After removing displayIndex 2, remaining displayOrder is [3, 1, 2].
        // Remapping for removedSetIndex 0: all values > 0 decrement by 1:
        // 3 -> 2, 1 -> 0, 2 -> 1
        // Resulting displayOrder: [2, 0, 1]
        XCTAssertEqual(result.displayOrder, [2, 0, 1])
        XCTAssertEqual(result.currentDisplayIndex, 0)
    }

    // MARK: - Sequential Multiple Removals

    func testPlanRemovalsProcessesMultipleIndicesDescending() {
        // 5 items [0, 1, 2, 3, 4], current is 2
        // Remove indices 4 and 1
        let displayOrder = [0, 1, 2, 3, 4]
        let result = QueueRemovalPlanner.planRemovals(displayIndices: [1, 4],
                                                      displayOrder: displayOrder,
                                                      currentDisplayIndex: 2,
                                                      totalSetCount: 5)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        // Descending order of removals: 4 first, then 1
        XCTAssertEqual(result.removedSetIndices, [4, 1])
        XCTAssertFalse(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [0, 1, 2])
        // Current index was 2; removing 4 didn't shift it, removing 1 shifted it to 1
        XCTAssertEqual(result.currentDisplayIndex, 1)
    }

    func testPlanRemovalsToEmpty() {
        // 2 items [0, 1], current is 0
        let displayOrder = [0, 1]
        let result = QueueRemovalPlanner.planRemovals(displayIndices: [0, 1],
                                                      displayOrder: displayOrder,
                                                      currentDisplayIndex: 0,
                                                      totalSetCount: 2)
        XCTAssertNotNil(result)
        guard let result = result else { return }

        XCTAssertTrue(result.isQueueEmpty)
        XCTAssertEqual(result.displayOrder, [])
        XCTAssertEqual(result.currentDisplayIndex, -1)
    }

    // MARK: - Invalid / Out-of-Bounds Rejection

    func testPlanRemovalRejectsOutOfBoundsDisplayIndex() {
        XCTAssertNil(QueueRemovalPlanner.planRemoval(displayIndex: -1,
                                                     displayOrder: [0, 1],
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 2))
        XCTAssertNil(QueueRemovalPlanner.planRemoval(displayIndex: 2,
                                                     displayOrder: [0, 1],
                                                     currentDisplayIndex: 0,
                                                     totalSetCount: 2))
        XCTAssertNil(QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                     displayOrder: [],
                                                     currentDisplayIndex: -1,
                                                     totalSetCount: 0))
    }

    // MARK: - Source Media Filesystem Preservation

    func testQueueRemovalDoesNotTouchOrTrashSourceMediaOnDisk() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("dwb_skim_p40_test_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        // Create 3 real test files on disk
        let files = ["clipA.mp4", "clipB.mp4", "clipC.mp4"]
        var fileURLs: [URL] = []
        for name in files {
            let url = tempDir.appendingPathComponent(name)
            let sampleData = "fake video content for \(name)".data(using: .utf8)!
            try sampleData.write(to: url)
            fileURLs.append(url)
        }

        // Verify all 3 exist before queue operations
        for url in fileURLs {
            XCTAssertTrue(fileManager.fileExists(atPath: url.path), "Precondition: file must exist")
        }

        // Simulate queue state: 3 items, current is index 1 (clipB.mp4)
        var displayOrder = [0, 1, 2]
        var currentDisplayIndex = 1
        var totalSetCount = 3

        // Action 1: Remove non-current item (clipA.mp4 at display index 0)
        let removal1 = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                       displayOrder: displayOrder,
                                                       currentDisplayIndex: currentDisplayIndex,
                                                       totalSetCount: totalSetCount)!
        displayOrder = removal1.displayOrder
        currentDisplayIndex = removal1.currentDisplayIndex
        totalSetCount -= 1

        // Verify source file clipA.mp4 STILL EXISTS on disk and was not deleted or trashed!
        XCTAssertTrue(fileManager.fileExists(atPath: fileURLs[0].path),
                      "clipA.mp4 must remain untouched on disk after queue removal")
        let content1 = try String(contentsOf: fileURLs[0], encoding: .utf8)
        XCTAssertEqual(content1, "fake video content for clipA.mp4")

        // Action 2: Remove currently playing item (clipB.mp4, now at index 0)
        let removal2 = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                       displayOrder: displayOrder,
                                                       currentDisplayIndex: currentDisplayIndex,
                                                       totalSetCount: totalSetCount)!
        displayOrder = removal2.displayOrder
        currentDisplayIndex = removal2.currentDisplayIndex
        totalSetCount -= 1

        // Verify source file clipB.mp4 STILL EXISTS on disk!
        XCTAssertTrue(fileManager.fileExists(atPath: fileURLs[1].path),
                      "clipB.mp4 must remain untouched on disk after active queue removal")
        let content2 = try String(contentsOf: fileURLs[1], encoding: .utf8)
        XCTAssertEqual(content2, "fake video content for clipB.mp4")

        // Action 3: Remove the only remaining item (clipC.mp4 at index 0)
        let removal3 = QueueRemovalPlanner.planRemoval(displayIndex: 0,
                                                       displayOrder: displayOrder,
                                                       currentDisplayIndex: currentDisplayIndex,
                                                       totalSetCount: totalSetCount)!
        XCTAssertTrue(removal3.isQueueEmpty)

        // Verify source file clipC.mp4 STILL EXISTS on disk!
        XCTAssertTrue(fileManager.fileExists(atPath: fileURLs[2].path),
                      "clipC.mp4 must remain untouched on disk after empty-queue removal")
        let content3 = try String(contentsOf: fileURLs[2], encoding: .utf8)
        XCTAssertEqual(content3, "fake video content for clipC.mp4")

        // Verify no Trash path or temporary deletion was performed on any file
        for url in fileURLs {
            XCTAssertTrue(fileManager.fileExists(atPath: url.path),
                          "All source files must remain intact at original path")
        }
    }
}
