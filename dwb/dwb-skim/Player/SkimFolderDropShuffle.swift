import Foundation

/// Pure decision seam for P37 "folder drag-and-drop auto-shuffle".
///
/// When the user drag-and-drops a folder (or a mixed selection containing at
/// least one folder) onto the app and that drop produces accepted media, the
/// queue's existing Queue Order mode is switched to the application's existing
/// `.shuffle` mode through the same authoritative setter the Queue Order control
/// uses (`SettingsWindowController.setQueueOrderMode`). This helper only decides
/// *whether* that switch is warranted; it performs no randomization itself and
/// owns no shuffle state.
enum SkimFolderDropShuffle {

    /// - Parameters:
    ///   - isDragAndDrop: true only for the external file/folder drag-and-drop
    ///     entry point (`MediaDropRouting.performDrop`). Open File / Open Folder
    ///     and programmatic intake pass false and are never affected.
    ///   - droppedContainedDirectory: true when the dropped pasteboard URLs
    ///     included at least one directory (folder-only or mixed folder+files).
    ///   - acceptedMediaCount: number of accepted media items the drop produced
    ///     after the existing supported-media filtering / folder expansion.
    /// - Returns: true when Queue Order should be set to the existing Shuffle mode.
    static func shouldRequestShuffle(isDragAndDrop: Bool,
                                     droppedContainedDirectory: Bool,
                                     acceptedMediaCount: Int) -> Bool {
        isDragAndDrop && droppedContainedDirectory && acceptedMediaCount > 0
    }
}
