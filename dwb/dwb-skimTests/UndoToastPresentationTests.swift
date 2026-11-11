import XCTest

final class UndoToastPresentationTests: XCTestCase {
    private func step(_ moves: [(String, String)]) -> SkimMarkerRenameUndoStep {
        SkimMarkerRenameUndoStep(moves: moves.map {
            SkimMarkerRenameMove(source: URL(fileURLWithPath: "/tmp/\($0.0)"),
                                 destination: URL(fileURLWithPath: "/tmp/\($0.1)"))
        })
    }

    func testOneFileShowsPrefixChangedAndTheNewFilename() {
        let presentation = UndoToastPresentation(step: step([("clip.mp4", "select_clip.mp4")]))
        XCTAssertEqual(presentation.leadingText, "Prefix changed:")
        XCTAssertEqual(presentation.valueText, "select_clip.mp4")
        XCTAssertEqual(presentation.content, .file(name: "select_clip.mp4"))
        XCTAssertEqual(presentation.announcement, "Prefix changed on select_clip.mp4. Undo with Command Z.")
    }

    func testSeveralFilesShowTheCountAndNoFilenames() {
        let presentation = UndoToastPresentation(step: step([("a.mp4", "select_a.mp4"),
                                                             ("b.mp4", "select_b.mp4"),
                                                             ("c.mp4", "select_c.mp4")]))
        XCTAssertEqual(presentation.leadingText, "Prefix changed on")
        XCTAssertEqual(presentation.valueText, "3 files")
        XCTAssertFalse(presentation.announcement.contains("select_a.mp4"))
        XCTAssertEqual(presentation.announcement, "Prefix changed on 3 files. Undo with Command Z.")
    }
}
