import Foundation
import XCTest

private final class FakeBackgroundPlayer: BackgroundAudioPlaying {
    var volume: Float = 0
    var numberOfLoops = 0
    var isPlaying = false
    var playCount = 0
    var pauseCount = 0
    var stopCount = 0
    var shouldPlay = true

    func prepareToPlay() -> Bool { true }
    func play() -> Bool {
        playCount += 1
        isPlaying = shouldPlay
        return shouldPlay
    }
    func pause() {
        pauseCount += 1
        isPlaying = false
    }
    func stop() {
        stopCount += 1
        isPlaying = false
    }
}

private final class FakeBackgroundPlayerFactory: BackgroundAudioPlayerMaking {
    var players: [FakeBackgroundPlayer] = []
    func makePlayer(for url: URL) throws -> BackgroundAudioPlaying {
        let player = FakeBackgroundPlayer()
        players.append(player)
        return player
    }
}

private final class PlaybackBookmarkCodec: BackgroundAudioBookmarkCoding {
    func bookmarkData(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> BackgroundAudioBookmarkResolution {
        BackgroundAudioBookmarkResolution(
            url: URL(fileURLWithPath: String(decoding: data, as: UTF8.self)),
            isStale: false
        )
    }
}

final class BackgroundAudioPlaybackControllerTests: XCTestCase {
    func testPlayerLoopsContinuouslyAndDoesNotRestartOnRepeatedApply() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in true },
                                                           stopAccessing: { _ in })
        controller.applySettings()
        let player = try XCTUnwrap(context.factory.players.first)
        XCTAssertEqual(player.numberOfLoops, -1)
        XCTAssertEqual(player.volume, 0.75, accuracy: 0.001)
        XCTAssertEqual(player.playCount, 1)

        controller.applySettings()
        XCTAssertEqual(context.factory.players.count, 1)
        XCTAssertEqual(player.playCount, 1, "Ordinary settings/queue refresh must not restart active audio")
    }

    func testReplacingAndClearingTrackStopOldPlayer() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in true },
                                                           stopAccessing: { _ in })
        try context.store.select(URL(fileURLWithPath: "/tmp/one.mp3"))
        controller.applySettings()
        let first = try XCTUnwrap(context.factory.players.first)
        try context.store.select(URL(fileURLWithPath: "/tmp/two.m4a"))
        controller.applySettings()
        XCTAssertEqual(first.stopCount, 1)
        XCTAssertEqual(context.factory.players.count, 2)
        context.store.clearSelection()
        controller.applySettings()
        XCTAssertEqual(context.factory.players.last?.stopCount, 1)
        XCTAssertEqual(controller.state, .inactive)
    }

    func testTwoControllersOwnIndependentPlaybackInstances() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/shared-selection.mp3"))
        let firstFactory = FakeBackgroundPlayerFactory()
        let secondFactory = FakeBackgroundPlayerFactory()
        let first = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                      playerFactory: firstFactory,
                                                      startAccessing: { _ in false },
                                                      stopAccessing: { _ in })
        let second = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                       playerFactory: secondFactory,
                                                       startAccessing: { _ in false },
                                                       stopAccessing: { _ in })
        first.applySettings()
        second.applySettings()
        XCTAssertEqual(firstFactory.players.count, 1)
        XCTAssertEqual(secondFactory.players.count, 1)
        XCTAssertFalse(firstFactory.players[0] === secondFactory.players[0])
        first.stop()
        XCTAssertFalse(firstFactory.players[0].isPlaying)
        XCTAssertTrue(secondFactory.players[0].isPlaying)
    }

    func testPauseResumeIsSynchronizedAndIdempotent() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        controller.applySettings()
        let player = try XCTUnwrap(context.factory.players.first)
        controller.pause()
        controller.pause()
        XCTAssertEqual(player.pauseCount, 1)
        XCTAssertEqual(controller.state, .paused(URL(fileURLWithPath: "/tmp/track.mp3")))
        controller.resume()
        controller.resume()
        XCTAssertEqual(player.playCount, 2)
        XCTAssertEqual(controller.state, .playing(URL(fileURLWithPath: "/tmp/track.mp3")))
    }

    func testApplyingSettingsWhilePausedDoesNotRestartAudio() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        controller.applySettings()
        let player = try XCTUnwrap(context.factory.players.first)
        controller.pause()
        controller.applySettings()
        XCTAssertEqual(player.playCount, 1)
        XCTAssertEqual(player.pauseCount, 1)
    }

    func testTrackSelectedWhileSessionPausedDoesNotAutoplay() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        controller.pause()
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        controller.applySettings()
        let player = try XCTUnwrap(context.factory.players.first)
        XCTAssertEqual(player.playCount, 0)
        XCTAssertEqual(controller.state, .paused(URL(fileURLWithPath: "/tmp/track.mp3")))
        controller.resume()
        XCTAssertEqual(player.playCount, 1)
    }

    // MARK: - Enable background audio (P57)

    func testTurningBackgroundAudioOffStopsTheTrackAndKeepsTheStoredSettings() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        let track = URL(fileURLWithPath: "/tmp/track.mp3")
        try context.store.select(track)
        context.store.setMixMode(.videoAndUploaded)
        context.store.setVolume(0.4)
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        XCTAssertEqual(controller.applySettings(), .playing(track))
        let player = try XCTUnwrap(context.factory.players.first)

        context.store.setEnabled(false)
        XCTAssertEqual(controller.applySettings(), .inactive)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(player.stopCount, 1)
        XCTAssertFalse(player.isPlaying)

        let snapshot = context.store.snapshot()
        XCTAssertFalse(snapshot.isEnabled)
        XCTAssertEqual(snapshot.selection.displayName, "track.mp3")
        XCTAssertTrue(snapshot.selection.isAvailable)
        XCTAssertEqual(snapshot.mixMode, .videoAndUploaded)
        XCTAssertEqual(snapshot.volume, 0.4, accuracy: 0.0001)
    }

    func testVideoAudioPlaysNormallyInUploadedOnlyModeWhileBackgroundAudioIsOff() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        controller.applySettings()
        XCTAssertEqual(context.store.snapshot().mixMode, .uploadedOnly)
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 64, muted: false,
                                                        mixMode: .uploadedOnly,
                                                        backgroundAudioIsActive: controller.isActive), 0)

        context.store.setEnabled(false)
        controller.applySettings()
        XCTAssertEqual(VideoAudioPolicy.effectiveVolume(storedVolume: 64, muted: false,
                                                        mixMode: .uploadedOnly,
                                                        backgroundAudioIsActive: controller.isActive), 64)
    }

    func testTurningBackgroundAudioBackOnStartsTheKeptTrackAgain() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        let track = URL(fileURLWithPath: "/tmp/track.mp3")
        try context.store.select(track)
        let controller = BackgroundAudioPlaybackController(settingsStore: context.store,
                                                           playerFactory: context.factory,
                                                           startAccessing: { _ in false },
                                                           stopAccessing: { _ in })
        controller.applySettings()
        context.store.setEnabled(false)
        controller.applySettings()
        context.store.setEnabled(true)
        XCTAssertEqual(controller.applySettings(), .playing(track))
        XCTAssertEqual(context.factory.players.count, 2)
        XCTAssertTrue(try XCTUnwrap(context.factory.players.last).isPlaying)
        XCTAssertEqual(try XCTUnwrap(context.factory.players.last).numberOfLoops, -1)
    }

    func testEveryWindowStopsWhenBackgroundAudioIsTurnedOff() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suite) }
        try context.store.select(URL(fileURLWithPath: "/tmp/track.mp3"))
        let firstFactory = FakeBackgroundPlayerFactory()
        let secondFactory = FakeBackgroundPlayerFactory()
        let first = BackgroundAudioPlaybackController(settingsStore: context.store, playerFactory: firstFactory,
                                                      startAccessing: { _ in false }, stopAccessing: { _ in })
        let second = BackgroundAudioPlaybackController(settingsStore: context.store, playerFactory: secondFactory,
                                                       startAccessing: { _ in false }, stopAccessing: { _ in })
        first.applySettings()
        second.applySettings()
        context.store.setEnabled(false)
        first.applySettings()
        second.applySettings()
        XCTAssertFalse(first.isActive)
        XCTAssertFalse(second.isActive)
        XCTAssertFalse(firstFactory.players[0].isPlaying)
        XCTAssertFalse(secondFactory.players[0].isPlaying)
    }

    private func makeContext() -> (defaults: UserDefaults,
                                   store: BackgroundAudioSettingsStore,
                                   factory: FakeBackgroundPlayerFactory,
                                   suite: String) {
        let suite = "com.dwb.skimTests.BackgroundPlayback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let store = BackgroundAudioSettingsStore(defaults: defaults,
                                                notificationCenter: NotificationCenter(),
                                                bookmarkCodec: PlaybackBookmarkCodec(),
                                                fileExists: { _ in true })
        return (defaults, store, FakeBackgroundPlayerFactory(), suite)
    }
}
