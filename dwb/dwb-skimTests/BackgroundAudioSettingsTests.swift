import Foundation
import XCTest

private final class FakeBackgroundBookmarkCodec: BackgroundAudioBookmarkCoding {
    var resolution: BackgroundAudioBookmarkResolution?
    var resolveError: Error?
    var bookmarkWrites = 0

    func bookmarkData(for url: URL) throws -> Data {
        bookmarkWrites += 1
        return Data(url.path.utf8)
    }

    func resolve(_ data: Data) throws -> BackgroundAudioBookmarkResolution {
        if let resolveError { throw resolveError }
        return resolution ?? BackgroundAudioBookmarkResolution(
            url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)),
            isStale: false
        )
    }
}

final class BackgroundAudioSettingsTests: XCTestCase {
    func testFilePolicyAcceptsOnlyMP3AndM4A() {
        XCTAssertTrue(BackgroundAudioFilePolicy.isSupported(URL(fileURLWithPath: "/tmp/a.mp3")))
        XCTAssertTrue(BackgroundAudioFilePolicy.isSupported(URL(fileURLWithPath: "/tmp/a.M4A")))
        XCTAssertFalse(BackgroundAudioFilePolicy.isSupported(URL(fileURLWithPath: "/tmp/a.wav")))
        XCTAssertFalse(BackgroundAudioFilePolicy.isSupported(URL(fileURLWithPath: "/tmp/a.mov")))
    }

    func testUnsupportedAndMissingFilesAreRejected() {
        let (_, store, suite) = makeStore(exists: { _ in false })
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        XCTAssertThrowsError(try store.select(URL(fileURLWithPath: "/tmp/a.wav")))
        XCTAssertThrowsError(try store.select(URL(fileURLWithPath: "/tmp/a.mp3")))
    }

    func testSelectionMixAndVolumePersist() throws {
        let (defaults, store, suite) = makeStore(exists: { _ in true })
        defer { defaults.removePersistentDomain(forName: suite) }
        try store.select(URL(fileURLWithPath: "/tmp/background.m4a"))
        store.setMixMode(.videoAndUploaded)
        store.setVolume(0.42)
        let restored = BackgroundAudioSettingsStore(defaults: defaults,
                                                    notificationCenter: NotificationCenter(),
                                                    bookmarkCodec: FakeBackgroundBookmarkCodec(),
                                                    fileExists: { _ in true })
        let snapshot = restored.snapshot()
        XCTAssertEqual(snapshot.selection.displayName, "background.m4a")
        XCTAssertTrue(snapshot.selection.isAvailable)
        XCTAssertEqual(snapshot.mixMode, .videoAndUploaded)
        XCTAssertEqual(snapshot.volume, 0.42, accuracy: 0.001)
    }

    func testStaleBookmarkRefreshesAndMissingFileBecomesUnavailable() throws {
        let codec = FakeBackgroundBookmarkCodec()
        let url = URL(fileURLWithPath: "/tmp/moved.mp3")
        codec.resolution = BackgroundAudioBookmarkResolution(url: url, isStale: true)
        let (defaults, store, suite) = makeStore(codec: codec, exists: { _ in true })
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("bookmark".utf8), forKey: SettingsDefaultsRegistry.Keys.backgroundAudioBookmark)
        defaults.set("moved.mp3", forKey: SettingsDefaultsRegistry.Keys.backgroundAudioDisplayName)
        XCTAssertTrue(store.snapshot().selection.isAvailable)
        XCTAssertEqual(codec.bookmarkWrites, 1)

        let missing = BackgroundAudioSettingsStore(defaults: defaults,
                                                   notificationCenter: NotificationCenter(),
                                                   bookmarkCodec: codec,
                                                   fileExists: { _ in false })
        XCTAssertFalse(missing.snapshot().selection.isAvailable)
        XCTAssertEqual(missing.snapshot().selection.displayName, "moved.mp3")
    }

    func testVideoAudioPolicyKeepsVolumesIndependent() {
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88, muted: false,
                                                        mixMode: .uploadedOnly,
                                                        backgroundAudioIsActive: true), 0)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88, muted: false,
                                                        mixMode: .videoAndUploaded,
                                                        backgroundAudioIsActive: true), 88)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88, muted: true,
                                                        mixMode: .videoAndUploaded,
                                                        backgroundAudioIsActive: true), 0)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 88, muted: false,
                                                        mixMode: .uploadedOnly,
                                                        backgroundAudioIsActive: false), 88)
    }

    private func makeStore(codec: FakeBackgroundBookmarkCodec = FakeBackgroundBookmarkCodec(),
                           exists: @escaping (String) -> Bool) -> (UserDefaults, BackgroundAudioSettingsStore, String) {
        let suite = "com.dwb.skimTests.BackgroundAudio.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let store = BackgroundAudioSettingsStore(defaults: defaults,
                                                notificationCenter: NotificationCenter(),
                                                bookmarkCodec: codec,
                                                fileExists: exists)
        return (defaults, store, suite)
    }
}
