import Foundation

/// Copy for the drag-and-drop overlay over the video stage (valid state only).
struct DropZonePresentation: Equatable {
    /// How many dragged items would be added to the queue.
    let itemCount: Int
    /// True when a folder is among the items, so the count is of items rather than files.
    let containsFolder: Bool

    var title: String {
        let noun = containsFolder ? "item" : "file"
        return "Add \(itemCount) \(noun)\(itemCount == 1 ? "" : "s") to the queue"
    }

    /// Skim inserts dropped items at the top of the queue.
    let detail = "Release to add to the top of the queue."
}
