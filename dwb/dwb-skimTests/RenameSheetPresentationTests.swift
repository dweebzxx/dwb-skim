import XCTest

final class RenameSheetPresentationTests: XCTestCase {

    private func validate(_ typed: String,
                          in filename: String = "nature_walk_01.mp4",
                          existing: Set<String> = []) -> RenameNameValidation {
        RenameNameValidation.validate(typedStem: typed,
                                      original: RenameFilenameParts(filename: filename),
                                      nameExists: { existing.contains($0) })
    }

    // MARK: - Parts

    func testFilenameSplitsIntoStemAndProtectedExtension() {
        let parts = RenameFilenameParts(filename: "nature_walk_01.mp4")
        XCTAssertEqual(parts.stem, "nature_walk_01")
        XCTAssertEqual(parts.extensionSuffix, ".mp4")
        XCTAssertEqual(parts.filename, "nature_walk_01.mp4")
    }

    func testOnlyTheLastExtensionIsProtected() {
        let parts = RenameFilenameParts(filename: "clip.final.mov")
        XCTAssertEqual(parts.stem, "clip.final")
        XCTAssertEqual(parts.extensionSuffix, ".mov")
    }

    func testFileWithoutAnExtensionHasNoToken() {
        let parts = RenameFilenameParts(filename: "README")
        XCTAssertEqual(parts.stem, "README")
        XCTAssertEqual(parts.extensionSuffix, "")
    }

    // MARK: - Validation

    func testUnchangedNameDisablesRenameWithoutAMessage() {
        let result = validate("nature_walk_01")
        XCTAssertEqual(result, .unchanged)
        XCTAssertFalse(result.allowsRename)
        XCTAssertNil(result.inlineMessage)
        XCTAssertFalse(result.isError)
    }

    func testUnchangedIgnoresSurroundingWhitespace() {
        XCTAssertEqual(validate("  nature_walk_01  "), .unchanged)
    }

    func testEmptyNameIsInvalid() {
        let result = validate("")
        XCTAssertEqual(result, .empty)
        XCTAssertEqual(result.inlineMessage, "Enter a name.")
        XCTAssertFalse(result.allowsRename)
        XCTAssertEqual(validate("   "), .empty)
    }

    func testSlashAndColonAreInvalid() {
        XCTAssertEqual(validate("a/b"), .forbiddenCharacter)
        XCTAssertEqual(validate("a:b"), .forbiddenCharacter)
        XCTAssertEqual(validate("a/b").inlineMessage, "Names can\u{2019}t contain \u{201C}/\u{201D} or \u{201C}:\u{201D}.")
        XCTAssertFalse(validate("a:b").allowsRename)
    }

    func testExistingNameIsInvalidAndNamesTheCompleteFile() {
        let result = validate("other", existing: ["other.mp4"])
        XCTAssertEqual(result, .alreadyExists("other.mp4"))
        XCTAssertEqual(result.inlineMessage, "\u{201C}other.mp4\u{201D} already exists in this folder.")
        XCTAssertFalse(result.allowsRename)
        XCTAssertTrue(result.isError)
    }

    func testExistenceIsCheckedWithTheExtensionAppended() {
        // "other" alone exists, but the file would be "other.mp4".
        XCTAssertEqual(validate("other", existing: ["other"]), .valid)
    }

    func testChangedValidNameAllowsRename() {
        let result = validate("renamed")
        XCTAssertEqual(result, .valid)
        XCTAssertTrue(result.allowsRename)
        XCTAssertNil(result.inlineMessage)
    }

    func testCompleteFilenameAppendsTheProtectedExtension() {
        let parts = RenameFilenameParts(filename: "nature_walk_01.mp4")
        XCTAssertEqual(RenameNameValidation.completeFilename(typedStem: " renamed ", original: parts),
                       "renamed.mp4")
    }

    func testFileWithoutExtensionRenamesToTheBareStem() {
        XCTAssertEqual(validate("NOTES", in: "README"), .valid)
        let parts = RenameFilenameParts(filename: "README")
        XCTAssertEqual(RenameNameValidation.completeFilename(typedStem: "NOTES", original: parts), "NOTES")
    }

    // MARK: - Batch preview

    private func moves(_ count: Int) -> [(oldName: String, newName: String)] {
        (1...count).map { (oldName: "clip\($0).mp4", newName: "keep_clip\($0).mp4") }
    }

    func testBatchTitleAndConfirmTitleStateTheCount() {
        let preview = BatchRenamePreview(moves: moves(3))
        XCTAssertEqual(preview.title, "Rename 3 Files?")
        XCTAssertEqual(preview.confirmTitle, "Rename 3 Files")
    }

    func testBatchShowsAllRowsUpToFour() {
        let preview = BatchRenamePreview(moves: moves(4))
        XCTAssertEqual(preview.rows.count, 4)
        XCTAssertEqual(preview.remainingCount, 0)
        XCTAssertNil(preview.moreText)
    }

    func testBatchSummarizesTheRestAsAndNMore() {
        let preview = BatchRenamePreview(moves: moves(9))
        XCTAssertEqual(preview.rows.count, 4)
        XCTAssertEqual(preview.remainingCount, 5)
        XCTAssertEqual(preview.moreText, "and 5 more")
        XCTAssertEqual(preview.totalCount, 9)
    }

    func testBatchRowsListOldThenNew() {
        let preview = BatchRenamePreview(moves: moves(2))
        XCTAssertEqual(preview.rows[0].oldName, "clip1.mp4")
        XCTAssertEqual(preview.rows[0].newName, "keep_clip1.mp4")
        XCTAssertEqual(preview.rows[0].text, "clip1.mp4 \u{203A} keep_clip1.mp4")
    }

    func testBatchCaptionLocatesThePrefix() {
        let caption = BatchRenamePreview.caption(prefix: "keep_", count: 3)
        XCTAssertEqual(caption.text, "Applying prefix \"keep_\" will rename 3 files on disk.")
        XCTAssertEqual((caption.text as NSString).substring(with: caption.prefixRange), "keep_")
    }
}
