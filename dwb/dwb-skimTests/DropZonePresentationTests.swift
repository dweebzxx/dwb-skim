import XCTest

final class DropZonePresentationTests: XCTestCase {
    func testTitleCountsFilesWithPluralOnlyAboveOne() {
        XCTAssertEqual(DropZonePresentation(itemCount: 1, containsFolder: false).title, "Add 1 file to the queue")
        XCTAssertEqual(DropZonePresentation(itemCount: 3, containsFolder: false).title, "Add 3 files to the queue")
    }

    func testTitleCountsItemsWhenAFolderIsAmongThem() {
        XCTAssertEqual(DropZonePresentation(itemCount: 1, containsFolder: true).title, "Add 1 item to the queue")
        XCTAssertEqual(DropZonePresentation(itemCount: 4, containsFolder: true).title, "Add 4 items to the queue")
    }

    func testDetailSaysDropsGoToTheTopOfTheQueue() {
        XCTAssertEqual(DropZonePresentation(itemCount: 2, containsFolder: false).detail,
                       "Release to add to the top of the queue.")
    }
}
