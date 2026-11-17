import Foundation

// Pure text and surface rules for the app's errors (design system 9.10). The message sheet that
// shows them is `MessageSheetController` in `DWBSheets.swift`.

/// The words of the app's error surfaces (design system 9.10): the title says what failed, in
/// sentence case, and never reads "Error". The messages that already existed keep their text.
enum DWBMessageText {
    static let exportFailed = "Export failed"
    static let cannotUndo = "Cannot undo"
    static let undoFailed = "Undo failed"
    static let cannotRename = "Cannot rename"
    static let renameFailed = "Rename failed"
    static let unableToOpenFolder = "Unable to open folder"
    static let nothingToPlay = "Nothing to play"
    static let unsupportedFiles = "Unsupported files"
    static let unsupportedAudioTrack = "Unsupported audio track"
    static let windowLimitReached = "Window limit reached"

    /// Rescan with no folder to scan: a Status HUD, not a sheet.
    static let noFolderToRescanTitle = "No folder to rescan"
    static let noFolderToRescanDetail = "Open or drop a folder first."
    static var noFolderToRescan: String { "\(noFolderToRescanTitle). \(noFolderToRescanDetail)" }

    /// Rescan that could not read the folder: a message sheet. The failure branch never changes the queue.
    static let couldNotRescanTitle = "Could not rescan folder"
    static let couldNotRescanMessage = "dwb skim could not read the folder contents. The queue was not changed."

    static func windowLimitMessage(maxPlayerWindows: Int) -> String {
        "dwb skim supports up to \(maxPlayerWindows) player windows."
    }
}

/// Where the window limit notice shows (design system 9.10): a Status HUD on a visible player window;
/// otherwise a message sheet on another open dwb window; a native alert only with no dwb window open.
enum WindowLimitSurface: Equatable {
    case statusHUD
    case messageSheet
    case nativeAlert

    static func choose(playerWindowVisible: Bool, otherDwbWindowOpen: Bool) -> WindowLimitSurface {
        if playerWindowVisible { return .statusHUD }
        return otherDwbWindowOpen ? .messageSheet : .nativeAlert
    }
}
