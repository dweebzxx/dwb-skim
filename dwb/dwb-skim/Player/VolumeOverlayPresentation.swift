import Foundation

struct VideoVolumeMeterPresentation: Equatable {
    static let regularVolumeMaximum = 100
    static let maximumVolume = 150

    let volume: Int
    /// The independently rendered 0...100% regular-volume meter fill.
    let regularLevel: Double
    /// The independently rendered 101...150% overdrive meter fill.
    let overdriveLevel: Double
    let isMuted: Bool
    let percentageText: String
    let symbolName: String

    init(volume: Int, muted: Bool) {
        let clamped = min(Self.maximumVolume, max(0, volume))
        self.volume = clamped
        self.regularLevel = Double(min(clamped, Self.regularVolumeMaximum)) / Double(Self.regularVolumeMaximum)
        self.overdriveLevel = Double(max(0, clamped - Self.regularVolumeMaximum))
            / Double(Self.maximumVolume - Self.regularVolumeMaximum)
        self.isMuted = muted || clamped == 0
        self.percentageText = "\(clamped)%"
        self.symbolName = self.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
    }
}

enum VolumeOverlayTiming {
    static let dismissalDelay: TimeInterval = 1.25
    static let fadeDuration: TimeInterval = 0.18
}
