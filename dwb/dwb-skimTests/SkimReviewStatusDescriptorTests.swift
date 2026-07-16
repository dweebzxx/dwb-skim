import Cocoa
import XCTest

final class SkimReviewStatusDescriptorTests: XCTestCase {

    private func components(_ color: NSColor?) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let color else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private func assertColor(_ actual: NSColor?, matches expected: NSColor, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualComponents = components(actual),
              let expectedComponents = components(expected) else {
            XCTFail("Expected both colors to expose RGB components", file: file, line: line)
            return
        }
        XCTAssertEqual(actualComponents.r, expectedComponents.r, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.g, expectedComponents.g, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actualComponents.b, expectedComponents.b, accuracy: 0.001, file: file, line: line)
    }

    func testKeepPrefixDescriptor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "keep_DSCF1234.MP4")

        XCTAssertEqual(descriptor.status, .keep)
        XCTAssertEqual(descriptor.prefixToken, "keep_")
        XCTAssertEqual(descriptor.visibleFilename, "DSCF1234.MP4")
        XCTAssertEqual(descriptor.statusLabel, "keep")
        assertColor(descriptor.statusColor, matches: SkimColors.darkTeal)
    }

    func testDeletePrefixDescriptor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "delete_clip_0002.mov")

        XCTAssertEqual(descriptor.status, .delete)
        XCTAssertEqual(descriptor.prefixToken, "delete_")
        XCTAssertEqual(descriptor.visibleFilename, "clip_0002.mov")
        XCTAssertEqual(descriptor.statusLabel, "delete")
        assertColor(descriptor.statusColor, matches: SkimColors.burntOrange)
    }

    func testRenamePrefixDescriptor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "rename_nature_still_01.jpg")

        XCTAssertEqual(descriptor.status, .rename)
        XCTAssertEqual(descriptor.prefixToken, "rename_")
        XCTAssertEqual(descriptor.visibleFilename, "nature_still_01.jpg")
        XCTAssertEqual(descriptor.statusLabel, "rename")
        assertColor(descriptor.statusColor, matches: SkimColors.periwinkle)
    }

    func testUnmarkedDescriptor() {
        let descriptor = SkimReviewStatusDescriptor.describe(displayName: "IMG_8921.HEIC")

        XCTAssertEqual(descriptor.status, .unmarked)
        XCTAssertNil(descriptor.prefixToken)
        XCTAssertEqual(descriptor.visibleFilename, "IMG_8921.HEIC")
        XCTAssertNil(descriptor.statusColor)
        XCTAssertNil(descriptor.statusLabel)
    }

    func testURLDescriptorUsesBasenameOnly() {
        let url = URL(fileURLWithPath: "/tmp/delete_clip_0002.mov")
        let descriptor = SkimReviewStatusDescriptor.describe(url: url)

        XCTAssertEqual(descriptor.status, .delete)
        XCTAssertEqual(descriptor.visibleFilename, "clip_0002.mov")
    }
}
