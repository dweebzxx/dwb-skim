import Foundation

/// Result of planning a single queue item removal.
public struct QueueRemovalResult: Equatable {
    public let displayOrder: [Int]
    public let currentDisplayIndex: Int
    public let removedSetIndex: Int
    public let removingCurrent: Bool
    public let isQueueEmpty: Bool

    public init(displayOrder: [Int],
                currentDisplayIndex: Int,
                removedSetIndex: Int,
                removingCurrent: Bool,
                isQueueEmpty: Bool) {
        self.displayOrder = displayOrder
        self.currentDisplayIndex = currentDisplayIndex
        self.removedSetIndex = removedSetIndex
        self.removingCurrent = removingCurrent
        self.isQueueEmpty = isQueueEmpty
    }
}

/// Pure deterministic planner for queue removals.
///
/// Converts a display index removal into updated display order, updated
/// current selection index, and empty-queue detection. Never touches the
/// filesystem, macOS Trash, or player hardware.
public enum QueueRemovalPlanner {
    public static func planRemoval(displayIndex: Int,
                                   displayOrder: [Int],
                                   currentDisplayIndex: Int,
                                   totalSetCount: Int) -> QueueRemovalResult? {
        guard displayIndex >= 0, displayIndex < displayOrder.count else { return nil }
        let removedSetIndex = displayOrder[displayIndex]
        guard removedSetIndex >= 0, removedSetIndex < totalSetCount else { return nil }

        let removingCurrent = displayIndex == currentDisplayIndex
        var newDisplayOrder = displayOrder
        newDisplayOrder.remove(at: displayIndex)
        newDisplayOrder = newDisplayOrder.map { $0 > removedSetIndex ? $0 - 1 : $0 }

        let newTotalCount = totalSetCount - 1
        if newTotalCount <= 0 || newDisplayOrder.isEmpty {
            return QueueRemovalResult(displayOrder: [],
                                      currentDisplayIndex: -1,
                                      removedSetIndex: removedSetIndex,
                                      removingCurrent: removingCurrent,
                                      isQueueEmpty: true)
        }

        let newCurrentIndex: Int
        if removingCurrent {
            newCurrentIndex = min(displayIndex, newDisplayOrder.count - 1)
        } else {
            if displayIndex < currentDisplayIndex {
                newCurrentIndex = currentDisplayIndex - 1
            } else if currentDisplayIndex >= newDisplayOrder.count {
                newCurrentIndex = newDisplayOrder.count - 1
            } else {
                newCurrentIndex = currentDisplayIndex
            }
        }

        return QueueRemovalResult(displayOrder: newDisplayOrder,
                                  currentDisplayIndex: newCurrentIndex,
                                  removedSetIndex: removedSetIndex,
                                  removingCurrent: removingCurrent,
                                  isQueueEmpty: false)
    }

    public static func planRemovals(displayIndices: [Int],
                                    displayOrder: [Int],
                                    currentDisplayIndex: Int,
                                    totalSetCount: Int) -> (displayOrder: [Int], currentDisplayIndex: Int, removedSetIndices: [Int], isQueueEmpty: Bool)? {
        var currentOrder = displayOrder
        var currentIdx = currentDisplayIndex
        var currentSetCount = totalSetCount
        var removedSetIndices: [Int] = []
        var empty = false

        let sortedIndices = displayIndices.sorted(by: >)
        for idx in sortedIndices {
            guard let result = planRemoval(displayIndex: idx,
                                           displayOrder: currentOrder,
                                           currentDisplayIndex: currentIdx,
                                           totalSetCount: currentSetCount) else {
                return nil
            }
            currentOrder = result.displayOrder
            currentIdx = result.currentDisplayIndex
            currentSetCount -= 1
            removedSetIndices.append(result.removedSetIndex)
            if result.isQueueEmpty {
                empty = true
                break
            }
        }
        return (currentOrder, currentIdx, removedSetIndices, empty)
    }
}

/// User-facing presentation constants for queue removal.
/// Ensures consistent, non-destructive wording across buttons, tooltips,
/// accessibility labels, context menus, and application menus.
public enum QueueRemovalPresentation {
    public static let buttonTitle = "Remove"
    public static let buttonToolTip = "Remove from Queue"
    public static let buttonAccessibilityLabel = "Remove from Queue"
    public static let buttonSymbolName = "minus.circle"
    public static let contextMenuItemTitle = "Remove from Queue"
    public static let menuItemTitle = "Remove Current from Queue"

    /// Rejection of destructive trash/filesystem semantics:
    public static let isDestructiveFilesystemOperation = false
}
