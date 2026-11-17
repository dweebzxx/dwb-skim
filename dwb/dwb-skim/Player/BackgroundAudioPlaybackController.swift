import Foundation
import AVFAudio

protocol BackgroundAudioPlaying: AnyObject {
    var volume: Float { get set }
    var numberOfLoops: Int { get set }
    var isPlaying: Bool { get }
    func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func pause()
    func stop()
}

extension AVAudioPlayer: BackgroundAudioPlaying {}

protocol BackgroundAudioPlayerMaking {
    func makePlayer(for url: URL) throws -> BackgroundAudioPlaying
}

struct SystemBackgroundAudioPlayerFactory: BackgroundAudioPlayerMaking {
    func makePlayer(for url: URL) throws -> BackgroundAudioPlaying {
        try AVAudioPlayer(contentsOf: url)
    }
}

enum BackgroundAudioPlaybackState: Equatable {
    case inactive
    case playing(URL)
    case paused(URL)
    case unavailable(String)
}

/// Per-player-window owner for continuously looping uploaded audio. This type
/// has no singleton state and never restarts for ordinary queue transitions.
final class BackgroundAudioPlaybackController {
    private let settingsStore: BackgroundAudioSettingsStore
    private let playerFactory: BackgroundAudioPlayerMaking
    private let startAccessing: (URL) -> Bool
    private let stopAccessing: (URL) -> Void

    private var player: BackgroundAudioPlaying?
    private var activeURL: URL?
    private var didStartSecurityScopedAccess = false
    private var isSessionPaused = false

    private(set) var state: BackgroundAudioPlaybackState = .inactive

    var isActive: Bool {
        switch state {
        case .playing, .paused: return true
        case .inactive, .unavailable: return false
        }
    }

    init(settingsStore: BackgroundAudioSettingsStore = .shared,
         playerFactory: BackgroundAudioPlayerMaking = SystemBackgroundAudioPlayerFactory(),
         startAccessing: @escaping (URL) -> Bool = { $0.startAccessingSecurityScopedResource() },
         stopAccessing: @escaping (URL) -> Void = { $0.stopAccessingSecurityScopedResource() }) {
        self.settingsStore = settingsStore
        self.playerFactory = playerFactory
        self.startAccessing = startAccessing
        self.stopAccessing = stopAccessing
    }

    deinit {
        stop()
    }

    @discardableResult
    func applySettings() -> BackgroundAudioPlaybackState {
        let snapshot = settingsStore.snapshot()
        // Enable background audio is off: stop this window's track and report it inactive so
        // video audio plays normally. The stored track, mix, and volume are not touched.
        guard snapshot.isEnabled else {
            stop()
            return state
        }
        switch snapshot.selection {
        case .none:
            stop()
            state = .inactive

        case .unavailable(_, let reason):
            stop()
            state = .unavailable(reason)

        case .available(let url):
            if activeURL?.standardizedFileURL == url.standardizedFileURL,
               let player {
                player.volume = Float(snapshot.volume)
                if isSessionPaused {
                    if player.isPlaying { player.pause() }
                    state = .paused(url)
                } else if !player.isPlaying, !player.play() {
                    stop()
                    state = .unavailable("The selected audio track could not be played.")
                } else {
                    state = .playing(url)
                }
                return state
            }
            let shouldRemainPaused = isSessionPaused
            stop()
            isSessionPaused = shouldRemainPaused
            let startedAccess = startAccessing(url)
            do {
                let nextPlayer = try playerFactory.makePlayer(for: url)
                nextPlayer.numberOfLoops = -1
                nextPlayer.volume = Float(snapshot.volume)
                _ = nextPlayer.prepareToPlay()
                guard isSessionPaused || nextPlayer.play() else {
                    if startedAccess { stopAccessing(url) }
                    state = .unavailable("The selected audio track could not be played.")
                    return state
                }
                player = nextPlayer
                activeURL = url
                didStartSecurityScopedAccess = startedAccess
                state = isSessionPaused ? .paused(url) : .playing(url)
            } catch {
                if startedAccess { stopAccessing(url) }
                state = .unavailable(error.localizedDescription)
            }
        }
        return state
    }

    func pause() {
        guard !isSessionPaused else { return }
        isSessionPaused = true
        guard let player, let activeURL else { return }
        if player.isPlaying { player.pause() }
        state = .paused(activeURL)
    }

    func resume() {
        guard isSessionPaused else { return }
        isSessionPaused = false
        guard let player, let activeURL else { return }
        if player.isPlaying || player.play() {
            state = .playing(activeURL)
        } else {
            stop()
            state = .unavailable("The selected audio track could not be played.")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if didStartSecurityScopedAccess, let activeURL {
            stopAccessing(activeURL)
        }
        activeURL = nil
        didStartSecurityScopedAccess = false
        isSessionPaused = false
        state = .inactive
    }
}
