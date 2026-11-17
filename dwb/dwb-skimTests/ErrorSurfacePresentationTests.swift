import XCTest

final class ErrorSurfacePresentationTests: XCTestCase {
    func testMessageSheetTitlesAreSentenceCase() {
        XCTAssertEqual(DWBMessageText.exportFailed, "Export failed")
        XCTAssertEqual(DWBMessageText.cannotUndo, "Cannot undo")
        XCTAssertEqual(DWBMessageText.undoFailed, "Undo failed")
        XCTAssertEqual(DWBMessageText.cannotRename, "Cannot rename")
        XCTAssertEqual(DWBMessageText.renameFailed, "Rename failed")
        XCTAssertEqual(DWBMessageText.unableToOpenFolder, "Unable to open folder")
        XCTAssertEqual(DWBMessageText.nothingToPlay, "Nothing to play")
        XCTAssertEqual(DWBMessageText.unsupportedFiles, "Unsupported files")
        XCTAssertEqual(DWBMessageText.unsupportedAudioTrack, "Unsupported audio track")
        XCTAssertEqual(DWBMessageText.windowLimitReached, "Window limit reached")
        XCTAssertEqual(DWBMessageText.couldNotRescanTitle, "Could not rescan folder")
    }

    func testNoTitleIsErrorAndEveryTitleIsSentenceCase() {
        let titles = [DWBMessageText.exportFailed, DWBMessageText.cannotUndo, DWBMessageText.undoFailed,
                      DWBMessageText.cannotRename, DWBMessageText.renameFailed,
                      DWBMessageText.unableToOpenFolder, DWBMessageText.nothingToPlay,
                      DWBMessageText.unsupportedFiles, DWBMessageText.unsupportedAudioTrack,
                      DWBMessageText.windowLimitReached, DWBMessageText.couldNotRescanTitle,
                      DWBMessageText.noFolderToRescanTitle]
        for title in titles {
            XCTAssertNotEqual(title.lowercased(), "error")
            let rest = title.dropFirst()
            XCTAssertEqual(String(rest), String(rest).lowercased(), "\(title) has a capital after the first word's first letter")
        }
    }

    func testRescanTextIsTheApprovedWording() {
        XCTAssertEqual(DWBMessageText.noFolderToRescan, "No folder to rescan. Open or drop a folder first.")
        XCTAssertEqual(DWBMessageText.couldNotRescanMessage,
                       "dwb skim could not read the folder contents. The queue was not changed.")
    }

    func testWindowLimitMessageKeepsItsText() {
        XCTAssertEqual(DWBMessageText.windowLimitMessage(maxPlayerWindows: 4),
                       "dwb skim supports up to 4 player windows.")
    }

    func testWindowLimitSurfaceChoice() {
        XCTAssertEqual(WindowLimitSurface.choose(playerWindowVisible: true, otherDwbWindowOpen: true), .statusHUD)
        XCTAssertEqual(WindowLimitSurface.choose(playerWindowVisible: true, otherDwbWindowOpen: false), .statusHUD)
        XCTAssertEqual(WindowLimitSurface.choose(playerWindowVisible: false, otherDwbWindowOpen: true), .messageSheet)
        XCTAssertEqual(WindowLimitSurface.choose(playerWindowVisible: false, otherDwbWindowOpen: false), .nativeAlert)
    }
}
