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

    private func describe(_ name: String,
                          primary: String = "select_",
                          secondary: String = "later_") -> SkimReviewStatusDescriptor {
        SkimReviewStatusDescriptor.describe(displayName: name, primaryPrefix: primary, secondaryPrefix: secondary)
    }

    func testConfiguredPrimaryPrefixIsPrimaryMarker() {
        let descriptor = describe("select_DSCF1234.MP4")

        XCTAssertEqual(descriptor.status, .primary)
        XCTAssertEqual(descriptor.prefixToken, "select_")
        XCTAssertEqual(descriptor.visibleFilename, "DSCF1234.MP4")
        assertColor(descriptor.statusColor, matches: theme.markerPrimary)
    }

    func testConfiguredSecondaryPrefixIsSecondaryMarker() {
        let descriptor = describe("later_DSCF1234.MP4")

        XCTAssertEqual(descriptor.status, .secondary)
        XCTAssertEqual(descriptor.prefixToken, "later_")
        XCTAssertEqual(descriptor.visibleFilename, "DSCF1234.MP4")
        assertColor(descriptor.statusColor, matches: theme.markerSecondary)
    }

    func testLiteralKeepAndDeletePrefixesAreNotMarkersWhenNotConfigured() {
        for name in ["keep_DSCF1234.MP4", "delete_DSCF1234.MP4"] {
            let descriptor = describe(name)
            XCTAssertEqual(descriptor.status, .unmarked, name)
            XCTAssertNil(descriptor.prefixToken, name)
            XCTAssertEqual(descriptor.visibleFilename, name)
            XCTAssertNil(descriptor.statusColor, name)
        }
    }

    func testKeepPrefixIsAMarkerOnlyWhenConfigured() {
        let descriptor = describe("keep_DSCF1234.MP4", primary: "keep_")

        XCTAssertEqual(descriptor.status, .primary)
        XCTAssertEqual(descriptor.prefixToken, "keep_")
    }

    func testBlankPrefixesRecognizeNothing() {
        let descriptor = describe("select_DSCF1234.MP4", primary: "", secondary: "")

        XCTAssertEqual(descriptor.status, .unmarked)
        XCTAssertNil(descriptor.prefixToken)
        XCTAssertNil(descriptor.statusColor)
    }

    func testOverlappingConfiguredPrefixesUseLongestMatch() {
        XCTAssertEqual(describe("a_b_clip.mov", primary: "a_", secondary: "a_b_").status, .secondary)
        XCTAssertEqual(describe("a_b_clip.mov", primary: "a_b_", secondary: "a_").status, .primary)
        XCTAssertEqual(describe("a_clip.mov", primary: "a_b_", secondary: "a_").status, .secondary)
    }

    func testUnmarkedDescriptor() {
        let descriptor = describe("DSCF1234.MP4")

        XCTAssertEqual(descriptor.status, .unmarked)
        XCTAssertNil(descriptor.prefixToken)
        XCTAssertEqual(descriptor.visibleFilename, "DSCF1234.MP4")
        XCTAssertNil(descriptor.statusColor)
    }

    func testURLDescriptorUsesBasenameOnly() {
        let url = URL(fileURLWithPath: "/tmp/select_folder/DSCF1234.MP4")
        let descriptor = SkimReviewStatusDescriptor.describe(url: url, primaryPrefix: "select_", secondaryPrefix: "later_")

        XCTAssertEqual(descriptor.status, .unmarked)
        XCTAssertEqual(descriptor.visibleFilename, "DSCF1234.MP4")
    }
}
