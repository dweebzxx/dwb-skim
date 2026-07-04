import Foundation
import XCTest
import ImageIO
import UniformTypeIdentifiers
import AppKit

final class MediaFileSupportCoreTests: XCTestCase {
    func testMediaKindClassifiesVideoImageGIFAndUnsupportedExtensions() {
        XCTAssertEqual(MediaFileSupport.mediaKind(forExtension: "mp4"), .video)
        XCTAssertEqual(MediaFileSupport.mediaKind(forExtension: "MKV"), .video)
        XCTAssertEqual(MediaFileSupport.mediaKind(forExtension: "jpg"), .image)
        XCTAssertEqual(MediaFileSupport.mediaKind(forExtension: "HEIC"), .image)
        XCTAssertEqual(MediaFileSupport.mediaKind(forExtension: "gif"), .gif)
        XCTAssertNil(MediaFileSupport.mediaKind(forExtension: "txt"))
    }

    func testSupportedAndAcceptedRespectVideoImageAndGIFFilters() {
        let video = URL(fileURLWithPath: "/tmp/clip.MOV")
        let image = URL(fileURLWithPath: "/tmp/photo.png")
        let gif = URL(fileURLWithPath: "/tmp/loop.GIF")
        let unsupported = URL(fileURLWithPath: "/tmp/readme.md")

        XCTAssertTrue(MediaFileSupport.isSupported(video))
        XCTAssertTrue(MediaFileSupport.isSupported(image))
        XCTAssertTrue(MediaFileSupport.isSupported(gif))
        XCTAssertFalse(MediaFileSupport.isSupported(unsupported))

        XCTAssertTrue(MediaFileSupport.isAccepted(video, acceptedKinds: [.video]))
        XCTAssertFalse(MediaFileSupport.isAccepted(video, acceptedKinds: [.image, .gif]))

        XCTAssertTrue(MediaFileSupport.isAccepted(image, acceptedKinds: [.image]))
        XCTAssertFalse(MediaFileSupport.isAccepted(image, acceptedKinds: [.video, .gif]))

        XCTAssertTrue(MediaFileSupport.isAccepted(gif, acceptedKinds: [.gif]))
        XCTAssertFalse(MediaFileSupport.isAccepted(gif, acceptedKinds: [.image]))
        XCTAssertFalse(MediaFileSupport.isAccepted(unsupported, acceptedKinds: [.video, .image, .gif]))
    }

    func testGIFIsBothImageBackedAndDistinctAcceptedKind() {
        let gif = URL(fileURLWithPath: "/tmp/animated.gif")
        let stillImage = URL(fileURLWithPath: "/tmp/still.jpeg")

        XCTAssertTrue(MediaFileSupport.isImage(gif))
        XCTAssertTrue(MediaFileSupport.isGIF(gif))
        XCTAssertTrue(MediaFileSupport.isImage(stillImage))
        XCTAssertFalse(MediaFileSupport.isGIF(stillImage))
    }

    func testFinderNaturalFilenameOrderingUsesDisplayNameBeforePathTieBreak() {
        let urls = [
            URL(fileURLWithPath: "/tmp/folder/clip 10.mp4"),
            URL(fileURLWithPath: "/tmp/folder/clip 2.mp4"),
            URL(fileURLWithPath: "/tmp/folder/clip 1.mp4")
        ]

        let sortedNames = urls
            .sorted(by: MediaFileSupport.finderNaturalFilenameAscending)
            .map(\.lastPathComponent)

        XCTAssertEqual(sortedNames, ["clip 1.mp4", "clip 2.mp4", "clip 10.mp4"])
    }

    func testFinderNaturalFilenameOrderingHasDeterministicPathTieBreak() {
        let first = URL(fileURLWithPath: "/tmp/A/same name.mp4")
        let second = URL(fileURLWithPath: "/tmp/B/same name.mp4")

        XCTAssertEqual(MediaFileSupport.compareFinderNaturalFilenames(first, second), .orderedAscending)
        XCTAssertEqual(MediaFileSupport.compareFinderNaturalFilenames(second, first), .orderedDescending)
    }

    func testExpandToSupportedMediaRecursesAndPreservesFinderNaturalFolderOrder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try writeEmptyFile(root.appendingPathComponent("clip 10.mp4"))
        try writeEmptyFile(nested.appendingPathComponent("clip 2.mp4"))
        try writeEmptyFile(root.appendingPathComponent("clip 1.mp4"))
        try writeEmptyFile(root.appendingPathComponent("notes.txt"))

        let result = try MediaFileSupport.expandToSupportedMedia(
            [root],
            acceptedKinds: [.video, .image, .gif],
            shouldCancel: { false }
        )

        XCTAssertEqual(result.media.map(\.lastPathComponent), ["clip 1.mp4", "clip 2.mp4", "clip 10.mp4"])
        XCTAssertEqual(result.emptyFolderNames, [])
        XCTAssertEqual(result.supportedMediaCount, 3)
        XCTAssertEqual(result.excludedMediaCount, 0)
    }

    func testExpandToSupportedMediaCountsExcludedAcceptedKinds() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEmptyFile(root.appendingPathComponent("movie.mp4"))
        try writeEmptyFile(root.appendingPathComponent("photo.jpg"))
        try writeEmptyFile(root.appendingPathComponent("loop.gif"))

        let result = try MediaFileSupport.expandToSupportedMedia(
            [root],
            acceptedKinds: [.image],
            shouldCancel: { false }
        )

        XCTAssertEqual(result.media.map(\.lastPathComponent), ["photo.jpg"])
        XCTAssertEqual(result.supportedMediaCount, 3)
        XCTAssertEqual(result.excludedMediaCount, 2)
    }

    func testExpandToSupportedMediaCancellationThrowsWithoutPartialResult() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeEmptyFile(root.appendingPathComponent("clip.mp4"))

        XCTAssertThrowsError(
            try MediaFileSupport.expandToSupportedMedia(
                [root],
                acceptedKinds: [.video, .image, .gif],
                shouldCancel: { true }
            )
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Prefix Rename Planning Tests

    func testPlanPrefixRenames_singleFileHappyPath() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("video.mp4")
        try writeEmptyFile(url)

        let result = MediaFileSupport.planPrefixRenames(urls: [url], prefix: "x_")

        guard case .success(let planned) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned.first?.sourceURL.standardizedFileURL, url.standardizedFileURL)
        XCTAssertEqual(planned.first?.destinationURL.lastPathComponent, "x_video.mp4")
    }

    func testPlanPrefixRenames_multiFileHappyPath() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let a = tmp.appendingPathComponent("alpha.mp4")
        let b = tmp.appendingPathComponent("beta.mp4")
        try writeEmptyFile(a)
        try writeEmptyFile(b)

        let result = MediaFileSupport.planPrefixRenames(urls: [a, b], prefix: "x_")

        guard case .success(let planned) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned[0].destinationURL.lastPathComponent, "x_alpha.mp4")
        XCTAssertEqual(planned[1].destinationURL.lastPathComponent, "x_beta.mp4")
    }

    func testPlanPrefixRenames_alreadyPrefixedFilteredAsNoop() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("x_video.mp4")
        try writeEmptyFile(url)

        let result = MediaFileSupport.planPrefixRenames(urls: [url], prefix: "x_")

        guard case .success(let planned) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertTrue(planned.isEmpty, "Already-prefixed file should be a no-op")
    }

    func testPlanPrefixRenames_missingSourceReturnsFailure() {
        let url = URL(fileURLWithPath: "/nonexistent/path/missing.mp4")
        let result = MediaFileSupport.planPrefixRenames(
            urls: [url],
            prefix: "x_",
            fileExistsAtPath: { _ in false }
        )

        guard case .failure(let failure) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        if case .missingSource(let filename) = failure {
            XCTAssertEqual(filename, "missing.mp4")
        } else {
            XCTFail("Expected missingSource failure, got \(failure)")
        }
    }

    func testPlanPrefixRenames_destinationCollisionReturnsFailure() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let source = tmp.appendingPathComponent("video.mp4")
        let destination = tmp.appendingPathComponent("x_video.mp4")
        try writeEmptyFile(source)
        try writeEmptyFile(destination)

        let result = MediaFileSupport.planPrefixRenames(urls: [source], prefix: "x_")

        guard case .failure(let failure) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        if case .destinationCollision(let newName) = failure {
            XCTAssertEqual(newName, "x_video.mp4")
        } else {
            XCTFail("Expected destinationCollision failure, got \(failure)")
        }
    }

    func testPlanPrefixRenames_duplicateURLProducesDuplicateDestination() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("video.mp4")
        try writeEmptyFile(url)

        // Same URL passed twice → same destination path → duplicate
        let result = MediaFileSupport.planPrefixRenames(urls: [url, url], prefix: "x_")

        guard case .failure(let failure) = result else {
            XCTFail("Expected duplicateDestination failure, got \(result)")
            return
        }
        if case .duplicateDestination(_) = failure {
            // Expected: second entry produces same destination as first
        } else {
            XCTFail("Expected duplicateDestination failure, got \(failure)")
        }
    }

    func testPlanPrefixRenames_extensionPreservedInDestination() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("clip.MOV")
        try writeEmptyFile(url)

        let result = MediaFileSupport.planPrefixRenames(urls: [url], prefix: "tagged_")

        guard case .success(let planned) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(planned.first?.destinationURL.lastPathComponent, "tagged_clip.MOV")
    }

    func testPlanPrefixRenames_noExtensionFileHandledCorrectly() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = tmp.appendingPathComponent("noextfile")
        try writeEmptyFile(url)

        let result = MediaFileSupport.planPrefixRenames(urls: [url], prefix: "x_")

        guard case .success(let planned) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(planned.first?.destinationURL.lastPathComponent, "x_noextfile")
    }

    func testPlanPrefixRenames_queueURLUpdateMappingIsDeterministic() throws {
        let tmp = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let urls = (1...3).map { tmp.appendingPathComponent("file\($0).mp4") }
        for url in urls { try writeEmptyFile(url) }

        let result1 = MediaFileSupport.planPrefixRenames(urls: urls, prefix: "p_")
        let result2 = MediaFileSupport.planPrefixRenames(urls: urls, prefix: "p_")

        guard case .success(let p1) = result1, case .success(let p2) = result2 else {
            XCTFail("Expected success for both calls")
            return
        }
        XCTAssertEqual(p1, p2, "Planning must be deterministic for the same inputs")
    }

    // MARK: - GIF lazy decoding / sampling tests

    func testGIFAnimationNormalLoadsWithoutSamplingAndWithFullCache() throws {
        let count = 5
        let url = try createTestGIF(frameCount: count, width: 100, height: 100)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let animation = MediaFileSupport.loadGIFAnimation(for: url) else {
            XCTFail("Failed to load GIF animation")
            return
        }

        XCTAssertEqual(animation.frames.count, count)
        XCTAssertEqual(animation.frameDurations.count, count)
        // Normal GIF: maxCacheSize is count, all frame delays are 0.1s
        XCTAssertEqual(animation.frameDurations[0], 0.1, accuracy: 0.001)

        // Verify we can access all frames lazily
        for idx in 0..<count {
            let frame = animation.frames[idx]
            XCTAssertEqual(frame.width, 100)
            XCTAssertEqual(frame.height, 100)
        }
    }

    func testGIFAnimationLargeOrHighFrameCountDownsamplesAndCapsCache() throws {
        let count = 120
        let url = try createTestGIF(frameCount: count, width: 100, height: 100)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let animation = MediaFileSupport.loadGIFAnimation(for: url) else {
            XCTFail("Failed to load GIF animation")
            return
        }

        // 120 frames > 100, so step is ceil(120/60) = 2.
        // Sampled frames count should be 60.
        XCTAssertEqual(animation.frames.count, 60)
        XCTAssertEqual(animation.frameDurations.count, 60)
        // With step 2, frame delay should be 0.1 + 0.1 = 0.2
        XCTAssertEqual(animation.frameDurations[0], 0.2, accuracy: 0.001)

        // Accessing frames works
        let firstFrame = animation.frames[0]
        XCTAssertEqual(firstFrame.width, 100)
    }

    // MARK: - Helpers

    private func createTestGIF(frameCount: Int, width: Int, height: Int) throws -> URL {
        let tmpDir = try makeTemporaryDirectory()
        let fileURL = tmpDir.appendingPathComponent("test-\(UUID().uuidString).gif")

        guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }

        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create image"])
        }

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.1
            ]
        ] as CFDictionary

        for _ in 0..<frameCount {
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "test", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize destination"])
        }

        return fileURL
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dwbTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeEmptyFile(_ url: URL) throws {
        try Data().write(to: url)
    }
}
