import Foundation
import VLCKitSPM

/// Per-window adaptive gain owner for VLCKit video audio. Skim+ uses a separate
/// AVAudioPlayer and never enters this signal path.
final class VideoAudioNormalizer {
    private weak var player: VLCMediaPlayer?
    private var equalizer: VLCAudioEqualizer?
    private var state = VideoAudioNormalizerState()
    private(set) var isEnabled = false

    @discardableResult
    func setEnabled(_ enabled: Bool, on player: VLCMediaPlayer) -> Bool {
        let playerChanged = self.player !== player
        if playerChanged {
            self.player?.equalizer = nil
            self.player = player
            equalizer = nil
        }
        if !playerChanged, enabled == isEnabled {
            if !enabled { return true }
            if equalizer != nil, player.equalizer != nil { return true }
        }
        isEnabled = enabled
        state.reset()

        guard enabled else {
            player.equalizer = nil
            equalizer = nil
            return true
        }

        let nextEqualizer = VLCAudioEqualizer()
        nextEqualizer.preAmplification = 0
        player.equalizer = nextEqualizer
        guard player.equalizer != nil else {
            equalizer = nil
            return false
        }
        equalizer = nextEqualizer
        return true
    }

    func prepareForNewVideo(on player: VLCMediaPlayer) {
        state.reset()
        guard isEnabled else { return }
        if self.player !== player || equalizer == nil {
            _ = setEnabled(true, on: player)
        }
        equalizer?.preAmplification = 0
    }

    func ingest(momentaryLoudnessLUFS: Double, from player: VLCMediaPlayer) {
        guard self.player === player else { return }
        switch state.evaluate(momentaryLoudnessLUFS: momentaryLoudnessLUFS,
                              isEnabled: isEnabled) {
        case .apply(_, let preamp):
            equalizer?.preAmplification = Float(preamp)
        case .bypassed, .ignoredMeasurement:
            return
        }
    }
}
